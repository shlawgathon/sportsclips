//
//  AppLifecycleManager.swift
//  sportsclips
//
//  Manages app lifecycle events for optimal resource usage
//

import SwiftUI
import Combine

@MainActor
class AppLifecycleManager: ObservableObject {
    static let shared = AppLifecycleManager()
    
    private var cancellables = Set<AnyCancellable>()
    private var videoPlayerManager: VideoPlayerManager?
    
    private init() {
        setupNotifications()
    }
    
    func setVideoPlayerManager(_ manager: VideoPlayerManager) {
        self.videoPlayerManager = manager
    }
    
    private func setupNotifications() {
        // App going to background
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                self?.handleAppDidEnterBackground()
            }
            .store(in: &cancellables)
        
        // App coming to foreground
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.handleAppWillEnterForeground()
            }
            .store(in: &cancellables)
        
        // App becoming active
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppDidBecomeActive()
            }
            .store(in: &cancellables)
        
        // App resigning active
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.handleAppWillResignActive()
            }
            .store(in: &cancellables)
        
        // Memory warning
        NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                self?.handleMemoryWarning()
            }
            .store(in: &cancellables)
    }
    
    private func handleAppDidEnterBackground() {
        print("🎬 App entered background - pausing all videos")
        videoPlayerManager?.pauseAllVideos()
    }
    
    private func handleAppWillEnterForeground() {
        print("🎬 App will enter foreground")
        // Videos will resume when user interacts with the app
    }
    
    private func handleAppDidBecomeActive() {
        print("🎬 App became active")
        // Videos will resume when user scrolls to a video
    }
    
    private func handleAppWillResignActive() {
        print("🎬 App will resign active - pausing all videos")
        videoPlayerManager?.pauseAllVideos()
    }
    
    private func handleMemoryWarning() {
        print("🎬 Memory warning received - cleaning up video resources")
        // Force cleanup of all video players to free memory
        videoPlayerManager?.cleanup()
    }
    
    deinit {
        cancellables.removeAll()
    }
}
