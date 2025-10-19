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
    @State private var gameNameCache: [String: String] = [:] // Cache gameId -> gameName to avoid refetching

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            contentView
            sportFilterBar
        }
        .onAppear {
            // Set initial sport based on user preference
            let savedCategory = localStorage.getLastHighlightsCategory()
            if let sport = VideoClip.Sport(rawValue: savedCategory) {
                selectedSport = sport
            }
            loadVideos()
            startTimeUpdateTimer()
        }
        .onChange(of: localStorage.navigateToVideoId) { _, videoId in
            if let videoId = videoId {
                handleNavigationToVideo(videoId: videoId)
            }
        }
        .onChange(of: localStorage.interactions) { _, _ in
            handleLocalStorageChange()
        }
        .onDisappear {
            handleViewDisappear()
        }
        .sheet(isPresented: $showingGameClips) {
            GameClipsView(gameId: selectedGameId, gameName: selectedGameName)
        }
    }

    // MARK: - Content View
    @ViewBuilder
    private var contentView: some View {
        if filteredVideos.isEmpty && isLoading {
            loadingView
        } else if filteredVideos.isEmpty {
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
            Image(systemName: "flame")
                .font(.system(size: 60, weight: .light))
                .foregroundColor(.white.opacity(0.6))

            Text("No videos available")
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
                        ForEach(Array(filteredVideos.enumerated()), id: \.element.id) { index, video in
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
                    handleIndexChange(newIndex)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Sport Filter Bar
    private var sportFilterBar: some View {
        VStack {
            HStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(VideoClip.Sport.allCases, id: \.self) { sport in
                            SportBubble(
                                sport: sport,
                                isSelected: selectedSport == sport,
                                action: {
                                    handleSportSelection(sport)
                                },
                                currentVideoSport: filteredVideos.isEmpty ? nil : filteredVideos[currentIndex].sport,
                                selectedSport: selectedSport
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 8) // Minimal top padding
            }

            Spacer()
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
                // Caption on the left
                CaptionView(
                    video: video,
                    gameName: selectedGameName,
                    onGameTap: {
                        handleGameTap(for: video)
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
            .padding(.bottom, 94) // Increased spacing between caption and menu bar
        }
        .zIndex(2) // Above everything else
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

            // Play triangle icon
            Image(systemName: "play.fill")
                .font(.system(size: 40, weight: .medium))
                .foregroundColor(.white)
                .offset(x: 3) // Slight offset to center the triangle
        }
    }

    // MARK: - Event Handlers
    private func handleVideoAppear(video: VideoClip, index: Int) {
        currentIndex = index
        currentVideoIndex = index

        print("🎬 Video appeared: \(video.id) at index \(index)")
        playerManager.playVideo(for: video.videoURL, videoId: video.id)
        // Preload next 5 videos to disk
        playerManager.updatePreloadQueue(currentIndex: index, clips: filteredVideos, count: 5)
        localStorage.recordView(videoId: video.id)
        Task { await apiService.markViewed(clipId: video.id) }

        pausedVideos[video.id] = false

        // Update game name for the "watch more" functionality
        selectedGameName = extractGameName(from: video)

        // Check if we need to load more videos
        if index >= filteredVideos.count - 3 && !isLoadingMore {
            preloadMoreVideos()
        }

        // Load like state from local storage
        if let interaction = localStorage.getInteraction(for: video.id) {
            videoLikeStates[video.id] = interaction.liked
            print("🔄 VideoFeedView: Loaded like state \(interaction.liked) for video \(video.id)")
        }
    }

    private func handleVideoDisappear(video: VideoClip) {
        playerManager.pauseVideo(for: video.videoURL, videoId: video.id)

        // Clean up control states
        showVideoControls[video.id] = false
        controlsVisible[video.id] = false
        controlShowTimes.removeValue(forKey: video.id)
        heartAnimations[video.id] = nil
    }

    private func handleIndexChange(_ newIndex: Int) {
        if newIndex < filteredVideos.count {
            let currentVideo = filteredVideos[newIndex]
            print("🎬 Scroll detected - switching to video index: \(newIndex), ID: \(currentVideo.id)")
            playerManager.playVideo(for: currentVideo.videoURL, videoId: currentVideo.id)
            // Preload next 5 videos to disk
            playerManager.updatePreloadQueue(currentIndex: newIndex, clips: filteredVideos, count: 5)
            localStorage.recordView(videoId: currentVideo.id)
            pausedVideos[currentVideo.id] = false
            
            // Update game name for the "watch more" functionality
            selectedGameName = extractGameName(from: currentVideo)
        }
    }

    private func handleSportSelection(_ sport: VideoClip.Sport) {
        print("🎬 Sport selected: \(sport.rawValue)")
        selectedSport = sport
        localStorage.saveLastHighlightsCategory(sport.rawValue)
        filterVideos()
    }
    
    private func handleNavigationToVideo(videoId: String) {
        // Find the video index in the filtered videos
        if let videoIndex = filteredVideos.firstIndex(where: { $0.id == videoId }) {
            // Scroll to the video
            currentIndex = videoIndex
            
            // If we need to open comments, we'll handle that in the video overlay
            if localStorage.shouldOpenComments {
                // The comment opening will be handled by the video overlay
                // Clear the navigation state after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    localStorage.clearNavigation()
                }
            }
        } else {
            // Video not found in current filtered list, clear navigation
            localStorage.clearNavigation()
        }
    }

    private func handleGameTap(for video: VideoClip) {
        Task {
            guard let gameId = video.gameId else {
                print("No gameId available")
                return
            }

            do {
                let game = try await APIClient.shared.getGame(gameId: gameId)

                // Update UI on main thread
                await MainActor.run {
                    self.selectedGameName = game.name
                    self.selectedGameId = gameId
                    if !self.selectedGameId.isEmpty {
                        self.showingGameClips = true
                    }
                }
            } catch {
                print("Failed to fetch game: \(error)")
            }
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
        controlsVisible[video.id] = true
        let removedTime = controlShowTimes.removeValue(forKey: video.id)
        print("🎬 Drag started for video: \(video.id)")
        print("🎬 Removed show time: \(removedTime?.description ?? "none")")
    }

    private func handleDragEnd(for video: VideoClip) {
        let newShowTime = Date()
        controlShowTimes[video.id] = newShowTime
        print("🎬 Drag ended for video: \(video.id)")
        print("🎬 New show time recorded: \(newShowTime)")
    }

    private func handleLocalStorageChange() {
        print("🔄 VideoFeedView: LocalStorage interactions changed, refreshing state")

        for video in filteredVideos {
            if let interaction = localStorage.getInteraction(for: video.id) {
                let storedLikedState = interaction.liked
                if videoLikeStates[video.id] != storedLikedState {
                    videoLikeStates[video.id] = storedLikedState
                    print("🔄 VideoFeedView: Updated like state to \(storedLikedState) for video \(video.id)")
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
        controlsVisible.removeAll()
        controlShowTimes.removeAll()
        heartAnimations.removeAll()

        print("🎬 VideoFeedView disappeared - cleaned up resources")
    }

    // MARK: - Data Loading Methods
    private func loadVideos() {
        guard !isLoading else { return }

        isLoading = true
        Task {
            do {
                let page = try await apiService.fetchFeedPage(
                    limit: 10,
                    cursor: nil,
                    sport: selectedSport == .all ? nil : APIClient.APISport(rawValue: selectedSport.rawValue)
                )
                await MainActor.run {
                    self.nextCursor = page.nextCursor
                    self.allVideos = page.videos
                    self.videos = page.videos
                    self.filterVideos()
                    self.isLoading = false

                    if !filteredVideos.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            autoPlayFirstVideo()
                        }
                    }

                    preloadMoreVideos()
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    private func autoPlayFirstVideo() {
        guard !filteredVideos.isEmpty else { return }

        print("🎬 Auto-playing first video after load: \(filteredVideos[0].id)")
        playerManager.playVideo(for: filteredVideos[0].videoURL, videoId: filteredVideos[0].id)
        // Preload next 5 videos to disk starting from index 0
        playerManager.updatePreloadQueue(currentIndex: 0, clips: filteredVideos, count: 5)
        localStorage.recordView(videoId: filteredVideos[0].id)
        Task { await apiService.markViewed(clipId: filteredVideos[0].id) }
        pausedVideos[filteredVideos[0].id] = false
    }

    private func preloadMoreVideos() {
        guard !isLoadingMore else { return }

        isLoadingMore = true
        Task {
            do {
                let page = try await apiService.fetchFeedPage(
                    limit: 10,
                    cursor: nextCursor,
                    sport: selectedSport == .all ? nil : APIClient.APISport(rawValue: selectedSport.rawValue)
                )
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

    private func filterVideos() {
        print("🎬 Filtering videos for sport: \(selectedSport.rawValue)")
        print("🎬 Total videos before filtering: \(videos.count)")

        if selectedSport == .all {
            filteredVideos = videos.shuffled()
            print("🎬 Randomized all videos for 'All' tab")
        } else {
            filteredVideos = videos.filter { $0.sport == selectedSport }
        }

        print("🎬 Filtered videos count: \(filteredVideos.count)")
        currentIndex = 0

        if !filteredVideos.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                autoPlayFirstVideo()
            }
        }
    }

    // MARK: - Interaction Handlers
    private func handleSingleTap(for video: VideoClip) {
        guard !(controlsVisible[video.id] ?? false) else {
            print("🎬 Single tap ignored - controls are visible")
            return
        }

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

    private func handleDoubleTapLike(for video: VideoClip, at location: CGPoint) {
        let currentLikeState = videoLikeStates[video.id] ?? false
        let newLikeState = !currentLikeState

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            videoLikeStates[video.id] = newLikeState
        }

        localStorage.recordInteraction(
            videoId: video.id,
            liked: newLikeState,
            commented: false,
            shared: false
        )

        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()

        let heartAnimation = HeartAnimation(
            id: UUID().uuidString,
            location: location,
            isLiked: newLikeState
        )
        heartAnimations[video.id] = heartAnimation

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            heartAnimations.removeValue(forKey: video.id)
        }

        Task {
            do {
                try await apiService.likeVideo(clipId: video.id)
                print("✅ Successfully liked/unliked video via double-tap: \(video.id)")
            } catch {
                print("❌ Failed to like/unlike video via double-tap: \(error)")
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        videoLikeStates[video.id] = !newLikeState
                    }
                }
            }
        }

        DispatchQueue.main.async {
            self.currentIndex = self.currentIndex
        }

        print("🎬 Double tapped to like video: \(video.id), new state: \(newLikeState)")
    }

    private func handleLongPress(for video: VideoClip) {
        let showTime = Date()
        showVideoControls[video.id] = true
        controlsVisible[video.id] = true
        controlShowTimes[video.id] = showTime

        print("🎬 Long pressed to show controls for video: \(video.id)")
    }

    // MARK: - Helper Methods
    private func extractGameName(from video: VideoClip) -> String {
        let textToAnalyze = video.title ?? video.description ?? video.caption
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

        // Fallback to first few words
        let words = textToAnalyze.components(separatedBy: " ")
        if words.count >= 2 {
            return "\(words[0]) \(words[1])"
        }

        return "Game Highlights"
    }

    // MARK: - Video Control Methods
    private func getCurrentTime(for videoId: String) -> Double {
        if filteredVideos.contains(where: { $0.id == videoId }) {
            return currentVideoTimes[videoId] ?? 0.0
        }
        return 0.0
    }

    private func getDuration(for videoId: String) -> Double {
        if filteredVideos.contains(where: { $0.id == videoId }) {
            return 596.0 // Fallback for BigBuckBunny
        }
        return 596.0
    }

    private func seekToTime(for videoId: String, time: Double) {
        if let video = filteredVideos.first(where: { $0.id == videoId }) {
            playerManager.seekVideo(for: video.videoURL, videoId: video.id, to: time)
        }
    }

    // MARK: - Timer Management
    private func startTimeUpdateTimer() {
        timeUpdateTimer?.invalidate()

        print("🎬 Starting time update timer for VideoFeedView")

        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                updateVideoTimes()
                checkControlVisibility()
            }
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
                    print("🎬 Timer check: Hiding controls for video \(video.id)")
                    showVideoControls[video.id] = false
                    controlsVisible[video.id] = false
                    controlShowTimes.removeValue(forKey: video.id)
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

// MARK: - Sport Bubble Component
struct SportBubble: View {
    let sport: VideoClip.Sport
    let isSelected: Bool
    let action: () -> Void
    let currentVideoSport: VideoClip.Sport?
    let selectedSport: VideoClip.Sport

    @State private var isPressed = false
    @State private var previousSport: VideoClip.Sport? = nil
    @State private var animationOpacity: Double = 1.0
    
    private var dynamicSportText: String {
        if sport == .all {
            if selectedSport != .all {
                return "All"
            }
            else if let currentSport = currentVideoSport, currentSport != .all {
                return "All - \(currentSport.rawValue)"
            }
        }
        return sport.rawValue
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: sport.icon)  //   Remove SwiftUI prefix
                    .imageScale(.medium)
                    .symbolEffect(.bounce, value: isSelected)
                    .foregroundColor(sport == .all ? Color.red : (isSelected ? Color.white : Color.white.opacity(0.7)))

                Text(dynamicSportText)
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .opacity(animationOpacity)
                    .frame(height: 16)
                    .clipped()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.1))  // Use consistent Color
                            .blur(radius: 6)
                            .scaleEffect(1.1)
                    }

                    Capsule()
                        .fill(isSelected ? .ultraThinMaterial : .thinMaterial)
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(isSelected ? 0.3 : 0.1),
                                            Color.white.opacity(isSelected ? 0.15 : 0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: isSelected ? 1.2 : 0.8
                                )
                        )
                        .shadow(
                            color: Color.black.opacity(isSelected ? 0.15 : 0.08),
                            radius: isSelected ? 6 : 3,
                            x: 0,
                            y: isSelected ? 3 : 1
                        )
                }
            )
        }
        .onChange(of: currentVideoSport) { oldValue, newValue in
            if sport == .all && oldValue != newValue && oldValue != nil && newValue != nil {
                withAnimation(.easeInOut(duration: 0.3)) {
                    animationOpacity = 0.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        animationOpacity = 1.0
                    }
                }
            }
        }
        .onChange(of: selectedSport) { oldValue, newValue in
            if sport == .all && oldValue != newValue {
                withAnimation(.easeInOut(duration: 0.3)) {
                    animationOpacity = 0.0
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        animationOpacity = 1.0
                    }
                }
            }
        }
        .onAppear {
            previousSport = currentVideoSport
        }
    }
}

#Preview {
    VideoFeedView()
}
