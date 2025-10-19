//
//  LiquidGlassSegmentedControl.swift
//  sportsclips
//
//  Apple's Liquid Glass Segmented Control with refracting edges
//

import SwiftUI

struct LiquidGlassSegmentedControl: View {
    @Binding var selectedIndex: Int
    let items: [SegmentedItem]
    let onSelectionChanged: (Int) -> Void
    
    @State private var dragLocation: CGFloat? = nil
    @Namespace private var animation
    
    var body: some View {
        GeometryReader { geometry in
            let itemWidth = geometry.size.width / CGFloat(items.count)
            
            ZStack {
                // Main liquid glass background
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule()
                            .fill(.thinMaterial)
                            .opacity(0.3)
                    }
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                    }
                    .shadow(color: Color.black.opacity(0.2), radius: 20, x: 0, y: 10)
                    .shadow(color: Color.white.opacity(0.1), radius: 1, x: 0, y: -1)
                
                // Selection indicator - clear glass with refraction
                HStack(spacing: 0) {
                    ForEach(0..<items.count, id: \.self) { index in
                        if index == currentIndex {
                            Capsule()
                                .fill(.thickMaterial)
                                .overlay {
                                    Capsule()
                                        .fill(.regularMaterial)
                                        .opacity(0.4)
                                }
                                .overlay {
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.8)
                                }
                                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
                                .shadow(color: Color.white.opacity(0.3), radius: 2, x: 0, y: 1)
                                .padding(3)
                                .matchedGeometryEffect(
                                    id: "selector",
                                    in: animation
                                )
                        } else {
                            Color.clear
                                .frame(width: itemWidth)
                        }
                    }
                }
                
                // Items with icons and text
                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedIndex = index
                                onSelectionChanged(index)
                            }
                        }) {
                            VStack(spacing: 4) {
                                if !item.icon.isEmpty {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 18, weight: .medium))
                                        .symbolEffect(.bounce, value: index == currentIndex)
                                }
                                
                                Text(item.title)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .foregroundStyle(Color.white.opacity(0.9))
                            .frame(width: itemWidth, height: 50)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragLocation = value.location.x
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            let segmentWidth = geometry.size.width / CGFloat(items.count)
                            let newIndex = min(max(Int(value.location.x / segmentWidth), 0), items.count - 1)
                            selectedIndex = newIndex
                            onSelectionChanged(newIndex)
                            dragLocation = nil
                        }
                    }
            )
        }
        .frame(height: 56)
    }
    
    private var currentIndex: Int {
        return selectedIndex
    }
}

struct SegmentedItem {
    let icon: String
    let title: String
    let tag: Int
    
    init(icon: String = "", title: String, tag: Int) {
        self.icon = icon
        self.title = title
        self.tag = tag
    }
}

#Preview {
    LiquidGlassSegmentedControlPreview()
}

struct LiquidGlassSegmentedControlPreview: View {
    @State private var selectedIndex = 1
    
    var body: some View {
        ZStack {
            // Background with depth to show glass refraction
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.1, blue: 0.12),
                    Color(red: 0.08, green: 0.08, blue: 0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Background elements to see glass effect
            VStack(spacing: 20) {
                ForEach(0..<15) { _ in
                    HStack(spacing: 15) {
                        Circle()
                            .fill(Color.purple.opacity(0.3))
                            .frame(width: 60, height: 60)
                        
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.2))
                            .frame(height: 40)
                        
                        Circle()
                            .fill(Color.pink.opacity(0.3))
                            .frame(width: 50, height: 50)
                    }
                    .padding(.horizontal)
                }
            }
            .offset(y: -200)
            
            VStack(spacing: 30) {
                // Main control with icons - Apple style
                LiquidGlassSegmentedControl(
                    selectedIndex: $selectedIndex,
                    items: [
                        SegmentedItem(icon: "video.circle.fill", title: "Live", tag: 0),
                        SegmentedItem(icon: "flame.fill", title: "Highlight", tag: 1),
                        SegmentedItem(icon: "person.crop.circle.fill", title: "Profile", tag: 2)
                    ],
                    onSelectionChanged: { index in
                        print("Selected: \(index)")
                    }
                )
                .frame(width: 320)
                
                // Secondary example with different icons
                LiquidGlassSegmentedControl(
                    selectedIndex: $selectedIndex,
                    items: [
                        SegmentedItem(icon: "music.note", title: "Music", tag: 0),
                        SegmentedItem(icon: "tv", title: "TV", tag: 1),
                        SegmentedItem(icon: "mic", title: "Podcasts", tag: 2)
                    ],
                    onSelectionChanged: { index in
                        print("Selected: \(index)")
                    }
                )
                .frame(width: 340)
            }
        }
        .preferredColorScheme(.dark)
    }
}