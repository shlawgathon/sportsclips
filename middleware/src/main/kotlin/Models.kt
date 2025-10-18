package gg.growly

import com.mongodb.client.MongoCollection
import com.mongodb.client.MongoDatabase
import com.mongodb.client.model.Filters
import com.mongodb.client.model.IndexOptions
import com.mongodb.client.model.Indexes
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.bson.Document
import org.bson.types.ObjectId
import java.security.MessageDigest
import java.time.Instant
import kotlin.math.sqrt

// ===================== MODELS =====================

@Serializable
data class User(
    val username: String,
    val passwordHash: String,
    val profilePictureBase64: String? = null,
    val likedClipIds: List<String> = emptyList()
) {
    fun toDocument(): Document = Document.parse(json.encodeToString(this))

    companion object {
        private val json = Json { ignoreUnknownKeys = true }
        fun fromDocument(document: Document): User = json.decodeFromString(document.toJson())
        fun hashPassword(password: String): String {
            val md = MessageDigest.getInstance("SHA-256")
            val digest = md.digest(password.toByteArray())
            return digest.joinToString("") { "%02x".format(it) }
        }
    }
}

@Serializable
data class LiveVideo(
    val title: String,
    val description: String,
    val streamUrl: String,
    val isLive: Boolean = true,
    val liveChatId: String? = null,
    val createdAt: Long = Instant.now().epochSecond
) {
    fun toDocument(): Document = Document.parse(json.encodeToString(this))

    companion object {
        private val json = Json { ignoreUnknownKeys = true }
        fun fromDocument(document: Document): LiveVideo = json.decodeFromString(document.toJson())
    }
}

@Serializable
enum class Sport {
    All,
    Football,
    Basketball,
    Soccer,
    Baseball,
    Tennis,
    Golf,
    Hockey,
    Boxing,
    MMA,
    Racing
}

@Serializable
data class LiveGame(
    val gameId: String,
    val name: String,
    val sport: Sport,
    val createdAt: Long = Instant.now().epochSecond
) {
    fun toDocument(): Document = Document.parse(json.encodeToString(this))

    companion object {
        private val json = Json { ignoreUnknownKeys = true }
        fun fromDocument(document: Document): LiveGame = json.decodeFromString(document.toJson())
    }
}

@Serializable
data class Clip(
    val s3Key: String,
    val title: String,
    val description: String,
    val gameId: String = "",
    val sport: Sport = Sport.All,
    val likesCount: Int = 0,
    val commentsCount: Int = 0,
    val embedding: List<Double>? = null,
    val createdAt: Long = Instant.now().epochSecond
) {
    fun toDocument(): Document = Document.parse(json.encodeToString(this))

    companion object {
        private val json = Json { ignoreUnknownKeys = true }
        fun fromDocument(document: Document): Clip = json.decodeFromString(document.toJson())
    }
}

@Serializable
data class Comment(
    val clipId: String,
    val userId: String,
    val text: String,
    val createdAt: Long = Instant.now().epochSecond
) {
    fun toDocument(): Document = Document.parse(json.encodeToString(this))

    companion object {
        private val json = Json { ignoreUnknownKeys = true }
        fun fromDocument(document: Document): Comment = json.decodeFromString(document.toJson())
    }
}

@Serializable
data class Like(
    val clipId: String,
    val userId: String,
    val createdAt: Long = Instant.now().epochSecond
) {
    fun toDocument(): Document = Document.parse(json.encodeToString(this))

    companion object {
        private val json = Json { ignoreUnknownKeys = true }
        fun fromDocument(document: Document): Like = json.decodeFromString(document.toJson())
    }
}

// ===================== SERVICES =====================

class UserService(private val database: MongoDatabase) {
    private val collection: MongoCollection<Document>

    init {
        try { database.createCollection("users") } catch (_: Exception) {}
        collection = database.getCollection("users")
        try { collection.createIndex(Indexes.ascending("username"), IndexOptions().unique(true)) } catch (_: Exception) {}
    }

    suspend fun create(username: String, password: String, profilePictureBase64: String?): String = withContext(Dispatchers.IO) {
        val user = User(username = username, passwordHash = User.hashPassword(password), profilePictureBase64 = profilePictureBase64)
        val doc = user.toDocument()
        collection.insertOne(doc)
        doc["_id"].toString()
    }

    suspend fun findByUsername(username: String): Pair<String, User>? = withContext(Dispatchers.IO) {
        val doc = collection.find(Filters.eq("username", username)).first() ?: return@withContext null
        val id = (doc["__id"] ?: doc["_id"]).toString()
        id to User.fromDocument(doc)
    }

    suspend fun verifyCredentials(username: String, password: String): Pair<String, User>? = withContext(Dispatchers.IO) {
        val existing = findByUsername(username) ?: return@withContext null
        val (id, user) = existing
        if (user.passwordHash == User.hashPassword(password)) id to user else null
    }

