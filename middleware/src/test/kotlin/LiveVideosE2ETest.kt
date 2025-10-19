package gg.growly

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.server.testing.*
import kotlin.test.*
import kotlinx.serialization.json.*
import module

class LiveVideosE2ETest {
    @Test
    fun GET_live_videos_returns_list_with_required_fields_and_defaults_when_empty() = testApplication {
        application { module() }

        val resp = client.get("/live-videos")
        assertEquals(HttpStatusCode.OK, resp.status)
        val body = resp.bodyAsText()
        assertTrue(body.isNotBlank(), "Response body should not be blank")

        val json = Json.parseToJsonElement(body)
        assertTrue(json is JsonArray, "Expected a JSON array, got: ${json::class}")

        val arr = json as JsonArray
        // When DB is empty, backend provides a minimal default item, so array should have at least 1 element
        assertTrue(arr.size >= 1, "Expected at least one live item (default provided when DB empty)")

        // Validate the shape for the first item
        val first = arr.first().jsonObject
        assertTrue("id" in first, "Item should contain 'id'")
        assertTrue("live" in first, "Item should contain 'live'")

        val live = first["live"]!!.jsonObject
        val requiredFields = listOf("title", "description", "streamUrl", "isLive", "createdAt")
        for (f in requiredFields) {
            assertTrue(f in live, "live should contain '$f'")
        }
        // Sanity checks on types
        assertTrue(live["title"]!!.jsonPrimitive.content.isNotBlank())
        assertTrue(live["description"]!!.jsonPrimitive.isString)
        assertTrue(live["streamUrl"]!!.jsonPrimitive.content.startsWith("http"))
        assertNotNull(live["isLive"]!!.jsonPrimitive.booleanOrNull)
        assertNotNull(live["createdAt"]!!.jsonPrimitive.longOrNull)
    }
}
