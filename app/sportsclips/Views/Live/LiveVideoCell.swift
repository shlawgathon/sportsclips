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
    @Binding var selectedSport: VideoClip.Sport
    let onSportChange: (VideoClip.Sport) -> Void

    @State private var isLiked = false
    @State private var commentText = ""
    @State private var heartAnimation: HeartAnimation?
    @StateObject private var localStorage = LocalStorageService.shared
    @StateObject private var liveService = LiveCommentService.shared
    @FocusState private var isCommentFieldFocused: Bool
    @State private var showSportDropdown = false
    @State private var isSummaryExpanded = false
    @State private var showComments = true

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

                            // Show icon if it exists in SF Symbols, otherwise show sport name
                            if UIImage(systemName: video.sport.icon) != nil {
                                Image(systemName: video.sport.icon)
                                    .font(.system(size: 13, weight: .medium))
                            } else {
                                Text(video.sport.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                            }

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

                        // Sport filter button - same height as live tag
                        Button(action: {
                            showSportDropdown.toggle()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "line.3.horizontal.decrease")
                                    .font(.system(size: 13, weight: .medium))

                                Text(selectedSport == .all ? "All" : selectedSport.rawValue)
                                    .font(.system(size: 11, weight: .bold))
                            }
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
                                                        .white.opacity(0.3),
                                                        .white.opacity(0.1)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1.5
                                            )
                                    )
                                    .shadow(color: .white.opacity(0.2), radius: 8, x: 0, y: 2)

                                // White tint overlay
                                Capsule()
                                    .fill(.white.opacity(0.1))
                            }
                        )

                        Spacer()

                        // View count
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))

                            Text("\(liveService.viewerCount)")
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

                        // Like counter
                        HStack(spacing: 4) {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(isLiked ? .red : .white)

                            Text(formatCount(video.likes + (isLiked ? 1 : 0)))
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

                // Overlay content - comments, summary, and comment input
                VStack(spacing: 0) {
                    Spacer()

                    // Left side - Caption and live comments (full width)
                    VStack(alignment: .leading, spacing: 8) {
                        // Live comments section (limited height) - hide when summary is expanded
                        if showComments && !isSummaryExpanded {
                            LiveCommentsView(liveId: video.id)
                                .frame(maxHeight: 180)
                        }

                        // Live summary with expand/collapse functionality
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "livephoto")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.red)

                                Text("Live Summary")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.9))

                                Text("-")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))

                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        isSummaryExpanded.toggle()
                                    }
                                }) {
                                    Text(isSummaryExpanded ? "see less" : "see more...")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                        .underline()
                                }

                                Spacer()

                                // Hide comments button
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showComments.toggle()
                                    }
                                }) {
                                    Image(systemName: showComments ? "eye.slash" : "eye")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }

                            // Expanded summary content
                            if isSummaryExpanded {
                                let liveSummary = generateLiveSummary(for: video)
                                Text(liveSummary)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white)
                                    .multilineTextAlignment(.leading)
                                    .padding(.top, 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)

                    // Comment input with share button - positioned right below caption
                    HStack(spacing: 10) {
                        // Share button (left side)
                        Button(action: {
                            shareVideo()
                        }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(
                                    Circle()
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        }

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
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(commentText.isEmpty ? .gray.opacity(0.5) : .blue)
                                .padding(10)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay(
                                    Circle()
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .disabled(commentText.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 88) // Same gap as highlights page
                    .background(
                        // Add a subtle background to ensure visibility
                        Rectangle()
                            .fill(.black.opacity(0.3))
                    )
                }
                .zIndex(20) // Ensure comment section is above menu bar and dropdown

                // Sport filter dropdown - positioned as overlay
                if showSportDropdown {
                    VStack {
                        HStack {
                            VStack(spacing: 0) {
                                ForEach(VideoClip.Sport.allCases, id: \.self) { sport in
                                    Button(action: {
                                        showSportDropdown = false
                                        onSportChange(sport)
                                    }) {
                                        HStack(spacing: 8) {
                                            if sport == .all {
                                                Image(systemName: "flame")
                                                    .font(.system(size: 14, weight: .medium))
                                            } else if UIImage(systemName: sport.icon) != nil {
                                                Image(systemName: sport.icon)
                                                    .font(.system(size: 14, weight: .medium))
                                            } else {
                                                Text(sport.rawValue)
                                                    .font(.system(size: 12, weight: .medium))
                                            }

                                            Text(sport == .all ? "All" : sport.rawValue)
                                                .font(.system(size: 12, weight: .medium))

                                            Spacer()

                                            if selectedSport == sport {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .medium))
                                            }
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            Rectangle()
                                                .fill(selectedSport == sport ? .white.opacity(0.1) : .clear)
                                        )
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(.white.opacity(0.2), lineWidth: 1)
                                    )
                            )
                            .padding(.leading, 16)
                            .padding(.top, 100) // Position below the top bar

                            Spacer()
                        }

                        Spacer()
                    }
                    .zIndex(20) // Above everything else
                }
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

        let commentToSend = commentText

        // Record comment interaction
        localStorage.recordInteraction(
            videoId: video.id,
            liked: isLiked,
            commented: true,
            shared: false
        )

        // Send comment to API via service
        Task {
            await LiveCommentService.shared.postComment(commentToSend)
        }

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


    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            let millions = Double(count) / 1_000_000.0
            if millions == floor(millions) {
                return "\(Int(millions))M"
            } else {
                return String(format: "%.1fM", millions)
            }
        } else if count >= 1_000 {
            let thousands = Double(count) / 1_000.0
            if thousands == floor(thousands) {
                return "\(Int(thousands))K"
            } else {
                return String(format: "%.1fK", thousands)
            }
        } else {
            return "\(count)"
        }
    }

    private func generateLiveSummary(for video: VideoClip) -> String {
        let sport = video.sport.rawValue
        let baseSummary = "Live \(sport) action happening right now! Join thousands of fans watching this exciting match. "

        // Add sport-specific details
        let sportDetails: String
        switch video.sport {
        case .basketball:
            sportDetails = "Watch as players make incredible shots, amazing dunks, and clutch plays in real-time. The energy is electric!"
        case .football:
            sportDetails = "Experience the intensity of every play, touchdown celebrations, and game-changing moments as they happen."
        case .soccer:
            sportDetails = "Follow the beautiful game with live goals, spectacular saves, and dramatic moments unfolding before your eyes."
        case .baseball:
            sportDetails = "Catch every pitch, home run, and incredible defensive play as the game unfolds in real-time."
        case .tennis:
            sportDetails = "Watch intense rallies, powerful serves, and match-defining points as the action heats up on court."
        case .hockey:
            sportDetails = "Feel the speed and intensity of every shift, goal, and bone-crushing hit as the game progresses."
        case .boxing:
            sportDetails = "Witness every punch, combination, and knockout moment as fighters battle it out in the ring."
        case .mma:
            sportDetails = "Experience the raw power and technique of mixed martial arts with every takedown, submission, and finish."
        case .racing:
            sportDetails = "Feel the speed and adrenaline as drivers push their limits on every turn and straightaway."
        case .golf:
            sportDetails = "Follow every swing, putt, and birdie as players navigate the course in this live tournament."
        case .all:
            sportDetails = "Don't miss any of the action as athletes compete at the highest level in this live sporting event."
        }

        return baseSummary + sportDetails
    }

}

//#Preview {
//    LiveVideoCell(
//        video: VideoClip.mock,
//        playerManager: VideoPlayerManager.shared,
//        selectedSport: .constant(.all),
//        onSportChange: { _ in }
//    )
//}
