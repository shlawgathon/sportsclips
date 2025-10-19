//
//  LiveView.swift
//  sportsclips
//
//  TikTok-style vertical scrolling live videos with live comments
//

import SwiftUI

struct LiveView: View {
    private let apiService = APIService.shared
    @StateObject private var playerManager = VideoPlayerManager.shared
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var liveVideos: [VideoClip] = []
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
                // Empty state
                VStack(spacing: 20) {
                    Image(systemName: "video.circle")
                        .font(.system(size: 80, weight: .light))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Text("No Live Streams")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Check back later for live sports")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
            } else {
                // TikTok-style vertical scroll - each scroll is full screen
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(filteredVideos.enumerated()), id: \.element.id) { index, video in
                                LiveVideoCell(
                                    video: video,
                                    playerManager: playerManager,
                                    selectedSport: $selectedSport,
                                    onSportChange: { newSport in
                                        selectedSport = newSport
                                        refreshFeedForSport(newSport)
                                    }
                                )
                                .containerRelativeFrame([.horizontal, .vertical])
                                .id(index)
                                    .onAppear {
                                        currentIndex = index
                                        playerManager.playVideo(for: video.videoURL, videoId: video.id)
                                        localStorage.recordView(videoId: video.id)
                                        
                                        if index >= filteredVideos.count - 2 {
                                            loadMoreVideos()
                                        }
                                    }
                            }
                            
                            // Loading indicator
                            if isLoading {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(1.2)
                                    Spacer()
                                }
                                .containerRelativeFrame(.vertical)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .ignoresSafeArea()
                }
            }
        }
        .onAppear {
            loadLiveVideos()
        }
    }
    
    private func loadLiveVideos() {
        guard !isLoading else { return }
        
        isLoading = true
        Task {
            do {
                // TODO: Replace with actual live streams endpoint
                let videos = try await apiService.fetchVideos()
                await MainActor.run {
                    self.liveVideos = videos
                    // Filter by sport and randomize order when "All" is selected
                    if self.selectedSport == .all {
                        self.filteredVideos = videos.shuffled()
                    } else {
                        self.filteredVideos = videos.filter { $0.sport == self.selectedSport }
                    }
                    self.isLoading = false
                    
                    // Auto-play first video
                    if !filteredVideos.isEmpty {
                        playerManager.playVideo(for: filteredVideos[0].videoURL, videoId: filteredVideos[0].id)
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
                let newVideos = try await apiService.fetchVideos(page: (liveVideos.count / 10) + 1)
                await MainActor.run {
                    self.liveVideos.append(contentsOf: newVideos)
                    // Filter by sport and randomize order when "All" is selected
                    if self.selectedSport == .all {
                        self.filteredVideos.append(contentsOf: newVideos.shuffled())
                    } else {
                        let filteredNewVideos = newVideos.filter { $0.sport == self.selectedSport }
                        self.filteredVideos.append(contentsOf: filteredNewVideos)
                    }
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func refreshFeedForSport(_ sport: VideoClip.Sport) {
        // Reset the video lists
        liveVideos = []
        filteredVideos = []
        currentIndex = 0
        
        // Load fresh videos for the selected sport
        loadLiveVideos()
    }
    
}

#Preview {
    LiveView()
}
