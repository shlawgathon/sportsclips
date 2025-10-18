//
//  sportsclipsApp.swift
//  sportsclips
//
//  Created by Subham on 10/18/25.
//

import SwiftUI

@main
struct sportsclipsApp: App {
    @StateObject private var localStorage = LocalStorageService.shared
    @StateObject private var appLifecycleManager = AppLifecycleManager.shared
    
    var body: some Scene {
        WindowGroup {
            if localStorage.userProfile?.isLoggedIn == true {
                MainTabView()
                    .onAppear {
                        // Set up video player manager for lifecycle management
                        appLifecycleManager.setVideoPlayerManager(VideoPlayerManager.shared)
                    }
            } else {
                AuthenticationView()
            }
        }
    }
}
