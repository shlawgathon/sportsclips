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
    @Published var viewerCount: Int = 0

    private let localStorage = LocalStorageService.shared
    private let apiClient = APIClient.shared

    private var currentLiveId: String?
    private var commentTimer: Timer?
    private var heartbeatTimer: Timer?

    private var mockCommentIndex = 0
    private var lastTimestamp: Int64? = nil
    private var viewerId: String = UUID().uuidString

    private init() {}

    // MARK: - Public Methods

    func startCommentStream(for liveId: String) {
        currentLiveId = liveId
        comments = []
        lastTimestamp = nil
        viewerCount = 0
        loadComments()
        startPeriodicRefresh()
        startHeartbeat()
        // fetch initial viewer info
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let info = try await self.apiClient.liveViewerInfo(clipId: liveId)
                await MainActor.run { self.viewerCount = info.viewers }
            } catch { /* ignore initial failure */ }
        }
    }

    func stopCommentStream() {
        commentTimer?.invalidate()
        commentTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        currentLiveId = nil
        viewerCount = 0
    }

    func postComment(_ text: String) async {
        guard let liveId = currentLiveId else { return }
        let currentUser = localStorage.userProfile
        do {
            let dto = try await apiClient.livePostComment(
                clipId: liveId,
                userId: currentUser?.id ?? "anonymous",
                username: currentUser?.username ?? "You",
                message: text
            )
            let mapped = map(dto: dto)
            comments.append(mapped)
        } catch {
            // Fallback: append locally
            let userComment = createUserComment(text: text)
            comments.append(userComment)
        }
        // Keep a rolling window of last 50
        if comments.count > 50 { comments = Array(comments.suffix(50)) }
        // Update lastTimestamp
        if let last = comments.last {
            lastTimestamp = max(lastTimestamp ?? 0, Int64(last.timestamp.timeIntervalSince1970))
        }
    }

    // MARK: - Private Methods

    private func loadComments() {
        guard let clipId = currentLiveId else { return }
        isLoading = true
        error = nil
        Task {
            do {
                let dtos = try await apiClient.liveFetchComments(clipId: clipId, limit: 10, afterTs: nil)
                let mapped = dtos.map { self.map(dto: $0) }
                await MainActor.run {
                    self.comments = mapped
                    if let last = mapped.last { self.lastTimestamp = Int64(last.timestamp.timeIntervalSince1970) }
                    self.isLoading = false
                }
            } catch {
                // Fallback to a few mock comments on failure
                await MainActor.run {
                    self.comments = self.getMockComments()
                    if let last = self.comments.last { self.lastTimestamp = Int64(last.timestamp.timeIntervalSince1970) }
                    self.isLoading = false
                }
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
            guard let self = self, let clipId = self.currentLiveId else { return }
            Task {
                do {
                    let dtos = try await self.apiClient.liveFetchComments(clipId: clipId, limit: 10, afterTs: self.lastTimestamp)
                    if !dtos.isEmpty {
                        let mapped = dtos.map { self.map(dto: $0) }
                        await MainActor.run {
                            self.comments.append(contentsOf: mapped)
                            if self.comments.count > 50 { self.comments = Array(self.comments.suffix(50)) }
                            if let last = self.comments.last {
                                self.lastTimestamp = max(self.lastTimestamp ?? 0, Int64(last.timestamp.timeIntervalSince1970))
                            }
                        }
                    }
                } catch {
                    // Silently ignore to avoid spamming UI; next tick will retry
                }
            }
        }
    }

    private func getMockComments() -> [LiveComment] {
        let mockComments = LiveComment.mockComments
        return Array(mockComments.prefix(3)) // Start with first 3 comments
    }

    private func addNewMockComment() {
        let allMockComments = LiveComment.mockComments
        guard !allMockComments.isEmpty else { return }
        // Cycle through mock comments
        let comment = allMockComments[mockCommentIndex % allMockComments.count]
        mockCommentIndex += 1
        // Update comments - add to the end (most recent)
        comments.append(comment)
        if comments.count > 50 { comments = Array(comments.suffix(50)) }
        lastTimestamp = Int64(comment.timestamp.timeIntervalSince1970)
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        guard let clipId = currentLiveId else { return }
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task {
                do {
                    let info = try await self.apiClient.liveHeartbeat(clipId: clipId, viewerId: self.viewerId)
                    await MainActor.run { self.viewerCount = info.viewers }
                } catch { /* ignore */ }
            }
        }
        // send immediately once
        Task {
            do {
                let info = try await self.apiClient.liveHeartbeat(clipId: clipId, viewerId: self.viewerId)
                await MainActor.run { self.viewerCount = info.viewers }
            } catch { }
        }
    }

    private func map(dto: APIClient.LiveCommentDTO) -> LiveComment {
        return LiveComment(
            id: dto.id,
            userId: dto.userId,
            username: dto.username,
            message: dto.message,
            timestamp: Date(timeIntervalSince1970: TimeInterval(dto.timestampEpochSec)),
            isOwnComment: dto.userId == localStorage.userProfile?.id
        )
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
