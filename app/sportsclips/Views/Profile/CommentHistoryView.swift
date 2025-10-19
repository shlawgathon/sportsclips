//
//  CommentHistoryView.swift
//  sportsclips
//
//  Comment history display for profile
//

import SwiftUI

struct CommentHistoryView: View {
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var videos: [VideoClip] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("Comments")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(localStorage.interactions.filter { $0.commented }.count)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            
            let commentedVideos = localStorage.interactions.filter { $0.commented }
            
            if commentedVideos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "message.slash")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("No comments yet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Start commenting on videos to see them here")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                // Comment history list - scrollable with template content
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // Show actual commented videos if available
                        ForEach(Array(commentedVideos.prefix(10).enumerated()), id: \.element) { index, interaction in
                            if let video = videos.first(where: { $0.id == interaction.videoId }) {
                                CommentHistoryRowItem(video: video, index: index + 1, commentedAt: interaction.viewedAt)
                            }
                        }
                        
                        // Add template comment items for demonstration (remove when API is ready)
                        ForEach(0..<6, id: \.self) { index in
                            CommentHistoryTemplateItem(index: index + 1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            
            // Recently commented text at bottom
            if !commentedVideos.isEmpty {
                HStack {
                    Spacer()
                    Text("Recently commented videos")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
        }
        .padding(.bottom, 100) // Account for tab bar
        .onAppear {
            loadVideos()
        }
    }
    
    private func loadVideos() {
        Task {
            let allVideos = try? await APIService.shared.fetchVideos()
            await MainActor.run {
                self.videos = allVideos ?? []
            }
        }
    }
}

struct CommentHistoryRowItem: View {
    let video: VideoClip
    let index: Int
    let commentedAt: Date
    
    var body: some View {
        Button(action: {
            // Navigate back to video - you can implement navigation here
            print("Navigate to video: \(video.id)")
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // Date and video title
                HStack {
                    Text(formatDate(commentedAt))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Spacer()
                    
                    Text("#\(index)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                // Video title
                HStack {
                    Image(systemName: video.sport.icon)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text(video.caption)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                
                // Your comment
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                        .padding(.top, 2)
                    
                    Text("This is an amazing play! The way he dodged the defenders was incredible.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(.leading, 4)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
    
    private func formatTimeAgo(_ date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        if timeInterval < 60 {
            return "now"
        } else if timeInterval < 3600 {
            let minutes = Int(timeInterval / 60)
            return "\(minutes)m ago"
        } else if timeInterval < 86400 {
            let hours = Int(timeInterval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(timeInterval / 86400)
            return "\(days)d ago"
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct CommentHistoryTemplateItem: View {
    let index: Int
    
    private let sampleComments = [
        "This is an amazing play! The way he dodged the defenders was incredible.",
        "Wow, that was a perfect shot! Can't believe he made that from that distance.",
        "The teamwork here is absolutely phenomenal. Great coordination!",
        "This goal will be remembered for years to come. What a moment!",
        "Incredible athleticism on display here. These players are on another level.",
        "The crowd reaction says it all - this was a game-changing moment!"
    ]
    
    private let sampleTitles = [
        "Amazing touchdown play from the game",
        "Incredible slam dunk highlight",
        "Perfect goal from midfield",
        "Game-winning three-pointer",
        "Spectacular save by the goalkeeper",
        "Unbelievable home run"
    ]
    
    private let sampleDates = [
        "Dec 15, 2024 at 2:30 PM",
        "Dec 14, 2024 at 8:45 AM",
        "Dec 13, 2024 at 6:15 PM",
        "Dec 12, 2024 at 11:20 AM",
        "Dec 11, 2024 at 4:50 PM",
        "Dec 10, 2024 at 9:30 AM"
    ]
    
    var body: some View {
        Button(action: {
            print("Navigate to template comment: \(index)")
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // Date and index
                HStack {
                    Text(sampleDates[index - 1])
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Spacer()
                    
                    Text("#\(index)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                // Video title
                HStack {
                    Image(systemName: "football")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text(sampleTitles[index - 1])
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                
                // Your comment
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.blue)
                        .padding(.top, 2)
                    
                    Text(sampleComments[index - 1])
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(.leading, 4)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ZStack {
        Color.black
        CommentHistoryView()
    }
}
