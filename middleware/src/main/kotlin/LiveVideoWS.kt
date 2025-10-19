package gg.growly

import gg.growly.services.AgentClient
import gg.growly.LiveVideoService
import gg.growly.connectToMongoDB
import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.websocket.*
import io.ktor.websocket.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.collectLatest
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import gg.growly.services.S3Utility
import java.security.MessageDigest

// Outgoing message container for websocket (text or binary)
sealed interface OutgoingMsg {
    data class Text(val json: String) : OutgoingMsg
    data class Binary(val bytes: ByteArray) : OutgoingMsg
}

object LiveStreamCache {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)


    private data class Stream(
        val url: String,
        val isLive: Boolean,
        val flow: MutableSharedFlow<OutgoingMsg> = MutableSharedFlow(replay = 3, extraBufferCapacity = 128),
        val refCount: AtomicInteger = AtomicInteger(0),
        var producerJob: Job? = null,
        var idleCancelJob: Job? = null
    )

    data class Handle internal constructor(internal val key: String, val flow: MutableSharedFlow<OutgoingMsg>)

    private val streams = ConcurrentHashMap<String, Stream>()
    private val backgroundKeys = Collections.newSetFromMap(ConcurrentHashMap<String, Boolean>())

    fun acquire(app: Application, url: String, isLive: Boolean): Handle {
        val key = "$url|$isLive"
        val st = streams.compute(key) { _, existing ->
            val s = existing ?: Stream(url, isLive)
            s
        }!!
        st.idleCancelJob?.cancel()
        st.idleCancelJob = null
        val count = st.refCount.incrementAndGet()
        if (count == 1) {
            startProducer(app, st)
        }
        return Handle(key, st.flow)
    }

    // Start producer in background (no WS client) and keep it alive until stopBackground is called.
    fun ensureBackgroundStart(app: Application, url: String, isLive: Boolean) {
        val key = "$url|$isLive"
        val st = streams.compute(key) { _, existing -> existing ?: Stream(url, isLive) }!!
        // Mark as background-tracked and cancel any pending idle teardown
        backgroundKeys.add(key)
        st.idleCancelJob?.cancel()
        st.idleCancelJob = null
        if (st.producerJob == null || st.producerJob?.isActive != true) {
            app.log.info("[LiveStreamCache] ensureBackgroundStart starting producer url=$url isLive=$isLive")
            startProducer(app, st)
        } else {
            app.log.debug("[LiveStreamCache] ensureBackgroundStart producer already active url=$url")
        }
    }

    fun stopBackground(app: Application, url: String, isLive: Boolean) {
        val key = "$url|$isLive"
        backgroundKeys.remove(key)
        val st = streams[key]
        if (st != null && st.refCount.get() == 0) {
            app.log.info("[LiveStreamCache] stopBackground tearing down producer for url=${st.url}")
            st.producerJob?.cancel(CancellationException("background stop"))
            streams.remove(key)
        }
    }

    fun release(app: Application, handle: Handle) {
        val stream = streams[handle.key] ?: return
        val remaining = stream.refCount.decrementAndGet().coerceAtLeast(0)
        if (remaining == 0 && !backgroundKeys.contains(handle.key)) {
            // schedule idle teardown
            stream.idleCancelJob = scope.launch {
                delay(30_000)
                if (stream.refCount.get() == 0 && !backgroundKeys.contains(handle.key)) {
                    app.log.info("[LiveStreamCache] Tearing down producer for url=${stream.url} (idle)")
                    stream.producerJob?.cancel(CancellationException("idle timeout"))
                    streams.remove(handle.key)
                }
            }
        }
    }

    private fun startProducer(app: Application, stream: Stream) {
        val agent = AgentClient(app)
        val liveService by lazy { LiveVideoService(app.connectToMongoDB()) }
        app.log.info("[LiveStreamCache] Starting producer for url=${stream.url}")
        stream.producerJob = scope.launch {
            try {
                val startedAt = System.currentTimeMillis()
                agent.processVideo(
                    sourceUrl = stream.url,
                    isLive = stream.isLive,
                    onSnippet = { bytes, title, description ->
                        val sz = bytes.size
                        app.log.info("[LiveStreamCache] onSnippet url=${stream.url} bytes=$sz title='${title ?: ""}' descLen=${description?.length ?: 0}")
                        val b64 = Base64.getEncoder().encodeToString(bytes)
                        val titleEsc = title?.replace("\"", "\\\"")
                        val descEsc = description?.replace("\"", "\\\"")
                        val msg = buildString {
                            append("{\"type\":\"snippet\",\"data\":{")
                            append("\"video_data\":\"")
                            append(b64)
                            append("\",\"metadata\":{")
                            append("\"src_video_url\":\"")
                            append(stream.url.replace("\"", "\\\""))
                            append("\"")
                            if (titleEsc != null) {
                                append(",\"title\":\"")
                                append(titleEsc)
                                append("\"")
                            }
                            if (descEsc != null) {
                                append(",\"description\":\"")
                                append(descEsc)
                                append("\"")
                            }
                            append("}}")
                            append("}")
                        }
                        val emitted = stream.flow.tryEmit(OutgoingMsg.Text(msg))
                        if (!emitted) {
                            app.log.warn("[LiveStreamCache] onSnippet drop url=${stream.url} bytes=$sz (buffer full)")
                        }
                    },
                    onLiveChunk = { bytes, meta ->
                        val sz = bytes.size
                        val ncp = meta.num_chunks_processed
                        val dt = System.currentTimeMillis() - startedAt
                        app.log.info("[LiveStreamCache] onLiveChunk url=${stream.url} chunk=${meta.chunk_number} bytes=$sz fmt=${meta.format} sr=${meta.audio_sample_rate} c_len=${meta.commentary_length_bytes} v_len=${meta.video_length_bytes} elapsedMs=$dt${if (ncp != null) " n=$ncp" else ""}")

                        // Upload chunk to S3 and persist reference
                        val s3 = S3Utility(bucketName = "sportsclips-clip-store", region = "auto")
                        val hash = MessageDigest.getInstance("SHA-1").digest(meta.src_video_url.toByteArray()).joinToString("") { "%02x".format(it) }
                        val s3Key = "live/${hash}/chunk_%06d.mp4".format(meta.chunk_number)
                        scope.launch {
                            try {
                                s3.uploadBytes(bytes, s3Key, contentType = "video/mp4")
                            } catch (e: Exception) {
                                app.log.warn("[LiveStreamCache] Failed to upload live chunk to S3 key=$s3Key reason=${e.message}", e)
                            }
                            try {
                                val liveChunkService = LiveChunkService(app.connectToMongoDB())
                                liveChunkService.addChunk(LiveChunk(streamUrl = meta.src_video_url, chunkNumber = meta.chunk_number, s3Key = s3Key))
                            } catch (e: Exception) {
                                app.log.warn("[LiveStreamCache] Failed to persist LiveChunk url=${meta.src_video_url} chunk=${meta.chunk_number}: ${e.message}")
                            }
                        }
                        // Persist progress in LiveVideos collection
                        scope.launch {
                            try {
                                liveService.updateProgressByStreamUrl(
                                    streamUrl = meta.src_video_url,
                                    lastChunkNumber = meta.chunk_number,
                                    numChunksProcessed = meta.num_chunks_processed,
                                    format = meta.format,
                                    audioSampleRate = meta.audio_sample_rate,
                                    commentaryLengthBytes = meta.commentary_length_bytes,
                                    videoLengthBytes = meta.video_length_bytes
                                )
                            } catch (e: Exception) {
                                app.log.warn("[LiveStreamCache] Failed to update LiveVideos progress for url=${meta.src_video_url}: ${e.message}")
                            }
                        }
                        // Send metadata-only JSON (include s3_key) and DO NOT stream binary
                        val metaJson = buildString {
                            append("{")
                            append("\"type\":\"live_commentary_chunk\",")
                            append("\"data\":{")
                            append("\"metadata\":{")
                            append("\"src_video_url\":\"")
                            append(meta.src_video_url)
                            append("\",")
                            append("\"chunk_number\":")
                            append(meta.chunk_number)
                            append(",")
                            append("\"format\":\"")
                            append(meta.format)
                            append("\",")
                            append("\"audio_sample_rate\":")
                            append(meta.audio_sample_rate)
                            append(",")
                            append("\"commentary_length_bytes\":")
                            append(meta.commentary_length_bytes)
                            append(",")
                            append("\"video_length_bytes\":")
                            append(meta.video_length_bytes)
                            if (ncp != null) {
                                append(",")
                                append("\"num_chunks_processed\":")
                                append(ncp)
                            }
                            append(",\"s3_key\":\"")
                            append(s3Key)
                            append("\"")
                            append("}") // end metadata
                            append("}") // end data
                            append("}") // end root
                        }
                        val emittedText = stream.flow.tryEmit(OutgoingMsg.Text(metaJson))
                        if (!emittedText) {
                            app.log.warn("[LiveStreamCache] onLiveChunk drop meta url=${stream.url} chunk=${meta.chunk_number} bytes=$sz (buffer full)")
                        }
                    }
                )
            } catch (t: Throwable) {
                app.log.warn("[LiveStreamCache] Producer failed url=${stream.url}: ${t.message}", t)
                val err = "{" +
                        "\"type\":\"error\"," +
                        "\"message\":\"${t.message?.replace("\"", "\\\"") ?: "unknown"}\"," +
                        "\"metadata\":{\"src_video_url\":\"${stream.url.replace("\"", "\\\"")}\"}}"
                stream.flow.tryEmit(OutgoingMsg.Text(err))
            }
        }
    }
}

