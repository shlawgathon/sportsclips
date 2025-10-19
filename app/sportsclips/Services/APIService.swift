//
//  APIService.swift
//  sportsclips
//
//  Network layer for video API integration
//

import Foundation

@MainActor
class APIService {
    static let shared = APIService()

    private let apiClient = APIClient.shared

    private init() {}

    struct FeedPage {
        let videos: [VideoClip]
        let nextCursor: Int64?
    }

    func fetchFeedPage(limit: Int = 10, cursor: Int64? = nil, sport: APIClient.APISport? = nil) async throws -> FeedPage {
        let resp = try await apiClient.fetchFeed(limit: limit, cursor: cursor, sport: sport)
        // Map FeedItem -> VideoClip with presigned URLs
        let items = resp.items
        let clips: [VideoClip] = try await withThrowingTaskGroup(of: VideoClip.self) { group in
            for item in items {
                group.addTask {
                    var model = VideoClip.fromClip(item.clip, clipId: item.id)
                    let url = try await model.fetchVideoURL()
                    return VideoClip(
                        id: model.id,
                        videoURL: url,
                        caption: model.caption,
                        sport: model.sport,
                        likes: model.likes,
                        comments: model.comments,
                        shares: model.shares,
                        createdAt: model.createdAt,
                        s3Key: model.s3Key,
                        title: model.title,
                        description: model.description,
                        gameId: model.gameId
                    )
                }
            }
            var results: [VideoClip] = []
            for try await vc in group { results.append(vc) }
            return results
        }
        return FeedPage(videos: clips, nextCursor: resp.nextCursor)
    }

    func markViewed(clipId: String) async {
        do { try await apiClient.markViewed(clipId: clipId) } catch {
            // non-fatal; rely on local storage fallback
            print("Failed to mark viewed: \(error)")
        }
    }

    func fetchVideos(page: Int = 1, limit: Int = 10) async throws -> [VideoClip] {
        do {
            // Fetch clips from middleware API
            let items = try await apiClient.listClips()
            // Apply simple pagination client-side until API supports it
            let start = max(0, (page - 1) * limit)
            let end = min(items.count, start + limit)
            guard start < end else { return [] }
            let slice = Array(items[start..<end])

            // Map to VideoClip models and fetch presigned URLs concurrently
            return try await withThrowingTaskGroup(of: VideoClip.self) { group in
                for item in slice {
                    group.addTask {
                        // Convert to app model
                        var clipModel = VideoClip.fromClip(item.clip, clipId: item.id)
                        // Fetch presigned URL
                        let url = try await clipModel.fetchVideoURL()
                        // Return new instance with actual URL
                        return VideoClip(
            id: clipModel.id,
            videoURL: url,
            caption: clipModel.caption,
            sport: clipModel.sport,
            likes: clipModel.likes,
            comments: clipModel.comments,
            shares: clipModel.shares,
            createdAt: clipModel.createdAt,
            s3Key: clipModel.s3Key,
            title: clipModel.title,
            description: clipModel.description,
            gameId: clipModel.gameId
        )
                    }
                }

                var results: [VideoClip] = []
                results.reserveCapacity(slice.count)
                for try await vc in group { results.append(vc) }
                // Preserve original order by sorting back using slice order
                let order = slice.enumerated().reduce(into: [String: Int]()) { acc, pair in acc[pair.element.id] = pair.offset }
                results.sort { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
                return results
            }
        } catch {
            print("Failed to fetch videos: \(error)")
            throw error
        }
    }

    /// Fetch a specific clip by ID and return a VideoClip with the presigned video URL
    func fetchVideoClip(clipId: String) async throws -> VideoClip {
        do {
            // Fetch clip details from API
            let clip = try await apiClient.getClip(id: clipId)

            // Convert to VideoClip
            let videoClip = VideoClip.fromClip(clip, clipId: clipId)

            // Fetch presigned download URL
            let videoURL = try await videoClip.fetchVideoURL()

            // Create new VideoClip with the actual video URL
            return VideoClip(
                id: videoClip.id,
                videoURL: videoURL,
                caption: videoClip.caption,
                sport: videoClip.sport,
                likes: videoClip.likes,
                comments: videoClip.comments,
                shares: videoClip.shares,
                createdAt: videoClip.createdAt,
                s3Key: videoClip.s3Key,
                title: videoClip.title,
                description: videoClip.description,
                gameId: videoClip.gameId
            )
        } catch {
            print("Failed to fetch video clip \(clipId): \(error)")
            throw error
        }
    }

    func likeVideo(clipId: String) async throws {
        do {
            try await apiClient.likeClip(id: clipId)
        } catch {
            print("Failed to like video: \(error)")
            throw error
        }
    }

    func unlikeVideo(clipId: String) async throws {
        do {
            try await apiClient.unlikeClip(id: clipId)
        } catch {
            print("Failed to unlike video: \(error)")
            throw error
        }
    }

    func postComment(clipId: String, text: String) async throws {
        do {
            try await apiClient.postComment(clipId: clipId, text: text)
        } catch {
            print("Failed to post comment: \(error)")
            throw error
        }
    }

    func getComments(clipId: String) async throws -> [CommentItem] {
        do {
            return try await apiClient.listComments(clipId: clipId)
        } catch {
            print("Failed to fetch comments: \(error)")
            throw error
        }
    }

    func getRecommendations(clipId: String) async throws -> [RecommendationItem] {
        do {
            return try await apiClient.recommendations(clipId: clipId)
        } catch {
            print("Failed to fetch recommendations: \(error)")
            throw error
        }
    }

}

// MARK: - API Response Models
private struct VideoResponse: Codable {
    let videos: [VideoClip]
    let hasMore: Bool
    let nextPage: Int?
}
