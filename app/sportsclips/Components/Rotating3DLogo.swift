//
//  Rotating3DLogo.swift
//  sportsclips
//
//  Horizontal disk rotating around vertical axis with icons moving along X-axis
//

import SwiftUI

struct Rotating3DLogo: View {
    @State private var rotation: Double = 0
    
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
    
    var body: some View {
        ZStack {
            ForEach(0..<sportsIcons.count, id: \.self) { index in
                IconView(
                    icon: sportsIcons[index],
                    index: index,
                    totalIcons: sportsIcons.count,
                    rotation: rotation
                )
            }
        }
        .frame(width: 280, height: 100)
        .onAppear {
            startRotation()
        }
    }
    
    private func startRotation() {
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
}

struct IconView: View {
    let icon: String
    let index: Int
    let totalIcons: Int
    let rotation: Double
    
    var body: some View {
        let angle = (Double(index) * 360.0 / Double(totalIcons)) + rotation
        let radians = angle * .pi / 180.0
        
        // Horizontal disk rotating around vertical (Y) axis
        let radius: CGFloat = 120
        let x = radius * CGFloat(sin(radians)) // Horizontal position (-x to +x)
        let z = radius * CGFloat(cos(radians)) // Depth (forward/back)
        
        // Calculate scale based on depth
        let normalizedZ = (z + radius) / (2 * radius) // 0 to 1
        let scale = 0.4 + (normalizedZ * 0.6) // 0.4 to 1.0
        
        // Opacity: front (z>0) visible, back (z<0) fades to 0
        let opacity = calculateOpacity(z: z, normalizedZ: normalizedZ)
        
        return Image(systemName: icon)
            .font(.system(size: 70, weight: .light))
            .foregroundColor(.white.opacity(0.8))
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(x: x)
            .zIndex(z)
            .animation(.linear(duration: 0), value: rotation) // Smooth continuous animation
    }
    
    private func calculateOpacity(z: CGFloat, normalizedZ: CGFloat) -> Double {
        if z > 0 {
            // Front half: fully visible
            return 0.7 + (normalizedZ * 0.3) // 0.7 to 1.0
        } else {
            // Back half: fade to 0
            return max(0, normalizedZ * 1.4) // Fades to 0 at the back
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
        
        Rotating3DLogo()
    }
}
