import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import gg.growly.connectToMongoDB
import gg.growly.LiveVideoService
import gg.growly.LiveChunkService
import gg.growly.LiveChunk
import gg.growly.services.S3Utility
import gg.growly.services.S3Helper

/**
 * Lightweight in-memory live system for comments and viewers per clip.
 */
object LiveHub {
    private const val MAX_BUFFER = 200
    private const val VIEWER_TIMEOUT_MS = 30_000L // 30s heartbeat window

    private data class ClipState(
        val comments: CopyOnWriteArrayList<LiveComment> = CopyOnWriteArrayList(),
        val viewers: ConcurrentHashMap<String, Long> = ConcurrentHashMap(),
        val viewerCount: AtomicInteger = AtomicInteger(0)
    )

    private val clips = ConcurrentHashMap<String, ClipState>()

    private fun state(clipId: String) = clips.computeIfAbsent(clipId) { ClipState() }

    fun addComment(clipId: String, comment: LiveComment) {
        val st = state(clipId)
        st.comments.add(comment)
        // trim buffer from the front (oldest) if needed
        while (st.comments.size > MAX_BUFFER) {
            st.comments.removeAt(0)
        }
    }

    fun latestComments(clipId: String, limit: Int, afterTs: Long?): List<LiveComment> {
        val st = state(clipId)
        val list = st.comments
        val filtered = if (afterTs != null) list.filter { it.timestampEpochSec > afterTs } else list.toList()
        // return the most recent N comments
        return filtered.takeLast(limit)
    }

    fun heartbeat(clipId: String, viewerId: String, nowMs: Long = System.currentTimeMillis()): Int {
        val st = state(clipId)
        val existing = st.viewers.put(viewerId, nowMs)
        if (existing == null) st.viewerCount.incrementAndGet()
        pruneOld(st, nowMs)
        return st.viewerCount.get()
    }

    fun viewerCount(clipId: String, nowMs: Long = System.currentTimeMillis()): Int {
        val st = state(clipId)
        pruneOld(st, nowMs)
        return st.viewerCount.get()
    }

    private fun pruneOld(st: ClipState, nowMs: Long) {
        var removed = 0
        st.viewers.entries.removeIf { (_, last) ->
            val expired = nowMs - last > VIEWER_TIMEOUT_MS
            if (expired) removed++
            expired
        }
        if (removed > 0) st.viewerCount.addAndGet(-removed)
        if (st.viewerCount.get() < 0) st.viewerCount.set(0)
    }
}

@Serializable
data class LiveComment(
    val id: String,
    val clipId: String,
    val userId: String,
    val username: String,
    val message: String,
    val timestampEpochSec: Long
)

@Serializable
data class PostCommentRequest(
    val userId: String,
    val username: String,
    val message: String
)

@Serializable
data class CommentsResponse(
    val comments: List<LiveComment>
)

@Serializable
data class ViewerHeartbeatRequest(
    val viewerId: String
)

@Serializable
data class ViewerInfoResponse(
    val clipId: String,
    val viewers: Int
)

@Serializable
data class LiveVideoDTO(
    val title: String,
    val description: String,
    val streamUrl: String,
    val isLive: Boolean,
    val liveChatId: String? = null,
    val createdAt: Long
)

@Serializable
data class LiveListItemDTO(
    val id: String,
    val live: LiveVideoDTO
)

@Serializable
data class LiveChunkDTO(
    val chunkNumber: Int,
    val s3Key: String,
    val url: String
)

@Serializable
data class LiveChunksResponse(
    val chunks: List<LiveChunkDTO>
)

