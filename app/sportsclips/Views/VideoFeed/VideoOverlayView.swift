//
//  VideoOverlayView.swift
//  sportsclips
//
//  Right-side action buttons (like, comment, share) with liquid glass
//

import SwiftUI

struct VideoOverlayView: View {
    let video: VideoClip
    let isLiked: Bool
    let onLikeChanged: ((Bool) -> Void)?
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var likeCount: Int
    @State private var currentLikedState: Bool
    @State private var commentCount: Int
    
    init(video: VideoClip, isLiked: Bool = false, onLikeChanged: ((Bool) -> Void)? = nil) {
        self.video = video
        self.isLiked = isLiked
        self.onLikeChanged = onLikeChanged
        self._currentLikedState = State(initialValue: isLiked)
        // Calculate like count based on current state
        self._likeCount = State(initialValue: video.likes + (isLiked ? 1 : 0))
        self._commentCount = State(initialValue: video.comments)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Like button
            ActionButton(
                icon: currentLikedState ? "heart.fill" : "heart",
                count: likeCount
            ) {
                // Toggle like state
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    currentLikedState.toggle()
                    likeCount += currentLikedState ? 1 : -1
                }
                
                // Notify parent of like state change
                onLikeChanged?(currentLikedState)
                
                // Record interaction in local storage
                localStorage.recordInteraction(
                    videoId: video.id,
                    liked: currentLikedState,
                    commented: false,
                    shared: false
                )
            }
            .foregroundColor(currentLikedState ? .red : .white)
            
            // Comment button
            ActionButton(
                icon: "message",
                count: commentCount
            ) {
                // Increment comment count
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    commentCount += 1
                }
                
                // Record interaction in local storage
                localStorage.recordInteraction(
                    videoId: video.id,
                    liked: isLiked,
                    commented: true,
                    shared: false
                )
            }
            
            // Share button
            ActionButton(
                icon: "square.and.arrow.up",
                count: video.shares
            ) {
                shareVideo()
                localStorage.recordInteraction(
                    videoId: video.id,
                    liked: isLiked,
                    commented: false,
                    shared: true
                )
            }
        }
        .padding(.trailing, 16) // Right padding for proper spacing from edge
    }
    
    private func shareVideo() {
        let activityVC = UIActivityViewController(
            activityItems: [video.videoURL],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityVC, animated: true)
        }
    }
}

#Preview {
    ZStack {
        Color.black
        HStack {
            Spacer()
            VideoOverlayView(video: VideoClip.mock, isLiked: false, onLikeChanged: { _ in })
        }
    }
}