    suspend fun addLikedClip(userId: String, clipId: String) = withContext(Dispatchers.IO) {
        val filter = Filters.eq("_id", ObjectId(userId))
        val current = collection.find(filter).first() ?: return@withContext
        val user = User.fromDocument(current)
        val updated = user.copy(likedClipIds = (user.likedClipIds + clipId).distinct())
        collection.findOneAndReplace(filter, updated.toDocument())
    }
}

class LiveVideoService(private val database: MongoDatabase) {
    private val collection: MongoCollection<Document>

    init {
        try { database.createCollection("live_videos") } catch (_: Exception) {}
        collection = database.getCollection("live_videos")
    }

    suspend fun listAll(): List<Pair<String, LiveVideo>> = withContext(Dispatchers.IO) {
        collection.find().map { it["_id"].toString() to LiveVideo.fromDocument(it) }.toList()
    }

    suspend fun get(id: String): LiveVideo? = withContext(Dispatchers.IO) {
        collection.find(Filters.eq("_id", ObjectId(id))).first()?.let(LiveVideo::fromDocument)
    }

    suspend fun create(live: LiveVideo): String = withContext(Dispatchers.IO) {
        val doc = live.toDocument()
        collection.insertOne(doc)
        doc["_id"].toString()
    }
}

class LiveGameService(private val database: MongoDatabase) {
    private val collection: MongoCollection<Document>

    init {
        try { database.createCollection("live_games") } catch (_: Exception) {}
        collection = database.getCollection("live_games")
        try { collection.createIndex(Indexes.ascending("gameId"), IndexOptions().unique(true)) } catch (_: Exception) {}
        try { collection.createIndex(Indexes.ascending("sport")) } catch (_: Exception) {}
    }

    suspend fun create(game: LiveGame): String = withContext(Dispatchers.IO) {
        val existing = collection.find(Filters.eq("gameId", game.gameId)).first()
        if (existing != null) return@withContext existing["_id"].toString()
        val doc = game.toDocument()
        collection.insertOne(doc)
        doc["_id"].toString()
    }

    suspend fun getByGameId(gameId: String): Pair<String, LiveGame>? = withContext(Dispatchers.IO) {
        val doc = collection.find(Filters.eq("gameId", gameId)).first() ?: return@withContext null
        doc["_id"].toString() to LiveGame.fromDocument(doc)
    }

    suspend fun listAll(): List<Pair<String, LiveGame>> = withContext(Dispatchers.IO) {
        collection.find().map { it["_id"].toString() to LiveGame.fromDocument(it) }.toList()
    }
}

class ClipService(private val database: MongoDatabase) {
    private val collection: MongoCollection<Document>

    init {
        try { database.createCollection("clips") } catch (_: Exception) {}
        collection = database.getCollection("clips")
        try { collection.createIndex(Indexes.ascending("sport")) } catch (_: Exception) {}
        try { collection.createIndex(Indexes.ascending("gameId")) } catch (_: Exception) {}
        try { collection.createIndex(Indexes.descending("createdAt")) } catch (_: Exception) {}
    }

    suspend fun create(clip: Clip): String = withContext(Dispatchers.IO) {
        val doc = clip.toDocument()
        collection.insertOne(doc)
        doc["_id"].toString()
    }

    suspend fun get(id: String): Clip? = withContext(Dispatchers.IO) {
        collection.find(Filters.eq("_id", ObjectId(id))).first()?.let(Clip::fromDocument)
    }

    suspend fun incLikeAndComments(id: String, likeDelta: Int = 0, commentDelta: Int = 0) = withContext(Dispatchers.IO) {
        val filter = Filters.eq("_id", ObjectId(id))
        val doc = collection.find(filter).first() ?: return@withContext
        val clip = Clip.fromDocument(doc)
        val updated = clip.copy(
            likesCount = (clip.likesCount + likeDelta).coerceAtLeast(0),
            commentsCount = (clip.commentsCount + commentDelta).coerceAtLeast(0)
        )
        collection.findOneAndReplace(filter, updated.toDocument())
    }

    suspend fun listAll(): List<Pair<String, Clip>> = withContext(Dispatchers.IO) {
        collection.find().map { it["_id"].toString() to Clip.fromDocument(it) }.toList()
    }

    suspend fun listByGame(gameId: String): List<Pair<String, Clip>> = withContext(Dispatchers.IO) {
        collection.find(Filters.eq("gameId", gameId)).map { it["_id"].toString() to Clip.fromDocument(it) }.toList()
    }

    suspend fun listBySport(sport: Sport): List<Pair<String, Clip>> = withContext(Dispatchers.IO) {
        collection.find(Filters.eq("sport", sport.name)).map { it["_id"].toString() to Clip.fromDocument(it) }.toList()
    }

    suspend fun updateEmbedding(id: String, embedding: List<Double>) = withContext(Dispatchers.IO) {
        val filter = Filters.eq("_id", ObjectId(id))
        val doc = collection.find(filter).first() ?: return@withContext
        val clip = Clip.fromDocument(doc)
        val updated = clip.copy(embedding = embedding)
        collection.findOneAndReplace(filter, updated.toDocument())
    }
}

class CommentService(private val database: MongoDatabase) {
    private val collection: MongoCollection<Document>

