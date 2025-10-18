//
//  LiquidGlassModifier.swift
//  sportsclips
//
//  Reusable liquid glass/frosted effect modifier
//

import SwiftUI

struct LiquidGlassModifier: ViewModifier {
    let material: Material
    let cornerRadius: CGFloat
    let shadowRadius: CGFloat
    let glowIntensity: CGFloat
    
    init(
        material: Material = .regularMaterial,
        cornerRadius: CGFloat = 12,
        shadowRadius: CGFloat = 8,
        glowIntensity: CGFloat = 0.1
    ) {
        self.material = material
        self.cornerRadius = cornerRadius
        self.shadowRadius = shadowRadius
        self.glowIntensity = glowIntensity
    }
    
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Outer glow
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.white.opacity(glowIntensity))
                        .blur(radius: shadowRadius * 2)
                        .scaleEffect(1.1)
                    
                    // Main glass background
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(material)
                        .overlay(
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.2),
                                            .white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                }
            )
            .shadow(
                color: .black.opacity(0.15),
                radius: shadowRadius,
                x: 0,
                y: shadowRadius / 2
            )
    }
}

extension View {
    func liquidGlass(
        material: Material = .regularMaterial,
        cornerRadius: CGFloat = 12,
        shadowRadius: CGFloat = 8,
        glowIntensity: CGFloat = 0.1
    ) -> some View {
        modifier(LiquidGlassModifier(
            material: material,
            cornerRadius: cornerRadius,
            shadowRadius: shadowRadius,
            glowIntensity: glowIntensity
        ))
    }
    
    func ultraThinGlass(cornerRadius: CGFloat = 12, glowIntensity: CGFloat = 0.15) -> some View {
        liquidGlass(material: .ultraThinMaterial, cornerRadius: cornerRadius, glowIntensity: glowIntensity)
    }
    
    func thinGlass(cornerRadius: CGFloat = 12, glowIntensity: CGFloat = 0.1) -> some View {
        liquidGlass(material: .thinMaterial, cornerRadius: cornerRadius, glowIntensity: glowIntensity)
    }
    
    func regularGlass(cornerRadius: CGFloat = 12, glowIntensity: CGFloat = 0.08) -> some View {
        liquidGlass(material: .regularMaterial, cornerRadius: cornerRadius, glowIntensity: glowIntensity)
    }
    
    func thickGlass(cornerRadius: CGFloat = 12, glowIntensity: CGFloat = 0.05) -> some View {
        liquidGlass(material: .thickMaterial, cornerRadius: cornerRadius, glowIntensity: glowIntensity)
    }
}
