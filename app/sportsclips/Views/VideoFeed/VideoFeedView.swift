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
    @StateObject private var playerManager = VideoPlayerManager()
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
    @State private var currentVideoTimes: [String: Double] = [:] // Track current time for each video
    @State private var allVideos: [VideoClip] = [] // All loaded videos
    @State private var currentVideoIndex: Int = 0 // Current video being viewed
    @State private var isLoadingMore: Bool = false // Loading more videos
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if filteredVideos.isEmpty && isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            } else if filteredVideos.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "flame")
                        .font(.system(size: 60, weight: .light))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text("No videos available")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
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
                                            .gesture(
                                                // Combined gesture to handle tap, double tap, and long press
                                                DragGesture(minimumDistance: 0)
                                                    .onEnded { value in
                                                        // Single tap (no drag)
                                                        if abs(value.translation.x) < 10 && abs(value.translation.y) < 10 {
                                                            handleSingleTap(for: video)
                                                        }
                                                    }
                                                    .simultaneously(with:
                                                        TapGesture(count: 2)
                                                            .onEnded { _ in
                                                                // Double tap to like
                                                                let location = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                                                handleDoubleTapLike(for: video, at: location)
                                                            }
                                                    )
                                                    .simultaneously(with:
                                                        LongPressGesture(minimumDuration: 0.5)
                                                            .onChanged { _ in
                                                                handleLongPress(for: video)
                                                            }
                                                            .onEnded { _ in
                                                                handleLongPressEnd(for: video)
                                                            }
                                                    )
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
                                                        self.selectedGameName = self.extractGameName(from: video.caption)
                                                        self.showingGameClips = true
                                                    },
                                                    showControls: showVideoControls[video.id] ?? false,
                                                    currentTime: currentVideoTimes[video.id] ?? 0,
                                                    duration: getDuration(for: video.id),
                                                    onSeek: { time in
                                                        seekToTime(for: video.id, time: time)
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
                                            .padding(.bottom, 80) // Same gap for both states
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
                                                    playerManager.playVideo(for: video.videoURL)
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
                                        playerManager.playVideo(for: video.videoURL)
                                        localStorage.recordView(videoId: video.id)
                                        
                                        // Check if we need to load more videos (when approaching end)
                                        if index >= filteredVideos.count - 3 && !isLoadingMore {
                                            preloadMoreVideos()
                                        }
                                        
                                        // Load like state from local storage
                                        if let interaction = localStorage.getInteraction(for: video.id) {
                                            videoLikeStates[video.id] = interaction.liked
                                        }
                                        
                                        // Load more videos if near end
                                        if index >= filteredVideos.count - 2 && !isLoadingMore {
                                            preloadMoreVideos()
                                        }
                                    }
                                    .onDisappear {
                                        // Pause video when it disappears
                                        playerManager.pauseVideo(for: video.videoURL)
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
                        .onChange(of: currentIndex) { _, newIndex in
                            // Pause all videos when scrolling
                            playerManager.pauseAllVideos()
                            
                            // Play the current video
                            if newIndex < filteredVideos.count {
                                let currentVideo = filteredVideos[newIndex]
                                playerManager.playVideo(for: currentVideo.videoURL)
                                localStorage.recordView(videoId: currentVideo.id)
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
                                        selectedSport = sport
                                        filterVideos()
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 8) // Minimal top padding
                    
                    Spacer()
                }
                
                Spacer()
            }
        }
        .onAppear {
            loadVideos()
            startTimeUpdateTimer()
        }
        .onDisappear {
            playerManager.pauseAllVideos()
        }
    }
    
    private func loadVideos() {
        guard !isLoading else { return }
        
        isLoading = true
        Task {
            do {
                // Load initial batch of videos
                let initialVideos = try await apiService.fetchVideos()
                await MainActor.run {
                    self.allVideos = initialVideos
                    self.videos = initialVideos
                    self.filterVideos()
                    self.isLoading = false
                    
                    // Auto-play first video
                    if !filteredVideos.isEmpty {
                        playerManager.playVideo(for: filteredVideos[0].videoURL)
                        localStorage.recordView(videoId: filteredVideos[0].id)
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
            // Simulate loading 8 more videos sequentially (not in parallel)
            for i in 1...8 {
                do {
                    // Simulate API delay
                    try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds between each
                    
                    // Generate new video with unique content
                    let newVideo = generateNewVideo(index: allVideos.count + i)
                    
                    await MainActor.run {
                        self.allVideos.append(newVideo)
                        self.videos = self.allVideos
                        self.filterVideos()
                    }
                } catch {
                    print("Error preloading video \(i): \(error)")
                }
            }
            
            await MainActor.run {
                self.isLoadingMore = false
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
            createdAt: Date()
        )
    }
    
    private func filterVideos() {
        if selectedSport == .all {
            filteredVideos = videos
        } else {
            filteredVideos = videos.filter { $0.sport == selectedSport }
        }
        currentIndex = 0
        
        // Auto-play first video after filtering
        if !filteredVideos.isEmpty {
            playerManager.playVideo(for: filteredVideos[0].videoURL)
            localStorage.recordView(videoId: filteredVideos[0].id)
        }
    }
    
    private func handleDoubleTapLike(for video: VideoClip, at location: CGPoint) {
        // Toggle like state
        let currentLikeState = videoLikeStates[video.id] ?? false
        let newLikeState = !currentLikeState
        videoLikeStates[video.id] = newLikeState
        
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
        
        print("Double tapped to \(newLikeState ? "like" : "unlike") video: \(video.id)")
    }
    
    private func handleSingleTap(for video: VideoClip) {
        // Toggle play/pause on single tap
        let player = playerManager.getPlayer(for: video.videoURL)
        if player.timeControlStatus == .playing {
            playerManager.pauseVideo(for: video.videoURL)
            pausedVideos[video.id] = true
        } else {
            playerManager.playVideo(for: video.videoURL)
            pausedVideos[video.id] = false
        }
        print("Single tapped to toggle play/pause for video: \(video.id)")
    }
    
    private func handleLongPress(for video: VideoClip) {
        // Show controls on long press - they stay visible until user releases
        showVideoControls[video.id] = true
        
        print("🎬 Long pressed to show controls for video: \(video.id)")
        print("🎬 showVideoControls[\(video.id)] = \(showVideoControls[video.id] ?? false)")
    }
    
    private func handleLongPressEnd(for video: VideoClip) {
        // Hide controls after 3 second delay to allow adjustment
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            showVideoControls[video.id] = false
            print("🎬 Long press ended - hiding controls for video: \(video.id) after 3s delay")
        }
    }
    
    private func extractGameName(from caption: String) -> String {
        // Extract game name from caption (simple implementation)
        // For now, return the first part of the caption or a default
        let words = caption.components(separatedBy: " ")
        if words.count >= 2 {
            return "\(words[0]) \(words[1])"
        }
        return "Game Highlights"
    }
    
    private func getCurrentTime(for videoId: String) -> Double {
        // Get current time from the video that matches this ID
        if let video = filteredVideos.first(where: { $0.id == videoId }) {
            return playerManager.getCurrentTime(for: video.videoURL)
        }
        return 0.0
    }
    
    private func getDuration(for videoId: String) -> Double {
        // Get duration from the video that matches this ID
        if let video = filteredVideos.first(where: { $0.id == videoId }) {
            let duration = playerManager.getDuration(for: video.videoURL)
            return duration > 0 ? duration : 596.0 // Fallback for BigBuckBunny
        }
        return 596.0
    }
    
    private func seekToTime(for videoId: String, time: Double) {
        // Seek the video that matches this ID
        if let video = filteredVideos.first(where: { $0.id == videoId }) {
            playerManager.seekVideo(for: video.videoURL, to: time)
        }
    }
    
    private func startTimeUpdateTimer() {
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            // Update current time for all videos
            for video in filteredVideos {
                let currentTime = playerManager.getCurrentTime(for: video.videoURL)
                currentVideoTimes[video.id] = currentTime
            }
        }
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
                
                Text(sport.rawValue)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? .white : .white.opacity(0.7))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
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

struct HeartAnimation {
    let id: String
    let location: CGPoint
    let isLiked: Bool
}

struct HeartAnimationView: View {
    let animation: HeartAnimation
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 1.0
    @State private var offset: CGFloat = 0
    
    var body: some View {
        Image(systemName: animation.isLiked ? "heart.fill" : "heart")
            .font(.system(size: 60, weight: .bold))
            .foregroundColor(animation.isLiked ? .red : .white)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(y: offset)
            .position(animation.location)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = 1.2
                }
                
                withAnimation(.easeOut(duration: 1.0).delay(0.1)) {
                    offset = -50
                    opacity = 0.0
                }
                
                withAnimation(.easeIn(duration: 0.2).delay(0.8)) {
                    scale = 0.8
                }
            }
    }
}


#Preview {
    VideoFeedView()
}
