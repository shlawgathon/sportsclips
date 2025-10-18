//
//  LoginView.swift
//  sportsclips
//
//  Login form with liquid glass styling
//

import SwiftUI

struct LoginView: View {
    @Binding var username: String
    @Binding var email: String
    @Binding var isPresented: Bool
    let onLogin: (String, String) -> Void
    
    @State private var password = ""
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
                            
                            SecureField("Enter password", text: $password)
                                .textFieldStyle(GlassTextFieldStyle())
                        }
                        
                        // Login button
                        Button(action: {
                            isLoading = true
                            // Simulate API call
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                onLogin(username, email)
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
                        .disabled(isLoading || username.isEmpty || email.isEmpty || password.isEmpty)
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
    LoginView(
        username: .constant(""),
        email: .constant(""),
        isPresented: .constant(true),
        onLogin: { _, _ in }
    )
}
