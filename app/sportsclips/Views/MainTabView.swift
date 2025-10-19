//
//  MainTabView.swift
//  sportsclips
//
//  Root tab bar container with liquid glass bottom navigation
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0 // Start with All tab
    
    var body: some View {
        ZStack {
            // Main content
            TabView(selection: $selectedTab) {
                LiveView()
                    .tag(0)
                
                VideoFeedView()
                    .tag(1)
                
                ProfileView()
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            
                    // Draggable glass bubble menu
                    VStack {
                        Spacer()

                        LiquidGlassSegmentedControl(
                            selectedIndex: $selectedTab,
                            items: [
                                SegmentedItem(icon: "video.circle", title: "Live", tag: 0),
                                SegmentedItem(icon: "flame.fill", title: "Highlight", tag: 1),
                                SegmentedItem(icon: "person.circle", title: "Profile", tag: 2)
                            ],
                            onSelectionChanged: { index in
                                // Animate the tab selection
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                    selectedTab = index
                                }
                                print("Tab selected: \(index)")
                            }
                        )
                        .padding(.horizontal, 20) // 10px shorter on each side (was 16px default)
                        .padding(.bottom, -20) // Move down 30px
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 0)
                    }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    MainTabView()
}
