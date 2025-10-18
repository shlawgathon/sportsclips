//
//  GameClipsView.swift
//  sportsclips
//
//  Game-specific clips feed view
//

import SwiftUI
import AVFoundation

struct GameClipsView: View {
    let gameName: String
    @StateObject private var playerManager = VideoPlayerManager()
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
                                            .onTapGesture(count: 1) { location in
                                                handleSingleTap(for: video)
                                            }
                                            .onTapGesture(count: 2) { location in
                                                handleDoubleTapLike(for: video, at: location)
                                            }
                                            .onLongPressGesture(minimumDuration: 0.5, maximumDistance: .infinity, pressing: { pressing in
                                                if pressing {
                                                    handleLongPress(for: video)
                                                } else {
                                                    handleLongPressEnd(for: video)
                                                }
                                            }, perform: {})
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
                                                    playerManager.playVideo(for: video.videoURL)
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
                                        playerManager.playVideo(for: video.videoURL)
                                        localStorage.recordView(videoId: video.id)
                                        
                                        if let interaction = localStorage.getInteraction(for: video.id) {
                                            videoLikeStates[video.id] = interaction.liked
                                        }
                                    }
                                    .onDisappear {
                                        playerManager.pauseVideo(for: video.videoURL)
                                    }
                                }
                            }
                        }
                        .scrollTargetBehavior(.paging)
                        .onChange(of: currentIndex) { _, newIndex in
                            playerManager.pauseAllVideos()
                            
                            if newIndex < videos.count {
                                let currentVideo = videos[newIndex]
                                playerManager.playVideo(for: currentVideo.videoURL)
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
                    
                    Text(gameName)
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
            loadGameClips()
            startTimeUpdateTimer()
        }
        .onDisappear {
            playerManager.pauseAllVideos()
        }
    }
    
    private func loadGameClips() {
        guard !isLoading else { return }
        
        isLoading = true
        Task {
            do {
                // Filter videos by game name (using caption as game identifier for now)
                let allVideos = try await APIService.shared.fetchVideos()
                let gameVideos = allVideos.filter { video in
                    video.caption.lowercased().contains(gameName.lowercased())
                }
                
                await MainActor.run {
                    self.videos = gameVideos
                    self.isLoading = false
                    
                    if !gameVideos.isEmpty {
                        playerManager.playVideo(for: gameVideos[0].videoURL)
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
        let player = playerManager.getPlayer(for: video.videoURL)
        if player.timeControlStatus == .playing {
            playerManager.pauseVideo(for: video.videoURL)
            pausedVideos[video.id] = true
        } else {
            playerManager.playVideo(for: video.videoURL)
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
        // Show controls on long press - they stay visible until user releases
        showVideoControls[video.id] = true
        print("🎬 Long pressed to show controls for video: \(video.id)")
    }
    
    private func handleLongPressEnd(for video: VideoClip) {
        // Hide controls after 3 second delay to allow adjustment
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            showVideoControls[video.id] = false
            print("🎬 Long press ended - hiding controls for video: \(video.id) after 3s delay")
        }
    }
    
    private func getCurrentTime(for videoId: String) -> Double {
        // Get current time from the video that matches this ID
        if let video = self.filteredVideos.first(where: { $0.id == videoId }) {
            return playerManager.getCurrentTime(for: video.videoURL)
        }
        return 0.0
    }
    
    private func getDuration(for videoId: String) -> Double {
        // Get duration from the video that matches this ID
        if let video = self.filteredVideos.first(where: { $0.id == videoId }) {
            let duration = playerManager.getDuration(for: video.videoURL)
            return duration > 0 ? duration : 596.0 // Fallback for BigBuckBunny
        }
        return 596.0
    }
    
    private func seekToTime(for videoId: String, time: Double) {
        // Seek the video that matches this ID
        if let video = self.filteredVideos.first(where: { $0.id == videoId }) {
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

#Preview {
    GameClipsView(gameName: "Football")
}
