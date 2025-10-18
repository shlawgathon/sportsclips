package gg.growly

import io.ktor.client.HttpClient
import io.ktor.client.engine.cio.CIO
import io.ktor.client.plugins.cookies.*
import io.ktor.client.request.*
import io.ktor.client.statement.*
import io.ktor.http.*
import io.ktor.server.testing.*
import module
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import gg.growly.services.S3PresignHelper
import java.util.UUID

class ApplicationTest {

    @Test
    fun testLoginLogoutFlow() = testApplication {
        application { module() }

        val uniqueUser = "testuser-" + UUID.randomUUID().toString().take(8)
        val registerResponse = client.post("/auth/register") {
            contentType(ContentType.Application.Json)
            setBody("""{"username":"$uniqueUser","password":"testpass"}""")
        }
        // Accept Created or Conflict (user may already exist from previous runs)
        check(registerResponse.status == HttpStatusCode.Created || registerResponse.status == HttpStatusCode.Conflict) { "Unexpected status: ${registerResponse.status}" }

        val authClient = createClient {
            install(HttpCookies)
        }

        val loginResponse = authClient.post("/auth/login") {
            contentType(ContentType.Application.Json)
            setBody("""{"username":"$uniqueUser","password":"testpass"}""")
        }
        assertEquals(HttpStatusCode.OK, loginResponse.status)
        val setCookieHeader = loginResponse.headers[HttpHeaders.SetCookie]
        assertNotNull(setCookieHeader, "Login should set session cookie")
        check(setCookieHeader.contains("USER_SESSION")) { "USER_SESSION cookie not found in Set-Cookie" }

        val logoutResponse: HttpResponse = authClient.post("/auth/logout")
        assertEquals(HttpStatusCode.OK, logoutResponse.status)
        val logoutSetCookie = logoutResponse.headers[HttpHeaders.SetCookie]
        assertNotNull(logoutSetCookie, "Logout should return Set-Cookie to clear session")
        // Ktor clears cookie by setting empty value and past expiration
        check(logoutSetCookie.contains("USER_SESSION")) { "USER_SESSION cookie not present on logout" }
        check(logoutSetCookie.contains("Expires=") || logoutSetCookie.contains("Max-Age=0")) { "Logout cookie should be expired" }
    }
}
