//
//  LocalStorageService.swift
//  sportsclips
//
//  Local storage for user interactions and view history
//

import Foundation
import Combine

struct VideoInteraction: Codable, Equatable, Hashable {
    let videoId: String
    let liked: Bool
    let commented: Bool
    let shared: Bool
    let viewedAt: Date
    let viewDuration: TimeInterval
}

struct UserProfile: Codable {
    let id: String
    var username: String
    let email: String
    let sessionToken: String
    let isLoggedIn: Bool
    let lastLoginAt: Date?
    var profilePictureBase64: String?
}

@MainActor
class LocalStorageService: ObservableObject {
    static let shared = LocalStorageService()

    @Published var userProfile: UserProfile?
    @Published var interactions: [VideoInteraction] = []
    @Published var viewHistory: [String] = [] // Video IDs in order of viewing
    
    // Category memory preferences
    @Published var rememberHighlightsCategory: Bool = false {
        didSet {
            userDefaults.set(rememberHighlightsCategory, forKey: "remember_highlights_category")
        }
    }
    @Published var rememberLiveCategory: Bool = false {
        didSet {
            userDefaults.set(rememberLiveCategory, forKey: "remember_live_category")
        }
    }
    
    // Last selected categories
    @Published var lastHighlightsCategory: String = "all" {
        didSet {
            userDefaults.set(lastHighlightsCategory, forKey: "last_highlights_category")
        }
    }
    @Published var lastLiveCategory: String = "all" {
        didSet {
            userDefaults.set(lastLiveCategory, forKey: "last_live_category")
        }
    }
    
    // Navigation state for comment history
    @Published var navigateToVideoId: String? = nil
    @Published var navigateToCommentId: String? = nil
    @Published var shouldOpenComments: Bool = false

    private let userDefaults = UserDefaults.standard
    private let interactionsKey = "video_interactions"
    private let profileKey = "user_profile"
    private let historyKey = "view_history"
    private let rememberHighlightsKey = "remember_highlights_category"
    private let rememberLiveKey = "remember_live_category"
    private let lastHighlightsKey = "last_highlights_category"
    private let lastLiveKey = "last_live_category"
    private let maxLocalInteractions = 10

    private init() {
        loadData()
    }

    // MARK: - User Profile Management
    func saveUserSession(userId: String, username: String, email: String, sessionToken: String) {
        let profile = UserProfile(
            id: userId,
            username: username,
            email: email,
            sessionToken: sessionToken,
            isLoggedIn: true,
            lastLoginAt: Date(),
            profilePictureBase64: nil
        )
        userProfile = profile
        saveProfile()
    }

    func updateUsername(_ newUsername: String) {
        guard var profile = userProfile else { return }
        profile.username = newUsername
        userProfile = profile
        saveProfile()
        forceRefresh()
    }

    func updateProfilePicture(_ base64: String?) {
        guard var profile = userProfile else { return }
        profile.profilePictureBase64 = base64
        userProfile = profile
        saveProfile()
        forceRefresh()
    }
    
    func isUserLoggedIn() -> Bool {
        return userProfile?.isLoggedIn == true
    }

    func logout() {
        // Force stop all video playback before logging out
        VideoPlayerManager.shared.forceStopAllPlayback()
        LiveVideoManager.shared.forceStopAllLivePlayback()
        
        userProfile = nil
        saveProfile()
    }

    // MARK: - Video Interactions
    func recordInteraction(videoId: String, liked: Bool = false, commented: Bool = false, shared: Bool = false, viewDuration: TimeInterval = 0) {
        let interaction = VideoInteraction(
            videoId: videoId,
            liked: liked,
            commented: commented,
            shared: shared,
            viewedAt: Date(),
            viewDuration: viewDuration
        )

        // Remove existing interaction for this video
        interactions.removeAll { $0.videoId == videoId }

        // Add new interaction
        interactions.append(interaction)

        // Keep only the most recent interactions locally
        if interactions.count > maxLocalInteractions {
            let sortedInteractions = interactions.sorted { $0.viewedAt > $1.viewedAt }
            interactions = Array(sortedInteractions.prefix(maxLocalInteractions))
        }

        saveInteractions()

        // Force UI update by triggering objectWillChange
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        print("🔄 LocalStorageService: Recorded interaction for video \(videoId) - liked: \(liked), commented: \(commented), shared: \(shared)")
    }

