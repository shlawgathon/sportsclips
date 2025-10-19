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
            // Section header - only show if there are videos
            if !videos.isEmpty {
                HStack {
                    Text("Recently Watched")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    Text("\(videos.count)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 20)
            }

            if videos.isEmpty {
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
                // View history grid - scrollable with template content
                let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)

                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        // Show actual viewed videos
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                            ViewHistoryGridItem(video: video, index: index + 1)
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
                let history = try await APIClient.shared.viewHistory(userId: userId)
                let clips = try await withThrowingTaskGroup(of: VideoClip.self) { group in
                    for item in history {
                        group.addTask {
                            var model = VideoClip.fromClip(item.clip.clip, clipId: item.clip.id)
                            let url = try await model.fetchVideoURL()
                            return VideoClip(
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
                        }
                    }
                    var results: [VideoClip] = []
                    for try await vc in group { results.append(vc) }
                    return results
                }
                await MainActor.run { self.videos = clips }
            } catch {
                print("Failed to load view history: \(error)")
            }
        }
    }
}

struct ViewHistoryGridItem: View {
    let video: VideoClip
    let index: Int

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
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.8))
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

struct ViewHistoryTemplateItem: View {
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
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.8))
                    )

                // Video info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "basketball")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))

                        Text("Basketball")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))

                        Spacer()

                        Text("#\(index)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                    }

                    Text("Incredible slam dunk highlight")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 8) {
                        HStack(spacing: 2) {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 8))
                                .foregroundColor(.red)

                            Text("856")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        HStack(spacing: 2) {
                            Image(systemName: "message")
                                .font(.system(size: 8))
                                .foregroundColor(.white.opacity(0.7))

                            Text("23")
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
        ViewHistoryView()
    }
}
