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
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var likeCount: Int
    
    init(video: VideoClip, isLiked: Bool = false) {
        self.video = video
        self.isLiked = isLiked
        // Calculate like count based on current state
        self._likeCount = State(initialValue: video.likes + (isLiked ? 1 : 0))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Like button
            ActionButton(
                icon: isLiked ? "heart.fill" : "heart",
                count: likeCount
            ) {
                // Record interaction in local storage
                localStorage.recordInteraction(
                    videoId: video.id,
                    liked: !isLiked, // Toggle the current state
                    commented: false,
                    shared: false
                )
            }
            .foregroundColor(isLiked ? .red : .white)
            
            // Comment button
            ActionButton(
                icon: "message",
                count: video.comments
            ) {
                // TODO: Open comments
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
            VideoOverlayView(video: VideoClip.mock, isLiked: false)
        }
    }
}
