//
//  AnimatedSportsLogo.swift
//  sportsclips
//
//  Animated sports icon carousel with fidget spinner-like rotation
//

import SwiftUI

struct AnimatedSportsLogo: View {
    @State private var currentIndex = 0
    @State private var offset: CGFloat = 0
    @State private var isSpinning = false
    @State private var spinVelocity: CGFloat = 0
    
    let sportsIcons = [
        "baseball.fill",
        "football.fill", 
        "basketball.fill",
        "soccerball",
        "tennisball.fill",
        "figure.golf",
        "hockey.puck.fill",
        "figure.boxing"
    ]
    
    private let iconSpacing: CGFloat = 100
    
    var body: some View {
        ZStack {
            // Show multiple icons during spin, only one when static
            ForEach(0..<sportsIcons.count, id: \.self) { index in
                let relativeIndex = (index - currentIndex + sportsIcons.count) % sportsIcons.count
                let position = CGFloat(relativeIndex) * iconSpacing + offset
                
                Image(systemName: sportsIcons[index])
                    .font(.system(size: 70, weight: .light))
                    .foregroundColor(.white.opacity(0.8))
                    .offset(x: position)
                    .opacity(calculateOpacity(for: position))
                    .scaleEffect(calculateScale(for: position))
            }
        }
        .frame(width: 180, height: 90)
        .clipped()
        .onAppear {
            startFidgetSpin()
        }
    }
    
    private func calculateOpacity(for position: CGFloat) -> Double {
        if !isSpinning {
            // Only show center icon when static
            return abs(position) < 10 ? 1.0 : 0.0
        } else {
            // Show all icons at full opacity during spin - no fade
            return 1.0
        }
    }
    
    private func calculateScale(for position: CGFloat) -> CGFloat {
        let distance = abs(position)
        if distance < 30 {
            return 1.0 // Full size for center
        } else if distance < 250 {
            return 0.98 - (distance / 1000) // Very gradual size reduction
        }
        return 0.85 // Keep side icons large and visible
    }
    
    private func startFidgetSpin() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            // Slower, more visible spin with deceleration
            isSpinning = true
            spinVelocity = -300 // Reduced initial velocity
            
            // Animate through icons with visible motion
            let spinsCount = Int.random(in: 2...3) // Fewer rotations for slower feel
            let targetOffset = -CGFloat(spinsCount * sportsIcons.count) * iconSpacing
            
            withAnimation(.interpolatingSpring(
                mass: 2.0,
                stiffness: 25,
                damping: 14,
                initialVelocity: 3
            )) {
                offset = targetOffset
            }
            
            // Update current index and reset
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                currentIndex = (currentIndex + spinsCount * sportsIcons.count) % sportsIcons.count
                offset = 0
                isSpinning = false
                spinVelocity = 0
            }
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
        
        AnimatedSportsLogo()
    }
}
