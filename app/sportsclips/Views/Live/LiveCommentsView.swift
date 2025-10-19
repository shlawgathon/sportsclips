//
//  LiveCommentsView.swift
//  sportsclips
//
//  Live comments overlay for bottom left corner
//  Fixed to ensure comments fit within screen bounds
//

import SwiftUI

struct LiveCommentsView: View {
    let liveId: String
    @StateObject private var commentService = LiveCommentService.shared
    @State private var visibleComments: [LiveComment] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(visibleComments.suffix(3)) { comment in
                CommentBubble(comment: comment)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 200, alignment: .leading)
        .onAppear {
            commentService.startCommentStream(for: liveId)
        }
        .onDisappear {
            commentService.stopCommentStream()
            visibleComments.removeAll()
        }
        .onChange(of: liveId) { newId in
            commentService.stopCommentStream()
            visibleComments.removeAll()
            commentService.startCommentStream(for: newId)
        }
        .onReceive(commentService.$comments) { comments in
            updateVisibleComments(from: comments)
        }
    }

    private func updateVisibleComments(from comments: [LiveComment]) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            // Show the most recent 3 comments, with newest at bottom
            visibleComments = Array(comments.suffix(3))
        }
    }
}

struct CommentBubble: View {
    let comment: LiveComment

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(comment.username)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(comment.isOwnComment ? .blue : .white.opacity(0.9))

                if comment.isOwnComment {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(.blue)
                }
            }

            Text(comment.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(comment.isOwnComment ? Color.blue.opacity(0.2) : Color.clear)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(comment.isOwnComment ? .blue.opacity(0.5) : .white.opacity(0.2), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            HStack {
                LiveCommentsView(liveId: "preview-live-id")
                Spacer()
            }
            .padding(.bottom, 150)
        }
    }
}
