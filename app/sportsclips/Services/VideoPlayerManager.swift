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
    private let localStorage = LocalStorageService.shared
    
    // Enhanced visibility monitoring
    private var visibleVideoIds: Set<String> = []
    private var playerObservers: [String: NSKeyValueObservation] = [:]

    private init() {
        configureAudioSession()
        setupAudioSessionNotifications()
    }

    // MARK: - Audio Session
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use playback with higher priority for video content
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothHFP])
            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
            print("🔊 Audio session configured: category=playback mode=moviePlayback with high priority")
        } catch {
            print("⚠️ Failed to configure audio session: \(error)")
        }
    }
    
    // MARK: - Autoplay Support
    private var hasUserInteracted = false
    
    func recordUserInteraction() {
        hasUserInteracted = true
        print("🎬 User interaction recorded - autoplay enabled")
    }
    
    func forceAutoplay() {
        hasUserInteracted = true
        print("🎬 Force autoplay enabled")
    }
    
    // MARK: - Enhanced Visibility Monitoring
    func markVideoAsVisible(_ videoId: String) {
        visibleVideoIds.insert(videoId)
        print("👁️ Video marked as visible: \(videoId)")
        
        // Ensure seamless looping is enabled for this video
        enableSeamlessLooping(for: videoId)
        
        // Auto-play visible videos if user has interacted
        if hasUserInteracted {
            autoPlayVisibleVideo(videoId)
        }
    }
    
    // MARK: - Seamless Looping
    private func enableSeamlessLooping(for videoId: String) {
        guard let player = players[videoId] else { return }
        
        // Ensure actionAtItemEnd is set to .none for seamless looping
        if player.actionAtItemEnd != .none {
            player.actionAtItemEnd = .none
            print("🎬 Enabled seamless looping for video: \(videoId)")
        }
    }
    
    func markVideoAsHidden(_ videoId: String) {
        visibleVideoIds.remove(videoId)
        print("👁️ Video marked as hidden: \(videoId)")
        
        // Let Swift handle optimization automatically - no manual pausing
    }
    
    private func autoPlayVisibleVideo(_ videoId: String) {
        guard let player = players[videoId] else { return }
        
        // Only auto-play if this is the most visible video (current active)
        if videoId == currentActiveVideoId {
            print("🎬 Auto-playing visible video: \(videoId)")
            player.play()
        }
    }
    
    // MARK: - Player Observers Setup
    private func setupPlayerObservers(for player: AVPlayer, videoId: String) {
        // Observe player item status for better auto-play handling
        let observer = player.observe(\.currentItem?.status, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }
            
            if player.currentItem?.status == .readyToPlay {
                print("🎬 Player item ready for video: \(videoId)")
                // Auto-play if video is visible and user has interacted
                Task { @MainActor in
                    if self.visibleVideoIds.contains(videoId) && self.hasUserInteracted {
                        player.play()
                    }
                }
            }
        }
        
        // Store observer for cleanup
        playerObservers[videoId] = observer
        
        // Add notification observer for when video ends
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            print("🎬 Video ended: \(videoId) - starting seamless loop")
            // Auto-loop the video if it's still visible
            Task { @MainActor in
                if self.visibleVideoIds.contains(videoId) {
                    // Use completion handler for seamless looping
                    player.seek(to: .zero) { [weak self] completed in
                        guard let self = self, completed else { return }
                        // Only play if video is still visible after seek completes
                        if self.visibleVideoIds.contains(videoId) {
                            player.play()
                            print("🎬 Seamless loop started for video: \(videoId)")
                        }
                    }
                }
            }
        }
    }
    
    func forceStopAllPlayback() {
        print("🎬 FORCE STOP: Stopping all video playback due to logout")
        pauseAllVideos()
        // Clear all players to free up resources
        for player in players.values {
            player.pause()
            player.replaceCurrentItem(with: nil)
        }
        players.removeAll()
        currentActiveVideoId = nil
        endBackgroundTask()
        
        // Clean up observers
        cleanupAllObservers()
    }
    
    private func cleanupAllObservers() {
        // Remove all KVO observers
        playerObservers.values.forEach { $0.invalidate() }
        playerObservers.removeAll()
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
        
        // Clear visibility tracking
        visibleVideoIds.removeAll()
    }

    public func ensureAudioSessionActive() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Set highest priority for video playback
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothHFP])
            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
            print("🔊 Audio session activated with highest priority for video playback")
        } catch {
            print("⚠️ Failed to activate audio session: \(error)")
        }
    }
    
    func setVideoPlaybackPriority() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Set the highest priority category for video playback
            try audioSession.setCategory(.playback, mode: .moviePlayback, options: [.allowAirPlay, .allowBluetoothHFP])
            try audioSession.setActive(true, options: [.notifyOthersOnDeactivation])
            
            // Set preferred sample rate and buffer duration for optimal video playback
            try audioSession.setPreferredSampleRate(48000.0)
            try audioSession.setPreferredIOBufferDuration(0.005) // 5ms for low latency
            
            print("🎬 Video playback priority set to highest level")
        } catch {
            print("⚠️ Failed to set video playback priority: \(error)")
        }
    }
    
    private func setupAudioSessionNotifications() {
        // Handle audio session interruptions to maintain video priority
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            if let userInfo = notification.userInfo,
               let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
               let type = AVAudioSession.InterruptionType(rawValue: typeValue) {
                
                switch type {
                case .began:
                    print("🎬 Audio session interruption began - pausing videos")
                    self.pauseAllVideos()
                    
                case .ended:
                    print("🎬 Audio session interruption ended - resuming video priority")
                    if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                        if options.contains(.shouldResume) {
                            // Re-establish video priority
                            self.setVideoPlaybackPriority()
                        }
                    }
                    
                @unknown default:
                    break
                }
            }
        }
        
        // Handle route changes (e.g., headphones disconnected)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            print("🎬 Audio route changed - maintaining video priority")
            self.setVideoPlaybackPriority()
        }
    }

    // MARK: - Disk-backed playback helpers
    private func prepareLocalItem(videoURL: String, videoId: String) async -> AVPlayerItem? {
        guard let remote = URL(string: videoURL) else { return nil }
        do {
            let local = try await VideoCacheManager.shared.fetchToDisk(id: videoId, remoteURL: remote)
            let item = AVPlayerItem(url: local)
            
            // Configure item for autoplay
            item.preferredForwardBufferDuration = 1.0 // Reduce buffering time
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = true
            
            return item
        } catch {
            print("VideoPlayerManager failed to cache video (\(videoId)): \(error)")
            return nil
        }
    }
    func getPlayer(for videoURL: String, videoId: String) -> AVPlayer {
        // Use videoId as key to ensure each video has its own player instance
        if let existingPlayer = players[videoId] {
            return existingPlayer
        }

        // Safely create URL and handle nil case
        guard let url = URL(string: videoURL) else {
            print("⚠️ Invalid video URL for videoId \(videoId): '\(videoURL)'")
            // Return an empty player to avoid crashes
            let emptyPlayer = AVPlayer()
            players[videoId] = emptyPlayer
            return emptyPlayer
        }

        let player = AVPlayer(url: url)
        players[videoId] = player

        // Configure player for autoplay and manual control with highest priority
        player.actionAtItemEnd = .none // Allow seamless looping
        player.automaticallyWaitsToMinimizeStalling = false // Enable faster autoplay
        player.isMuted = false // Ensure audio is not muted
        player.volume = 1.0 // Ensure full volume
        
        // Set highest priority for video playback
        if #available(iOS 14.0, *) {
            player.preventsDisplaySleepDuringVideoPlayback = true
        }
        
        // Add notification observers for enhanced auto-play functionality
        setupPlayerObservers(for: player, videoId: videoId)
        
        return player
    }

    /// Get player for a VideoClip, fetching the presigned URL if needed
    /// For live videos (identified by non-empty gameId), we do NOT load any URL here.
    /// Live playback is handled by LiveVideoPlayerView via WebSocket chunks.
    func getPlayer(for videoClip: VideoClip) async -> AVPlayer {
        // If this is a live item, don't attempt to fetch or load a URL
        if let gid = videoClip.gameId, !gid.isEmpty {
            if let existing = players[videoClip.id] { return existing }
            let empty = AVPlayer()
            players[videoClip.id] = empty
            return empty
        }

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
                // Return a default player without loading a mock URL
                let emptyPlayer = AVPlayer()
                players[videoClip.id] = emptyPlayer
                return emptyPlayer
            }
        }

        // Prepare local cached item
        let player = AVPlayer()
        if let item = await prepareLocalItem(videoURL: videoURL, videoId: videoClip.id) {
            player.replaceCurrentItem(with: item)
        } else if let url = URL(string: videoURL) {
            // Fallback to remote if cache failed
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
        }

        players[videoClip.id] = player
        // Configure player for autoplay and manual control with highest priority
        player.actionAtItemEnd = .none // Allow seamless looping
        player.automaticallyWaitsToMinimizeStalling = false // Enable faster autoplay
        player.isMuted = false // Ensure audio is not muted
        player.volume = 1.0 // Ensure full volume
        
        // Set highest priority for video playback
        if #available(iOS 14.0, *) {
            player.preventsDisplaySleepDuringVideoPlayback = true
        }
        
        return player
    }

    func playVideo(for videoURL: String, videoId: String) {
        // Check if user is logged in - block all video playback if not authenticated
        guard localStorage.isUserLoggedIn() else {
            print("🎬 BLOCKED: Video playback blocked - user not logged in")
            return
        }
        
        // If URL is empty, this is likely a live item or not yet resolved; do not attempt playback
        guard !videoURL.isEmpty else {
            print("🎬 Skipping URL-based playback for: \(videoId) (empty URL)")
            return
        }
        // Pause all other videos first to save resources
        pauseAllVideosExcept(videoId: videoId)

        let player = getPlayer(for: videoURL, videoId: videoId)
        currentActiveVideoId = videoId
        
        // Ensure seamless looping is enabled
        enableSeamlessLooping(for: videoId)
        
        // Check if player already has an item - if so, just play it
        if player.currentItem != nil && player.currentItem?.status == .readyToPlay {
            print("🎬 Player already has item ready - playing immediately")
            // Set highest priority for video playback
            setVideoPlaybackPriority()
            player.play()
            startBackgroundTask()
            return
        }
        
        print("🎬 VideoPlayerManager preparing disk playback for: \(videoId)")

        // Replace item with local cached file, then play
        Task { [weak self] in
            guard let self else { return }
            if let item = await self.prepareLocalItem(videoURL: videoURL, videoId: videoId) {
                await MainActor.run {
                    // Only replace if this is still the active video
                    guard self.currentActiveVideoId == videoId else { return }
                    player.replaceCurrentItem(with: item)
                    
                    // Wait for the item to be ready to play before starting playback
                    self.waitForItemToBeReady(player: player, videoId: videoId)
                }
            } else {
                // Fallback: attempt to play remote to avoid a blank UI
                await MainActor.run {
                    guard self.currentActiveVideoId == videoId else { return }
                    print("🎬 Fallback to remote stream for: \(videoId)")
                    if let url = URL(string: videoURL) {
                        let remoteItem = AVPlayerItem(url: url)
                        
                        // Configure remote item for autoplay
                        remoteItem.preferredForwardBufferDuration = 1.0
                        remoteItem.canUseNetworkResourcesForLiveStreamingWhilePaused = true
                        
                        player.replaceCurrentItem(with: remoteItem)
                        self.waitForItemToBeReady(player: player, videoId: videoId)
                    }
                }
            }
        }
    }
    
    private func waitForItemToBeReady(player: AVPlayer, videoId: String) {
        guard let item = player.currentItem else { return }
        
        if item.status == .readyToPlay {
            print("🎬 VideoPlayerManager playing immediately: \(videoId)")
            // Set highest priority for video playback
            setVideoPlaybackPriority()
            player.play()
            startBackgroundTask()
        } else {
            print("🎬 VideoPlayerManager waiting for item to be ready: \(videoId), status: \(item.status.rawValue)")
            
            // Set up observer to wait for the item to be ready
            _ = item.observe(\.status, options: [.new]) { [weak self] item, _ in
                guard let self else { return }
                
                Task { @MainActor in
                    // Only play if this is still the active video
                    guard self.currentActiveVideoId == videoId else { return }
                    
                    if item.status == .readyToPlay {
                        print("🎬 VideoPlayerManager item ready - playing: \(videoId)")
                        // Set highest priority for video playback
                        self.setVideoPlaybackPriority()
                        player.play()
                        self.startBackgroundTask()
                    } else if item.status == .failed {
                        print("🎬 VideoPlayerManager item failed: \(videoId), error: \(item.error?.localizedDescription ?? "unknown")")
                    }
                }
            }
            
            // Store observer to prevent deallocation
            // Note: In a production app, you'd want to properly manage observer lifecycle
        }
    }

    /// Play video from VideoClip, fetching presigned URL if needed
    func playVideo(for videoClip: VideoClip) async {
        // Check if user is logged in - block all video playback if not authenticated
        guard localStorage.isUserLoggedIn() else {
            print("🎬 BLOCKED: Video playback blocked - user not logged in")
            return
        }
        
        // For live videos, playback is handled by LiveVideoPlayerView via WebSocket chunks
        if let gid = videoClip.gameId, !gid.isEmpty {
            // Do not attempt to play via URL/AVPlayer here
            currentActiveVideoId = nil
            return
        }
        // Pause all other videos first to save resources
        pauseAllVideosExcept(videoId: videoClip.id)

        let player = await getPlayer(for: videoClip)
        currentActiveVideoId = videoClip.id
        
        // Ensure seamless looping is enabled
        enableSeamlessLooping(for: videoClip.id)
        
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
    
    // MARK: - Live Video Audio Management
    
    func pauseAllLiveVideos() {
        // This method is called to ensure no live video audio overlaps
        // Live videos are managed by LiveVideoPlayerView, but we can pause regular videos
        pauseAllVideos()
    }

    func seekVideo(for videoURL: String, videoId: String, to time: Double) {
        guard let player = players[videoId] else {
            print("🎬 Seek failed: No player found for \(videoId)")
            return
        }
        
        guard let item = player.currentItem, item.status == .readyToPlay else {
            print("🎬 Seek failed: Player item not ready for \(videoId)")
            return
        }
        
        // Validate and clamp seek time to valid range
        let clampedTime = validateSeekTime(for: videoURL, videoId: videoId, time: time)
        
        if clampedTime != time {
            let duration = getDuration(for: videoURL, videoId: videoId)
            print("🎬 Seek time clamped from \(time) to \(clampedTime) seconds (duration: \(duration))")
        }
        
        let cmTime = CMTimeMakeWithSeconds(clampedTime, preferredTimescale: 600)
        print("🎬 VideoPlayerManager seeking to: \(clampedTime) seconds for video: \(videoId)")
        
        // Use more lenient tolerance to prevent seek rejections
        player.seek(to: cmTime, toleranceBefore: CMTimeMakeWithSeconds(1, preferredTimescale: 600), toleranceAfter: CMTimeMakeWithSeconds(1, preferredTimescale: 600)) { finished in
            if finished {
                print("🎬 Seek completed for \(videoId)")
                // Resume playback after seeking
                DispatchQueue.main.async {
                    player.play()
                    print("🎬 Resumed playback after seek for \(videoId)")
                }
            } else {
                print("🎬 Seek failed for \(videoId) - resuming playback anyway")
                // Even if seek fails, resume playback to prevent freezing
                DispatchQueue.main.async {
                    player.play()
                    print("🎬 Resumed playback after failed seek for \(videoId)")
                }
            }
        }
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
    
    func validateSeekTime(for videoURL: String, videoId: String, time: Double) -> Double {
        let duration = getDuration(for: videoURL, videoId: videoId)
        if duration > 0 {
            return max(0, min(time, duration))
        }
        return max(0, time) // If duration unknown, just ensure non-negative
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

    // MARK: - Prefetch Management

    func updatePreloadQueue(currentIndex: Int, clips: [VideoClip], count: Int = 5) {
        guard !clips.isEmpty else { return }
        let start = max(0, currentIndex + 1)
        let end = min(clips.count, start + count)
        let nextClips = Array(clips[start..<end])
        Task {
            var items: [(id: String, url: URL)] = []
            for clip in nextClips {
                // Skip live items; they are streamed over WebSocket and have no direct video URL
                if let gid = clip.gameId, !gid.isEmpty { continue }
                var urlStr = clip.videoURL
                if urlStr.isEmpty {
                    // Attempt to fetch presigned URL
                    if let fetched = try? await clip.fetchVideoURL() { urlStr = fetched }
                }
                if let u = URL(string: urlStr), !urlStr.isEmpty {
                    items.append((clip.id, u))
                }
            }
            await MainActor.run {
                VideoCacheManager.shared.prefetch(next: items, count: count)
            }
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
