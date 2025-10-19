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
                    .ignoresSafeArea()
            } else if filteredVideos.isEmpty {
                // Empty state mirrors LiveVideoCell layout but greyed out
                GeometryReader { geometry in
                    ZStack {
                        // Full-screen placeholder background (muted)
                        Rectangle()
                            .fill(LinearGradient(
                                colors: [.gray.opacity(0.45), .black.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .ignoresSafeArea()

                        // Top bar - same structure/order as LiveVideoCell
                        VStack {
                            HStack(spacing: 12) {
                                // Sport tag with LIVE indicator (greyed)
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(.gray.opacity(0.6))
                                        .frame(width: 8, height: 8)

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
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    ZStack {
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

                                        Capsule()
                                            .fill(.gray.opacity(0.2))
                                    }
                                )

                                // Sport filter (same height as tag)
                                Button(action: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        showSportDropdown.toggle()
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "line.3.horizontal.decrease")
                                            .font(.system(size: 13, weight: .medium))
                                        Text(selectedSport == .all ? "All" : selectedSport.rawValue)
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                }
                                .foregroundColor(.white.opacity(0.9))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    ZStack {
                                        Capsule()
                                            .fill(.ultraThinMaterial)
                                            .overlay(
                                                Capsule()
                                                    .stroke(
                                                        LinearGradient(
                                                            colors: [
                                                                .white.opacity(0.25),
                                                                .white.opacity(0.1)
                                                            ],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        ),
                                                        lineWidth: 1.5
                                                    )
                                            )
                                            .shadow(color: .white.opacity(0.15), radius: 8, x: 0, y: 2)

                                        Capsule()
                                            .fill(.white.opacity(0.08))
                                    }
                                )

                                Spacer()

                                // View count (greyed)
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

                                // Like counter (greyed)
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
                            .padding(.horizontal, 16)
                            .padding(.top, 50)

                            Spacer()
                        }
                        .zIndex(2)

                        // Bottom overlays - comments/summary and input (greyed content)
                        VStack(spacing: 0) {
                            Spacer()

                            VStack(alignment: .leading, spacing: 8) {
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

                            // Comments input removed in empty state placeholder per requirement
                            Spacer(minLength: 0)
                                .frame(height: 104)
                                .frame(maxWidth: .infinity)
                                .background(
                                    Rectangle()
                                        .fill(.black.opacity(0.3))
                                )
                        }
                        .zIndex(20)
                    }
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
                                        // Do not attempt URL-based playback for live items; LiveVideoPlayerView handles WebSocket streaming
                                        if (video.gameId == nil) || (video.gameId?.isEmpty == true) {
                                            playerManager.playVideo(for: video.videoURL, videoId: video.id)
                                        }
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
                        .padding(.top, 85) // Position below the top bar (moved up 15px)

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
                let videos = try await apiService.fetchLiveVideos()
                await MainActor.run {
                    self.liveVideos = videos
                    // Filter by sport and randomize order when "All" is selected
                    if self.selectedSport == .all {
                        self.filteredVideos = videos.shuffled()
                    } else {
                        self.filteredVideos = videos.filter { $0.sport == self.selectedSport }
                    }
                    self.isLoading = false

                    // Auto-play first video (non-live only; live playback handled in LiveVideoPlayerView)
                    if let first = filteredVideos.first {
                        if (first.gameId == nil) || (first.gameId?.isEmpty == true) {
                            playerManager.playVideo(for: first.videoURL, videoId: first.id)
                        }
                        localStorage.recordView(videoId: first.id)
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
