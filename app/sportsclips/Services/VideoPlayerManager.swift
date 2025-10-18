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
        
        // Configure player for manual control (no auto-looping)
        player.actionAtItemEnd = .pause
        
        return player
    }
    
    func playVideo(for videoURL: String) {
        let player = getPlayer(for: videoURL)
        print("🎬 VideoPlayerManager playing video: \(videoURL)")
        player.play()
    }

    func pauseVideo(for videoURL: String) {
        print("🎬 VideoPlayerManager pausing video: \(videoURL)")
        players[videoURL]?.pause()
    }
    
    func pauseAllVideos() {
        for player in players.values {
            player.pause()
        }
    }
    
    func seekVideo(for videoURL: String, to time: Double) {
        guard let player = players[videoURL] else { 
            print("🎬 Seek failed: No player found for \(videoURL)")
            return 
        }
        let cmTime = CMTimeMakeWithSeconds(time, preferredTimescale: 600)
        print("🎬 VideoPlayerManager seeking to: \(time) seconds")
        player.seek(to: cmTime)
    }
    
    func getCurrentTime(for videoURL: String) -> Double {
        guard let player = players[videoURL] else { return 0.0 }
        return player.currentTime().seconds
    }
    
    func isPlaying(for videoURL: String) -> Bool {
        guard let player = players[videoURL] else { return false }
        return player.rate > 0
    }
    
    func getDuration(for videoURL: String) -> Double {
        guard let player = players[videoURL],
              let currentItem = player.currentItem else { return 0.0 }
        let duration = currentItem.duration
        return duration.seconds.isFinite ? duration.seconds : 0.0
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