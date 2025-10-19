//
//  LiveView.swift
//  sportsclips
//
//  Placeholder view for future live videos
//

import SwiftUI

struct LiveView: View {
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [.black, .purple.opacity(0.3), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "video.circle")
                    .font(.system(size: 80, weight: .light))
                    .foregroundColor(.white.opacity(0.6))
                
                Text("Live Videos")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Coming Soon")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                
                Text("Live sports streaming will be available here")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
    }
}

#Preview {
    LiveView()
}
