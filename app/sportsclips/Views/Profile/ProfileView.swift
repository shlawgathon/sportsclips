//
//  ProfileView.swift
//  sportsclips
//
//  Full-page user profile
//

import SwiftUI

struct ProfileView: View {
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var showingLogin = false
    @State private var showingSignup = false
    @State private var username = ""
    @State private var email = ""
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [.black, .purple.opacity(0.2), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if let user = localStorage.userProfile {
                // Logged in view
                ScrollView {
                    VStack(spacing: 0) {
                        // Profile header
                        ProfileHeaderView(user: user)
                        
                        // View history
                        ViewHistoryView()
                    }
                }
            } else {
                // Not logged in view
                VStack(spacing: 30) {
                    Spacer()
                    
                    // App logo/icon
                    Image(systemName: "flame.fill")
                        .font(.system(size: 80, weight: .light))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text("Sports Clips")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Watch the best sports moments")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                    
                    // Login/Signup buttons
                    VStack(spacing: 16) {
                        Button(action: { showingLogin = true }) {
                            Text("Login")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 25)
                                        .stroke(.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: { showingSignup = true }) {
                            Text("Sign Up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(.white, in: RoundedRectangle(cornerRadius: 25))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 100)
                }
            }
        }
        .sheet(isPresented: $showingLogin) {
            LoginView(
                username: $username,
                email: $email,
                isPresented: $showingLogin,
                onLogin: { username, email in
                    localStorage.login(username: username, email: email)
                }
            )
        }
        .sheet(isPresented: $showingSignup) {
            SignupView(
                username: $username,
                email: $email,
                isPresented: $showingSignup,
                onSignup: { username, email in
                    localStorage.signup(username: username, email: email)
                }
            )
        }
    }
}

#Preview {
    ProfileView()
}
