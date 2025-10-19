package gg.growly

import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import kotlinx.serialization.Serializable

@Serializable
data class ClipDTO(
    val id: String,
    val clip: Clip
)

@Serializable
data class ViewHistoryItem(
    val id: String,
    val viewedAt: Long,
    val clip: ClipDTO
)

@Serializable
data class LikeHistoryItem(
    val id: String,
    val likedAt: Long,
    val clip: ClipDTO
)

@Serializable
data class CommentHistoryItem(
    val id: String,
    val text: String,
    val commentedAt: Long,
    val clip: ClipDTO
)

fun Route.historyRoutes(
    userService: UserService,
    clipService: ClipService,
    viewService: ViewService,
    likeService: LikeService,
    commentService: CommentService
) {
    route("/users/{userId}/history") {
        get("/views") {
            val userId = call.parameters["userId"] ?: return@get call.respond(HttpStatusCode.BadRequest)
            val items = viewService.listByUser(userId)
                .sortedByDescending { it.second.viewedAt }
                .mapNotNull { (id, v) ->
                    val clip = clipService.get(v.clipId) ?: return@mapNotNull null
                    ViewHistoryItem(
                        id = id,
                        viewedAt = v.viewedAt,
                        clip = ClipDTO(id = v.clipId, clip = clip)
                    )
                }
            call.respond(items)
        }

        get("/likes") {
            val userId = call.parameters["userId"] ?: return@get call.respond(HttpStatusCode.BadRequest)
            val items = likeService.listByUser(userId)
                .sortedByDescending { it.second.createdAt }
                .mapNotNull { (id, l) ->
                    val clip = clipService.get(l.clipId) ?: return@mapNotNull null
                    LikeHistoryItem(
                        id = id,
                        likedAt = l.createdAt,
                        clip = ClipDTO(id = l.clipId, clip = clip)
                    )
                }
            call.respond(items)
        }

        get("/comments") {
            val userId = call.parameters["userId"] ?: return@get call.respond(HttpStatusCode.BadRequest)
            val items = commentService.listByUser(userId)
                .sortedByDescending { it.second.createdAt }
                .mapNotNull { (id, c) ->
                    val clip = clipService.get(c.clipId) ?: return@mapNotNull null
                    CommentHistoryItem(
                        id = id,
                        text = c.text,
                        commentedAt = c.createdAt,
                        clip = ClipDTO(id = c.clipId, clip = clip)
                    )
                }
            call.respond(items)
        }
    }
}
