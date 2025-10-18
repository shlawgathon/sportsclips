//
//  CaptionView.swift
//  sportsclips
//
//  Bottom caption display with author info
//

import SwiftUI

struct CaptionView: View {
    let video: VideoClip
    let onGameTap: () -> Void
    let showControls: Bool
    let currentTime: Double
    let duration: Double
    let onSeek: (Double) -> Void
    let onDragStart: (() -> Void)?
    let onDragEnd: (() -> Void)?
    @State private var sliderTime: Double = 0
    @State private var jiggleScale: CGFloat = 1.0
    @State private var isExpanded: Bool = false
    @State private var isDragging: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sport category
            HStack(spacing: 8) {
                Image(systemName: video.sport.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Text(video.sport.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.bottom, 8)
            
            // Title and description with expandable "see more/less"
            VStack(alignment: .leading, spacing: 4) {
                // Show title if available
                if let title = video.title, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                
                // Show description/caption
                let displayText = video.description ?? video.caption
                Text(displayText)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(isExpanded ? nil : 3)
                    .multilineTextAlignment(.leading)
                
                // Show "see more" or "see less" button if text is long
                if displayText.count > 80 {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            isExpanded.toggle()
                        }
                    }) {
                        Text(isExpanded ? "see less" : "see more")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                            .underline()
                    }
                }
            }
            .padding(.bottom, 16) // Same spacing as bottom menu
            
                    // Fixed height container to prevent caption shifting
                    ZStack {
                        // Game bubble (always present, animated opacity)
                        GameBubble(gameName: extractGameName(from: video)) {
                            onGameTap()
                        }
                        .opacity(showControls ? 0 : 1)
                        .scaleEffect(showControls ? 0.95 : jiggleScale)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showControls)
                        .onChange(of: showControls) { _, newValue in
                            // Only animate when game bubble is becoming visible
                            if !newValue {
                                jiggleScale = 1.08
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                                    jiggleScale = 1.0
                                }
                            }
                        }
                        
                        // Slider control (always present, animated opacity)
                        HStack {
                            Text(formatTime(currentTime))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 40)
                            
                            Slider(value: Binding(
                                get: { sliderTime },
                                set: { newTime in
                                    sliderTime = newTime
                                    onSeek(newTime)
                                }
                            ), in: 0...max(duration, 1.0))
                            .accentColor(.white)
                            .frame(height: 20)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        // Only handle drag events if controls are actually visible
                                        guard showControls else { return }
                                        
                                        if !isDragging {
                                            isDragging = true
                                            onDragStart?()
                                        }
                                        
                                        // Drag is in progress - no timer needed
                                    }
                                    .onEnded { _ in
                                        // Only handle drag end if we were actually dragging
                                        guard isDragging else { return }
                                        
                                        isDragging = false
                                        onDragEnd?()
                                    }
                            )
                            
                            Text(formatTime(duration))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                                .frame(width: 40)
                        }
                        .padding(.horizontal, 16) // Match GameBubble horizontal padding
                        .padding(.vertical, 10)   // Match GameBubble vertical padding
                        .background(
                            ZStack {
                                // Liquid Glass background - match GameBubble styling
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Capsule()
                                            .stroke(
                                                LinearGradient(
                                                    colors: [
                                                        .white.opacity(0.2),
                                                        .white.opacity(0.05)
                                                    ],
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 0.5
                                            )
                                    )
                            }
                            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                        )
                        .opacity(showControls ? 1 : 0)
                        .scaleEffect(showControls ? jiggleScale : 0.95)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: showControls)
                        .onChange(of: showControls) { _, newValue in
                            // Only animate when slider is becoming visible
                            if newValue {
                                jiggleScale = 1.08
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                                    jiggleScale = 1.0
                                }
                            }
                        }
                    }
                    .frame(height: 50) // Fixed height to prevent layout shifts
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16) // Keep horizontal padding for caption text
        .padding(.top, 8)         // Further reduced top padding for even spacing
        .padding(.bottom, 8)      // Reduced bottom padding to move controls down
        .background(
            ZStack {
                // Sticky background with stronger opacity
                LinearGradient(
                    colors: [.clear, .black.opacity(0.85)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Additional blur effect for better readability
                Rectangle()
                    .fill(.ultraThinMaterial.opacity(0.3))
                    .blendMode(.overlay)
            }
        )
        .onAppear {
            sliderTime = currentTime
        }
        .onChange(of: currentTime) { _, newTime in
            sliderTime = newTime
        }
        .onDisappear {
            // Clean up drag state when view disappears
            isDragging = false
        }
    }
    
    private func extractGameName(from video: VideoClip) -> String {
        // Try to extract game name from title first, then description
        let textToAnalyze = video.title ?? video.description ?? video.caption
        
        // Look for common game patterns
        let lowercasedText = textToAnalyze.lowercased()
        
        // Check for specific game types
        if lowercasedText.contains("championship") || lowercasedText.contains("final") {
            return "Championship Game"
        } else if lowercasedText.contains("playoff") {
            return "Playoff Game"
        } else if lowercasedText.contains("semifinal") {
            return "Semifinal"
        } else if lowercasedText.contains("quarterfinal") {
            return "Quarterfinal"
        } else if lowercasedText.contains("derby") {
            return "Derby Match"
        } else if lowercasedText.contains("classic") {
            return "Classic Match"
        }
        
        // Extract from title if available
        if let title = video.title, !title.isEmpty {
            let words = title.components(separatedBy: " ")
            if words.count >= 2 {
                return "\(words[0]) \(words[1])"
            }
            return title
        }
        
        // Fallback to first few words of description
        let words = textToAnalyze.components(separatedBy: " ")
        if words.count >= 2 {
            return "\(words[0]) \(words[1])"
        }
        
        return "Game Highlights"
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    ZStack {
        Color.black
        VStack {
            Spacer()
            CaptionView(
                video: VideoClip.mock,
                onGameTap: { print("Game tapped") },
                showControls: false,
                currentTime: 120.0,
                duration: 596.0,
                onSeek: { _ in },
                onDragStart: { print("Drag started") },
                onDragEnd: { print("Drag ended") }
            )
        }
    }
}
