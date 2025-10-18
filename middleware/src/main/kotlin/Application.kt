import gg.growly.configureDatabases
import io.ktor.server.application.*
import io.ktor.server.netty.EngineMain
import io.ktor.server.plugins.contentnegotiation.ContentNegotiation
import io.ktor.serialization.kotlinx.json.*

fun main(args: Array<String>)
{
    EngineMain.main(args)
}

fun Application.module()
{
    install(ContentNegotiation) { json() }

    configureHTTP()
    configureSecurity()
    configureMonitoring()
    configureDatabases()
}
