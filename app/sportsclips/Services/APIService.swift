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
    
    func fetchVideos(page: Int = 1, limit: Int = 10) async throws -> [VideoClip] {
        do {
            // For now, we'll use mock data since we don't have a clips list endpoint
            // In a real implementation, you'd call something like:
            // let clips = try await apiClient.listClips()
            // return clips.map { convertClipToVideoClip($0) }
            
            // Simulate network delay
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            return VideoClip.mockArray
        } catch {
            print("Failed to fetch videos: \(error)")
            // Return mock data as fallback
            return VideoClip.mockArray
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
    
    func fetchUserProfile(userId: String) async throws -> UserProfile {
        // TODO: Implement actual API call
        /*
        let url = URL(string: "\(baseURL)/users/\(userId)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(UserProfile.self, from: data)
        */
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        return UserProfile(
            id: userId,
            username: "testuser",
            email: "test@example.com",
            sessionToken: "mock_session_token",
            isLoggedIn: true,
            lastLoginAt: Date()
        )
    }
}

// MARK: - API Response Models
private struct VideoResponse: Codable {
    let videos: [VideoClip]
    let hasMore: Bool
    let nextPage: Int?
}
