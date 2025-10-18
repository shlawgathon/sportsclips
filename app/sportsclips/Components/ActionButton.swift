//
//  ActionButton.swift
//  sportsclips
//
//  Animated action buttons with haptics and liquid glass
//

import SwiftUI

struct ActionButton: View {
    let icon: String
    let count: Int?
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var isLiked = false
    
    init(icon: String, count: Int? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.count = count
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 6) {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = true
                }
                
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                action()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                        isPressed = false
                    }
                }
            }) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        ZStack {
                            // Outer glow
                            Circle()
                                .fill(.white.opacity(0.1))
                                .blur(radius: 8)
                                .scaleEffect(1.2)
                            
                            // Main button
                            Circle()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Circle()
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
                                .shadow(
                                    color: .black.opacity(0.2),
                                    radius: 8,
                                    x: 0,
                                    y: 4
                                )
                        }
                    )
                    .scaleEffect(isPressed ? 0.9 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            }
            .buttonStyle(PlainButtonStyle())
            
            if let count = count {
                Text(formatCount(count))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, x: 0, y: 1)
            }
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

#Preview {
    ZStack {
        Color.black
        VStack(spacing: 20) {
            ActionButton(icon: "heart", count: 12500) { }
            ActionButton(icon: "message", count: 432) { }
            ActionButton(icon: "square.and.arrow.up", count: 89) { }
        }
    }
}
