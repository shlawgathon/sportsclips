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
import kotlinx.coroutines.channels.consumeEach
import kotlinx.coroutines.isActive
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.*
import kotlin.coroutines.cancellation.CancellationException

class AgentClient(application: Application) {
    private val baseUrl: String = "ws://localhost:5353"
    private val client = HttpClient(CIO) {
        install(WebSockets)
        install(ContentNegotiation) { json(Json { ignoreUnknownKeys = true }) }
    }

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
        val url = URLBuilder(baseUrl).apply {
            encodedPath += "/ws/video-snippets"
            parameters.append("video_url", sourceUrl)
            parameters.append("is_live", isLive.toString())
        }.buildString().replace("http://", "ws://").replace("https://", "wss://")

        try {
            client.webSocket(urlString = url, request = {}) {
                while (this.isActive) {
                    val frame = incoming.receiveCatching().getOrNull() ?: break
                    when (frame) {
                        is Frame.Text -> {
                            val txt = frame.readText()
                            val element = Json.parseToJsonElement(txt)
                            val type = element.jsonObject["type"]?.jsonPrimitive?.content
                            if (type == "snippet") {
                                val data = element.jsonObject["data"] as? JsonElement ?: continue
                                val meta = data.jsonObject["metadata"]!!.jsonObject
                                val base64 = data.jsonObject["video_data"]!!.jsonPrimitive.content
                                val title = meta["title"]?.jsonPrimitive?.content
                                val description = meta["description"]?.jsonPrimitive?.content
                                val bytes = Base64.getDecoder().decode(base64)
                                onSnippet(bytes, title, description)
                            } else if (type == "snippet_complete") {
                                break
                            } else if (type == "error") {
                                // log and break
                                break
                            }
                        }
                        is Frame.Close -> break
                        else -> {}
                    }
                }
            }
        } catch (ce: CancellationException) {
            throw ce
        } catch (e: Exception) {
            // swallow for now / log
        }
    }
}
