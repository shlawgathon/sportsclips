//
//  LoginView.swift
//  sportsclips
//
//  Login form with liquid glass styling
//

import SwiftUI

struct LoginView: View {
    @StateObject private var localStorage = LocalStorageService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
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
                
                    // Logo
                    AnimatedSportsLogo()
                        .scaleEffect(0.75)
                
                Text("Welcome Back")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                
                    // Login form
                    VStack(spacing: 20) {
                        // Username field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Username")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            TextField("Enter username", text: $username)
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
                        
                        SecureField("Enter password", text: $password)
                            .textFieldStyle(GlassTextFieldStyle())
                    }
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red.opacity(0.9))
                            .padding(.horizontal, 16)
                    }
                    
                    // Login button
                    Button(action: {
                        Task {
                            await handleLogin()
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("Login")
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
                        .disabled(isLoading || username.isEmpty || password.isEmpty) // Removed email check
                }
                .padding(.horizontal, 40)
                
                Spacer()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
    
    // MARK: - Login Handler
    private func handleLogin() async {
        errorMessage = nil
        isLoading = true
        
        do {
            // TODO: Replace with actual API call when documentation is provided
            let authResponse = try await AuthService.shared.login(
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
            errorMessage = "Login failed. Please check your credentials."
        }
    }
}

struct GlassTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.2), lineWidth: 1)
            )
            .foregroundColor(.white)
    }
}

#Preview {
    LoginView()
}
