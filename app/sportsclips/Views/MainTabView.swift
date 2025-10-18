//
//  MainTabView.swift
//  sportsclips
//
//  Root tab bar container with liquid glass bottom navigation
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 1 // Start with Highlight tab
    @State private var isMenuVisible = true
    @State private var menuOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    
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

                        DraggableGlassMenu(
                            selectedTab: $selectedTab,
                            isMenuVisible: $isMenuVisible,
                            menuOffset: $menuOffset,
                            dragOffset: $dragOffset,
                            isDragging: $isDragging
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 0)
                    }
        }
        .preferredColorScheme(.dark)
    }
}

struct DraggableGlassMenu: View {
    @Binding var selectedTab: Int
    @Binding var isMenuVisible: Bool
    @Binding var menuOffset: CGFloat
    @Binding var dragOffset: CGFloat
    @Binding var isDragging: Bool
    
    @State private var dragGesture = DragGesture()
    
    var body: some View {
        HStack(spacing: 0) {
            CapsuleTab(
                icon: "video.circle",
                title: "Live",
                isSelected: selectedTab == 0,
                action: { 
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        selectedTab = 0
                    }
                }
            )
            
            CapsuleTab(
                icon: "flame.fill",
                title: "Highlight",
                isSelected: selectedTab == 1,
                action: { 
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        selectedTab = 1
                    }
                }
            )
            
            CapsuleTab(
                icon: "person.circle",
                title: "Profile",
                isSelected: selectedTab == 2,
                action: { 
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        selectedTab = 2
                    }
                }
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            ZStack {
                // Ultra-thin glass effect following Apple HIG
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
        .padding(.horizontal, 16)
        .padding(.bottom, 0) // No bottom padding - stick to bottom
        .offset(y: dragOffset)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isDragging)
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation.height
                    
                    // Add haptic feedback when dragging starts
                    if abs(value.translation.height) > 10 {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }
                }
                .onEnded { value in
                    isDragging = false
                    
                    // Determine if menu should hide based on drag distance and velocity
                    let shouldHide = value.translation.height > 50 || value.predictedEndTranslation.height > 100
                    
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        if shouldHide {
                            isMenuVisible = false
                            menuOffset = 100
                        }
                        dragOffset = 0
                    }
                }
        )
        .onTapGesture(count: 2) {
            // Double tap to toggle menu
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isMenuVisible.toggle()
                menuOffset = isMenuVisible ? 0 : 100
            }
        }
        .opacity(isMenuVisible ? 1 : 0)
        .offset(y: menuOffset)
        .onAppear {
            // Keep menu visible - no auto-hide
            isMenuVisible = true
            menuOffset = 0
        }
    }
}

struct CapsuleTab: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
                    .symbolEffect(.bounce, value: isSelected)
                
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                ZStack {
                    // Selected state - ultra-thin following Apple HIG
                    if isSelected {
                        Capsule()
                            .fill(.thinMaterial)
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                .white.opacity(0.3),
                                                .white.opacity(0.1)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.8
                                    )
                            )
                            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    }
                }
            )
            .contentShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isPressed ? 0.95 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            isPressed = pressing
        }, perform: {})
    }
}

#Preview {
    MainTabView()
}
