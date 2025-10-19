//
//  LikeHistoryView.swift
//  sportsclips
//
//  Like history display for profile
//

import SwiftUI

struct LikeHistoryView: View {
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var videos: [(VideoClip, Int64)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Text("Liked Videos")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)

                Spacer()

                Text("\(videos.count)")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 20)

            if videos.isEmpty {
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
                // Like history grid
                let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(Array(videos.enumerated()), id: \.element.0.id) { index, videoTuple in
                            let (video, likedAt) = videoTuple
                            // Convert Int64 timestamp to Date for display
                            LikeHistoryGridItem(video: video, index: index + 1, likedAt: Date(timeIntervalSince1970: TimeInterval(likedAt / 1000)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }

        }
        .padding(.bottom, 100) // Account for tab bar
        .onAppear {
            loadVideos()
        }
    }

    private func loadVideos() {
        Task {
            guard let userId = localStorage.userProfile?.id else {
                await MainActor.run { self.videos = [] }
                return
            }
            do {
                let history = try await APIClient.shared.likeHistory(userId: userId)
                let clips = try await withThrowingTaskGroup(of: (VideoClip, Int64).self) { group in
                    for item in history {
                        group.addTask {
                            let model = await MainActor.run {
                                VideoClip.fromClip(item.clip.clip, clipId: item.clip.id)
                            }
                            let url = try await model.fetchVideoURL()
                            let videoClip = VideoClip(
                                id: model.id,
                                videoURL: url,
                                caption: model.caption,
                                sport: model.sport,
                                likes: model.likes,
                                comments: model.comments,
                                shares: model.shares,
                                createdAt: model.createdAt,
                                s3Key: model.s3Key,
                                title: model.title,
                                description: model.description,
                                gameId: model.gameId
                            )
                            return (videoClip, item.likedAt)
                        }
                    }
                    var results: [(VideoClip, Int64)] = []
                    for try await result in group { results.append(result) }
                    return results
                }
                await MainActor.run { self.videos = clips }
            } catch {
                print("Failed to load like history: \(error)")
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


#Preview {
    ZStack {
        Color.black
        LikeHistoryView()
    }
}
