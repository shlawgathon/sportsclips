//
//  CommentSectionView.swift
//  sportsclips
//
//  Comment section modal with list and input
//

import SwiftUI

struct CommentSectionView: View {
    let video: VideoClip
    @Environment(\.dismiss) private var dismiss
    private let apiService = APIService.shared
    @State private var comments: [CommentItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var newCommentText = ""
    @State private var isPosting = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                headerView

                // Comments List
                commentsListView

                // Input Section
                commentInputView
            }
            .navigationBarHidden(true)
        }
        .onAppear {
            loadComments()
        }
    }

    private var headerView: some View {
        HStack {
            Button("Close") {
                dismiss()
            }
            .foregroundColor(.white)

            Spacer()

            Text("Comments")
                .font(.headline)
                .foregroundColor(.white)

            Spacer()

            // Placeholder for symmetry
            Text("Close")
                .opacity(0)
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }

    private var commentsListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if isLoading {
                    ProgressView("Loading comments...")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 50)
                } else if comments.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "message")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)

                        Text("No comments yet")
                            .font(.headline)
                            .foregroundColor(.white)

                        Text("Be the first to comment!")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 50)
                } else {
                    ForEach(comments, id: \.id) { commentItem in
                        CommentRowView(comment: commentItem.comment)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top)
        }
        .background(Color.black.opacity(0.9))
    }

    private var commentInputView: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.gray)

            HStack(spacing: 12) {
                TextField("Add a comment...", text: $newCommentText, axis: .vertical)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(20)
                    .foregroundColor(.white)
                    .lineLimit(1...4)

                Button(action: postComment) {
                    if isPosting {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(width: 40, height: 40)
                .background(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(20)
                .disabled(newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
            }
            .padding()
            .background(Color.black.opacity(0.8))
        }
    }

    private func loadComments() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetchedComments = try await apiService.getComments(clipId: video.id)
                await MainActor.run {
                    self.comments = fetchedComments
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load comments"
                    self.isLoading = false
                }
            }
        }
    }

    private func postComment() {
        let commentText = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commentText.isEmpty else { return }

        isPosting = true

        Task {
            do {
                try await apiService.postComment(clipId: video.id, text: commentText)
                await MainActor.run {
                    self.newCommentText = ""
                    self.isPosting = false
                    // Reload comments to show the new one
                    loadComments()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to post comment"
                    self.isPosting = false
                }
            }
        }
    }
}

struct CommentRowView: View {
    let comment: Comment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // User Avatar
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 36, height: 36)
                .overlay(
                    Text(String(comment.userId.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                // Username and timestamp
                HStack {
                    Text(comment.postedByUsername)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer()

                    Text(formatTimestamp(comment.createdAt))
                        .font(.system(size: 12))
                        .foregroundColor(.gray)
                }

                // Comment text
                Text(comment.text)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }

    private func formatTimestamp(_ timestamp: Int64) -> String {
        // Backend sends seconds since epoch; convert directly
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    let sample = VideoClip(
        id: "preview",
        videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
        caption: "Preview caption",
        sport: .football,
        likes: 0,
        comments: 0,
        shares: 0,
        createdAt: Date(),
        s3Key: nil,
        title: "Preview Title",
        description: "Preview description"
    )
    CommentSectionView(video: sample)
        .preferredColorScheme(.dark)
}