    func recordView(videoId: String) {
        // Remove from history if already exists
        viewHistory.removeAll { $0 == videoId }

        // Add to beginning of history
        viewHistory.insert(videoId, at: 0)

        // Keep only last 50 views
        if viewHistory.count > 50 {
            viewHistory = Array(viewHistory.prefix(50))
        }

        saveHistory()

        // Force UI update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }

        print("🔄 LocalStorageService: Recorded view for video \(videoId)")
    }

    func getInteraction(for videoId: String) -> VideoInteraction? {
        return interactions.first { $0.videoId == videoId }
    }

    func isLiked(videoId: String) -> Bool {
        return getInteraction(for: videoId)?.liked ?? false
    }

    // MARK: - State Refresh
    func forceRefresh() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        print("🔄 LocalStorageService: Forced state refresh")
    }

    // MARK: - Data Persistence
    private func loadData() {
        loadProfile()
        loadInteractions()
        loadHistory()
        loadPreferences()
    }

    private func loadProfile() {
        if let data = userDefaults.data(forKey: profileKey),
           let profile = try? JSONDecoder().decode(UserProfile.self, from: data) {
            userProfile = profile
        }
    }

    private func saveProfile() {
        if let profile = userProfile,
           let data = try? JSONEncoder().encode(profile) {
            userDefaults.set(data, forKey: profileKey)
        } else {
            userDefaults.removeObject(forKey: profileKey)
        }
    }

    private func loadInteractions() {
        if let data = userDefaults.data(forKey: interactionsKey),
           let interactions = try? JSONDecoder().decode([VideoInteraction].self, from: data) {
            self.interactions = interactions
        }
    }

    private func saveInteractions() {
        if let data = try? JSONEncoder().encode(interactions) {
            userDefaults.set(data, forKey: interactionsKey)
        }
    }

    private func loadHistory() {
        if let history = userDefaults.stringArray(forKey: historyKey) {
            viewHistory = history
        }
    }

    private func saveHistory() {
        userDefaults.set(viewHistory, forKey: historyKey)
    }
    
    private func loadPreferences() {
        rememberHighlightsCategory = userDefaults.bool(forKey: rememberHighlightsKey)
        rememberLiveCategory = userDefaults.bool(forKey: rememberLiveKey)
        lastHighlightsCategory = userDefaults.string(forKey: lastHighlightsKey) ?? "all"
        lastLiveCategory = userDefaults.string(forKey: lastLiveKey) ?? "all"
    }
    
    // MARK: - Category Memory Methods
    func saveLastHighlightsCategory(_ category: String) {
        lastHighlightsCategory = category
    }
    
    func saveLastLiveCategory(_ category: String) {
        lastLiveCategory = category
    }
    
    func getLastHighlightsCategory() -> String {
        return rememberHighlightsCategory ? lastHighlightsCategory : "all"
    }
    
    func getLastLiveCategory() -> String {
        return rememberLiveCategory ? lastLiveCategory : "all"
    }
    
    // MARK: - Navigation Methods
    func navigateToVideoWithComment(videoId: String, commentId: String) {
        navigateToVideoId = videoId
        navigateToCommentId = commentId
        shouldOpenComments = true
    }
    
    func clearNavigation() {
        navigateToVideoId = nil
        navigateToCommentId = nil
        shouldOpenComments = false
    }

    // MARK: - API Sync (for future implementation)
    func syncToAPI() async {
        // TODO: Send interactions to API when user is logged in
        // This would batch send the local interactions to the server
    }

    // MARK: - Profile Refresh from Server
    func refreshProfileFromServer() async {
        guard userProfile != nil else { return }
        do {
            let me = try await APIClient.shared.getMe()
            // Prefer displayName when available; fallback to username from server
            let newDisplayName = me.user.displayName ?? me.user.username
            var profile = self.userProfile!
            profile.username = newDisplayName
            profile.profilePictureBase64 = me.user.profilePictureBase64
            self.userProfile = profile
            saveProfile()
            forceRefresh()
            print("✅ LocalStorageService: Refreshed profile from server")
        } catch {
            print("⚠️ LocalStorageService: Failed to refresh profile from server - \(error)")
        }
    }
}
