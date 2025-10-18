//
//  VideoPlayerView.swift
//  sportsclips
//
//  Individual video player cell with AVPlayer
//

import SwiftUI
import AVKit
import UIKit

struct VideoPlayerView: View {
    let video: VideoClip
    @ObservedObject var playerManager: VideoPlayerManager
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            // Video player - full screen without controls
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(9/16, contentMode: .fill)
                    .clipped()
                    .ignoresSafeArea()
                    .onAppear {
                        // Hide video controls
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
            } else {
                // Loading placeholder
                Rectangle()
                    .fill(Color.black)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    )
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            playerManager.pauseVideo(for: video.videoURL)
        }
    }
    
    private func findVideoPlayerView(in view: UIView) -> AVPlayerViewController? {
        // Look for AVPlayerViewController in the view hierarchy
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
        player = playerManager.getPlayer(for: video.videoURL)
        playerManager.playVideo(for: video.videoURL)
    }
}

#Preview {
    VideoPlayerView(video: VideoClip.mock, playerManager: VideoPlayerManager())
}
