//
//  LiveCommentsView.swift
//  sportsclips
//
//  Live comments overlay for bottom left corner
//  Fixed to ensure comments fit within screen bounds
//

import SwiftUI

struct LiveCommentsView: View {
    @State private var comments: [LiveComment] = []
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
            loadComments()
            startCommentStream()
        }
    }
    
    private func loadComments() {
        comments = LiveComment.mockComments
        visibleComments = Array(comments.prefix(3))
    }
    
    private func startCommentStream() {
        var index = 3
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            guard index < comments.count else { return }
            
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                visibleComments.append(comments[index])
                // Keep only last 3 comments visible
                if visibleComments.count > 3 {
                    visibleComments.removeFirst()
                }
            }
            
            index += 1
            
            // Loop back when we run out
            if index >= comments.count {
                index = 0
            }
        }
    }
}

struct CommentBubble: View {
    let comment: LiveComment
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(comment.username)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))
            
            Text(comment.message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
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
                LiveCommentsView()
                Spacer()
            }
            .padding(.bottom, 150)
        }
    }
}