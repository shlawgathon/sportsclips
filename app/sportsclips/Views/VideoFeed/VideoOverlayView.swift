//
//  VideoOverlayView.swift
//  sportsclips
//
//  Right-side action buttons (like, comment, share) with liquid glass
//

import SwiftUI

struct VideoOverlayView: View {
    let video: VideoClip
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var isLiked = false
    @State private var likeCount: Int
    
    init(video: VideoClip) {
        self.video = video
        self._likeCount = State(initialValue: video.likes)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Like button
            ActionButton(
                icon: isLiked ? "heart.fill" : "heart",
                count: likeCount
            ) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isLiked.toggle()
                    likeCount += isLiked ? 1 : -1
                    
                    // Record interaction in local storage
                    localStorage.recordInteraction(
                        videoId: video.id,
                        liked: isLiked,
                        commented: false,
                        shared: false
                    )
                }
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
        .onAppear {
            // Load current like state from local storage
            if let interaction = localStorage.getInteraction(for: video.id) {
                isLiked = interaction.liked
                likeCount = video.likes + (interaction.liked ? 1 : 0)
            }
        }
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
            VideoOverlayView(video: VideoClip.mock)
        }
    }
}
