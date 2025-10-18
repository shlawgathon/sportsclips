package gg.growly.services

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import io.ktor.server.application.*
import io.ktor.server.config.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

class VoyageClient(application: Application) {
    private val apiKey: String? = application.environment.config.tryGetString("voyage.apiKey")
    private val client = HttpClient(CIO) {
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true })
        }
    }

    @Serializable
    private data class EmbeddingRequest(
        val model: String = "voyage-2",
        val input: List<String>
    )

    @Serializable
    private data class EmbeddingData(
        val embedding: List<Double>
    )

    @Serializable
    private data class EmbeddingResponse(
        val data: List<EmbeddingData>
    )

    suspend fun embed(text: String): List<Double>? {
        val key = apiKey ?: return null
        val resp = client.post("https://api.voyageai.com/v1/embeddings") {
            contentType(ContentType.Application.Json)
            headers { append(HttpHeaders.Authorization, "Bearer $key") }
            setBody(EmbeddingRequest(input = listOf(text)))
        }
        if (!resp.status.isSuccess()) return null
        val payload: EmbeddingResponse = resp.body()
        return payload.data.firstOrNull()?.embedding
    }
}
