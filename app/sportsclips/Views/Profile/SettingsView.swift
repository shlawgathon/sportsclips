//
//  SettingsView.swift
//  sportsclips
//
//  Settings view with category memory preferences
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var localStorage = LocalStorageService.shared
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    colors: [.black, .black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Settings")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("Customize your app experience")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 20)
                    
                    // Settings Options
                    VStack(spacing: 16) {
                        // Category Memory Settings
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Category Memory")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white)
                            
                            // Highlights Category Memory
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Remember Highlights Category")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Text("Keep your last selected sport when returning to highlights")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $localStorage.rememberHighlightsCategory)
                                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )
                            
                            // Live Category Memory
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Remember Live Category")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white)
                                    
                                    Text("Keep your last selected sport when returning to live")
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                                
                                Spacer()
                                
                                Toggle("", isOn: $localStorage.rememberLiveCategory)
                                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }
            }
            .navigationBarHidden(true)
            .overlay(
                // Close button
                VStack {
                    HStack {
                        Spacer()
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.trailing, 20)
                        .padding(.top, 10)
                    }
                    Spacer()
                }
            )
        }
    }
}

#Preview {
    SettingsView()
}
