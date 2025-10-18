package gg.growly

import UserSession
import com.mongodb.client.MongoClients
import com.mongodb.client.MongoDatabase
import gg.growly.services.S3Helper
import gg.growly.services.VoyageClient
import io.ktor.http.*
import io.ktor.server.application.*
import io.ktor.server.auth.authenticate
import io.ktor.server.config.*
import io.ktor.server.request.*
import io.ktor.server.response.*
import io.ktor.server.routing.*
import io.ktor.server.sessions.*
import kotlinx.serialization.Serializable

fun Application.configureDatabases()
{
    val mongoDatabase = connectToMongoDB()

    // TikTok-style services and helpers
    val userService = UserService(mongoDatabase)
    val liveService = LiveVideoService(mongoDatabase)
    val clipService = ClipService(mongoDatabase)
    val commentService = CommentService(mongoDatabase)
    val likeService = LikeService(mongoDatabase)
    val s3 = S3Helper(this)
    val voyage = VoyageClient(this)

    @Serializable data class RegisterRequest(val username: String, val password: String, val profilePictureBase64: String? = null)
    @Serializable data class LoginRequest(val username: String, val password: String)
    @Serializable data class CreateLiveRequest(val title: String, val description: String, val streamUrl: String, val isLive: Boolean = true)
    @Serializable data class PresignUploadRequest(val key: String, val contentType: String? = null)
    @Serializable data class CreateClipRequest(val s3Key: String, val title: String, val description: String)
    @Serializable data class CommentRequest(val text: String)

    // Serializable wrappers for responses
    @Serializable data class LiveListItem(val id: String, val live: LiveVideo)
    @Serializable data class CommentItem(val id: String, val comment: Comment)
    @Serializable data class RecommendationItem(val id: String, val score: Double, val clip: Clip)

    routing {
        // ========== Auth ==========
        post("/auth/register") {
            val body = call.receive<RegisterRequest>()
            try {
                val id = userService.create(body.username, body.password, body.profilePictureBase64)
                call.respond(HttpStatusCode.Created, mapOf("userId" to id))
            } catch (e: Exception) {
                call.respond(HttpStatusCode.Conflict, mapOf("error" to (e.message ?: "conflict")))
            }
        }
        post("/auth/login") {
            val body = call.receive<LoginRequest>()
            val verified = userService.verifyCredentials(body.username, body.password)
            if (verified != null) {
                val (id, _) = verified
                call.sessions.set(UserSession(id))
                call.respond(mapOf("userId" to id))
            } else {
                call.respond(HttpStatusCode.Unauthorized)
            }
        }
        post("/auth/logout") {
            call.sessions.clear<UserSession>()
            call.respond(HttpStatusCode.OK)
        }

        authenticate {
            // ========== Live Video ==========
            get("/live") {
                val lives = liveService.listAll().map { (id, live) -> LiveListItem(id = id, live = live) }
                call.respond(lives)
            }
            get("/live/{id}") {
                val id = call.parameters["id"] ?: return@get call.respond(HttpStatusCode.BadRequest)
                val live = liveService.get(id) ?: return@get call.respond(HttpStatusCode.NotFound)
                call.respond(live)
            }
            // optional create live
            post("/live") {
                val body = call.receive<CreateLiveRequest>()
                val id = liveService.create(LiveVideo(body.title, body.description, body.streamUrl, body.isLive))
                call.respond(HttpStatusCode.Created, mapOf("id" to id))
            }

            // ========== Clips ==========
            post("/clips/presign-upload") {
                val req = call.receive<PresignUploadRequest>()
                val url = s3.presignUpload(req.key, req.contentType)
                call.respond(mapOf("url" to url, "key" to req.key))
            }
            get("/clips/presign-download/{id}") {
                val id = call.parameters["id"] ?: return@get call.respond(HttpStatusCode.BadRequest)
                val clip = clipService.get(id) ?: return@get call.respond(HttpStatusCode.NotFound)
                val url = s3.directDownloadUrl(clip.s3Key)
                call.respond(mapOf("url" to url))
            }
            post("/clips") {
                val body = call.receive<CreateClipRequest>()
                val text = "${body.title}\n${body.description}"
                val embedding = try { voyage.embed(text) } catch (_: Exception) { null }
                val id = clipService.create(Clip(s3Key = body.s3Key, title = body.title, description = body.description, embedding = embedding))
                call.respond(HttpStatusCode.Created, mapOf("id" to id))
            }
            get("/clips/{id}") {
                val id = call.parameters["id"] ?: return@get call.respond(HttpStatusCode.BadRequest)
                val clip = clipService.get(id) ?: return@get call.respond(HttpStatusCode.NotFound)
                call.respond(clip)
            }
            post("/clips/{id}/like") {
                val id = call.parameters["id"] ?: return@post call.respond(HttpStatusCode.BadRequest)
                val session = call.sessions.get(UserSession::class) as? UserSession
                val userId = session?.userId ?: "anonymous"
                likeService.add(Like(clipId = id, userId = userId))
                clipService.incLikeAndComments(id, likeDelta = 1)
                if (userId != "anonymous") {
                    userService.addLikedClip(userId, id)
                }
                call.respond(HttpStatusCode.OK)
            }
            post("/clips/{id}/comments") {
                val id = call.parameters["id"] ?: return@post call.respond(HttpStatusCode.BadRequest)
                val session = call.sessions.get(UserSession::class) as? UserSession
                val userId = session?.userId ?: "anonymous"
                val body = call.receive<CommentRequest>()
                commentService.add(Comment(clipId = id, userId = userId, text = body.text))
                clipService.incLikeAndComments(id, commentDelta = 1)
                call.respond(HttpStatusCode.Created)
            }
            get("/clips/{id}/comments") {
                val id = call.parameters["id"] ?: return@get call.respond(HttpStatusCode.BadRequest)
                val comments = commentService.listByClip(id).map { (cid, c) -> CommentItem(id = cid, comment = c) }
                call.respond(comments)
            }

            // ========== Recommendations ==========
            get("/clips/{id}/recommendations") {
                val id = call.parameters["id"] ?: return@get call.respond(HttpStatusCode.BadRequest)
                val target = clipService.get(id) ?: return@get call.respond(HttpStatusCode.NotFound)
                val targetEmb = target.embedding ?: return@get call.respond(emptyList<RecommendationItem>())
                val all = clipService.listAll()
                val scored = all.filter { it.first != id && (it.second.embedding != null) }
                    .map { (cid, clip) ->
                        val sim = Recommender.cosineSimilarity(targetEmb, clip.embedding!!)
                        RecommendationItem(id = cid, score = sim, clip = clip)
                    }
                    .sortedByDescending { it.score }
                    .take(10)
                call.respond(scored)
            }
        }
    }
}

