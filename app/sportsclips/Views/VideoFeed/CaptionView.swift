//
//  CaptionView.swift
//  sportsclips
//
//  Bottom caption display with author info
//

import SwiftUI

struct CaptionView: View {
    let video: VideoClip
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Sport category
            HStack(spacing: 8) {
                Image(systemName: video.sport.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                
                Text(video.sport.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            
            // Caption text
            Text(video.caption)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(.white)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

#Preview {
    ZStack {
        Color.black
        VStack {
            Spacer()
            CaptionView(video: VideoClip.mock)
        }
    }
}
