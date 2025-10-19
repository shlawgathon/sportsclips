package gg.growly.services

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.statement.bodyAsText
import io.ktor.http.*
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

class VoyageClient {
    private val apiKey = Env.get("VOYAGE_API_KEY")
    private val client = HttpClient(CIO) {
        install(ContentNegotiation) {
            json(Json { ignoreUnknownKeys = true })
        }
    }

    @Serializable
    private data class EmbeddingRequest(
        val model: String = "voyage-3",
        val input: String
    )

    @Serializable
    private data class EmbeddingData(
        val embedding: List<Double>
    )

    @Serializable
    private data class EmbeddingResponse(
        val data: List<EmbeddingData>
    )

    // Backwards-compatible helper used by tests; defaults to voyage-3
    suspend fun embed(text: String): List<Double>? = embedWithModel(text, "voyage-3")

    private suspend fun embedWithModel(text: String, model: String): List<Double>? {
        val key = apiKey ?: return null
        val resp = client.post("https://api.voyageai.com/v1/embeddings") {
            contentType(ContentType.Application.Json)
            headers { append(HttpHeaders.Authorization, "Bearer $key") }
            setBody("{\"model\": \"$model\", \"input\": \"$text\"}")
        }
        println(resp.bodyAsText())
        if (!resp.status.isSuccess()) return null
        val payload: EmbeddingResponse = resp.body()
        return payload.data.firstOrNull()?.embedding
    }
}
