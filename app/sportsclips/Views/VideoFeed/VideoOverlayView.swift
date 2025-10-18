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
    private let apiService = APIService.shared
    @State private var likeCount: Int
    @State private var currentLikedState: Bool
    @State private var commentCount: Int
    @State private var showingComments = false
    @State private var isLiking = false
    
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
                handleLikeToggle()
            }
            .foregroundColor(currentLikedState ? .red : .white)
            
            // Comment button
            ActionButton(
                icon: "message",
                count: commentCount
            ) {
                showingComments = true
                
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
        .sheet(isPresented: $showingComments) {
            CommentSectionView(video: video)
        }
        .onAppear {
            // Ensure comment count is properly initialized
            commentCount = video.comments
            
            // Load current like state from local storage
            if let interaction = localStorage.getInteraction(for: video.id) {
                let storedLikedState = interaction.liked
                if currentLikedState != storedLikedState {
                    currentLikedState = storedLikedState
                    likeCount = video.likes + (storedLikedState ? 1 : 0)
                }
            }
            
            print("🔄 VideoOverlayView onAppear: video \(video.id), isLiked: \(isLiked), currentLikedState: \(currentLikedState)")
        }
        .onChange(of: isLiked) { _, newValue in
            // Sync with parent's like state when it changes (e.g., from double tap)
            if currentLikedState != newValue {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    currentLikedState = newValue
                    likeCount = video.likes + (newValue ? 1 : 0)
                }
                print("🔄 VideoOverlayView onChange: Updated like state to \(newValue) for video \(video.id)")
            }
        }
        .onChange(of: localStorage.interactions) { _, _ in
            // React to changes in local storage interactions
            if let interaction = localStorage.getInteraction(for: video.id) {
                let storedLikedState = interaction.liked
                if currentLikedState != storedLikedState {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        currentLikedState = storedLikedState
                        likeCount = video.likes + (storedLikedState ? 1 : 0)
                    }
                    print("🔄 VideoOverlayView localStorage change: Updated like state to \(storedLikedState) for video \(video.id)")
                }
            }
        }
    }
    
    private func handleLikeToggle() {
        guard !isLiking else { return }
        
        isLiking = true
        let newLikedState = !currentLikedState
        
        // Optimistically update UI
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            currentLikedState = newLikedState
            likeCount += newLikedState ? 1 : -1
        }
        
        // Notify parent of like state change
        onLikeChanged?(newLikedState)
        
        // Record interaction in local storage
        localStorage.recordInteraction(
            videoId: video.id,
            liked: newLikedState,
            commented: false,
            shared: false
        )
        
        // Call API to like/unlike the video
        Task {
            do {
                try await apiService.likeVideo(clipId: video.id)
                print("✅ Successfully liked/unliked video: \(video.id)")
            } catch {
                print("❌ Failed to like/unlike video: \(error)")
                // Revert the optimistic update on failure
                await MainActor.run {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        currentLikedState = !newLikedState
                        likeCount += newLikedState ? -1 : 1
                    }
                    onLikeChanged?(!newLikedState)
                }
            }
            
            await MainActor.run {
                isLiking = false
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
            VideoOverlayView(video: VideoClip.mock, isLiked: false, onLikeChanged: { _ in })
        }
    }
}
