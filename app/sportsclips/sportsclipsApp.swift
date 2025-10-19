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
    
    var body: some Scene {
        WindowGroup {
            if localStorage.userProfile?.isLoggedIn == true {
                MainTabView()
            } else {
                AuthenticationView()
            }
        }
    }
}
