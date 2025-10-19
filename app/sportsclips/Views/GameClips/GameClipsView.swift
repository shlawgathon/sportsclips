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

            if videos.isEmpty && isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            } else if videos.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 60, weight: .light))
                        .foregroundColor(.white.opacity(0.6))

                    Text("No clips for \(gameName)")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            } else {
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                                    ZStack {
                                        // Full-screen video player
                                        VideoPlayerView(video: video, playerManager: playerManager)
                                            .frame(width: geometry.size.width, height: geometry.size.height)
                                            .clipped()

                                        // Invisible overlay for tap detection
                                        Rectangle()
                                            .fill(Color.clear)
                                            .frame(width: geometry.size.width, height: geometry.size.height)
                                            .contentShape(Rectangle())
                                            .simultaneousGesture(
                                                // Long press gesture for slider controls (more restrictive to avoid scroll conflicts)
                                                LongPressGesture(minimumDuration: 1.0, maximumDistance: 10)
                                                    .onEnded { _ in
                                                        handleLongPress(for: video)
                                                    }
                                            )
                                            .simultaneousGesture(
                                                // Tap gesture for pause/play
                                                TapGesture(count: 1)
                                                    .onEnded { _ in
                                                        // Only handle single tap if double tap is not in progress
                                                        if !(doubleTapInProgress[video.id] ?? false) {
                                                            handleSingleTap(for: video)
                                                        }
                                                    }
                                            )
                                            .simultaneousGesture(
                                                // Double tap gesture for like
                                                TapGesture(count: 2)
                                                    .onEnded { _ in
                                                        doubleTapInProgress[video.id] = true
                                                        handleDoubleTapLike(for: video, at: CGPoint(x: geometry.size.width/2, y: geometry.size.height/2))

                                                        // Reset the flag after a short delay
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                            doubleTapInProgress[video.id] = false
                                                        }
                                                    }
                                            )
                                            .zIndex(1)

                                        // Video overlay with buttons and caption
                                        VStack {
                                            Spacer()

                                            HStack(alignment: .bottom) {
                                                // Caption on the left
                                                            CaptionView(
                                                                video: video,
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
                                                                    // Keep controls visible when dragging starts
                                                                    showVideoControls[video.id] = true
                                                                    // Remove the show time so controls don't auto-hide while dragging
                                                                    let removedTime = controlShowTimes.removeValue(forKey: video.id)
                                                                    print("🎬 Drag started for video: \(video.id)")
                                                                    print("🎬 Removed show time: \(removedTime?.description ?? "none")")
                                                                    print("🎬 Controls will stay visible while dragging")
                                                                },
                                                                onDragEnd: {
                                                                    // Reset the 3-second timer when dragging ends
                                                                    let newShowTime = Date()
                                                                    controlShowTimes[video.id] = newShowTime
                                                                    print("🎬 Drag ended for video: \(video.id)")
                                                                    print("🎬 New show time recorded: \(newShowTime)")
                                                                    print("🎬 Timer will auto-hide controls at: \(Date(timeIntervalSinceNow: 3.0))")
                                                                }
                                                            )

                                                Spacer()

                                                // Action buttons on the right
                                                VideoOverlayView(
                                                    video: video,
                                                    isLiked: videoLikeStates[video.id] ?? false
                                                )
                                            }
                                            .padding(.bottom, 80) // Reduced gap to match VideoFeedView
                                        }
                                        .zIndex(2)

                                        // Heart animation overlay
                                        if let heartAnimation = heartAnimations[video.id] {
                                            HeartAnimationView(animation: heartAnimation)
                                                .zIndex(3)
                                        }

                                        // Custom video controls (now integrated into CaptionView)

                                        // Glass play button overlay
                                        if pausedVideos[video.id] == true {
                                            ZStack {
                                                Color.black.opacity(0.2)
                                                    .ignoresSafeArea()

                                                Button(action: {
                                                    playerManager.playVideo(for: video.videoURL, videoId: video.id)
                                                    pausedVideos[video.id] = false
                                                }) {
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
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                                            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: pausedVideos[video.id])
                                            .zIndex(5)
                                        }
                                    }
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .id(index)
                                    .onAppear {
                                        currentIndex = index
                                        playerManager.playVideo(for: video.videoURL, videoId: video.id)
                                        localStorage.recordView(videoId: video.id)

                                        if let interaction = localStorage.getInteraction(for: video.id) {
                                            videoLikeStates[video.id] = interaction.liked
                                        }
                                    }
        .onDisappear {
            playerManager.pauseVideo(for: video.videoURL, videoId: video.id)

            // Clean up control states to prevent UI breaking
            showVideoControls[video.id] = false
            controlShowTimes.removeValue(forKey: video.id)
            heartAnimations[video.id] = nil
        }
                                }
                            }
                        }
                        .scrollTargetBehavior(.paging)
                        .onChange(of: currentIndex) { _, newIndex in
                            playerManager.pauseAllVideos()

                            if newIndex < videos.count {
                                let currentVideo = videos[newIndex]
                                playerManager.playVideo(for: currentVideo.videoURL, videoId: currentVideo.id)
                                localStorage.recordView(videoId: currentVideo.id)
                            }
                        }
                    }
                }
                .ignoresSafeArea()
            }

            // Header with back button and game name
            VStack {
                HStack {
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

                    Spacer()

                    Text(resolvedGameName ?? gameName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    // Invisible spacer to center the title
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }
        }
        .onAppear {
            loadGameDetails()
            loadGameClips()
            startTimeUpdateTimer()
        }
        .onChange(of: localStorage.interactions) { _, _ in
            // React to changes in local storage interactions
            print("🔄 GameClipsView: LocalStorage interactions changed, refreshing state")

            // Update like states for all videos
            for video in filteredVideos {
                if let interaction = localStorage.getInteraction(for: video.id) {
                    let storedLikedState = interaction.liked
                    if videoLikeStates[video.id] != storedLikedState {
                        videoLikeStates[video.id] = storedLikedState
                        print("🔄 GameClipsView: Updated like state to \(storedLikedState) for video \(video.id)")
                    }
                }
            }

            // Force UI refresh by updating a dummy state
            DispatchQueue.main.async {
                // Trigger a state change to force UI refresh
                self.currentIndex = self.currentIndex
            }
        }
        .onDisappear {
            playerManager.pauseAllVideos()
            stopTimeUpdateTimer()

            // Clean up unused players to free memory
            let activeVideoIds = filteredVideos.map { $0.id }
            playerManager.cleanupUnusedPlayers(activeVideoIds: activeVideoIds)

            // Clean up all control states to prevent UI breaking
            showVideoControls.removeAll()
            controlShowTimes.removeAll()
            heartAnimations.removeAll()

            print("🎬 GameClipsView disappeared - cleaned up resources")
        }
    }

    private func loadGameDetails() {
        Task {
            do {
                let game = try await APIClient.shared.getGame(gameId: gameId)
                await MainActor.run {
                    self.resolvedGameName = game.game.name
                }
            } catch {
                // Leave resolvedGameName as nil on failure; fallback to passed gameName
                print("Failed to load game details for id \(gameId): \(error)")
            }
        }
    }

    private func loadGameClips() {
        guard !isLoading else { return }

        isLoading = true
        Task {
            do {
                // Fetch clips for this specific game from backend
                let items = try await APIClient.shared.listClipsByGame(gameId: gameId)
                // Map to VideoClip and fetch presigned URLs concurrently
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

        // Update local storage
        localStorage.recordInteraction(
            videoId: video.id,
            liked: newLikeState,
            commented: false,
            shared: false
        )

        // Heart animation
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
        // Show controls on long press
        let showTime = Date()
        showVideoControls[video.id] = true
        controlShowTimes[video.id] = showTime // Record when controls were shown

        print("🎬 Long pressed to show controls for video: \(video.id)")
        print("🎬 Control show time recorded: \(showTime)")
        print("🎬 Timer will auto-hide controls at: \(Date(timeIntervalSinceNow: 3.0))")
    }


    private func getCurrentTime(for videoId: String) -> Double {
        // Get current time from the video that matches this ID
        if let video = self.filteredVideos.first(where: { $0.id == videoId }) {
            return playerManager.getCurrentTime(for: video.videoURL, videoId: video.id)
        }
        return 0.0
    }

    private func getDuration(for videoId: String) -> Double {
        // Get duration from the video that matches this ID
        if let video = self.filteredVideos.first(where: { $0.id == videoId }) {
            let duration = playerManager.getDuration(for: video.videoURL, videoId: video.id)
            return duration > 0 ? duration : 596.0 // Fallback for BigBuckBunny
        }
        return 596.0
    }

    private func seekToTime(for videoId: String, time: Double) {
        // Seek the video that matches this ID
        if let video = self.filteredVideos.first(where: { $0.id == videoId }) {
            playerManager.seekVideo(for: video.videoURL, videoId: video.id, to: time)
        }
    }

        private func startTimeUpdateTimer() {
            // Invalidate existing timer to prevent duplicates
            timeUpdateTimer?.invalidate()

            print("🎬 Starting time update timer for GameClipsView")

            timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                // Update current time for all videos
                for video in filteredVideos {
                    let currentTime = playerManager.getCurrentTime(for: video.videoURL, videoId: video.id)
                    currentVideoTimes[video.id] = currentTime

                    // Check if controls should be hidden (3 seconds after showing)
                    if let showTime = controlShowTimes[video.id] {
                        let elapsed = Date().timeIntervalSince(showTime)
                        if elapsed >= 3.0 {
                            print("🎬 Timer check: Hiding controls for video \(video.id) after \(String(format: "%.1f", elapsed))s")
                            showVideoControls[video.id] = false
                            controlShowTimes.removeValue(forKey: video.id)
                            print("🎬 Auto-hiding controls for video: \(video.id) after 3s")
                        } else {
                            // Debug: Log remaining time every 0.5 seconds
                            if Int(elapsed * 10) % 5 == 0 {
                                let remaining = 3.0 - elapsed
                                print("🎬 Timer check: Video \(video.id) controls visible for \(String(format: "%.1f", elapsed))s, remaining: \(String(format: "%.1f", remaining))s")
                            }
                        }
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