/**
 * Establishes connection with a MongoDB database.
 *
 * The following configuration properties (in application.yaml/application.conf) can be specified:
 * * `db.mongo.user` username for your database
 * * `db.mongo.password` password for the user
 * * `db.mongo.host` host that will be used for the database connection
 * * `db.mongo.port` port that will be used for the database connection
 * * `db.mongo.maxPoolSize` maximum number of connections to a MongoDB server
 * * `db.mongo.database.name` name of the database
 *
 * IMPORTANT NOTE: in order to make MongoDB connection working, you have to start a MongoDB server first.
 * See the instructions here: https://www.mongodb.com/docs/manual/administration/install-community/
 * all the paramaters above
 *
 * @returns [MongoDatabase] instance
 * */
fun Application.connectToMongoDB(): MongoDatabase
{
    val user = environment.config.tryGetString("db.mongo.user")
    val password = environment.config.tryGetString("db.mongo.password")
    val host = environment.config.tryGetString("db.mongo.host") ?: "127.0.0.1"
    val port = environment.config.tryGetString("db.mongo.port") ?: "27017"
    val maxPoolSize = environment.config.tryGetString("db.mongo.maxPoolSize")?.toInt() ?: 20
    val databaseName = environment.config.tryGetString("db.mongo.database.name") ?: "myDatabase"

    val credentials = user?.let { userVal -> password?.let { passwordVal -> "$userVal:$passwordVal@" } }.orEmpty()
    val uri = "mongodb://$credentials$host:$port/?maxPoolSize=$maxPoolSize&w=majority"

    val mongoClient = MongoClients.create(uri)
    val database = mongoClient.getDatabase(databaseName)

    monitor.subscribe(ApplicationStopped) {
        mongoClient.close()
    }

    return database
}