fun Route.liveVideoRoutes() {
    webSocket("/ws/live-video") {
        val app = call.application
        val log = app.log
        val videoUrl = call.request.queryParameters["video_url"]
        val isLiveParam = call.request.queryParameters["is_live"]
        if (videoUrl.isNullOrBlank() || isLiveParam.isNullOrBlank()) {
            val url = videoUrl ?: ""
            val errJson = """{"type":"error","message":"Missing required parameters","metadata":{"src_video_url":"$url"}}"""
            log.warn("[LiveVideoWS] reject connection: missing params videoUrl='$url' isLiveParam='$isLiveParam'")
            send(Frame.Text(errJson))
            close(CloseReason(CloseReason.Codes.CANNOT_ACCEPT, "missing params"))
            return@webSocket
        }
        val isLive = isLiveParam.equals("true", ignoreCase = true)
        log.info("[LiveVideoWS] Client connected videoUrl=$videoUrl isLive=$isLive")
        val stream = LiveStreamCache.acquire(app, videoUrl, isLive)
        log.info("[LiveVideoWS] acquired stream url=$videoUrl isLive=$isLive")
        var totalSent = 0
        val sendJob = launch {
            var sent = 0
            stream.flow.collectLatest { out ->
                try {
                    when (out) {
                        is OutgoingMsg.Text -> send(Frame.Text(out.json))
                        is OutgoingMsg.Binary -> send(Frame.Binary(true, out.bytes))
                    }
                    sent++
                    totalSent++
                    if (sent % 10 == 0) {
                        log.debug("[LiveVideoWS] sent=$sent total=$totalSent videoUrl=$videoUrl")
                    }
                } catch (t: Throwable) {
                    log.debug("[LiveVideoWS] send failed: ${t.message}")
                }
            }
        }
        try {
            // keep the socket alive until client closes
            for (frame in incoming) {
                if (frame is Frame.Close) break
            }
        } finally {
            sendJob.cancel()
            LiveStreamCache.release(app, stream)
            log.info("[LiveVideoWS] client disconnected url=$videoUrl isLive=$isLive totalSent=$totalSent")
            try { close() } catch (_: Exception) {}
        }
    }
}
