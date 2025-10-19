//
//  HeartAnimation.swift
//  sportsclips
//
//  Heart animation component for like interactions
//

import SwiftUI

struct HeartAnimation {
    let id: String
    let location: CGPoint
    let isLiked: Bool
}

struct HeartAnimationView: View {
    let animation: HeartAnimation
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 1.0
    @State private var offset: CGFloat = 0
    
    var body: some View {
        Image(systemName: animation.isLiked ? "heart.fill" : "heart")
            .font(.system(size: 60, weight: .bold))
            .foregroundColor(animation.isLiked ? .red : .white)
            .scaleEffect(scale)
            .opacity(opacity)
            .offset(y: offset)
            .position(animation.location)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = 1.2
                }
                
                withAnimation(.easeOut(duration: 1.0).delay(0.1)) {
                    offset = -50
                    opacity = 0
                }
            }
    }
}
