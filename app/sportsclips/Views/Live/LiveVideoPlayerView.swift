//
//  LiveVideoPlayerView.swift
//  sportsclips
//
//  Individual live video player for TikTok-style scrolling
//

import SwiftUI
import AVKit

struct LiveVideoPlayerView: View {
    let video: VideoClip
    @ObservedObject var playerManager: VideoPlayerManager
    @Binding var isLiked: Bool
    @Binding var showingCommentInput: Bool
    @State private var player: AVPlayer?
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video player - same dimensions as video feed
                if let player = player {
                    VideoPlayer(player: player)
                        .aspectRatio(9/16, contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .allowsHitTesting(false) // Prevent all user interaction
                        .onAppear {
                            hideVideoControls()
                        }
                } else {
                    // Loading placeholder
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(
                            VStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)
                                
                                Text("LIVE")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(.top, 12)
                            }
                        )
                        .ignoresSafeArea()
                }
            }
            .onAppear {
                setupPlayer()
            }
        .onDisappear {
            playerManager.pauseVideo(for: video.videoURL, videoId: video.id)
        }
        }
    }
    
    private func hideVideoControls() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                window.subviews.forEach { subview in
                    if let videoPlayerView = findVideoPlayerView(in: subview) {
                        videoPlayerView.showsPlaybackControls = false
                    }
                }
            }
        }
    }
    
    private func findVideoPlayerView(in view: UIView) -> AVPlayerViewController? {
        for subview in view.subviews {
            if let playerVC = subview as? AVPlayerViewController {
                return playerVC
            }
            if let found = findVideoPlayerView(in: subview) {
                return found
            }
        }
        return nil
    }
    
    private func setupPlayer() {
        player = playerManager.getPlayer(for: video.videoURL, videoId: video.id)
        playerManager.playVideo(for: video.videoURL, videoId: video.id)
    }
}

#Preview {
    LiveVideoPlayerView(
        video: VideoClip.mock,
        playerManager: VideoPlayerManager.shared,
        isLiked: .constant(false),
        showingCommentInput: .constant(false)
    )
}

