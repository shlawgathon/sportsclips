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
    
    private init() {}
    
    // TODO: Replace with actual API endpoint
    private let baseURL = "YOUR_API_ENDPOINT"
    
    func fetchVideos(page: Int = 1, limit: Int = 10) async throws -> [VideoClip] {
        // For now, return mock data
        // TODO: Implement actual API call
        /*
        let url = URL(string: "\(baseURL)/videos?page=\(page)&limit=\(limit)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(VideoResponse.self, from: data)
        return response.videos
        */
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        return VideoClip.mockArray
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
