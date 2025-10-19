//
//  LiveVideoManager.swift
//  sportsclips
//
//  Manages live video players to prevent audio overlap during scrolling
//

import AVFoundation
import SwiftUI

@MainActor
class LiveVideoManager {
    static let shared = LiveVideoManager()
    
    private var livePlayers: [String: AVQueuePlayer] = [:]
    private var currentActiveLiveId: String?
    private let localStorage = LocalStorageService.shared
    
    private init() {}
    
    func registerLivePlayer(_ player: AVQueuePlayer, for videoId: String) {
        // Check if user is logged in - block live video registration if not authenticated
        guard localStorage.isUserLoggedIn() else {
            print("🔴 BLOCKED: Live video registration blocked - user not logged in")
            return
        }
        livePlayers[videoId] = player
    }
    
    func unregisterLivePlayer(for videoId: String) {
        if let player = livePlayers[videoId] {
            player.pause()
            player.isMuted = true
        }
        livePlayers.removeValue(forKey: videoId)
        
        if currentActiveLiveId == videoId {
            currentActiveLiveId = nil
        }
    }
    
    func pauseAllLiveVideos() {
        for (videoId, player) in livePlayers {
            player.pause()
            player.isMuted = true
            print("🔴 LiveVideoManager paused live video: \(videoId)")
        }
        currentActiveLiveId = nil
    }
    
    func activateLiveVideo(_ videoId: String) {
        // Check if user is logged in - block live video activation if not authenticated
        guard localStorage.isUserLoggedIn() else {
            print("🔴 BLOCKED: Live video activation blocked - user not logged in")
            return
        }
        
        // Pause all other live videos first
        pauseAllLiveVideos()
        
        // Activate the current one
        if let player = livePlayers[videoId] {
            player.isMuted = false
            currentActiveLiveId = videoId
            print("🔴 LiveVideoManager activated live video: \(videoId)")
            
            // Set highest priority for live video playback
            VideoPlayerManager.shared.setVideoPlaybackPriority()
        }
    }
    
    func isLiveVideoActive(_ videoId: String) -> Bool {
        return currentActiveLiveId == videoId
    }
    
    func getCurrentActiveLiveId() -> String? {
        return currentActiveLiveId
    }
    
    func forceStopAllLivePlayback() {
        print("🔴 FORCE STOP: Stopping all live video playback due to logout")
        pauseAllLiveVideos()
        // Clear all live players to free up resources
        for (_, player) in livePlayers {
            player.pause()
            player.isMuted = true
            player.removeAllItems()
        }
        livePlayers.removeAll()
        currentActiveLiveId = nil
    }
}
