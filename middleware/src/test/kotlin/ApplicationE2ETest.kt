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

        val r2 = client.post("/clips") {
            contentType(ContentType.Application.Json)
            setBody("""{"s3Key":"k","title":"t","description":"d"}""")
        }
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

        // Presign upload
        val presign = authClient.post("/clips/presign-upload") {
            contentType(ContentType.Application.Json)
            setBody("""{"key":"uploads/test-${UUID.randomUUID()}.mp4","contentType":"video/mp4"}""")
        }
        assertEquals(HttpStatusCode.OK, presign.status)
        val presignJson = Json.parseToJsonElement(presign.bodyAsText()).jsonObject
        val presignedUrl = presignJson["url"]?.jsonPrimitive?.content
        val presignKey = presignJson["key"]?.jsonPrimitive?.content
        assertNotNull(presignedUrl)
        assertNotNull(presignKey)

        // Create clip
        val clipCreate = authClient.post("/clips") {
            contentType(ContentType.Application.Json)
            setBody("""{"s3Key":"$presignKey","title":"Goal","description":"Amazing goal"}""")
        }
        assertEquals(HttpStatusCode.Created, clipCreate.status)
        val clipJson = Json.parseToJsonElement(clipCreate.bodyAsText()).jsonObject
        val clipId = clipJson["id"]?.jsonPrimitive?.content
        assertNotNull(clipId)

        // Get clip
        val clipGet = authClient.get("/clips/$clipId")
        assertEquals(HttpStatusCode.OK, clipGet.status)

        // Like clip
        val like = authClient.post("/clips/$clipId/like")
        assertEquals(HttpStatusCode.OK, like.status)

        // Comment on clip
        val comment = authClient.post("/clips/$clipId/comments") {
            contentType(ContentType.Application.Json)
            setBody("""{"text":"Great clip!"}""")
        }
        assertEquals(HttpStatusCode.Created, comment.status)

        // List comments
        val comments = authClient.get("/clips/$clipId/comments")
        assertEquals(HttpStatusCode.OK, comments.status)
        assertTrue(comments.bodyAsText().contains("Great clip!"))

        // Presign download
        val download = authClient.get("/clips/presign-download/$clipId")
        assertEquals(HttpStatusCode.OK, download.status)
        val downloadUrl = Json.parseToJsonElement(download.bodyAsText()).jsonObject["url"]?.jsonPrimitive?.content
        assertNotNull(downloadUrl)

        // Recommendations (may be empty list)
        val recs = authClient.get("/clips/$clipId/recommendations")
        assertEquals(HttpStatusCode.OK, recs.status)

        // Logout
        val logout = authClient.post("/auth/logout")
        assertEquals(HttpStatusCode.OK, logout.status)
    }
}
