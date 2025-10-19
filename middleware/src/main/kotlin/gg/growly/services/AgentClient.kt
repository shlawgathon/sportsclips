package gg.growly.services

import io.ktor.client.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.plugins.websocket.*
import io.ktor.client.request.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.websocket.*
import io.ktor.server.application.*
import io.ktor.server.config.*
import kotlinx.coroutines.isActive
import kotlinx.coroutines.sync.Semaphore
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.*
import kotlin.coroutines.cancellation.CancellationException

class AgentClient(application: Application) {
    private val log = application.log
    private val baseUrl: String = "ws://100.108.114.78:5353"
    private val client = HttpClient(CIO) {
        install(WebSockets)
        install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
    }

    // Gate to ensure only one processVideo request is allowed to proceed
    // until it receives a first response from the agent.
    private val startGate = Semaphore(1)

    @Serializable
    data class SnippetMessage(
        val type: String,
        val data: SnippetData? = null,
        val message: String? = null
    )

    @Serializable
    data class SnippetData(
        val video_data: String,
        val metadata: SnippetMeta
    )

    @Serializable
    data class SnippetMeta(
        val src_video_url: String,
        val title: String? = null,
        val description: String? = null
    )

    suspend fun processVideo(
        sourceUrl: String,
        isLive: Boolean,
        onSnippet: suspend (bytes: ByteArray, title: String?, description: String?) -> Unit
    ) {
        // Acquire the gate before starting the websocket. Other callers will suspend
        // here until we receive at least one response (or error/close) from the agent.
        startGate.acquire()
        log.info("[AgentClient] startGate acquired sourceUrl=$sourceUrl isLive=$isLive")
        var gateReleased = false
        fun releaseGateIfNeeded() {
            if (!gateReleased) {
                gateReleased = true
                startGate.release()
                log.info("[AgentClient] startGate released sourceUrl=$sourceUrl")
            }
        }

        val url = URLBuilder(baseUrl).apply {
            encodedPath += "/ws/video-snippets"
            parameters.append("video_url", sourceUrl)
            parameters.append("is_live", isLive.toString())
        }.buildString().replace("http://", "ws://").replace("https://", "wss://")
        log.info("[AgentClient] Connecting to agent websocket url=$url sourceUrl=$sourceUrl isLive=$isLive")

        try {
            client.webSocket(urlString = url, request = {}) {
                log.info("[AgentClient] WebSocket connected url=$url")
                var snippetCount = 0
                val startedAt = System.currentTimeMillis()
                while (this.isActive) {
                    val frame = incoming.receiveCatching().getOrNull() ?: run {
                        // No frame means stream ended; release gate if not yet.
                        log.info("[AgentClient] WebSocket stream ended (no frame) url=$url runtimeMs=${System.currentTimeMillis() - startedAt}")
                        releaseGateIfNeeded()
                        break
                    }
                    when (frame) {
                        is Frame.Text -> {
                            val txt = frame.readText()
                            log.debug("[AgentClient] Received text frame length=${txt.length}")
                            try {
                                val element = Json.parseToJsonElement(txt)
                                val type = element.jsonObject["type"]?.jsonPrimitive?.content
                                when (type) {
                                    "snippet" -> {
                                        // First actual response from agent: release the gate now.
                                        releaseGateIfNeeded()
                                        val data = element.jsonObject["data"] as? JsonElement
                                        if (data == null) {
                                            log.warn("[AgentClient] 'snippet' message missing 'data' field: $txt")
                                            continue
                                        }
                                        val meta = data.jsonObject["metadata"]?.jsonObject
                                        val base64 = data.jsonObject["video_data"]?.jsonPrimitive?.content
                                        if (base64 == null) {
                                            log.warn("[AgentClient] 'snippet' message missing 'video_data' field: $txt")
                                            continue
                                        }
                                        val title = meta?.get("title")?.jsonPrimitive?.content
                                        val description = meta?.get("description")?.jsonPrimitive?.content
                                        val bytes = Base64.getDecoder().decode(base64)
                                        snippetCount += 1
                                        log.info("[AgentClient] Received snippet #$snippetCount bytes=${bytes.size} title=${title ?: ""} descLen=${description?.length ?: 0}")
                                        onSnippet(bytes, title, description)
                                    }
                                    "snippet_complete" -> {
                                        // If complete arrives before any snippet, still release.
                                        releaseGateIfNeeded()
                                        log.info("[AgentClient] snippet_complete received after $snippetCount snippets; closing")
                                        break
                                    }
                                    "error" -> {
                                        // Release and break on error.
                                        releaseGateIfNeeded()
                                        val msg = try { element.jsonObject["message"]?.jsonPrimitive?.content } catch (t: Throwable) { null }
                                        log.warn("[AgentClient] error message from agent: ${msg ?: "<none>"}")
                                        break
                                    }
                                    else -> {
                                        // Unknown message still counts as a response; release once.
                                        releaseGateIfNeeded()
                                        log.debug("[AgentClient] Unknown message type=$type payloadLen=${txt.length}")
                                    }
                                }
                            } catch (t: Throwable) {
                                // Any parse error counts as a response too; release once.
                                releaseGateIfNeeded()
                                log.warn("[AgentClient] Failed to parse incoming text frame: ${t.message}")
                            }
                        }
                        is Frame.Close -> {
                            log.info("[AgentClient] Received close frame from agent url=$url")
                            releaseGateIfNeeded()
                            break
                        }
                        else -> {
                            // Any other frame counts as a response for gating purposes.
                            log.debug("[AgentClient] Received non-text frame type=${frame.frameType} url=$url")
                            releaseGateIfNeeded()
                        }
                    }
                }
            }
        } catch (ce: CancellationException) {
            log.info("[AgentClient] processVideo cancelled for sourceUrl=$sourceUrl: ${ce.message}")
            releaseGateIfNeeded()
            throw ce
        } catch (e: Exception) {
            // Ensure gate is released on exceptions as well.
            releaseGateIfNeeded()
            log.error("[AgentClient] processVideo failed for sourceUrl=$sourceUrl", e)
        }
    }
}
