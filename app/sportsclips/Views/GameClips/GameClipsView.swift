//
//  GameClipsView.swift
//  sportsclips
//
//  Game-specific clips feed view
//

import SwiftUI
import AVFoundation

struct GameClipsView: View {
    let gameId: String
    let gameName: String
    @StateObject private var playerManager = VideoPlayerManager.shared
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var videos: [VideoClip] = []
    @State private var filteredVideos: [VideoClip] = []
    @State private var isLoading = false
    @State private var currentIndex = 0
    @State private var videoLikeStates: [String: Bool] = [:]
    @State private var heartAnimations: [String: HeartAnimation] = [:]
    @State private var showVideoControls: [String: Bool] = [:]
    @State private var pausedVideos: [String: Bool] = [:]
    @State private var currentVideoTimes: [String: Double] = [:] // Track current time for each video
    @State private var timeUpdateTimer: Timer?
    @State private var doubleTapInProgress: [String: Bool] = [:] // Track if double tap is in progress
    @State private var controlShowTimes: [String: Date] = [:] // Track when controls were shown for each video
    @State private var resolvedGameName: String? = nil // Loaded from backend using gameId
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            contentView
            headerView
        }
        .onAppear {
            loadGameDetails()
            loadGameClips()
            startTimeUpdateTimer()
        }
        .onChange(of: localStorage.interactions) { _, _ in
            handleLocalStorageChange()
        }
        .onDisappear {
            handleViewDisappear()
        }
    }

    // MARK: - Content View
    @ViewBuilder
    private var contentView: some View {
        if videos.isEmpty && isLoading {
            loadingView
        } else if videos.isEmpty {
            emptyStateView
        } else {
            videoScrollView
        }
    }

    // MARK: - Loading View
    private var loadingView: some View {
        ProgressView()
        .progressViewStyle(CircularProgressViewStyle(tint: .white))
        .scaleEffect(1.5)
    }

    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
            .font(.system(size: 60, weight: .light))
            .foregroundColor(.white.opacity(0.6))

            Text("No clips for \(gameName)")
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
        }
    }

    // MARK: - Video Scroll View
    private var videoScrollView: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                            videoCell(for: video, at: index, geometry: geometry)
                        }
                    }
                }
                .scrollTargetBehavior(.paging)
                .onChange(of: currentIndex) { _, newIndex in
                    handleIndexChange(newIndex)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Video Cell
    private func videoCell(for video: VideoClip, at index: Int, geometry: GeometryProxy) -> some View {
        ZStack {
            // Full-screen video player
            VideoPlayerView(video: video, playerManager: playerManager)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()

            // Tap detection overlay
            tapDetectionOverlay(for: video, geometry: geometry)

            // Video overlay with buttons and caption
            videoOverlayContent(for: video, geometry: geometry)

            // Heart animation overlay
            if let heartAnimation = heartAnimations[video.id] {
                HeartAnimationView(animation: heartAnimation)
                .zIndex(3)
            }

            // Play button overlay when paused
            if pausedVideos[video.id] == true {
                pausedVideoOverlay(for: video)
            }
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .id(index)
        .onAppear {
            handleVideoAppear(video: video, index: index)
        }
        .onDisappear {
            handleVideoDisappear(video: video)
        }
    }

    // MARK: - Tap Detection Overlay
    private func tapDetectionOverlay(for video: VideoClip, geometry: GeometryProxy) -> some View {
        Rectangle()
        .fill(Color.clear)
        .frame(width: geometry.size.width, height: geometry.size.height)
        .contentShape(Rectangle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 1.0, maximumDistance: 10)
            .onEnded { _ in
                handleLongPress(for: video)
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1)
            .onEnded { _ in
                if !(doubleTapInProgress[video.id] ?? false) {
                    handleSingleTap(for: video)
                }
            }
        )
        .simultaneousGesture(
            TapGesture(count: 2)
            .onEnded { _ in
                handleDoubleTap(for: video, geometry: geometry)
            }
        )
        .zIndex(1)
    }

    // MARK: - Video Overlay Content
    private func videoOverlayContent(for video: VideoClip, geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom) {
                captionView(for: video)
                Spacer()
                VideoOverlayView(
                    video: video,
                    isLiked: videoLikeStates[video.id] ?? false
                )
            }
            .padding(.bottom, 80)
        }
        .zIndex(2)
    }

    // MARK: - Caption View
    private func captionView(for video: VideoClip) -> some View {
        CaptionView(
            video: video,
            gameName: resolvedGameName ?? gameName,
            onGameTap: {
                // No action needed in game clips view
            },
            showControls: showVideoControls[video.id] ?? false,
            currentTime: currentVideoTimes[video.id] ?? 0,
            duration: getDuration(for: video.id),
            onSeek: { time in
                seekToTime(for: video.id, time: time)
            },
            onDragStart: {
                handleDragStart(for: video)
            },
            onDragEnd: {
                handleDragEnd(for: video)
            }
        )
    }

    // MARK: - Paused Video Overlay
    private func pausedVideoOverlay(for video: VideoClip) -> some View {
        ZStack {
            Color.black.opacity(0.2)
            .ignoresSafeArea()

            Button(action: {
                playerManager.playVideo(for: video.videoURL, videoId: video.id)
                pausedVideos[video.id] = false
            }) {
                playButtonView
            }
            .buttonStyle(PlainButtonStyle())
        }
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: pausedVideos[video.id])
        .zIndex(5)
    }

    // MARK: - Play Button View
    private var playButtonView: some View {
        ZStack {
            Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 120, height: 120)
            .overlay(
                Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.3),
                            .white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
            )
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)

            Image(systemName: "play.fill")
            .font(.system(size: 40, weight: .medium))
            .foregroundColor(.white)
            .offset(x: 3)
        }
    }

    // MARK: - Header View
    private var headerView: some View {
        VStack {
            HStack {
                backButton
                Spacer()
                titleText
                Spacer()
                spacerCircle
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Header Components
    private var backButton: some View {
        Button(action: { dismiss() }) {
            Image(systemName: "chevron.left")
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(.white)
            .frame(width: 44, height: 44)
            .background(
                Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                    .stroke(.white.opacity(0.2), lineWidth: 1)
                )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var titleText: some View {
        Text(resolvedGameName ?? gameName)
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(.white)
    }

    private var spacerCircle: some View {
        Circle()
        .fill(Color.clear)
        .frame(width: 44, height: 44)
    }

    // MARK: - Event Handlers
    private func handleVideoAppear(video: VideoClip, index: Int) {
        currentIndex = index
        playerManager.playVideo(for: video.videoURL, videoId: video.id)
        localStorage.recordView(videoId: video.id)

        if let interaction = localStorage.getInteraction(for: video.id) {
            videoLikeStates[video.id] = interaction.liked
        }
    }

    private func handleVideoDisappear(video: VideoClip) {
        playerManager.pauseVideo(for: video.videoURL, videoId: video.id)

        // Clean up control states to prevent UI breaking
        showVideoControls[video.id] = false
        controlShowTimes.removeValue(forKey: video.id)
        heartAnimations[video.id] = nil
    }

    private func handleIndexChange(_ newIndex: Int) {
        playerManager.pauseAllVideos()

        if newIndex < videos.count {
            let currentVideo = videos[newIndex]
            playerManager.playVideo(for: currentVideo.videoURL, videoId: currentVideo.id)
            localStorage.recordView(videoId: currentVideo.id)
        }
    }

    private func handleDoubleTap(for video: VideoClip, geometry: GeometryProxy) {
        doubleTapInProgress[video.id] = true
        handleDoubleTapLike(for: video, at: CGPoint(x: geometry.size.width/2, y: geometry.size.height/2))

DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
doubleTapInProgress[video.id] = false
}
}

private func handleDragStart(for video: VideoClip) {
showVideoControls[video.id] = true
let removedTime = controlShowTimes.removeValue(forKey: video.id)
print("🎬 Drag started for video: \(video.id)")
print("🎬 Removed show time: \(removedTime?.description ?? "none")")
print("🎬 Controls will stay visible while dragging")
}

private func handleDragEnd(for video: VideoClip) {
let newShowTime = Date()
controlShowTimes[video.id] = newShowTime
print("🎬 Drag ended for video: \(video.id)")
print("🎬 New show time recorded: \(newShowTime)")
print("🎬 Timer will auto-hide controls at: \(Date(timeIntervalSinceNow: 3.0))")
}

private func handleLocalStorageChange() {
print("🔄 GameClipsView: LocalStorage interactions changed, refreshing state")

for video in filteredVideos {
if let interaction = localStorage.getInteraction(for: video.id) {
let storedLikedState = interaction.liked
if videoLikeStates[video.id] != storedLikedState {
videoLikeStates[video.id] = storedLikedState
print("🔄 GameClipsView: Updated like state to \(storedLikedState) for video \(video.id)")
}
}
}

DispatchQueue.main.async {
self.currentIndex = self.currentIndex
}
}

private func handleViewDisappear() {
playerManager.pauseAllVideos()
stopTimeUpdateTimer()

let activeVideoIds = filteredVideos.map { $0.id }
playerManager.cleanupUnusedPlayers(activeVideoIds: activeVideoIds)

showVideoControls.removeAll()
controlShowTimes.removeAll()
heartAnimations.removeAll()

print("🎬 GameClipsView disappeared - cleaned up resources")
}

// MARK: - Data Loading Methods
private func loadGameDetails() {
Task {
do {
let game = try await APIClient.shared.getGame(gameId: gameId)
await MainActor.run {
self.resolvedGameName = game.name
}
} catch {
print("Failed to load game details for id \(gameId): \(error)")
}
}
}

private func loadGameClips() {
guard !isLoading else { return }

isLoading = true
Task {
do {
let items = try await APIClient.shared.listClipsByGame(gameId: gameId)
let gameVideos: [VideoClip] = try await withThrowingTaskGroup(of: VideoClip.self) { group in
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

await MainActor.run {
self.videos = gameVideos
self.isLoading = false

if !gameVideos.isEmpty {
playerManager.playVideo(for: gameVideos[0].videoURL, videoId: gameVideos[0].id)
localStorage.recordView(videoId: gameVideos[0].id)
}
}
} catch {
await MainActor.run {
self.isLoading = false
}
}
}
}

// MARK: - Interaction Handlers
private func handleSingleTap(for video: VideoClip) {
let player = playerManager.getPlayer(for: video.videoURL, videoId: video.id)
if player.timeControlStatus == .playing {
playerManager.pauseVideo(for: video.videoURL, videoId: video.id)
pausedVideos[video.id] = true
} else {
playerManager.playVideo(for: video.videoURL, videoId: video.id)
pausedVideos[video.id] = false
}
}

private func handleDoubleTapLike(for video: VideoClip, at location: CGPoint) {
let currentLikeState = videoLikeStates[video.id] ?? false
let newLikeState = !currentLikeState

videoLikeStates[video.id] = newLikeState

localStorage.recordInteraction(
videoId: video.id,
liked: newLikeState,
commented: false,
shared: false
)

let heartAnimation = HeartAnimation(
id: UUID().uuidString,
location: location,
isLiked: newLikeState
)
heartAnimations[video.id] = heartAnimation

DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
heartAnimations.removeValue(forKey: video.id)
}
}

private func handleLongPress(for video: VideoClip) {
let showTime = Date()
showVideoControls[video.id] = true
controlShowTimes[video.id] = showTime

print("🎬 Long pressed to show controls for video: \(video.id)")
print("🎬 Control show time recorded: \(showTime)")
print("🎬 Timer will auto-hide controls at: \(Date(timeIntervalSinceNow: 3.0))")
}

// MARK: - Video Control Methods
private func getCurrentTime(for videoId: String) -> Double {
if let video = self.filteredVideos.first(where: { $0.id == videoId }) {
return playerManager.getCurrentTime(for: video.videoURL, videoId: video.id)
}
return 0.0
}

private func getDuration(for videoId: String) -> Double {
if let video = self.filteredVideos.first(where: { $0.id == videoId }) {
let duration = playerManager.getDuration(for: video.videoURL, videoId: video.id)
return duration > 0 ? duration : 596.0
}
return 596.0
}

private func seekToTime(for videoId: String, time: Double) {
if let video = self.filteredVideos.first(where: { $0.id == videoId }) {
playerManager.seekVideo(for: video.videoURL, videoId: video.id, to: time)
}
}

// MARK: - Timer Management
private func startTimeUpdateTimer() {
timeUpdateTimer?.invalidate()

print("🎬 Starting time update timer for GameClipsView")

timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
updateVideoTimes()
checkControlVisibility()
}
}

private func updateVideoTimes() {
for video in filteredVideos {
let currentTime = playerManager.getCurrentTime(for: video.videoURL, videoId: video.id)
currentVideoTimes[video.id] = currentTime
}
}

private func checkControlVisibility() {
for video in filteredVideos {
if let showTime = controlShowTimes[video.id] {
let elapsed = Date().timeIntervalSince(showTime)
if elapsed >= 3.0 {
print("🎬 Timer check: Hiding controls for video \(video.id) after \(String(format: "%.1f", elapsed))s")
showVideoControls[video.id] = false
controlShowTimes.removeValue(forKey: video.id)
print("🎬 Auto-hiding controls for video: \(video.id) after 3s")
} else if Int(elapsed * 10) % 5 == 0 {
let remaining = 3.0 - elapsed
print("🎬 Timer check: Video \(video.id) controls visible for \(String(format: "%.1f", elapsed))s, remaining: \(String(format: "%.1f", remaining))s")
}
}
}
}

private func stopTimeUpdateTimer() {
print("🎬 Stopping time update timer for GameClipsView")
timeUpdateTimer?.invalidate()
timeUpdateTimer = nil
}
}

#Preview {
GameClipsView(gameId: "demo-game-id", gameName: "Football")
}
