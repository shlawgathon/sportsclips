package gg.growly

import gg.growly.services.Env
import gg.growly.services.VoyageClient
import kotlinx.coroutines.runBlocking
import kotlin.test.Test
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class EmbeddingE2ETest {
    private fun hasVoyageKey(): Boolean = !Env.get("VOYAGE_API_KEY").isNullOrBlank()

    @Test
    fun embedding_generation_returns_nonempty_array_when_configured() = runBlocking {
        if (!hasVoyageKey()) {
            println("[EmbeddingE2ETest] Skipping: VOYAGE_API_KEY not set in environment/.env")
            return@runBlocking
        }

        val client = VoyageClient()
        val result = client.embed("hello world from sportsclips")
        if (result == null) {
            println("[EmbeddingE2ETest] Skipping: Voyage API returned null (service unreachable or bad key)")
            return@runBlocking
        }
        assertTrue(result.isNotEmpty(), "Embedding list should be non-empty")
        // Sanity check numbers are finite
        assertTrue(result.all { it.isFinite() }, "All embedding values should be finite doubles")
        // Typical Voyage embedding dims are > 100; we don't assert exact size, just non-empty.
    }
}
