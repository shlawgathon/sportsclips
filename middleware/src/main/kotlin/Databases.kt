package gg.growly

import UserSession
import com.mongodb.client.MongoClients
import com.mongodb.client.MongoDatabase
import gg.growly.services.Env
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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

fun Application.configureDatabases()
{
    val mongoDatabase = connectToMongoDB()

    // TikTok-style services and helpers
    val userService = UserService(mongoDatabase)
    val liveService = LiveVideoService(mongoDatabase)
    val liveGameService = LiveGameService(mongoDatabase)
    val clipService = ClipService(mongoDatabase)
    val commentService = CommentService(mongoDatabase)
    val likeService = LikeService(mongoDatabase)
    val trackedVideoService = TrackedVideoService(mongoDatabase)
    val s3 = S3Helper(this)
    val s3u = gg.growly.services.S3Utility(
        bucketName = "sportsclips-clip-store",
        region = "us-east-1"
    )
    val voyage = VoyageClient(this)
    val youtube = gg.growly.services.YouTubeKtorService(
        Env.getRequired("YOUTUBE_API_KEY")
    )
    val agent = gg.growly.services.AgentClient(this)

    // ========== Periodic YouTube Top Games Collector ==========
    // Every minute, query YouTube for top live videos per sport and catalog them.
    // Keeps LiveGame and TrackedVideo collections fresh with top 10 items per sport.
    run {
        val log = this.log
        val schedulerScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        var schedulerJob: Job? = null
        environment.monitor.subscribe(ApplicationStopped) {
            log.info("[YT-SCHEDULER] Application stopping, cancelling YouTube scheduler if running")
            schedulerJob?.cancel()
        }
        environment.monitor.subscribe(ApplicationStarted) {
            log.info("[YT-SCHEDULER] Starting YouTube top games scheduler")
            schedulerJob = schedulerScope.launch {
                try {
                    while (isActive) {
                        val tickStartedAt = System.currentTimeMillis()
                        try {
                            log.info("[YT-SCHEDULER] Tick started")
                            val sports = Sport.values().filter { it != Sport.All }
                            for (sp in sports) {
                                try {
                                    log.debug("[YT-SCHEDULER] Querying YouTube for sport=${sp.name}")
                                    val resp = youtube.searchLiveSports("${sp.name} live", 10)
                                    log.info("[YT-SCHEDULER] sport=${sp.name} fetched=${resp.items.size}")
                                    resp.items.forEach { item ->
                                        val videoId = item.id.videoId
                                        val title = item.snippet.title
                                        val sourceUrl = "https://www.youtube.com/watch?v=$videoId"
                                        log.debug("[YT-SCHEDULER] Processing item sport=${sp.name} videoId=$videoId title='${title}'")
                                        // Ensure game exists/upsert
                                        try {
                                            liveGameService.create(LiveGame(gameId = videoId, name = title, sport = sp))
                                            log.debug("[YT-SCHEDULER] Upserted LiveGame videoId=$videoId")
                                        } catch (e: Exception) {
                                            log.debug("[YT-SCHEDULER] LiveGame upsert skipped or failed videoId=$videoId reason=${e.message}")
                                        }
                                        // Track video in catalog as Queued if new
                                        try {
                                            val id = trackedVideoService.upsert(
                                                TrackedVideo(
                                                    youtubeVideoId = videoId,
                                                    sourceUrl = sourceUrl,
                                                    sport = sp,
                                                    gameName = title,
                                                    status = ProcessingStatus.Queued
                                                )
                                            )
                                            log.debug("[YT-SCHEDULER] Upserted TrackedVideo id=$id videoId=$videoId sport=${sp.name}")
                                        } catch (e: Exception) {
                                            log.warn("[YT-SCHEDULER] Failed to upsert TrackedVideo videoId=$videoId sport=${sp.name} reason=${e.message}", e)
                                        }
                                    }
                                } catch (e: Exception) {
                                    // swallow sport-specific errors to keep loop healthy
                                    log.error("[YT-SCHEDULER] Error while querying/processing sport=${sp.name}: ${e.message}", e)
                                }
                            }
                            log.info("[YT-SCHEDULER] Tick completed durationMs=${System.currentTimeMillis() - tickStartedAt}")
                        } catch (e: Exception) {
                            // ignore outer loop errors
                            log.error("[YT-SCHEDULER] Unhandled error in tick: ${e.message}", e)
                        }
                        // Sleep for one minute
                        val sleepMs = 60_000L
                        log.debug("[YT-SCHEDULER] Sleeping for ${sleepMs}ms")
                        kotlinx.coroutines.delay(sleepMs)
                    }
                } catch (e: Exception) {
                    // exiting scheduler
                    log.warn("[YT-SCHEDULER] Scheduler exiting due to exception: ${e.message}", e)
                }
            }
        }
    }

    @Serializable data class RegisterRequest(val username: String, val password: String, val profilePictureBase64: String? = null)
    @Serializable data class LoginRequest(val username: String, val password: String)
    @Serializable data class CreateLiveRequest(val title: String, val description: String, val streamUrl: String, val isLive: Boolean = true)
    @Serializable data class PresignUploadRequest(val key: String, val contentType: String? = null)
    @Serializable data class CreateClipRequest(val s3Key: String, val title: String, val description: String, val gameId: String, val sport: Sport)
    @Serializable data class CreateGameRequest(val gameId: String, val name: String, val sport: Sport)
    @Serializable data class CommentRequest(val text: String)

    // Serializable wrappers for responses
    @Serializable data class LiveListItem(val id: String, val live: LiveVideo)
    @Serializable data class ClipListItem(val id: String, val clip: Clip)
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

            // ========== Games ==========
            post("/games") {
                val body = call.receive<CreateGameRequest>()
                val id = liveGameService.create(LiveGame(gameId = body.gameId, name = body.name, sport = body.sport))
                call.respond(HttpStatusCode.Created, mapOf("id" to id))
            }
            get("/games") {
                val games = liveGameService.listAll().map { (id, game) -> mapOf("id" to id, "game" to game) }
                call.respond(games)
            }
            get("/games/{gameId}") {
                val gid = call.parameters["gameId"] ?: return@get call.respond(HttpStatusCode.BadRequest)
                val game = liveGameService.getByGameId(gid) ?: return@get call.respond(HttpStatusCode.NotFound)
                call.respond(mapOf("id" to game.first, "game" to game.second))
            }

            // ========== Clips ==========
            // Listing endpoints
            get("/clips") {
                val items = clipService.listAll().map { (id, clip) -> ClipListItem(id, clip) }
                call.respond(items)
            }
            get("/clips/by-game/{gameId}") {
                val gid = call.parameters["gameId"] ?: return@get call.respond(HttpStatusCode.BadRequest)
                val items = clipService.listByGame(gid).map { (id, clip) -> ClipListItem(id, clip) }
                call.respond(items)
            }
            get("/clips/by-sport/{sport}") {
                val sportParam = call.parameters["sport"] ?: return@get call.respond(HttpStatusCode.BadRequest)
                val sport = try { Sport.valueOf(sportParam) } catch (_: Exception) {
                    // try case-insensitive
                    Sport.values().firstOrNull { it.name.equals(sportParam, ignoreCase = true) }
                        ?: return@get call.respond(HttpStatusCode.BadRequest, mapOf("error" to "Invalid sport"))
                }
                val items = clipService.listBySport(sport).map { (id, clip) -> ClipListItem(id, clip) }
                call.respond(items)
            }

            // Removed user clip upload endpoints in favor of automated ingestion.
            get("/clips/presign-download/{id}") {
                val id = call.parameters["id"] ?: return@get call.respond(HttpStatusCode.BadRequest)
                val clip = clipService.get(id) ?: return@get call.respond(HttpStatusCode.NotFound)
                val url = s3.directDownloadUrl(clip.s3Key)
                call.respond(mapOf("url" to url))
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

            // ========== Ingestion ==========
            post("/ingest/youtube") {
                val sportParam = call.request.queryParameters["sport"] ?: "All"
                val sport = try { Sport.valueOf(sportParam) } catch (_: Exception) {
                    Sport.values().firstOrNull { it.name.equals(sportParam, ignoreCase = true) } ?: Sport.All
                }

                // Search YouTube live for this sport and pick one video
                val query = if (sport == Sport.All) "sports live" else "${sport.name} live"
                val results = try { youtube.searchLiveSports(query, 1) } catch (e: Exception) {
                    return@post call.respond(HttpStatusCode.BadRequest, mapOf("error" to (e.message ?: "YouTube search failed")))
                }
                val item = results.items.firstOrNull() ?: return@post call.respond(HttpStatusCode.NotFound, mapOf("error" to "No live videos found"))
                val videoId = item.id.videoId
                val sourceUrl = "https://www.youtube.com/watch?v=$videoId"
                val gameName = item.snippet.title

                // Ensure only one processing at a time
                val existing = trackedVideoService.getByYouTubeId(videoId)
                if (existing?.second?.status == ProcessingStatus.Processing) {
                    return@post call.respond(HttpStatusCode.Conflict, mapOf("error" to "Video already processing"))
                }

                // Ensure a game exists for this event
                liveGameService.create(LiveGame(gameId = videoId, name = gameName, sport = sport))

                // Upsert catalog and set to Processing
                trackedVideoService.upsert(TrackedVideo(youtubeVideoId = videoId, sourceUrl = sourceUrl, sport = sport, gameName = gameName, status = ProcessingStatus.Processing))

                // Stream snippets from Agent and persist clips
                var created = 0
                try {
                    agent.processVideo(sourceUrl, isLive = true) { bytes, title, description ->
                        val key = "clips/$videoId/${System.currentTimeMillis()}.mp4"
                        try { s3u.uploadBytes(bytes, key, contentType = "video/mp4") } catch (_: Exception) {}
                        val text = listOfNotNull(title, description).joinToString("\n")
                        val embedding = if (text.isNotBlank()) try { voyage.embed(text) } catch (_: Exception) { null } else null
                        clipService.create(
                            Clip(
                                s3Key = key,
                                title = title ?: gameName,
                                description = description ?: "",
                                gameId = videoId,
                                sport = sport,
                                embedding = embedding
                            )
                        )
                        created++
                    }
                    trackedVideoService.setStatus(videoId, ProcessingStatus.Completed)
                } catch (_: Exception) {
                    trackedVideoService.setStatus(videoId, ProcessingStatus.Error)
                }

                call.respond(HttpStatusCode.Accepted, mapOf("videoId" to videoId, "createdClips" to created))
            }

            get("/catalog") {
                val items = trackedVideoService.listAll().map { (id, tv) -> mapOf("id" to id, "tracked" to tv) }
                call.respond(items)
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
    val uri = "mongodb://localhost:27017/?maxPoolSize=20&w=majority"
    val mongoClient = MongoClients.create(uri)
    val database = mongoClient.getDatabase("sportsclips-v1")

    monitor.subscribe(ApplicationStopped) {
        mongoClient.close()
    }

    return database
}
