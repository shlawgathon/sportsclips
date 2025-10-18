//
//  AuthenticationView.swift
//  sportsclips
//
//  Initial authentication screen shown on first app launch
//

import SwiftUI

struct AuthenticationView: View {
    @State private var showingLogin = false
    @State private var showingSignup = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [.black, .purple.opacity(0.3), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    Spacer()
                    
                    // 3D Rotating sports logo
                    Rotating3DLogo()
                    
                    Text("Sports Clips")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Watch the best sports moments")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Spacer()
                    
                    // Login/Signup buttons
                    VStack(spacing: 16) {
                        NavigationLink(destination: LoginView()) {
                            Text("Login")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 25))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 25)
                                        .stroke(.white.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        NavigationLink(destination: SignupView()) {
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
                    .padding(.bottom, 60)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    AuthenticationView()
}

