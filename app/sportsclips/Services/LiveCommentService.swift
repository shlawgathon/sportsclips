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

    // WebSocket
    private var wsSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: cfg)
    }()
    private var wsTask: URLSessionWebSocketTask?

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
        // Try WebSocket first; fallback to polling if WS connect fails
        connectWebSocket(clipId: liveId)
        startHeartbeat()
        // Also kick an initial HTTP fetch as seed
        loadComments()
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
        wsTask?.cancel(with: .goingAway, reason: nil)
        wsTask = nil
        currentLiveId = nil
        viewerCount = 0
    }

    func postComment(_ text: String) async {
        guard let liveId = currentLiveId else { return }
        let currentUser = localStorage.userProfile
        // Try WS first
        if wsTask != nil {
            sendPostCommentWS(text: text)
        } else {
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
        }
        // Keep a rolling window of last 50
        if comments.count > 50 { comments = Array(comments.suffix(50)) }
        // Update lastTimestamp
        if let last = comments.last {
            lastTimestamp = max(lastTimestamp ?? 0, Int64(last.timestamp.timeIntervalSince1970))
        }
    }

    // MARK: - WebSocket

    private func connectWebSocket(clipId: String) {
        // Build ws/wss URL from APIClient baseURL
        var base = APIClient.shared.baseWebSocketURL()
        base.append(path: "ws/live-comments/\(clipId)")
        let task = wsSession.webSocketTask(with: base)
        wsTask = task
        task.resume()
        // Start listening
        listen()
    }

    private func listen() {
        wsTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                // Fallback to HTTP polling if WS fails
                self.startPeriodicRefresh()
            case .success(let msg):
                switch msg {
                case .string(let text):
                    self.handleWSMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) { self.handleWSMessage(text) }
                @unknown default:
                    break
                }
                // continue
                self.listen()
            }
        }
    }

    private func handleWSMessage(_ text: String) {
        // Very light parsing by type substring, then JSON decode to simple structs
        guard let typeRange = text.range(of: "\"type\":\"") else { return }
        let after = text[typeRange.upperBound...]
        guard let end = after.firstIndex(of: "\"") else { return }
        let type = String(after[..<end])
        if type == "init" {
            // parse {comments:[], viewer_count:int}
            struct InitPayload: Decodable {
                struct DataModel: Decodable {
                    let comments: [APIClient.LiveCommentDTO]
                    let viewer_count: Int
                }
                let type: String
                let data: DataModel
            }
            if let data = try? JSONDecoder().decode(InitPayload.self, from: Data(text.utf8)) {
                let mapped = data.data.comments.map { self.map(dto: $0) }
                self.comments = mapped
                self.viewerCount = data.data.viewer_count
                if let last = mapped.last { self.lastTimestamp = Int64(last.timestamp.timeIntervalSince1970) }
            }
        } else if type == "comment" {
            struct CommentPayload: Decodable {
                struct DataModel: Decodable {
                    let id: String
                    let clipId: String
                    let userId: String
                    let username: String
                    let message: String
                    let timestampEpochSec: Int64
                }
                let type: String
                let data: DataModel
            }
            if let data = try? JSONDecoder().decode(CommentPayload.self, from: Data(text.utf8)) {
                let dto = APIClient.LiveCommentDTO(id: data.data.id, clipId: data.data.clipId, userId: data.data.userId, username: data.data.username, message: data.data.message, timestampEpochSec: data.data.timestampEpochSec)
                let mapped = self.map(dto: dto)
                self.comments.append(mapped)
                if self.comments.count > 50 { self.comments = Array(self.comments.suffix(50)) }
                if let last = self.comments.last { self.lastTimestamp = max(self.lastTimestamp ?? 0, Int64(last.timestamp.timeIntervalSince1970)) }
            }
        } else if type == "viewer_count" {
            struct ViewerPayload: Decodable {
                struct DataModel: Decodable {
                    let clipId: String
                    let viewers: Int
                }
                let type: String
                let data: DataModel
            }
            if let data = try? JSONDecoder().decode(ViewerPayload.self, from: Data(text.utf8)) {
                self.viewerCount = data.data.viewers
            }
        } else if type == "error" {
            self.error = text
        }
    }

    func sendPostCommentWS(text: String) {
        guard let wsTask else { return }
        let currentUser = localStorage.userProfile
        let payload: [String: Any] = [
            "type": "post_comment",
            "userId": currentUser?.id ?? "anonymous",
            "username": currentUser?.username ?? "You",
            "message": text
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload), let str = String(data: data, encoding: .utf8) {
            wsTask.send(.string(str)) { _ in }
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
