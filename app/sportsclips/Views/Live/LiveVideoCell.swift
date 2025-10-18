//
//  LiveVideoCell.swift
//  sportsclips
//
//  Complete live video cell with player, overlays, and always-visible comments
//  Fixed to ensure all elements fit within screen bounds and comment section works
//

import SwiftUI

struct LiveVideoCell: View {
    let video: VideoClip
    @ObservedObject var playerManager: VideoPlayerManager
    
    @State private var isLiked = false
    @State private var commentText = ""
    @State private var heartAnimation: HeartAnimation?
    @StateObject private var localStorage = LocalStorageService.shared
    @FocusState private var isCommentFieldFocused: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video player (non-interactive) - fills entire container
                LiveVideoPlayerView(
                    video: video,
                    playerManager: playerManager,
                    isLiked: $isLiked,
                    showingCommentInput: .constant(false)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Invisible overlay for double-tap to like (excludes comment bar area)
                VStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            handleDoubleTapLike(at: CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2))
                        }
                    
                    // Empty space for comment bar and UI elements (not tappable for likes)
                    Spacer()
                        .frame(height: 320) // Enough space for comments, caption, and input
                }
                .allowsHitTesting(!isCommentFieldFocused) // Disable double-tap when typing
                .zIndex(1)
                
                // Top bar - category, likes, and share
                VStack {
                    HStack(spacing: 12) {
                        // Sport tag with LIVE indicator
                        HStack(spacing: 6) {
                            Circle()
                                .fill(.red)
                                .frame(width: 8, height: 8)
                            
                            Image(systemName: video.sport.icon)
                                .font(.system(size: 13, weight: .medium))
                            Text(video.sport.rawValue)
                                .font(.system(size: 12, weight: .semibold))
                            
                            Text("LIVE")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            ZStack {
                                // Liquid glass background
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [
                                                        .red.opacity(0.6),
                                                        .red.opacity(0.3)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1.5
                                            )
                                    )
                                    .shadow(color: .red.opacity(0.3), radius: 8, x: 0, y: 2)
                                
                                // Red tint overlay
                                Capsule()
                                    .fill(.red.opacity(0.4))
                            }
                        )
                        
                        Spacer()
                        
                        // Like counter
                        HStack(spacing: 4) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(isLiked ? .red : .white)
                            
                            Text("\(video.likes + (isLiked ? 1 : 0))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                        .onTapGesture {
                            toggleLike()
                        }
                        
                        // Share button
                        Button(action: {
                            shareVideo()
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(
                                    Circle()
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 50)
                    
                    Spacer()
                }
                .zIndex(2)
                
                // Heart animation overlay
                if let heartAnimation = heartAnimation {
                    HeartAnimationView(animation: heartAnimation)
                        .zIndex(3)
                        .allowsHitTesting(false)
                }
                
                // Overlay content - all aligned to bottom and within screen bounds
                VStack(spacing: 0) {
                    Spacer()
                    
                    // Left side - Caption and live comments (full width)
                    VStack(alignment: .leading, spacing: 8) {
                        // Live comments section (limited height)
                        LiveCommentsView()
                            .frame(maxHeight: 180)
                        
                        // Caption text
                        Text(video.caption)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    
                    // Comment input - always visible at bottom (full width)
                    HStack(spacing: 10) {
                        // Comment input field (expandable)
                        TextField("Add a comment...", text: $commentText)
                            .focused($isCommentFieldFocused)
                            .font(.system(size: 14))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
                            .overlay(
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(.white.opacity(0.3), lineWidth: 1.5)
                            )
                            .foregroundColor(.white)
                            .submitLabel(.send)
                            .onSubmit {
                                sendComment()
                            }
                        
                        // Send button (aligned to right)
                        Button(action: {
                            sendComment()
                        }) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundColor(commentText.isEmpty ? .gray.opacity(0.5) : .blue)
                        }
                        .disabled(commentText.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, geometry.safeAreaInsets.bottom > 0 ? 20 : 100)
                }
                .zIndex(4) // Ensure comment section is above double-tap overlay
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
    
    private func toggleLike() {
        isLiked.toggle()
        
        // Record interaction in local storage
        localStorage.recordInteraction(
            videoId: video.id,
            liked: isLiked,
            commented: false,
            shared: false
        )
        
        // Haptic feedback
        if isLiked {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        }
    }
    
    private func sendComment() {
        guard !commentText.isEmpty else { return }
        
        // Record comment interaction
        localStorage.recordInteraction(
            videoId: video.id,
            liked: isLiked,
            commented: true,
            shared: false
        )
        
        // TODO: Send comment to API
        print("Sending comment: \(commentText)")
        
        // Clear input and dismiss keyboard
        commentText = ""
        isCommentFieldFocused = false
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
    }
    
    private func shareVideo() {
        // Record share interaction in local storage
        localStorage.recordInteraction(
            videoId: video.id,
            liked: isLiked,
            commented: false,
            shared: true
        )
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        // Present share sheet
        let activityVC = UIActivityViewController(
            activityItems: [video.videoURL],
            applicationActivities: nil
        )
        
        // Get the current window scene to present the share sheet
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            
            // For iPad, set the popover presentation controller
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            
            rootViewController.present(activityVC, animated: true)
        }
    }
    
    private func handleDoubleTapLike(at location: CGPoint) {
        // Toggle like state
        isLiked.toggle()
        
        // Record interaction in local storage
        localStorage.recordInteraction(
            videoId: video.id,
            liked: isLiked,
            commented: false,
            shared: false
        )
        
        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        // Create heart animation
        let animation = HeartAnimation(
            id: UUID().uuidString,
            location: location,
            isLiked: isLiked
        )
        heartAnimation = animation
        
        // Remove animation after it completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            heartAnimation = nil
        }
    }
}

#Preview {
    LiveVideoCell(
        video: VideoClip.mock,
        playerManager: VideoPlayerManager()
    )
}