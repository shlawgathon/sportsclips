import dev.hayden.KHealth
import io.ktor.server.application.*

fun Application.configureMonitoring()
{
    install(KHealth)
}
