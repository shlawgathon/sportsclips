//
//  ProfileView.swift
//  sportsclips
//
//  User profile placeholder
//

import SwiftUI

struct ProfileView: View {
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var showingLogoutConfirmation = false
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [.black, .purple.opacity(0.2), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 30) {
                Spacer()
                
                // User icon
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 80, weight: .light))
                    .foregroundColor(.white.opacity(0.8))
                
                if let user = localStorage.userProfile {
                    VStack(spacing: 12) {
                        Text(user.username)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text(user.email)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                } else {
                    Text("Profile")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
                
                Text("Profile features coming soon...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Spacer()
                
                // Logout button
                Button(action: {
                    showingLogoutConfirmation = true
                }) {
                    Text("Logout")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.red.opacity(0.3), in: RoundedRectangle(cornerRadius: 25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(.red.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 40)
                .padding(.bottom, 100)
            }
        }
        .confirmationDialog("Are you sure you want to logout?", isPresented: $showingLogoutConfirmation) {
            Button("Logout", role: .destructive) {
                Task {
                    await handleLogout()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
    
    // MARK: - Logout Handler
    private func handleLogout() async {
        // Attempt to invalidate session on server
        if let sessionToken = localStorage.userProfile?.sessionToken {
            try? await AuthService.shared.logout(sessionToken: sessionToken)
        }
        
        // Clear local session
        localStorage.logout()
    }
}

#Preview {
    ProfileView()
}
