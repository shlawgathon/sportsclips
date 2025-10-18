//
//  ViewHistoryView.swift
//  sportsclips
//
//  View history display for profile
//

import SwiftUI

struct ViewHistoryView: View {
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var videos: [VideoClip] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("Recently Watched")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                
                Spacer()
                
                Text("\(localStorage.viewHistory.count)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)
            
            if localStorage.viewHistory.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Text("No videos watched yet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text("Start watching videos to see your history here")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                // View history list
                LazyVStack(spacing: 12) {
                    ForEach(Array(localStorage.viewHistory.prefix(10).enumerated()), id: \.element) { index, videoId in
                        if let video = videos.first(where: { $0.id == videoId }) {
                            ViewHistoryItem(video: video, index: index + 1)
                        }
                    }
                }
                .padding(.horizontal, 20)
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

struct ViewHistoryItem: View {
    let video: VideoClip
    let index: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Video thumbnail
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 60, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.8))
                )
            
            // Video info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: video.sport.icon)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Text(video.sport.rawValue)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                    
                    Spacer()
                    
                    Text("#\(index)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                Text(video.caption)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                        
                        Text(formatCount(video.likes))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemName: "message")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                        
                        Text(formatCount(video.comments))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
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
        ViewHistoryView()
    }
}
