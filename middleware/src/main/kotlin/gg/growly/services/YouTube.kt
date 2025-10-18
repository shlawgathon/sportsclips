package gg.growly.services

import io.ktor.client.*
import io.ktor.client.call.*
import io.ktor.client.engine.cio.*
import io.ktor.client.plugins.contentnegotiation.*
import io.ktor.client.request.*
import io.ktor.client.statement.bodyAsText
import io.ktor.serialization.kotlinx.json.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

class YouTubeKtorService(private val apiKey: String) {
    private val client = HttpClient(CIO) {
        install(ContentNegotiation) {
            json(Json {
                ignoreUnknownKeys = true
                isLenient = true
            })
        }
    }

    suspend fun searchLiveSports(
        query: String = "sports",
        maxResults: Int = 25
    ): YouTubeSearchResponse {
        return client.get("https://www.googleapis.com/youtube/v3/search") {
            parameter("part", "snippet")
            parameter("eventType", "live")
            parameter("type", "video")
            parameter("videoCategoryId", "17")  // Sports category
            parameter("q", query)
            parameter("maxResults", maxResults)
            parameter("order", "viewCount")
            parameter("key", apiKey)
        }.body()
    }

    suspend fun getVideoDetails(videoIds: List<String>): YouTubeVideoDetailsResponse {
        return client.get("https://www.googleapis.com/youtube/v3/videos") {
            parameter("part", "snippet,statistics,liveStreamingDetails")
            parameter("id", videoIds.joinToString(","))
            parameter("key", apiKey)
        }.body()
    }

    suspend fun searchMultipleSports(): Map<String, List<YouTubeSearchItem>> {
        val sports = listOf("NBA", "NFL", "Premier League", "MLB", "NHL", "UFC")

        return sports.associateWith { sport ->
            try {
                searchLiveSports("$sport live", 10).items
            } catch (e: Exception) {
                println("Error searching $sport: ${e.message}")
                emptyList()
            }
        }
    }

    fun close() {
        client.close()
    }
}

// Data Classes for YouTube API Responses
@Serializable
data class YouTubeSearchResponse(
    val kind: String? = null,
    val etag: String? = null,
    val nextPageToken: String? = null,
    val prevPageToken: String? = null,
    val regionCode: String? = null,
    val pageInfo: PageInfo? = null,
    val items: List<YouTubeSearchItem> = emptyList()
)

@Serializable
data class YouTubeSearchItem(
    val kind: String? = null,
    val etag: String? = null,
    val id: VideoId,
    val snippet: Snippet
)

@Serializable
data class VideoId(
    val kind: String? = null,
    val videoId: String
)

@Serializable
data class Snippet(
    val publishedAt: String? = null,
    val channelId: String,
    val title: String,
    val description: String,
    val thumbnails: Thumbnails? = null,
    val channelTitle: String,
    val liveBroadcastContent: String? = null,
    val publishTime: String? = null
)

@Serializable
data class Thumbnails(
    val default: Thumbnail? = null,
    val medium: Thumbnail? = null,
    val high: Thumbnail? = null,
    val standard: Thumbnail? = null,
    val maxres: Thumbnail? = null
)

@Serializable
data class Thumbnail(
    val url: String,
    val width: Int? = null,
    val height: Int? = null
)

@Serializable
data class PageInfo(
    val totalResults: Int,
    val resultsPerPage: Int
)

// For video details request
@Serializable
data class YouTubeVideoDetailsResponse(
    val kind: String? = null,
    val etag: String? = null,
    val items: List<YouTubeVideoDetail> = emptyList()
)

@Serializable
data class YouTubeVideoDetail(
    val kind: String? = null,
    val etag: String? = null,
    val id: String,
    val snippet: Snippet? = null,
    val statistics: Statistics? = null,
    val liveStreamingDetails: LiveStreamingDetails? = null
)

@Serializable
data class Statistics(
    val viewCount: String? = null,
    val likeCount: String? = null,
    val dislikeCount: String? = null,
    val favoriteCount: String? = null,
    val commentCount: String? = null
)

@Serializable
data class LiveStreamingDetails(
    val actualStartTime: String? = null,
    val actualEndTime: String? = null,
    val scheduledStartTime: String? = null,
    val scheduledEndTime: String? = null,
    val concurrentViewers: String? = null,
    val activeLiveChatId: String? = null
)