fun Route.liveRoutes() {
    // Live videos collection
    get("/live-videos") {
        val log = call.application.log
        val started = System.currentTimeMillis()
        log.info("[LiveAPI] GET /live-videos start")

        // Read from the live_videos collection populated by the background runner
        try {
            val app = call.application
            val db = app.connectToMongoDB()
            val liveService = LiveVideoService(db)
            val chunkService = LiveChunkService(db)
            // Only include lives that have at least one chunk recorded for their streamUrl
            val lives = liveService.listAll()
                .filter { (_, live) ->
                    try {
                        chunkService.listByStreamUrl(live.streamUrl, null, 1).isNotEmpty()
                    } catch (_: Exception) { false }
                }
                .map { (id, live) ->
                    LiveListItemDTO(
                        id = id,
                        live = LiveVideoDTO(
                            title = live.title,
                            description = live.description,
                            streamUrl = live.streamUrl,
                            isLive = live.isLive,
                            liveChatId = live.liveChatId,
                            createdAt = (live.updatedAt ?: System.currentTimeMillis() / 1000) * 1000 // ms for client
                        )
                    )
                }

            val items = lives

            val dt = System.currentTimeMillis() - started
            log.info("[LiveAPI] GET /live-videos success count=${items.size} durationMs=$dt")
            call.respond(items)
        } catch (t: Throwable) {
            val dt = System.currentTimeMillis() - started
            log.warn("[LiveAPI] GET /live-videos error: ${t.message} durationMs=$dt", t)
            // On failure, return empty list to avoid misleading results
            call.respond(emptyList<LiveListItemDTO>())
        }
    }

    route("/live") {
        // Poll latest comments
        get("/{clipId}/comments") {
            val clipId = call.parameters["clipId"] ?: return@get call.respondText("Missing clipId", status = io.ktor.http.HttpStatusCode.BadRequest)
            val limit = call.request.queryParameters["limit"]?.toIntOrNull()?.coerceIn(1, 50) ?: 10
            val afterTs = call.request.queryParameters["afterTs"]?.toLongOrNull()
            val comments = LiveHub.latestComments(clipId, limit, afterTs)
            call.respond(CommentsResponse(comments))
        }

        // Post a new comment
        post("/{clipId}/comments") {
            val clipId = call.parameters["clipId"] ?: return@post call.respondText("Missing clipId", status = io.ktor.http.HttpStatusCode.BadRequest)
            val req = call.receive<PostCommentRequest>()
            val nowSec = System.currentTimeMillis() / 1000
            val comment = LiveComment(
                id = java.util.UUID.randomUUID().toString(),
                clipId = clipId,
                userId = req.userId,
                username = req.username,
                message = req.message,
                timestampEpochSec = nowSec
            )
            LiveHub.addComment(clipId, comment)
            try { LiveCommentsWSHub.broadcastComment(comment) } catch (_: Exception) {}
            call.respond(comment)
        }

        // Viewers endpoints
        get("/{clipId}/viewers") {
            val clipId = call.parameters["clipId"] ?: return@get call.respondText("Missing clipId", status = io.ktor.http.HttpStatusCode.BadRequest)
            val count = LiveHub.viewerCount(clipId)
            call.respond(ViewerInfoResponse(clipId, count))
        }

        post("/{clipId}/viewers/heartbeat") {
            val clipId = call.parameters["clipId"] ?: return@post call.respondText(
                "Missing clipId", status = io.ktor.http.HttpStatusCode.BadRequest
            )
            val hb = call.receive<ViewerHeartbeatRequest>()
            val count = LiveHub.heartbeat(clipId, hb.viewerId)
            try { LiveCommentsWSHub.broadcastViewerCount(clipId) } catch (_: Exception) {}
            call.respond(ViewerInfoResponse(clipId, count))
        }

        // Live chunk references: poll for latest uploaded chunk URLs
        get("/chunks") {
            val app = call.application
            val log = app.log
            val started = System.currentTimeMillis()
            val streamUrl = call.request.queryParameters["stream_url"]
            val afterChunk = call.request.queryParameters["after_chunk"]?.toIntOrNull()
            val limit = call.request.queryParameters["limit"]?.toIntOrNull()?.coerceIn(1, 50) ?: 10
            log.info("[LiveAPI] GET /live/chunks start stream_url='${streamUrl ?: ""}' after_chunk=${afterChunk ?: -1} limit=$limit")
            if (streamUrl.isNullOrBlank()) {
                log.warn("[LiveAPI] GET /live/chunks missing stream_url")
                return@get call.respondText("Missing stream_url", status = io.ktor.http.HttpStatusCode.BadRequest)
            }
            val svc = LiveChunkService(app.connectToMongoDB())
            val chunks = svc.listByStreamUrl(streamUrl, afterChunk, limit)
            val s3 = S3Utility(bucketName = "sportsclips-clip-store", region = "auto")
            var presigned = true
            val dtos = chunks.map {
                LiveChunkDTO(chunkNumber = it.chunkNumber, s3Key = it.s3Key, url = "https://clipstore.liftgate.io/${it.s3Key}")
            }
            val dt = System.currentTimeMillis() - started
            log.info("[LiveAPI] GET /live/chunks success count=${dtos.size} presigned=$presigned durationMs=$dt stream_url='$streamUrl'")
            call.respond(LiveChunksResponse(dtos))
        }
    }
}
