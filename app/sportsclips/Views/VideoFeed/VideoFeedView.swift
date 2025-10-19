//
//  VideoFeedView.swift
//  sportsclips
//
//  Main vertical scroll feed (Highlight tab)
//

import SwiftUI
import UIKit
import AVFoundation

struct VideoFeedView: View {
    private let apiService = APIService.shared
    @StateObject private var playerManager = VideoPlayerManager.shared
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var videos: [VideoClip] = []
    @State private var filteredVideos: [VideoClip] = []
    @State private var currentIndex = 0
    @State private var isLoading = false
    @State private var selectedSport: VideoClip.Sport = .all
    @State private var videoLikeStates: [String: Bool] = [:] // Track like states for double-tap
    @State private var heartAnimations: [String: HeartAnimation] = [:] // Track heart animations
    @State private var showVideoControls: [String: Bool] = [:] // Track which videos should show controls
    @State private var pausedVideos: [String: Bool] = [:] // Track which videos are paused
    @State private var errorMessage: String?
    @State private var showingGameClips = false
    @State private var selectedGameName = ""
    @State private var selectedGameId = ""
    @State private var currentVideoTimes: [String: Double] = [:] // Track current time for each video
    @State private var allVideos: [VideoClip] = [] // All loaded videos
    @State private var nextCursor: Int64? = nil // Cursor for paginated feed
    @State private var currentVideoIndex: Int = 0 // Current video being viewed
    @State private var isLoadingMore: Bool = false // Loading more videos
    @State private var controlsVisible: [String: Bool] = [:] // Track when controls are visible for each video
    @State private var timeUpdateTimer: Timer?
    @State private var doubleTapInProgress: [String: Bool] = [:] // Track if double tap is in progress
    @State private var controlShowTimes: [String: Date] = [:] // Track when controls were shown for each video

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if filteredVideos.isEmpty && isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                    .ignoresSafeArea()
            } else if filteredVideos.isEmpty {
                GeometryReader { geometry in
                    VStack {
                        Spacer()

                        VStack(spacing: 20) {
                            Image(systemName: "flame")
                                .font(.system(size: 60, weight: .light))
                                .foregroundColor(.white.opacity(0.6))

                            Text("No videos available")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .padding(.bottom, 98) // Exactly 10px gap to menu bar

                        Spacer()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .ignoresSafeArea()
            } else {
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(filteredVideos.enumerated()), id: \.element.id) { index, video in
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
                                            .zIndex(1) // Above video player

                                        // Video overlay with buttons and caption
                                        VStack {
                                            Spacer()

                                            HStack(alignment: .bottom) {
                                                // Caption on the left
                                                CaptionView(
                                                    video: video,
                                                    onGameTap: {
                                                        self.selectedGameName = self.extractGameName(from: video)
                                                        self.selectedGameId = video.gameId ?? ""
                                                        if !self.selectedGameId.isEmpty {
                                                            self.showingGameClips = true
                                                        }
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
                                                        controlsVisible[video.id] = true
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
                                                    isLiked: videoLikeStates[video.id] ?? false,
                                                    onLikeChanged: { newLikedState in
                                                        videoLikeStates[video.id] = newLikedState
                                                    }
                                                )
                                            }
                                            .padding(.bottom, 98) // Exactly 10px gap to menu bar
                                        }
                                        .zIndex(2) // Above everything else

                                        // Heart animation overlay
                                        if let heartAnimation = heartAnimations[video.id] {
                                            HeartAnimationView(animation: heartAnimation)
                                                .zIndex(3) // Above everything
                                        }

                                        // Custom video controls (now integrated into CaptionView)

                                        // Glass play button overlay (shows when paused)
                                        if pausedVideos[video.id] == true {
                                            ZStack {
                                                Color.black.opacity(0.2)
                                                    .ignoresSafeArea()

                                                Button(action: {
                                                    // Resume playback
                                                    playerManager.playVideo(for: video.videoURL, videoId: video.id)
                                                    pausedVideos[video.id] = false
                                                }) {
                                                    ZStack {
                                                        // Glass button background
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

                                                        // Play triangle icon
                                                        Image(systemName: "play.fill")
                                                            .font(.system(size: 40, weight: .medium))
                                                            .foregroundColor(.white)
                                                            .offset(x: 3) // Slight offset to center the triangle
                                                    }
                                                }
                                                .buttonStyle(PlainButtonStyle())
                                            }
                                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                                            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: pausedVideos[video.id])
                                            .zIndex(5) // Above everything including controls
                                        }
                                    }
                                    .frame(width: geometry.size.width, height: geometry.size.height)
                                    .id(index)
                                    .onAppear {
                                        // Update current index and play video
                                        currentIndex = index
                                        currentVideoIndex = index

                                        // Auto-play the video when it becomes visible
                                        print("🎬 Video appeared: \(video.id) at index \(index)")
                                        playerManager.playVideo(for: video.videoURL, videoId: video.id)
                                        localStorage.recordView(videoId: video.id)
                                        Task { await apiService.markViewed(clipId: video.id) }

        // Reset pause state when video becomes visible
                                        pausedVideos[video.id] = false

                                        // Check if we need to load more videos (when approaching end)
                                        if index >= filteredVideos.count - 3 && !isLoadingMore {
                                            preloadMoreVideos()
                                        }

                                        // Load like state from local storage
                                        if let interaction = localStorage.getInteraction(for: video.id) {
                                            videoLikeStates[video.id] = interaction.liked
                                            print("🔄 VideoFeedView: Loaded like state \(interaction.liked) for video \(video.id)")
                                        }

                                        // Load more videos if near end
                                        if index >= filteredVideos.count - 2 && !isLoadingMore {
                                            preloadMoreVideos()
                                        }
                                    }
        .onDisappear {
            // Pause video when it disappears
            playerManager.pauseVideo(for: video.videoURL, videoId: video.id)

            // Clean up control states to prevent UI breaking
            showVideoControls[video.id] = false
            controlsVisible[video.id] = false
            controlShowTimes.removeValue(forKey: video.id)
            heartAnimations[video.id] = nil
        }
                                }

                                // Loading indicator at bottom
                                if isLoading {
                                    HStack {
                                        Spacer()
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(1.2)
                                        Spacer()
                                    }
                                    .frame(width: geometry.size.width, height: 100)
                                }
                            }
                        }
                        .scrollTargetBehavior(.paging)
                        .id(selectedSport) // Force ScrollView to refresh when sport changes
                        .onChange(of: currentIndex) { _, newIndex in
                            // Play the new current video (VideoPlayerManager will handle pausing others)
                            if newIndex < filteredVideos.count {
                                let currentVideo = filteredVideos[newIndex]
                                print("🎬 Scroll detected - switching to video index: \(newIndex), ID: \(currentVideo.id)")
                                playerManager.playVideo(for: currentVideo.videoURL, videoId: currentVideo.id)
                                localStorage.recordView(videoId: currentVideo.id)

                                // Reset pause state for the new current video
                                pausedVideos[currentVideo.id] = false
                            }
                        }
                    }
                }
                .ignoresSafeArea()
            }

            // Sports filter bubbles at top
            VStack {
                HStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(VideoClip.Sport.allCases, id: \.self) { sport in
                                SportBubble(
                                    sport: sport,
                                    isSelected: selectedSport == sport,
                                    action: {
                                        print("🎬 Sport selected: \(sport.rawValue)")
                                        selectedSport = sport
                                        filterVideos()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8) // Add vertical padding to prevent cutoff
                    }
                    .padding(.top, 35) // Increased top padding for safe area (moved up 15px)
                    .frame(maxHeight: 60) // Ensure enough height for the bubbles

                    Spacer()
                }

                Spacer()
            }
        }
        .onAppear {
            loadVideos()
            startTimeUpdateTimer()
        }
        .onChange(of: localStorage.interactions) { _, _ in
            // React to changes in local storage interactions
            print("🔄 VideoFeedView: LocalStorage interactions changed, refreshing state")

            // Update like states for all videos
            for video in filteredVideos {
                if let interaction = localStorage.getInteraction(for: video.id) {
                    let storedLikedState = interaction.liked
                    if videoLikeStates[video.id] != storedLikedState {
                        videoLikeStates[video.id] = storedLikedState
                        print("🔄 VideoFeedView: Updated like state to \(storedLikedState) for video \(video.id)")
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
            controlsVisible.removeAll()
            controlShowTimes.removeAll()
            heartAnimations.removeAll()

            print("🎬 VideoFeedView disappeared - cleaned up resources")
        }
        .sheet(isPresented: $showingGameClips) {
            GameClipsView(gameId: selectedGameId, gameName: selectedGameName)
        }
    }

    private func loadVideos() {
        guard !isLoading else { return }

        isLoading = true
        Task {
            do {
                // Load initial feed page from API
                let page = try await apiService.fetchFeedPage(limit: 10, cursor: nil, sport: selectedSport == .all ? nil : APIClient.APISport(rawValue: selectedSport.rawValue))
                await MainActor.run {
                    self.nextCursor = page.nextCursor
                    self.allVideos = page.videos
                    self.videos = page.videos
                    self.filterVideos()
                    self.isLoading = false

                    // Auto-play first video after a short delay to ensure UI is ready
                    if !filteredVideos.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            print("🎬 Auto-playing first video after load: \(filteredVideos[0].id)")
                            playerManager.playVideo(for: filteredVideos[0].videoURL, videoId: filteredVideos[0].id)
                            localStorage.recordView(videoId: filteredVideos[0].id)
                            Task { await apiService.markViewed(clipId: filteredVideos[0].id) }
                            // Reset pause state for first video
                            pausedVideos[filteredVideos[0].id] = false
                        }
                    }

                    // Start preloading more videos
                    preloadMoreVideos()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    private func preloadMoreVideos() {
        guard !isLoadingMore else { return }

        isLoadingMore = true
        Task {
            do {
                let page = try await apiService.fetchFeedPage(limit: 10, cursor: nextCursor, sport: selectedSport == .all ? nil : APIClient.APISport(rawValue: selectedSport.rawValue))
                await MainActor.run {
                    self.nextCursor = page.nextCursor
                    self.allVideos.append(contentsOf: page.videos)
                    self.videos = self.allVideos
                    self.filterVideos()
                    self.isLoadingMore = false
                }
            } catch {
                print("Error preloading videos: \(error)")
                await MainActor.run { self.isLoadingMore = false }
            }
        }
    }

    private func generateNewVideo(index: Int) -> VideoClip {
        let sports: [VideoClip.Sport] = [.football, .basketball, .soccer, .baseball, .tennis, .golf, .hockey, .boxing, .mma, .racing]
        let sport = sports[index % sports.count]

        let captions = [
            "Amazing \(sport.rawValue.lowercased()) moment! This incredible play will blow your mind! The athlete showed incredible skill and determination to pull off this spectacular move. Watch as they defy all odds and create a moment that will be remembered for years to come! 🏆",
            "Unbelievable \(sport.rawValue.lowercased()) action! This is what peak performance looks like! The precision and timing required for this play is absolutely mind-blowing. Every second of this clip showcases the incredible talent and dedication of these athletes! ⚡",
            "Incredible \(sport.rawValue.lowercased()) highlight! This play demonstrates why this sport is so exciting to watch! The combination of skill, strategy, and pure athleticism creates moments like this that keep fans on the edge of their seats! 🎯",
            "Spectacular \(sport.rawValue.lowercased()) moment! This is the kind of play that makes you jump out of your seat! The athlete's incredible performance shows what years of training and dedication can achieve. This is sports at its finest! 🌟",
            "Outstanding \(sport.rawValue.lowercased()) play! This incredible moment showcases the very best of what this sport has to offer! The skill, precision, and determination shown here is absolutely inspiring. This is why we love sports! 💪"
        ]

        return VideoClip(
            id: UUID().uuidString,
            videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
            caption: captions[index % captions.count],
            sport: sport,
            likes: Int.random(in: 1000...50000),
            comments: Int.random(in: 50...1000),
            shares: Int.random(in: 10...500),
            createdAt: Date(),
            s3Key: "uploads/generated-\(sport.rawValue.lowercased())-\(index).mp4",
            title: "\(sport.rawValue) Highlight \(index + 1)",
            description: captions[index % captions.count],
            gameId: ""
        )
    }

    private func filterVideos() {
        print("🎬 Filtering videos for sport: \(selectedSport.rawValue)")
        print("🎬 Total videos before filtering: \(videos.count)")
        print("🎬 Videos sports: \(videos.map { $0.sport.rawValue })")

        if selectedSport == .all {
            // Randomize the order of all videos for the "All" tab
            filteredVideos = videos.shuffled()
            print("🎬 Randomized all videos for 'All' tab")
        } else {
            filteredVideos = videos.filter { $0.sport == selectedSport }
        }

        print("🎬 Filtered videos count: \(filteredVideos.count)")
        print("🎬 Filtered videos sports: \(filteredVideos.map { $0.sport.rawValue })")

        currentIndex = 0

        // Auto-play first video after filtering
        if !filteredVideos.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                print("🎬 Auto-playing first video after filter: \(filteredVideos[0].id)")
                playerManager.playVideo(for: filteredVideos[0].videoURL, videoId: filteredVideos[0].id)
                localStorage.recordView(videoId: filteredVideos[0].id)
                // Reset pause state for first video
                pausedVideos[filteredVideos[0].id] = false
            }
        }
    }

    private func handleDoubleTapLike(for video: VideoClip, at location: CGPoint) {
        // Toggle like state
        let currentLikeState = videoLikeStates[video.id] ?? false
        let newLikeState = !currentLikeState

        // Update state with animation
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            videoLikeStates[video.id] = newLikeState
        }

        // Record interaction in local storage
        localStorage.recordInteraction(
            videoId: video.id,
            liked: newLikeState,
            commented: false,
            shared: false
        )

        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        // Create heart animation
        let heartAnimation = HeartAnimation(
            id: UUID().uuidString,
            location: location,
            isLiked: newLikeState
        )
        heartAnimations[video.id] = heartAnimation

        // Remove animation after it completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            heartAnimations.removeValue(forKey: video.id)
        }

        // Call API to like/unlike the video
        Task {
            do {
                try await apiService.likeVideo(clipId: video.id)
                print("✅ Successfully liked/unliked video via double-tap: \(video.id)")
            } catch {
                print("❌ Failed to like/unlike video via double-tap: \(error)")
                // Revert the optimistic update on failure
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        videoLikeStates[video.id] = !newLikeState
                    }
                }
            }
        }

        // Force UI refresh by updating a dummy state
        DispatchQueue.main.async {
            // Trigger a state change to force UI refresh
            self.currentIndex = self.currentIndex
        }

        print("🎬 Double tapped to like video: \(video.id), new state: \(newLikeState)")
    }

    private func handleSingleTap(for video: VideoClip) {
        // Don't handle single tap if controls are visible (during slider interaction)
        guard !(controlsVisible[video.id] ?? false) else {
            print("🎬 Single tap ignored - controls are visible")
            return
        }

        // Toggle play/pause on single tap
        let player = playerManager.getPlayer(for: video.videoURL, videoId: video.id)
        if player.timeControlStatus == .playing {
            playerManager.pauseVideo(for: video.videoURL, videoId: video.id)
            pausedVideos[video.id] = true
        } else {
            playerManager.playVideo(for: video.videoURL, videoId: video.id)
            pausedVideos[video.id] = false
        }
        print("Single tapped to toggle play/pause for video: \(video.id)")
    }

    private func handleLongPress(for video: VideoClip) {
        // Show controls on long press
        let showTime = Date()
        showVideoControls[video.id] = true
        controlsVisible[video.id] = true
        controlShowTimes[video.id] = showTime // Record when controls were shown

        print("🎬 Long pressed to show controls for video: \(video.id)")
        print("🎬 showVideoControls[\(video.id)] = \(showVideoControls[video.id] ?? false)")
        print("🎬 Control show time recorded: \(showTime)")
        print("🎬 Timer will auto-hide controls at: \(Date(timeIntervalSinceNow: 3.0))")
    }

    private func extractGameName(from video: VideoClip) -> String {
        // Try to extract game name from title first, then description
        let textToAnalyze = video.title ?? video.description ?? video.caption

        // Look for common game patterns
        let lowercasedText = textToAnalyze.lowercased()

        // Check for specific game types
        if lowercasedText.contains("championship") || lowercasedText.contains("final") {
            return "Championship Game"
        } else if lowercasedText.contains("playoff") {
            return "Playoff Game"
        } else if lowercasedText.contains("semifinal") {
            return "Semifinal"
        } else if lowercasedText.contains("quarterfinal") {
            return "Quarterfinal"
        } else if lowercasedText.contains("derby") {
            return "Derby Match"
        } else if lowercasedText.contains("classic") {
            return "Classic Match"
        }

        // Extract from title if available
        if let title = video.title, !title.isEmpty {
            let words = title.components(separatedBy: " ")
            if words.count >= 2 {
                return "\(words[0]) \(words[1])"
            }
            return title
        }

        // Fallback to first few words of description
        let words = textToAnalyze.components(separatedBy: " ")
        if words.count >= 2 {
            return "\(words[0]) \(words[1])"
        }

        return "Game Highlights"
    }

    private func getCurrentTime(for videoId: String) -> Double {
        // Get current time from the video that matches this ID
        if filteredVideos.contains(where: { $0.id == videoId }) {
            return currentVideoTimes[videoId] ?? 0.0
        }
        return 0.0
    }

    private func getDuration(for videoId: String) -> Double {
        // Get duration from the video that matches this ID
        if filteredVideos.contains(where: { $0.id == videoId }) {
            // Use a cached duration or fallback
            return 596.0 // Fallback for BigBuckBunny - we can improve this later
        }
        return 596.0
    }

    private func seekToTime(for videoId: String, time: Double) {
        // Seek the video that matches this ID
        if let video = filteredVideos.first(where: { $0.id == videoId }) {
            playerManager.seekVideo(for: video.videoURL, videoId: video.id, to: time)
        }
    }

        private func startTimeUpdateTimer() {
            // Invalidate existing timer to prevent duplicates
            timeUpdateTimer?.invalidate()

            print("🎬 Starting time update timer for VideoFeedView")

            timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
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
                            controlsVisible[video.id] = false
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
        }

    private func stopTimeUpdateTimer() {
        print("🎬 Stopping time update timer for VideoFeedView")
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }
}

