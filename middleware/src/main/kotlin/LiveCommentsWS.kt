import io.ktor.server.application.*
import io.ktor.server.routing.*
import io.ktor.server.websocket.*
import io.ktor.websocket.*
import kotlinx.coroutines.channels.ClosedReceiveChannelException
import java.util.concurrent.ConcurrentHashMap

object LiveCommentsWSHub {
    private val sessions = ConcurrentHashMap<String, MutableSet<DefaultWebSocketServerSession>>()

    fun register(clipId: String, session: DefaultWebSocketServerSession) {
        val set = sessions.computeIfAbsent(clipId) { ConcurrentHashMap.newKeySet() }
        set.add(session)
        try { session.call.application.log.info("[LiveCommentsWS] register clipId=$clipId size=${set.size}") } catch (_: Throwable) {}
    }

    fun unregister(session: DefaultWebSocketServerSession) {
        sessions.entries.forEach { (clipId, set) ->
            if (set.remove(session)) {
                try { session.call.application.log.info("[LiveCommentsWS] unregister clipId=$clipId size=${set.size}") } catch (_: Throwable) {}
            }
        }
    }

    suspend fun broadcastComment(comment: LiveComment) {
        val set = sessions[comment.clipId] ?: return
        val json = """{"type":"comment","data":${commentJson(comment)}}"""
        var sent = 0
        for (sess in set) {
            try { sess.send(Frame.Text(json)); sent++ } catch (_: Throwable) {}
        }
        try { set.firstOrNull()?.call?.application?.log?.debug("[LiveCommentsWS] broadcastComment clipId=${comment.clipId} sent=$sent") } catch (_: Throwable) {}
    }

    suspend fun broadcastViewerCount(clipId: String) {
        val set = sessions[clipId] ?: return
        val count = LiveHub.viewerCount(clipId)
        val json = """{"type":"viewer_count","data":{"clipId":"$clipId","viewers":$count}}"""
        var sent = 0
        for (sess in set) {
            try { sess.send(Frame.Text(json)); sent++ } catch (_: Throwable) {}
        }
        try { set.firstOrNull()?.call?.application?.log?.debug("[LiveCommentsWS] broadcastViewerCount clipId=$clipId viewers=$count sent=$sent") } catch (_: Throwable) {}
    }
}

fun Route.liveCommentsSocketRoutes() {
    webSocket("/ws/live-comments/{clipId}") {
        val app = call.application
        val log = app.log
        val connId = java.util.UUID.randomUUID().toString().substring(0, 8)
        val clipId = call.parameters["clipId"]
        if (clipId.isNullOrBlank()) {
            send(Frame.Text("{" +
                "\"type\":\"error\",\"message\":\"Missing clipId\"}"))
            log.warn("[LiveCommentsWS][conn=$connId] reject connection: missing clipId")
            close(CloseReason(CloseReason.Codes.CANNOT_ACCEPT, "missing clipId"))
            return@webSocket
        }
        log.info("[LiveCommentsWS][conn=$connId] client connected clipId=$clipId")
        LiveCommentsWSHub.register(clipId, this)
        try {
            // send init payload: latest comments + viewer count
            val comments = LiveHub.latestComments(clipId, limit = 20, afterTs = null)
            val commentsJson = comments.joinToString(prefix = "[", postfix = "]") { commentJson(it) }
            val viewers = LiveHub.viewerCount(clipId)
            val initJson = """{"type":"init","data":{"comments":$commentsJson,"viewer_count":$viewers}}"""
            log.debug("[LiveCommentsWS][conn=$connId] init payload clipId=$clipId comments=${comments.size} viewers=$viewers")
            send(Frame.Text(initJson))

            // listen for messages from client
            for (frame in incoming) {
                if (frame is Frame.Text) {
                    val txt = frame.readText()
                    if (txt.contains("\"type\":\"post_comment\"")) {
                        // crude parse for minimal change
                        val userId = regexExtract(txt, "\\\"userId\\\":\\\"(.*?)\\\"") ?: "anon"
                        val username = regexExtract(txt, "\\\"username\\\":\\\"(.*?)\\\"") ?: "anon"
                        val message = regexExtract(txt, "\\\"message\\\":\\\"(.*?)\\\"") ?: ""
                        val nowSec = System.currentTimeMillis() / 1000
                        val comment = LiveComment(
                            id = java.util.UUID.randomUUID().toString(),
                            clipId = clipId,
                            userId = userId,
                            username = username,
                            message = message,
                            timestampEpochSec = nowSec
                        )
                        log.info("[LiveCommentsWS][conn=$connId] post_comment clipId=$clipId userId=$userId username=${username.take(16)} msgLen=${message.length}")
                        LiveHub.addComment(clipId, comment)
                        LiveCommentsWSHub.broadcastComment(comment)
                    } else if (frame is Frame.Close) {
                        break
                    } else {
                        log.debug("[LiveCommentsWS][conn=$connId] unknown text msg clipId=$clipId len=${txt.length}")
                    }
                } else if (frame is Frame.Close) {
                    break
                }
            }
        } catch (e: ClosedReceiveChannelException) {
            log.debug("[LiveCommentsWS][conn=$connId] client closed clipId=$clipId")
        } catch (t: Throwable) {
            log.debug("[LiveCommentsWS][conn=$connId] error: ${t.message}")
        } finally {
            LiveCommentsWSHub.unregister(this)
            log.info("[LiveCommentsWS][conn=$connId] client disconnected clipId=$clipId")
            try { close() } catch (_: Exception) {}
        }
    }
}

private fun commentJson(c: LiveComment): String = buildString {
    append('{')
    append("\"id\":\"${c.id}\",")
    append("\"clipId\":\"${c.clipId}\",")
    append("\"userId\":\"${c.userId}\",")
    append("\"username\":\"${c.username.replace("\"","\\\"")}\",")
    append("\"message\":\"${c.message.replace("\"","\\\"")}\",")
    append("\"timestampEpochSec\":${c.timestampEpochSec}")
    append('}')
}

private fun regexExtract(text: String, pattern: String): String? {
    return Regex(pattern).find(text)?.groupValues?.getOrNull(1)
}
