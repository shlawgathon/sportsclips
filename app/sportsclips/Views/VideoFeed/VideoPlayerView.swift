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
                        // Hide video controls - simplified approach
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            // The VideoPlayer will handle hiding controls automatically
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
            playerManager.pauseVideo(for: video.videoURL, videoId: video.id)
        }
    }

    private func setupPlayer() {
        player = playerManager.getPlayer(for: video.videoURL, videoId: video.id)
        // Don't auto-play here - let VideoFeedView handle play/pause logic
    }
}
