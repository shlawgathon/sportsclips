//
//  VideoPlayerView.swift
//  sportsclips
//
//  Individual video player cell with AVPlayer
//

import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let video: VideoClip
    @StateObject private var playerManager = VideoPlayerManager()
    @State private var player: AVPlayer?
    
    var body: some View {
        ZStack {
            // Video player - full screen
            if let player = player {
                VideoPlayer(player: player)
                    .aspectRatio(9/16, contentMode: .fill)
                    .clipped()
                    .ignoresSafeArea()
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
    
    private func setupPlayer() {
        player = playerManager.getPlayer(for: video.videoURL)
        playerManager.playVideo(for: video.videoURL)
    }
}

#Preview {
    VideoPlayerView(video: VideoClip.mock)
}
