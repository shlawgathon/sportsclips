import gg.growly.services.AgentClient
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

private object LiveStreamCache {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private data class Stream(
        val url: String,
        val isLive: Boolean,
        val flow: MutableSharedFlow<String> = MutableSharedFlow(replay = 3, extraBufferCapacity = 128),
        val refCount: AtomicInteger = AtomicInteger(0),
        var producerJob: Job? = null,
        var idleCancelJob: Job? = null
    )

    data class Handle internal constructor(internal val key: String, val flow: MutableSharedFlow<String>)

    private val streams = ConcurrentHashMap<String, Stream>()

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

    fun release(app: Application, handle: Handle) {
        val stream = streams[handle.key] ?: return
        val remaining = stream.refCount.decrementAndGet().coerceAtLeast(0)
        if (remaining == 0) {
            // schedule idle teardown
            stream.idleCancelJob = scope.launch {
                delay(30_000)
                if (stream.refCount.get() == 0) {
                    app.log.info("[LiveStreamCache] Tearing down producer for url=${stream.url} (idle)")
                    stream.producerJob?.cancel(CancellationException("idle timeout"))
                    streams.remove(handle.key)
                }
            }
        }
    }

    private fun startProducer(app: Application, stream: Stream) {
        val agent = AgentClient(app)
        app.log.info("[LiveStreamCache] Starting producer for url=${stream.url}")
        stream.producerJob = scope.launch {
            try {
                agent.processVideo(
                    sourceUrl = stream.url,
                    isLive = stream.isLive,
                    onSnippet = { bytes, title, description ->
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
                        stream.flow.tryEmit(msg)
                    },
                    onLiveChunk = { bytes, meta ->
                        val b64 = Base64.getEncoder().encodeToString(bytes)
                        val msg = """
                        {
                          "type": "live_commentary_chunk",
                          "data": {
                            "video_data": "$b64",
                            "metadata": {
                              "src_video_url": "${meta.src_video_url}",
                              "chunk_number": ${meta.chunk_number},
                              "format": "${meta.format}",
                              "audio_sample_rate": ${meta.audio_sample_rate},
                              "commentary_length_bytes": ${meta.commentary_length_bytes},
                              "video_length_bytes": ${meta.video_length_bytes},
                              "num_chunks_processed": ${meta.num_chunks_processed}
                            }
                          }
                        }
                        """.trimIndent()
                        stream.flow.tryEmit(msg)
                    }
                )
            } catch (t: Throwable) {
                app.log.warn("[LiveStreamCache] Producer failed url=${stream.url}: ${t.message}", t)
                val err = "{" +
                        "\"type\":\"error\"," +
                        "\"message\":\"${t.message?.replace("\"", "\\\"") ?: "unknown"}\"," +
                        "\"metadata\":{\"src_video_url\":\"${stream.url.replace("\"", "\\\"")}\"}}"
                stream.flow.tryEmit(err)
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
            send(Frame.Text(errJson))
            close(CloseReason(CloseReason.Codes.CANNOT_ACCEPT, "missing params"))
            return@webSocket
        }
        val isLive = isLiveParam.equals("true", ignoreCase = true)
        val stream = LiveStreamCache.acquire(app, videoUrl, isLive)
        val sendJob = launch {
            stream.flow.collectLatest { json ->
                try {
                    send(Frame.Text(json))
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
            try { close() } catch (_: Exception) {}
        }
    }
}
