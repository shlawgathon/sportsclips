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
                                            .onTapGesture(count: 1) { location in
                                                // Single tap to pause/play
                                                handleSingleTap(for: video)
                                            }
                                            .onTapGesture(count: 2) { location in
                                                // Double tap to like with location
                                                handleDoubleTapLike(for: video, at: location)
                                            }
                                            .onLongPressGesture(minimumDuration: 0.5) {
                                                // Long press to show controls
                                                handleLongPress(for: video)
                                            }
                                            .zIndex(1) // Above video player
                                        
                                        // Video overlay with buttons and caption
                                        VStack {
                                            Spacer()
                                            
                                            HStack(alignment: .bottom) {
                                                // Caption on the left
                                                CaptionView(video: video)
                                                
                                                Spacer()
                                                
                                                // Action buttons on the right
                                                VideoOverlayView(
                                                    video: video,
                                                    isLiked: videoLikeStates[video.id] ?? false
                                                )
                                            }
                                            .padding(.bottom, 120) // Higher to avoid bottom menu overlap
                                        }
                                        .zIndex(2) // Above everything else
                                        
                                        // Heart animation overlay
                                        if let heartAnimation = heartAnimations[video.id] {
                                            HeartAnimationView(animation: heartAnimation)
                                                .zIndex(3) // Above everything
                                        }
                                        
                                        // Custom video controls
                                        CustomVideoControls(
                                            video: video,
                                            showControls: showVideoControls[video.id] ?? false,
                                            playerManager: playerManager,
                                            pausedVideos: $pausedVideos
                                        )
                                            .zIndex(4) // Above everything including heart
                                        
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
                                        playerManager.playVideo(for: video.videoURL)
                                        localStorage.recordView(videoId: video.id)
                                        
                                        // Load like state from local storage
                                        if let interaction = localStorage.getInteraction(for: video.id) {
                                            videoLikeStates[video.id] = interaction.liked
                                        }
                                        
                                        // Load more videos if near end
                                        if index >= filteredVideos.count - 2 {
                                            loadMoreVideos()
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
                let newVideos = try await apiService.fetchVideos()
                await MainActor.run {
                    self.videos = newVideos
                    self.filterVideos()
                    self.isLoading = false
                    
                    // Auto-play first video
                    if !filteredVideos.isEmpty {
                        playerManager.playVideo(for: filteredVideos[0].videoURL)
                        localStorage.recordView(videoId: filteredVideos[0].id)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadMoreVideos() {
        guard !isLoading else { return }
        
        isLoading = true
        Task {
            do {
                let newVideos = try await apiService.fetchVideos(page: (videos.count / 10) + 1)
                await MainActor.run {
                    self.videos.append(contentsOf: newVideos)
                    self.filterVideos()
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
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
        // Show controls on long press
        showVideoControls[video.id] = true
        
        // Auto-hide controls after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            showVideoControls[video.id] = false
        }
        
        print("Long pressed to show controls for video: \(video.id)")
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

struct CustomVideoControls: View {
    let video: VideoClip
    let showControls: Bool
    @ObservedObject var playerManager: VideoPlayerManager
    @Binding var pausedVideos: [String: Bool] // Add binding to track paused state
    @State private var isPlaying = true
    @State private var playbackRate: Float = 1.0
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isDragging = false
    
    var body: some View {
        VStack {
            Spacer()
            
                    // Bottom controls bar
                    VStack(spacing: 12) {
                        // Progress slider - raised up
                        HStack {
                            Text(formatTime(currentTime))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 40)
                            
                            Slider(value: $currentTime, in: 0...max(duration, 1.0), onEditingChanged: { editing in
                                isDragging = editing
                                if !editing {
                                    print("🎬 Seeking to: \(currentTime) seconds")
                                    seekToTime(currentTime)
                                }
                            })
                            .accentColor(.white)
                            .frame(height: 20)
                            
                            Text(formatTime(duration))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 40)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8) // Raise the slider up
                
                // Control buttons
                HStack(spacing: 30) {
                    // Play/Pause button
                    Button(action: togglePlayPause) {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .medium))
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
                    
                    // Speed button
                    Button(action: toggleSpeed) {
                        Text("\(playbackRate == 1.0 ? "1x" : "2x")")
                            .font(.system(size: 16, weight: .semibold))
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
                    .onLongPressGesture(minimumDuration: 0.5) {
                        // Long press for 2x speed
                        setSpeed(2.0)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
            .background(
                LinearGradient(
                    colors: [.clear, .black.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
                .opacity(showControls ? 1 : 0)
                .onAppear {
                    setupPlayerObserver()
                }
    }
    
    private func togglePlayPause() {
        print("🎬 Toggle Play/Pause - Current state: \(isPlaying)")
        if isPlaying {
            playerManager.pauseVideo(for: video.videoURL)
            // Set paused state to show glass button
            pausedVideos[video.id] = true
        } else {
            playerManager.playVideo(for: video.videoURL)
            // Clear paused state to hide glass button
            pausedVideos[video.id] = false
        }
        isPlaying.toggle()
        print("🎬 New state: \(isPlaying)")
    }
    
    private func toggleSpeed() {
        playbackRate = playbackRate == 1.0 ? 2.0 : 1.0
        setSpeed(playbackRate)
    }
    
    private func setSpeed(_ speed: Float) {
        playbackRate = speed
        let player = playerManager.getPlayer(for: video.videoURL)
        player.rate = playbackRate
        print("🎬 Set speed to: \(playbackRate)x")
    }
    
    private func seekToTime(_ time: Double) {
        playerManager.seekVideo(for: video.videoURL, to: time)
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func setupPlayerObserver() {
        let player = playerManager.getPlayer(for: video.videoURL)
        
        // Initialize current time and playing state using VideoPlayerManager methods
        currentTime = playerManager.getCurrentTime(for: video.videoURL)
        isPlaying = playerManager.isPlaying(for: video.videoURL)
        
        // Set initial duration with fallback
        let playerDuration = playerManager.getDuration(for: video.videoURL)
        if playerDuration > 0 {
            self.duration = playerDuration
        } else {
            // Fallback duration for mock videos (BigBuckBunny is ~596 seconds)
            self.duration = 596.0
        }
        
        print("🎬 Video Controls Setup:")
        print("🎬 Current Time: \(currentTime)")
        print("🎬 Is Playing: \(isPlaying)")
        print("🎬 Duration: \(duration)")
        print("🎬 Player Rate: \(player.rate)")
        
        // Observe time changes - using CMTimeMake like the tutorial
        _ = player.addPeriodicTimeObserver(forInterval: CMTimeMake(value: 1, timescale: 10), queue: .main) { time in
            if !isDragging {
                let timeSeconds = time.seconds
                if timeSeconds.isFinite && timeSeconds >= 0 {
                    currentTime = timeSeconds
                }
            }
        }
    }
}

#Preview {
    VideoFeedView()
}
