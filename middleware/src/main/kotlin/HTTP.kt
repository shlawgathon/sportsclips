import com.asyncapi.kotlinasyncapi.context.service.AsyncApiExtension
import com.asyncapi.kotlinasyncapi.ktor.AsyncApiPlugin
import com.ucasoft.ktor.simpleCache.SimpleCache
import com.ucasoft.ktor.simpleMemoryCache.memoryCache
import io.ktor.server.application.*
import io.ktor.server.routing.*
import kotlin.time.Duration.Companion.seconds
import gg.growly.liveVideoRoutes

fun Application.configureHTTP()
{
    install(AsyncApiPlugin) {
        extension = AsyncApiExtension.builder {
            info {
                title("Sample API")
                version("1.0.0")
            }
        }
    }

    install(SimpleCache) {
        memoryCache {
            invalidateAt = 10.seconds
        }
    }

    // Enable server WebSockets for live video streaming bridge
    install(io.ktor.server.websocket.WebSockets)

    routing {
        liveRoutes()
        liveVideoRoutes()
        liveCommentsSocketRoutes()
    }
}
