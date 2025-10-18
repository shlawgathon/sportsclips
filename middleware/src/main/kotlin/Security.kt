import io.ktor.server.application.*
import io.ktor.server.sessions.*
import kotlinx.serialization.Serializable

// Configures only session-based auth to work with Mongo-backed user system.
fun Application.configureSecurity() {
    install(Sessions) {
        cookie<UserSession>("USER_SESSION") {
            cookie.extensions["SameSite"] = "lax"
        }
    }
}

@Serializable
data class UserSession(val userId: String = "")
