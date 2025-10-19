import io.ktor.server.application.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger

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

fun Route.liveRoutes() {
    // Live videos collection
    get("/live-videos") {
        val apiKey = gg.growly.services.Env.get("YOUTUBE_API_KEY")
        val yt = gg.growly.services.YouTubeKtorService(apiKey ?: "")
        try {
            val resp = yt.searchLiveSports("sports live", 20)
            val items = resp.items.map { item ->
                val vid = item.id.videoId
                val title = item.snippet.title
                val desc = item.snippet.description
                val url = "https://www.youtube.com/watch?v=$vid"
                LiveListItemDTO(
                    id = vid,
                    live = LiveVideoDTO(
                        title = title,
                        description = desc,
                        streamUrl = url,
                        isLive = true,
                        liveChatId = null,
                        createdAt = System.currentTimeMillis()
                    )
                )
            }
            call.respond(items)
        } catch (t: Throwable) {
            call.respondText("Failed to fetch live videos: ${t.message}", status = io.ktor.http.HttpStatusCode.InternalServerError)
        } finally {
            yt.close()
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
    }
}
