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
    static let shared = VideoPlayerManager()
    
    private var players: [String: AVPlayer] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var currentActiveVideoId: String? = nil
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    private init() {}
    
    func getPlayer(for videoURL: String, videoId: String) -> AVPlayer {
        // Use videoId as key to ensure each video has its own player instance
        if let existingPlayer = players[videoId] {
            return existingPlayer
        }
        
        let player = AVPlayer(url: URL(string: videoURL)!)
        players[videoId] = player
        
        // Configure player for manual control (no auto-looping)
        player.actionAtItemEnd = .pause
        
        return player
    }
    
    /// Get player for a VideoClip, fetching the presigned URL if needed
    func getPlayer(for videoClip: VideoClip) async -> AVPlayer {
        // Check if we already have a player for this video
        if let existingPlayer = players[videoClip.id] {
            return existingPlayer
        }
        
        // If videoURL is empty, we need to fetch the presigned URL
        var videoURL = videoClip.videoURL
        if videoURL.isEmpty {
            do {
                videoURL = try await videoClip.fetchVideoURL()
            } catch {
                print("Failed to fetch video URL for \(videoClip.id): \(error)")
                // Fallback to mock URL
                videoURL = "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
            }
        }
        
        let player = AVPlayer(url: URL(string: videoURL)!)
        players[videoClip.id] = player
        
        // Configure player for manual control (no auto-looping)
        player.actionAtItemEnd = .pause
        
        return player
    }
    
    func playVideo(for videoURL: String, videoId: String) {
        // Pause all other videos first to save resources
        pauseAllVideosExcept(videoId: videoId)
        
        let player = getPlayer(for: videoURL, videoId: videoId)
        currentActiveVideoId = videoId
        print("🎬 VideoPlayerManager playing video: \(videoId)")
        player.play()
        
        // Start background task to keep video playing
        startBackgroundTask()
    }
    
    /// Play video from VideoClip, fetching presigned URL if needed
    func playVideo(for videoClip: VideoClip) async {
        // Pause all other videos first to save resources
        pauseAllVideosExcept(videoId: videoClip.id)
        
        let player = await getPlayer(for: videoClip)
        currentActiveVideoId = videoClip.id
        print("🎬 VideoPlayerManager playing video: \(videoClip.id)")
        player.play()
        
        // Start background task to keep video playing
        startBackgroundTask()
    }

    func pauseVideo(for videoURL: String, videoId: String) {
        print("🎬 VideoPlayerManager pausing video: \(videoId)")
        players[videoId]?.pause()
    }
    
    func pauseAllVideos() {
        for player in players.values {
            player.pause()
        }
        currentActiveVideoId = nil
        endBackgroundTask()
        print("🎬 VideoPlayerManager paused all videos")
    }
    
    func pauseAllVideosExcept(videoId: String) {
        for (id, player) in players {
            if id != videoId {
                player.pause()
                print("🎬 VideoPlayerManager paused background video: \(id)")
            }
        }
    }
    
    func seekVideo(for videoURL: String, videoId: String, to time: Double) {
        guard let player = players[videoId] else { 
            print("🎬 Seek failed: No player found for \(videoId)")
            return 
        }
        let cmTime = CMTimeMakeWithSeconds(time, preferredTimescale: 600)
        print("🎬 VideoPlayerManager seeking to: \(time) seconds for video: \(videoId)")
        player.seek(to: cmTime)
    }
    
    func getCurrentTime(for videoURL: String, videoId: String) -> Double {
        guard let player = players[videoId] else { return 0.0 }
        return player.currentTime().seconds
    }
    
    func isPlaying(for videoURL: String, videoId: String) -> Bool {
        guard let player = players[videoId] else { return false }
        return player.rate > 0
    }
    
    func getDuration(for videoURL: String, videoId: String) -> Double {
        guard let player = players[videoId],
              let currentItem = player.currentItem else { return 0.0 }
        let duration = currentItem.duration
        return duration.seconds.isFinite ? duration.seconds : 0.0
    }
    
    func cleanup() {
        for player in players.values {
            player.pause()
            player.replaceCurrentItem(with: nil) // Release video resources
        }
        players.removeAll()
        cancellables.removeAll()
    }
    
    func cleanupUnusedPlayers(activeVideoIds: [String]) {
        let activeSet = Set(activeVideoIds)
        let playersToRemove = players.keys.filter { !activeSet.contains($0) }
        
        for videoId in playersToRemove {
            if let player = players[videoId] {
                player.pause()
                player.replaceCurrentItem(with: nil)
                print("🎬 VideoPlayerManager cleaned up unused player: \(videoId)")
            }
            players.removeValue(forKey: videoId)
        }
        
        // Update current active video if it was removed
        if let currentId = currentActiveVideoId, !activeSet.contains(currentId) {
            currentActiveVideoId = nil
            endBackgroundTask()
        }
    }
    
    // MARK: - Background Task Management
    
    private func startBackgroundTask() {
        endBackgroundTask() // End any existing task
        
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "VideoPlayback") {
            // This block is called when the background task is about to expire
            print("🎬 Background task expiring, pausing all videos")
            self.pauseAllVideos()
        }
        
        print("🎬 Started background task: \(backgroundTask.rawValue)")
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            print("🎬 Ending background task: \(backgroundTask.rawValue)")
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    // MARK: - Resource Management
    
    func pauseNonVisibleVideos(visibleVideoIds: [String]) {
        let visibleSet = Set(visibleVideoIds)
        
        for (videoId, player) in players {
            if !visibleSet.contains(videoId) && player.rate > 0 {
                player.pause()
                print("🎬 VideoPlayerManager paused non-visible video: \(videoId)")
            }
        }
    }
    
    func getActiveVideoId() -> String? {
        return currentActiveVideoId
    }
    
    func isVideoActive(videoId: String) -> Bool {
        return currentActiveVideoId == videoId
    }
    
    deinit {
        // Clean up players without calling main actor methods
        for player in players.values {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        players.removeAll()
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        
        // Note: Background task cleanup is handled by the system when the app terminates
    }
}