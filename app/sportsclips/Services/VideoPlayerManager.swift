//
//  VideoPlayerManager.swift
//  sportsclips
//
//  Manages AVPlayer instances for smooth video playback
//

import AVFoundation
import SwiftUI
import Combine

@MainActor
class VideoPlayerManager: ObservableObject {
    private var players: [String: AVPlayer] = [:]
    private var cancellables = Set<AnyCancellable>()
    
    func getPlayer(for videoURL: String) -> AVPlayer {
        if let existingPlayer = players[videoURL] {
            return existingPlayer
        }
        
        let player = AVPlayer(url: URL(string: videoURL)!)
        players[videoURL] = player
        
        // Configure player for seamless looping
        player.actionAtItemEnd = .none
        
        // Set up notification for loop
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        
        return player
    }
    
    func playVideo(for videoURL: String) {
        let player = getPlayer(for: videoURL)
        player.play()
    }
    
    func pauseVideo(for videoURL: String) {
        players[videoURL]?.pause()
    }
    
    func pauseAllVideos() {
        for player in players.values {
            player.pause()
        }
    }
    
    func cleanup() {
        for player in players.values {
            player.pause()
        }
        players.removeAll()
        cancellables.removeAll()
    }
    
    deinit {
        // Clean up players without calling main actor methods
        for player in players.values {
            player.pause()
        }
        players.removeAll()
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
    }
}