    init {
        try { database.createCollection("comments") } catch (_: Exception) {}
        collection = database.getCollection("comments")
    }

    suspend fun add(comment: Comment): String = withContext(Dispatchers.IO) {
        val doc = comment.toDocument()
        collection.insertOne(doc)
        doc["_id"].toString()
    }

    suspend fun listByClip(clipId: String): List<Pair<String, Comment>> = withContext(Dispatchers.IO) {
        collection.find(Filters.eq("clipId", clipId)).map { it["_id"].toString() to Comment.fromDocument(it) }.toList()
    }
}

class LikeService(private val database: MongoDatabase) {
    private val collection: MongoCollection<Document>

    init {
        try { database.createCollection("likes") } catch (_: Exception) {}
        collection = database.getCollection("likes")
        try { collection.createIndex(Indexes.compoundIndex(Indexes.ascending("clipId"), Indexes.ascending("userId")), IndexOptions().unique(true)) } catch (_: Exception) {}
    }

    suspend fun add(like: Like): String? = withContext(Dispatchers.IO) {
        val doc = like.toDocument()
        return@withContext try {
            collection.insertOne(doc)
            doc["_id"].toString()
        } catch (_: Exception) {
            null
        }
    }
}

// ===================== RECOMMENDATION HELPERS =====================

object Recommender {
    fun cosineSimilarity(a: List<Double>, b: List<Double>): Double {
        if (a.isEmpty() || b.isEmpty() || a.size != b.size) return 0.0
        var dot = 0.0
        var na = 0.0
        var nb = 0.0
        for (i in a.indices) {
            val x = a[i]
            val y = b[i]
            dot += x * y
            na += x * x
            nb += y * y
        }
        return if (na == 0.0 || nb == 0.0) 0.0 else dot / (sqrt(na) * sqrt(nb))
    }
}

// ===================== CATALOG (TRACKED VIDEOS) =====================

@Serializable
data class TrackedVideo(
    val youtubeVideoId: String,
    val sourceUrl: String,
    val sport: Sport,
    val gameName: String,
    val status: ProcessingStatus = ProcessingStatus.Queued,
    val lastProcessedAt: Long? = null,
    val createdAt: Long = Instant.now().epochSecond
) {
    fun toDocument(): Document = Document.parse(json.encodeToString(this))

    companion object {
        private val json = Json { ignoreUnknownKeys = true }
        fun fromDocument(document: Document): TrackedVideo = json.decodeFromString(document.toJson())
    }
}

@Serializable
enum class ProcessingStatus { Queued, Processing, Completed, Error }

class TrackedVideoService(private val database: MongoDatabase) {
    private val collection: MongoCollection<Document>

    init {
        try { database.createCollection("tracked_videos") } catch (_: Exception) {}
        collection = database.getCollection("tracked_videos")
        try { collection.createIndex(Indexes.ascending("youtubeVideoId"), IndexOptions().unique(true)) } catch (_: Exception) {}
        try { collection.createIndex(Indexes.ascending("status")) } catch (_: Exception) {}
        try { collection.createIndex(Indexes.ascending("sport")) } catch (_: Exception) {}
    }

    suspend fun upsert(tv: TrackedVideo): String = withContext(Dispatchers.IO) {
        val existing = collection.find(Filters.eq("youtubeVideoId", tv.youtubeVideoId)).first()
        if (existing != null) {
            val id = existing["_id"].toString()
            val current = TrackedVideo.fromDocument(existing)
            val updated = current.copy(
                sourceUrl = tv.sourceUrl,
                sport = tv.sport,
                gameName = tv.gameName,
                status = tv.status,
                lastProcessedAt = tv.lastProcessedAt ?: current.lastProcessedAt
            )
            collection.findOneAndReplace(Filters.eq("_id", ObjectId(id)), updated.toDocument())
            id
        } else {
            val doc = tv.toDocument()
            collection.insertOne(doc)
            doc["_id"].toString()
        }
    }

    suspend fun setStatus(youtubeVideoId: String, status: ProcessingStatus) = withContext(Dispatchers.IO) {
        val existing = collection.find(Filters.eq("youtubeVideoId", youtubeVideoId)).first() ?: return@withContext
        val id = existing["_id"].toString()
        val current = TrackedVideo.fromDocument(existing)
        val updated = current.copy(status = status, lastProcessedAt = if (status == ProcessingStatus.Completed) Instant.now().epochSecond else current.lastProcessedAt)
        collection.findOneAndReplace(Filters.eq("_id", ObjectId(id)), updated.toDocument())
    }

    suspend fun getByYouTubeId(youtubeVideoId: String): Pair<String, TrackedVideo>? = withContext(Dispatchers.IO) {
        val doc = collection.find(Filters.eq("youtubeVideoId", youtubeVideoId)).first() ?: return@withContext null
        doc["_id"].toString() to TrackedVideo.fromDocument(doc)
    }

    suspend fun listAll(): List<Pair<String, TrackedVideo>> = withContext(Dispatchers.IO) {
        collection.find().map { it["_id"].toString() to TrackedVideo.fromDocument(it) }.toList()
    }
}
