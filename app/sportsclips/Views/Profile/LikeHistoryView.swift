//
//  LikeHistoryView.swift
//  sportsclips
//
//  Like history display for profile
//

import SwiftUI

struct LikeHistoryView: View {
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var videos: [VideoClip] = []
    @State private var items: [LikeHistoryItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("Liked Videos")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Text("\(localStorage.interactions.filter { $0.liked }.count)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)

            let likedVideos = localStorage.interactions.filter { $0.liked }

            if likedVideos.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.white.opacity(0.5))

                    Text("No liked videos yet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))

                    Text("Start liking videos to see them here")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                // Like history grid - scrollable with template content
                let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        // Show actual liked videos if available
                        ForEach(Array(likedVideos.prefix(10).enumerated()), id: \.element) { index, interaction in
                            if let video = videos.first(where: { $0.id == interaction.videoId }) {
                                LikeHistoryGridItem(video: video, index: index + 1, likedAt: interaction.viewedAt)
                            }
                        }

                        // Add template boxes for demonstration (remove when API is ready)
                        ForEach(0..<8, id: \.self) { index in
                            LikeHistoryTemplateItem(index: index + 1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }

            // Recently liked text at bottom
            if !likedVideos.isEmpty {
                HStack {
                    Spacer()
                    Text("Recently liked videos")
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

struct LikeHistoryGridItem: View {
    let video: VideoClip
    let index: Int
    let likedAt: Date

    var body: some View {
        Button(action: {
            // Navigate back to video - you can implement navigation here
            print("Navigate to video: \(video.id)")
        }) {
            VStack(spacing: 8) {
                // Video thumbnail
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        VStack {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    )

                // Video info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: video.sport.icon)
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))

                        Text(video.sport.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))

                        Spacer()

                        Text("#\(index)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Text(video.caption)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.red)

                            Text(formatCount(video.likes))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        HStack(spacing: 2) {
                            Image(systemName: "message")
                                .font(.system(size: 8))
                                .foregroundColor(.white.opacity(0.7))

                            Text(formatCount(video.comments))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Spacer()
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
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
}

struct LikeHistoryTemplateItem: View {
    let index: Int

    var body: some View {
        Button(action: {
            print("Navigate to template video: \(index)")
        }) {
            VStack(spacing: 8) {
                // Video thumbnail
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        VStack {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.red)
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    )

                // Video info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "football")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))

                        Text("Football")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))

                        Spacer()

                        Text("#\(index)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Text("Amazing touchdown play from the game")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.red)

                            Text("1.2K")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        HStack(spacing: 2) {
                            Image(systemName: "message")
                                .font(.system(size: 8))
                                .foregroundColor(.white.opacity(0.7))

                            Text("45")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Spacer()
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
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
        LikeHistoryView()
    }
}
