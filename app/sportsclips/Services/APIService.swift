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
        do {
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
                            description: model.description
                        )
                    }
                }
                var results: [VideoClip] = []
                for try await vc in group { results.append(vc) }
                return results
            }
            return FeedPage(videos: clips, nextCursor: resp.nextCursor)
        } catch {
            print("Failed to fetch feed from server: \(error)")
            print("Falling back to mock data for UI testing...")
            let mockVideos = generateMockVideos(page: 1, limit: limit)
            return FeedPage(videos: mockVideos, nextCursor: nil)
        }
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
                            description: clipModel.description
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
            print("Failed to fetch videos from server: \(error)")
            print("Falling back to mock data for UI testing...")
            return generateMockVideos(page: page, limit: limit)
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
                description: videoClip.description
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

    // MARK: - Mock Data for UI Testing
    
    private func generateMockVideos(page: Int, limit: Int) -> [VideoClip] {
        let allSports: [VideoClip.Sport] = [.football, .basketball, .soccer, .baseball, .tennis, .hockey, .boxing, .mma, .racing, .golf]
        let mockVideos: [VideoClip] = [
            VideoClip(
                id: "mock-1",
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                caption: "Amazing touchdown catch in the final seconds! 🏈",
                sport: .football,
                likes: 1250,
                comments: 89,
                shares: 45,
                createdAt: Date(),
                s3Key: "mock-1.mp4",
                title: "Incredible Touchdown",
                description: "Last second touchdown catch that won the game"
            ),
            VideoClip(
                id: "mock-2",
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
                caption: "Slam dunk contest winner! 🏀",
                sport: .basketball,
                likes: 2100,
                comments: 156,
                shares: 78,
                createdAt: Date().addingTimeInterval(-3600),
                s3Key: "mock-2.mp4",
                title: "Slam Dunk Champion",
                description: "The most creative dunk of the season"
            ),
            VideoClip(
                id: "mock-3",
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
                caption: "Goal of the year candidate! ⚽",
                sport: .soccer,
                likes: 3200,
                comments: 234,
                shares: 123,
                createdAt: Date().addingTimeInterval(-7200),
                s3Key: "mock-3.mp4",
                title: "World Class Goal",
                description: "Incredible long-range strike from midfield"
            ),
            VideoClip(
                id: "mock-4",
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
                caption: "Home run that broke the record! ⚾",
                sport: .baseball,
                likes: 1800,
                comments: 112,
                shares: 67,
                createdAt: Date().addingTimeInterval(-10800),
                s3Key: "mock-4.mp4",
                title: "Record Breaking Home Run",
                description: "Longest home run in stadium history"
            ),
            VideoClip(
                id: "mock-5",
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4",
                caption: "Ace serve that won the match! 🎾",
                sport: .tennis,
                likes: 950,
                comments: 67,
                shares: 34,
                createdAt: Date().addingTimeInterval(-14400),
                s3Key: "mock-5.mp4",
                title: "Championship Ace",
                description: "Perfect serve to win the championship"
            ),
            VideoClip(
                id: "mock-6",
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4",
                caption: "Hat trick in the playoffs! 🏒",
                sport: .hockey,
                likes: 2800,
                comments: 189,
                shares: 95,
                createdAt: Date().addingTimeInterval(-18000),
                s3Key: "mock-6.mp4",
                title: "Playoff Hat Trick",
                description: "Three goals in one period"
            ),
            VideoClip(
                id: "mock-7",
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4",
                caption: "Knockout punch in round 3! 🥊",
                sport: .boxing,
                likes: 4500,
                comments: 312,
                shares: 156,
                createdAt: Date().addingTimeInterval(-21600),
                s3Key: "mock-7.mp4",
                title: "Devastating Knockout",
                description: "One punch knockout that ended the fight"
            ),
            VideoClip(
                id: "mock-8",
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4",
                caption: "Submission hold that won the title! 🥋",
                sport: .mma,
                likes: 3600,
                comments: 278,
                shares: 134,
                createdAt: Date().addingTimeInterval(-25200),
                s3Key: "mock-8.mp4",
                title: "Championship Submission",
                description: "Perfect triangle choke for the win"
            ),
            VideoClip(
                id: "mock-9",
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4",
                caption: "Overtake on the final lap! 🏎️",
                sport: .racing,
                likes: 2200,
                comments: 145,
                shares: 78,
                createdAt: Date().addingTimeInterval(-28800),
                s3Key: "mock-9.mp4",
                title: "Last Lap Victory",
                description: "Incredible overtake to win the race"
            ),
            VideoClip(
                id: "mock-10",
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/VolkswagenGTIReview.mp4",
                caption: "Eagle on the 18th hole! ⛳",
                sport: .golf,
                likes: 1200,
                comments: 89,
                shares: 45,
                createdAt: Date().addingTimeInterval(-32400),
                s3Key: "mock-10.mp4",
                title: "Tournament Eagle",
                description: "Hole-in-one on the final hole"
            )
        ]
        
        // Apply pagination
        let start = max(0, (page - 1) * limit)
        let end = min(mockVideos.count, start + limit)
        guard start < end else { return [] }
        
        return Array(mockVideos[start..<end])
    }

}

// MARK: - API Response Models
private struct VideoResponse: Codable {
    let videos: [VideoClip]
    let hasMore: Bool
    let nextPage: Int?
}
