//
//  SignupView.swift
//  sportsclips
//
//  Signup form with liquid glass styling
//

import SwiftUI

struct SignupView: View {
    @Binding var username: String
    @Binding var email: String
    @Binding var isPresented: Bool
    let onSignup: (String, String) -> Void
    
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
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
                    Image(systemName: "flame.fill")
                        .font(.system(size: 60, weight: .light))
                        .foregroundColor(.white.opacity(0.8))
                    
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
                        }
                        
                        // Email field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.8))
                            
                            TextField("Enter email", text: $email)
                                .textFieldStyle(GlassTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .autocapitalization(.none)
                        }
                        
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
                        
                        // Signup button
                        Button(action: {
                            isLoading = true
                            // Simulate API call
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                onSignup(username, email)
                                isPresented = false
                                isLoading = false
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
                        .disabled(isLoading || username.isEmpty || email.isEmpty || password.isEmpty || password != confirmPassword)
                    }
                    .padding(.horizontal, 40)
                    
                    Spacer()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    SignupView(
        username: .constant(""),
        email: .constant(""),
        isPresented: .constant(true),
        onSignup: { _, _ in }
    )
}
