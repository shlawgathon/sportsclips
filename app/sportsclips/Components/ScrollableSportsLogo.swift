//
//  ScrollableSportsLogo.swift
//  sportsclips
//
//  Auto-scrolling sports icons with Apple's liquid glass design
//  Scrolls left automatically + manual swipe control
//

import SwiftUI

struct ScrollableSportsLogo: View {
    // All available SF Symbol sports icons
    let sportsIcons = [
        "figure.run",
        "figure.basketball",
        "figure.baseball",
        "football.fill",
        "baseball.fill",
        "basketball.fill",
        "soccerball",
        "tennisball.fill",
        "figure.tennis",
        "figure.soccer",
        "figure.golf",
        "figure.skiing.downhill",
        "figure.snowboarding",
        "figure.hockey",
        "hockey.puck.fill",
        "figure.boxing",
        "figure.wrestling",
        "figure.martial.arts",
        "figure.volleyball",
        "figure.surfing",
        "figure.skating",
        "figure.bowling",
        "figure.fishing",
        "figure.equestrian.sports",
        "figure.badminton",
        "figure.rugby",
        "cricket.ball.fill",
        "figure.archery"
    ]
    
    // Create infinite copies
    private var infiniteIcons: [String] {
        Array(repeating: sportsIcons, count: 20).flatMap { $0 }
    }
    
    @State private var scrollOffset: CGFloat = 0
    @State private var isAutoScrolling = true
    @State private var userIsDragging = false
    @State private var dragStartOffset: CGFloat = 0
    
    let iconWidth: CGFloat = 120 // 100 + 20 spacing
    let autoScrollSpeed: Double = 1.0 // Points per frame (about 30fps) - Faster scroll
    
    var body: some View {
        GeometryReader { outerGeometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(0..<infiniteIcons.count, id: \.self) { index in
                            GeometryReader { geometry in
                                let frame = geometry.frame(in: .global)
                                let midX = frame.midX
                                let screenWidth = outerGeometry.size.width 
                                let screenMidX = screenWidth / 2
                                
                                // Calculate offset from center
                                let offset = (midX - screenMidX) / (screenWidth / 2)
                                let clampedOffset = max(-2.5, min(2.5, offset))
                                
                                LiquidGlassSportsIcon(
                                    icon: infiniteIcons[index],
                                    offset: clampedOffset
                                )
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                            .frame(width: 100, height: 250)
                            .id(index)
                        }
                    }
                    .padding(.horizontal, (outerGeometry.size.width - 100) / 2)
                    .offset(x: scrollOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Stop auto-scroll when user starts dragging
                                if !userIsDragging {
                                    userIsDragging = true
                                    isAutoScrolling = false
                                    dragStartOffset = scrollOffset
                                }
                                
                                // Apply user's drag
                                scrollOffset = dragStartOffset + value.translation.width
                            }
                            .onEnded { value in
                                userIsDragging = false
                                
                                // Resume auto-scroll after 2 seconds of no interaction
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                    if !userIsDragging {
                                        isAutoScrolling = true
                                    }
                                }
                                
                                // Add momentum to the scroll
                                let velocity = value.predictedEndTranslation.width - value.translation.width
                                withAnimation(.interpolatingSpring(stiffness: 100, damping: 15)) {
                                    scrollOffset += velocity * 0.3
                                }
                                
                                // Check if we need to loop
                                checkAndLoopScroll()
                            }
                    )
                }
                .frame(height: 150)
                .onAppear {
                    // Start from middle
                    let middleIndex = infiniteIcons.count / 2
                    scrollOffset = -CGFloat(middleIndex) * iconWidth + (outerGeometry.size.width / 2)
                    
                    // Start auto-scroll
                    startAutoScroll()
                }
            }
        }
        .frame(height: 150)
    }
    
    private func startAutoScroll() {
        Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { timer in
            guard isAutoScrolling else { return }
            
            withAnimation(.linear(duration: 1/30)) {
                scrollOffset -= autoScrollSpeed
            }
            
            // Loop the scroll when reaching end
            checkAndLoopScroll()
        }
    }
    
    private func checkAndLoopScroll() {
        let totalWidth = CGFloat(infiniteIcons.count) * iconWidth
        let loopPoint = totalWidth / 4 // Loop at 1/4 through the array
        
        // If scrolled too far left, jump back
        if scrollOffset < -loopPoint * 3 {
            scrollOffset += loopPoint
        }
        
        // If scrolled too far right, jump forward
        if scrollOffset > -loopPoint {
            scrollOffset -= loopPoint
        }
    }
}

// Individual liquid glass sports icon
struct LiquidGlassSportsIcon: View {
    let icon: String
    let offset: CGFloat
    
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(glowOpacity),
                            .clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
                .blur(radius: 15)
                .scaleEffect(isCenter ? 1.3 : 1.0)
            
            // Main liquid glass container
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    .white.opacity(0.5),
                                    .white.opacity(0.1),
                                    .white.opacity(0.3)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .overlay(
                    // Inner shimmer
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    .white.opacity(0.15),
                                    .clear
                                ],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 50
                            )
                        )
                )
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                .shadow(color: .white.opacity(0.1), radius: 5, x: 0, y: -5)
                .frame(width: 90, height: 90)
            
            // Sport icon
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            .white,
                            .white.opacity(0.8)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 2)
        }
        .rotation3DEffect(
            .degrees(Double(offset) * -30),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.6
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .brightness(brightness)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: offset)
    }
    
    // Computed properties for smooth animations
    private var isCenter: Bool {
        abs(offset) < 0.2
    }
    
    private var scale: CGFloat {
        let absOffset = abs(offset)
        if absOffset < 0.2 {
            return 1.15 // Larger at center
        } else if absOffset > 1.5 {
            return 0.75 // Smaller at edges
        } else {
            let progress = (absOffset - 0.2) / 1.3
            return 1.15 - (progress * 0.4)
        }
    }
    
    private var opacity: Double {
        let absOffset = abs(offset)
        if absOffset < 0.2 {
            return 1.0
        } else if absOffset > 2.0 {
            return 0.6
        } else {
            let progress = (absOffset - 0.2) / 1.8
            return 1.0 - (progress * 0.4)
        }
    }
    
    private var brightness: Double {
        let absOffset = abs(offset)
        if absOffset < 0.2 {
            return 0.15 // Brightest at center
        } else if absOffset > 1.5 {
            return -0.15 // Dimmer at edges
        } else {
            let progress = (absOffset - 0.2) / 1.3
            return 0.15 - (progress * 0.3)
        }
    }
    
    private var glowOpacity: Double {
        let absOffset = abs(offset)
        if absOffset < 0.2 {
            return 0.4 // Strong glow at center
        } else if absOffset > 1.5 {
            return 0.0 // No glow at edges
        } else {
            let progress = (absOffset - 0.2) / 1.3
            return 0.4 - (progress * 0.4)
        }
    }
    
    private var iconSize: CGFloat {
        let absOffset = abs(offset)
        if absOffset < 0.2 {
            return 42 // Larger icon at center
        } else if absOffset > 1.5 {
            return 32 // Smaller at edges
        } else {
            let progress = (absOffset - 0.2) / 1.3
            return 42 - (progress * 10)
        }
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [.black, .purple.opacity(0.3), .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        
        VStack {
            Text("Auto-Scrolling Sports Icons")
                .font(.title2.bold())
                .foregroundColor(.white)
                .padding(.top, 60)
            
            Text("Swipe to pause • Auto-resumes in 2s")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.bottom, 20)
            
            ScrollableSportsLogo()
            
            Spacer()
        }
    }
}