struct SportBubble: View {
    let sport: VideoClip.Sport
    let isSelected: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: sport.icon)
                    .font(.system(size: 16, weight: .medium))
                    .symbolEffect(.bounce, value: isSelected)
                    .foregroundColor(sport == .all ? .red : (isSelected ? .white : .white.opacity(0.7)))

                Text(sport.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                    .lineLimit(1) // Ensure text doesn't wrap
                    .minimumScaleFactor(0.8) // Allow slight scaling for long text
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12) // Increased vertical padding
            .frame(minHeight: 44) // Ensure minimum height for touch targets
            .background(
                ZStack {
                    // Outer glow for selected state
                    if isSelected {
                        Capsule()
                            .fill(.white.opacity(0.1))
                            .blur(radius: 6)
                            .scaleEffect(1.1)
                    }

                    // Main capsule
                    Capsule()
                        .fill(isSelected ? .ultraThinMaterial : .thinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(isSelected ? 0.3 : 0.1),
                                            .white.opacity(isSelected ? 0.15 : 0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isSelected ? 1.2 : 0.8
                                )
                        )
                        .shadow(
                            color: .black.opacity(isSelected ? 0.15 : 0.08),
                            radius: isSelected ? 6 : 3,
                            x: 0,
                            y: isSelected ? 3 : 1
                        )
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.08 : (isPressed ? 0.95 : 1.0))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

// MARK: - Heart Animation Models and Views

#Preview {
    VideoFeedView()
}
