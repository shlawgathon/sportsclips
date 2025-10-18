//
//  ProfileHeaderView.swift
//  sportsclips
//
//  User stats and info with liquid glass cards
//

import SwiftUI

struct ProfileHeaderView: View {
    let user: UserProfile
    @StateObject private var localStorage = LocalStorageService.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Profile picture and basic info
            VStack(spacing: 16) {
                // Profile picture
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.6))
                    )
                    .frame(width: 100, height: 100)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 3)
                    )
                
                // Username
                Text("@\(user.username)")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                // Email
                Text(user.email)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                
                // Logout button
                Button(action: { localStorage.logout() }) {
                    Text("Logout")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Stats cards
            HStack(spacing: 16) {
                StatCard(title: "Videos Watched", value: localStorage.viewHistory.count)
                StatCard(title: "Likes Given", value: localStorage.interactions.filter { $0.liked }.count)
                StatCard(title: "Comments", value: localStorage.interactions.filter { $0.commented }.count)
                StatCard(title: "Shares", value: localStorage.interactions.filter { $0.shared }.count)
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 60)
        .padding(.bottom, 30)
    }
}

struct StatCard: View {
    let title: String
    let value: Int
    
    var body: some View {
        VStack(spacing: 4) {
            Text(formatCount(value))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .regularGlass(cornerRadius: 16)
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

#Preview {
    ZStack {
        Color.black
        ProfileHeaderView(user: UserProfile(
            id: "preview",
            username: "previewuser",
            email: "preview@example.com",
            isLoggedIn: true,
            lastLoginAt: Date()
        ))
    }
}
