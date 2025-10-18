//
//  VideoFeedView.swift
//  sportsclips
//
//  Main vertical scroll feed (Highlight tab)
//

import SwiftUI

struct VideoFeedView: View {
    private let apiService = APIService.shared
    @StateObject private var playerManager = VideoPlayerManager()
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var videos: [VideoClip] = []
    @State private var filteredVideos: [VideoClip] = []
    @State private var currentIndex = 0
    @State private var isLoading = false
    @State private var selectedSport: VideoClip.Sport = .all
    
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
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredVideos.enumerated()), id: \.element.id) { index, video in
                                VideoPlayerView(video: video)
                                    .frame(height: UIScreen.main.bounds.height)
                                    .id(index)
                                    .onAppear {
                                        // Play video when it appears on screen
                                        playerManager.playVideo(for: video.videoURL)
                                        localStorage.recordView(videoId: video.id)
                                        
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
                                .frame(height: 100)
                            }
                        }
                    }
                    .scrollTargetBehavior(.paging)
                    .onChange(of: currentIndex) { _, newIndex in
                        // Pause all videos when scrolling
                        playerManager.pauseAllVideos()
                    }
                }
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
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 50) // Account for status bar
                    
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

#Preview {
    VideoFeedView()
}
