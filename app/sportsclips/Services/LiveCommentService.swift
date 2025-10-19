//
//  LiveCommentService.swift
//  sportsclips
//
//  Service for managing live comments with mock data and local functionality
//

import Foundation
import Combine
import SwiftUI

@MainActor
class LiveCommentService: ObservableObject {
    static let shared = LiveCommentService()
    
    @Published var comments: [LiveComment] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let localStorage = LocalStorageService.shared
    private var currentLiveId: String?
    private var commentTimer: Timer?
    private var mockCommentIndex = 0
    
    private init() {}
    
    // MARK: - Public Methods
    
    func startCommentStream(for liveId: String) {
        currentLiveId = liveId
        loadComments()
        startPeriodicRefresh()
    }
    
    func stopCommentStream() {
        commentTimer?.invalidate()
        commentTimer = nil
        currentLiveId = nil
    }
    
    func postComment(_ text: String) async {
        // Create and add user's comment immediately at the end (most recent)
        let userComment = createUserComment(text: text)
        comments.append(userComment)
        
        // Keep only the most recent 8 comments
        if comments.count > 8 {
            comments = Array(comments.suffix(8))
        }
        
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        
        // In a real implementation, this would be sent to API
        print("Posted comment: \(text)")
    }
    
    // MARK: - Private Methods
    
    private func loadComments() {
        guard currentLiveId != nil else { return }
        
        isLoading = true
        error = nil
        
        // Simulate network delay
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
            
            await MainActor.run {
                self.comments = self.getMockComments()
                self.isLoading = false
            }
        }
    }
    
    private func startPeriodicRefresh() {
        // Don't start a new timer if one is already running
        guard commentTimer == nil else { 
            print("Timer already running, skipping start")
            return 
        }
        
        print("Starting comment timer")
        commentTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.addNewMockComment()
            }
        }
    }
    
    private func getMockComments() -> [LiveComment] {
        let mockComments = LiveComment.mockComments
        return Array(mockComments.prefix(3)) // Start with first 3 comments
    }
    
    private func addNewMockComment() {
        let allMockComments = LiveComment.mockComments
        
        guard !allMockComments.isEmpty else { 
            print("No mock comments available")
            return 
        }
        
        // Cycle through mock comments
        let comment = allMockComments[mockCommentIndex % allMockComments.count]
        mockCommentIndex += 1
        
        print("Adding mock comment: \(comment.message)")
        
        // Update comments - add to the end (most recent)
        comments.append(comment)
        
        // Keep only the most recent 8 comments for continuous flooding
        if comments.count > 8 {
            comments = Array(comments.suffix(8))
        }
        
        print("Total comments now: \(comments.count)")
    }
    
    private func createUserComment(text: String) -> LiveComment {
        let currentUser = localStorage.userProfile
        return LiveComment(
            id: UUID().uuidString,
            userId: currentUser?.id ?? "current_user",
            username: currentUser?.username ?? "You",
            message: text,
            timestamp: Date(),
            isOwnComment: true
        )
    }
}
