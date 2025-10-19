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
    @State private var showSportDropdown = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            
            if filteredVideos.isEmpty && isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            } else if filteredVideos.isEmpty {
                // Empty state with exact same structure as LiveVideoCell
                ZStack {
                    // Top bar - exact same structure as LiveVideoCell
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            // Sport filter button (round, on the left)
                            Button(action: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.1)) {
                                    showSportDropdown.toggle()
                                }
                            }) {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 13, weight: .medium))
                                    .rotationEffect(.degrees(showSportDropdown ? 180 : 0))
                                    .scaleEffect(showSportDropdown ? 1.1 : 1.0)
                            }
                            .foregroundColor(.white)
                            .padding(8)
                            .background(
                                ZStack {
                                    // Liquid glass background with bubble effect
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [
                                                            .white.opacity(showSportDropdown ? 0.5 : 0.3),
                                                            .white.opacity(showSportDropdown ? 0.3 : 0.1)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: showSportDropdown ? 2.0 : 1.5
                                                )
                                        )
                                        .shadow(
                                            color: .white.opacity(showSportDropdown ? 0.4 : 0.2), 
                                            radius: showSportDropdown ? 12 : 8, 
                                            x: 0, 
                                            y: showSportDropdown ? 4 : 2
                                        )
                                        .scaleEffect(showSportDropdown ? 1.05 : 1.0)

                                    // White tint overlay with bubble effect
                                    Circle()
                                        .fill(.white.opacity(showSportDropdown ? 0.2 : 0.1))
                                        .scaleEffect(showSportDropdown ? 1.1 : 1.0)
                                }
                            )

                            // Sport tag with LIVE indicator (greyed out)
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(.gray.opacity(0.6))
                                    .frame(width: 8, height: 8)

                                // Show icon if it exists in SF Symbols, otherwise show sport name
                                if UIImage(systemName: selectedSport.icon) != nil {
                                    Image(systemName: selectedSport.icon)
                                        .font(.system(size: 13, weight: .medium))
                                } else {
                                    Text(selectedSport.rawValue)
                                        .font(.system(size: 12, weight: .semibold))
                                }

                                Text("LIVE")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .frame(minWidth: 80)
                            .foregroundColor(.white.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                ZStack {
                                    // Liquid glass background (greyed out)
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .overlay(
                                            Capsule()
                                                .stroke(
                                                    LinearGradient(
                                                        colors: [
                                                            .gray.opacity(0.4),
                                                            .gray.opacity(0.2)
                                                        ],
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    ),
                                                    lineWidth: 1.5
                                                )
                                        )
                                        .shadow(color: .gray.opacity(0.2), radius: 8, x: 0, y: 2)

                                    // Grey tint overlay
                                    Capsule()
                                        .fill(.gray.opacity(0.2))
                                }
                            )

                            Spacer()

                            // Views and likes in column (greyed out)
                            VStack(spacing: 8) {
                                // View count
                                HStack(spacing: 4) {
                                    Image(systemName: "eye.fill")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.4))

                                    Text("--")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial.opacity(0.5), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(.white.opacity(0.1), lineWidth: 1)
                                )

                                // Like counter
                                HStack(spacing: 4) {
                                    Image(systemName: "heart")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.4))

                                    Text("--")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial.opacity(0.5), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(.white.opacity(0.1), lineWidth: 1)
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 50)

                        Spacer()
                    }
                    .zIndex(2)

                    // Overlay content - exact same structure as LiveVideoCell
                    VStack(spacing: 0) {
                        Spacer()

                        // Left side - Caption and live comments (greyed out)
                        VStack(alignment: .leading, spacing: 8) {
                            // Live comments section (greyed out) - same structure as LiveVideoCell
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "bubble.left.and.bubble.right")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.4))

                                    Text("Live Comments")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.6))
                                }

                                Text("No comments available")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                                    .padding(.top, 4)
                            }
                            .frame(maxHeight: 180)

                            // Live summary section (greyed out) - matches LiveVideoCell structure
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "livephoto")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.4))

                                    Text("Live Summary")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.6))

                                    Text("-")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))

                                    Text("...")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.5))

                                    Spacer()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)

                        // Comment input with share button (greyed out)
                        HStack(spacing: 10) {
                            // Share button (greyed out)
                            Button(action: {}) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.white.opacity(0.4))
                                    .padding(10)
                                    .background(.ultraThinMaterial.opacity(0.5), in: Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(.white.opacity(0.1), lineWidth: 1)
                                    )
                            }
                            .disabled(true)

                            // Comment input field (greyed out)
                            TextField("Comments disabled", text: .constant(""))
                                .font(.system(size: 14))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 24))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 24)
                                        .stroke(.white.opacity(0.2), lineWidth: 1.5)
                                )
                                .foregroundColor(.white.opacity(0.5))
                                .disabled(true)

                            // Send button (greyed out)
                            Button(action: {}) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(.gray.opacity(0.5))
                                    .padding(10)
                                    .background(.ultraThinMaterial.opacity(0.5), in: Circle())
                                    .overlay(
                                        Circle()
                                            .stroke(.white.opacity(0.1), lineWidth: 1)
                                    )
                            }
                            .disabled(true)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 88) // Same gap as highlights page
                        .background(
                            Rectangle()
                                .fill(.black.opacity(0.3))
                        )
                    }
                    .zIndex(20) // Same zIndex as LiveVideoCell
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
            
            // Sport filter dropdown for empty state - positioned as overlay with bubble animation
            if showSportDropdown && filteredVideos.isEmpty {
                VStack {
                    HStack {
                        VStack(spacing: 0) {
                            ForEach(VideoClip.Sport.allCases, id: \.self) { sport in
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        showSportDropdown = false
                                        selectedSport = sport
                                        refreshFeedForSport(sport)
                                    }
                                }) {
                                    HStack(spacing: 8) {
                                        if sport == .all {
                                            Image(systemName: "flame")
                                                .font(.system(size: 14, weight: .medium))
                                        } else if UIImage(systemName: sport.icon) != nil {
                                            Image(systemName: sport.icon)
                                                .font(.system(size: 14, weight: .medium))
                                        } else {
                                            Text(sport.rawValue)
                                                .font(.system(size: 12, weight: .medium))
                                        }

                                        Text(sport == .all ? "All" : sport.rawValue)
                                            .font(.system(size: 12, weight: .medium))

                                        Spacer()

                                        if selectedSport == sport {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 12, weight: .medium))
                                        }
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(
                                        Rectangle()
                                            .fill(selectedSport == sport ? .white.opacity(0.1) : .clear)
                                    )
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        )
                        .scaleEffect(showSportDropdown ? 1.0 : 0.8)
                        .opacity(showSportDropdown ? 1.0 : 0.0)
                        .padding(.leading, 16)
                        .padding(.top, 100) // Position below the top bar

                        Spacer()
                    }

                    Spacer()
                }
                .zIndex(20) // Above everything else
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.8).combined(with: .opacity),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                ))
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
