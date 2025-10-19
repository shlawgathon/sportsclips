//
//  CommentHistoryView.swift
//  sportsclips
//
//  Comment history display for profile
//

import SwiftUI

struct CommentHistoryView: View {
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var comments: [CommentHistoryItem] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header - only show if there are comments
            if !comments.isEmpty {
                HStack {
                    Text("Comments")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Text("\(comments.count)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 20)
            }
            
            if comments.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
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
                // Comment history list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                            CommentHistoryRowItem(comment: comment, index: index + 1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            
        }
        .padding(.bottom, 100) // Account for tab bar
        .onAppear {
            loadComments()
        }
    }
    
    private func loadComments() {
        Task {
            guard let userId = localStorage.userProfile?.id else {
                await MainActor.run { self.comments = [] }
                return
            }
            do {
                let history = try await APIClient.shared.commentHistory(userId: userId)
                await MainActor.run { self.comments = history }
            } catch {
                print("Failed to load comment history: \(error)")
            }
        }
    }
}

struct CommentHistoryRowItem: View {
    let comment: CommentHistoryItem
    let index: Int
    @StateObject private var localStorage = LocalStorageService.shared
    
    var body: some View {
        Button(action: {
            // Navigate to video with comment highlighted
            localStorage.navigateToVideoWithComment(videoId: comment.clip.id, commentId: comment.id)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // Date and video title
                HStack {
                    Text(formatDate(Date(timeIntervalSince1970: TimeInterval(comment.commentedAt / 1000))))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    
                    Spacer()
                    
                    Text("#\(index)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                // Video title
                HStack {
                    // Sport icon based on API sport string
                    Image(systemName: getSportIcon(for: comment.clip.clip.sport))
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text(comment.clip.clip.title)
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
                    
                    Text(comment.text)
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
    
    private func getSportIcon(for sportString: String) -> String {
        switch sportString.lowercased() {
        case "football": return "football"
        case "basketball": return "basketball"
        case "soccer": return "soccerball"
        case "baseball": return "baseball"
        case "tennis": return "tennisball"
        case "golf": return "golf"
        case "hockey": return "hockey.puck"
        case "boxing": return "boxing.glove"
        case "mma": return "figure.martial.arts"
        case "racing": return "car.racing"
        default: return "sportscourt"
        }
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


#Preview {
    ZStack {
        Color.black
        CommentHistoryView()
    }
}
