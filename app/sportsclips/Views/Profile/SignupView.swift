//
//  SignupView.swift
//  sportsclips
//
//  Signup form with liquid glass styling
//

import SwiftUI

struct SignupView: View {
    @StateObject private var localStorage = LocalStorageService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
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
                
                // Logo - 3D Rotating Carousel
                Rotating3DLogo()
                    .scaleEffect(0.75)
                
                Text("Join Sports Clips")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                    // Signup form
                    VStack(spacing: 20) {
                        // Username field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            TextField("Choose username", text: $username)
                                .textFieldStyle(GlassTextFieldStyle())
                                .textInputAutocapitalization(.never)
                        }
                        
                        // Email field - COMMENTED OUT FOR NOW
                        /*
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            TextField("Enter email", text: $email)
                                .textFieldStyle(GlassTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                        }
                        */
                    
                    // Password field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        SecureField("Create password", text: $password)
                            .textFieldStyle(GlassTextFieldStyle())
                    }
                    
                    // Confirm password field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Confirm Password")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))
                        
                        SecureField("Confirm password", text: $confirmPassword)
                            .textFieldStyle(GlassTextFieldStyle())
                    }
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red.opacity(0.9))
                            .padding(.horizontal, 16)
                    }
                    
                    // Signup button
                    Button(action: {
                        Task {
                            await handleSignup()
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Sign Up")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(.white.opacity(0.3), lineWidth: 1)
                        )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isLoading || username.isEmpty || password.isEmpty || password != confirmPassword) // Removed email check
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Signup Handler
    private func handleSignup() async {
        errorMessage = nil
        
        // Validate password match
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match"
            return
        }
        
        isLoading = true
        
        do {
            // TODO: Replace with actual API call when documentation is provided
            let authResponse = try await AuthService.shared.signup(
                username: username,
                email: "", // Email commented out for now
                password: password
            )
            
            // Save user session
            localStorage.saveUserSession(
                userId: authResponse.userId,
                username: authResponse.username,
                email: authResponse.email,
                sessionToken: authResponse.sessionToken
            )
            
            isLoading = false
        } catch {
            isLoading = false
            errorMessage = "Signup failed. Please try again."
        }
    }
}

#Preview {
    SignupView()
}
