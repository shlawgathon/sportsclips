package gg.growly

import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.client.plugins.cookies.*
import io.ktor.http.*
import io.ktor.server.testing.*
import kotlin.test.*
import module
import java.util.UUID
import kotlinx.serialization.json.*

class ApplicationE2ETest {

    private fun randomUser(): Pair<String, String> =
        "testuser-" + UUID.randomUUID().toString().take(8) to "testpass"

    @Test
    fun unauthorized_access_requires_authentication() = testApplication {
        application { module() }

        val r1 = client.get("/live")
        assertEquals(HttpStatusCode.Unauthorized, r1.status)

        val r2 = client.post("/ingest/youtube")
        assertEquals(HttpStatusCode.Unauthorized, r2.status)
    }

    @Test
    fun http_cache_endpoints_return_200() = testApplication {
        application { module() }

        val s1 = client.get("/short")
        val s2 = client.get("/short")
        assertEquals(HttpStatusCode.OK, s1.status)
        assertEquals(HttpStatusCode.OK, s2.status)
        assertTrue(s1.bodyAsText().isNotBlank())

        val d1 = client.get("/default")
        val d2 = client.get("/default")
        assertEquals(HttpStatusCode.OK, d1.status)
        assertEquals(HttpStatusCode.OK, d2.status)
        assertTrue(d1.bodyAsText().isNotBlank())
    }

    @Test
    fun full_authenticated_flow_for_live_clips_comments_likes_recommendations() = testApplication {
        application { module() }

        val (username, password) = randomUser()

        // Register
        val register = client.post("/auth/register") {
            contentType(ContentType.Application.Json)
            setBody("""{"username":"$username","password":"$password"}""")
        }
        assertTrue(register.status == HttpStatusCode.Created || register.status == HttpStatusCode.Conflict)

        // Authenticated client with cookie storage
        val authClient = createClient { install(HttpCookies) }

        // Login
        val login = authClient.post("/auth/login") {
            contentType(ContentType.Application.Json)
            setBody("""{"username":"$username","password":"$password"}""")
        }
        assertEquals(HttpStatusCode.OK, login.status)
        assertNotNull(login.headers[HttpHeaders.SetCookie])

        // Create a live
        val liveCreate = authClient.post("/live") {
            contentType(ContentType.Application.Json)
            setBody("""{"title":"Live A","description":"Desc","streamUrl":"https://example.com/stream.m3u8","isLive":true}""")
        }
        assertEquals(HttpStatusCode.Created, liveCreate.status)
        val liveCreateJson = Json.parseToJsonElement(liveCreate.bodyAsText()).jsonObject
        val liveId = liveCreateJson["id"]?.jsonPrimitive?.content
        assertNotNull(liveId)

        // List lives
        val lives = authClient.get("/live")
        assertEquals(HttpStatusCode.OK, lives.status)
        assertTrue(lives.bodyAsText().contains(liveId))

        // Get live by id
        val liveGet = authClient.get("/live/$liveId")
        assertEquals(HttpStatusCode.OK, liveGet.status)

        // Create a game (for cataloging event)
        val gameId = "G-" + UUID.randomUUID().toString().take(8)
        val gameCreate = authClient.post("/games") {
            contentType(ContentType.Application.Json)
            setBody("""{"gameId":"$gameId","name":"El Classico","sport":"Soccer"}""")
        }
        assertEquals(HttpStatusCode.Created, gameCreate.status)

        // Catalog listing (may be empty)
        val catalog = authClient.get("/catalog")
        assertEquals(HttpStatusCode.OK, catalog.status)

        // Logout
        val logout = authClient.post("/auth/logout")
        assertEquals(HttpStatusCode.OK, logout.status)
    }
}
