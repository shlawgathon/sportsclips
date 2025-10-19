//
//  ProfileView.swift
//  sportsclips
//
//  User profile placeholder
//

import SwiftUI
import PhotosUI
import UIKit

struct ProfileView: View {
    @StateObject private var localStorage = LocalStorageService.shared
    @State private var showingLogoutConfirmation = false
    @State private var isEditingName = false
    @State private var tempName: String = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var isUpdatingProfile = false

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [.black, .purple.opacity(0.2), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 30) {
                Spacer()

                // Profile picture + picker
                if let user = localStorage.userProfile {
                    VStack(spacing: 16) {
                        ZStack(alignment: .bottomTrailing) {
                            // Avatar circle with either image or placeholder
                            if let base64 = user.profilePictureBase64,
                               let data = Data(base64Encoded: base64),
                               let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 3))
                            } else {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(.white.opacity(0.6))
                                    )
                                    .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 3))
                            }

                            PhotosPicker(selection: $selectedItem, matching: .images) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.blue, in: Circle())
                                    .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                            }
                            .offset(x: 6, y: 6)
                            .disabled(isUpdatingProfile)
                        }

                        VStack(spacing: 8) {
                            if isEditingName {
                                HStack(spacing: 8) {
                                    TextField("Display name", text: $tempName)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(8)
                                        .foregroundColor(.white)

                                    Button(action: saveName) {
                                        if isUpdatingProfile { ProgressView().tint(.white) } else { Text("Save").bold() }
                                    }
                                    .disabled(isUpdatingProfile || tempName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                    Button("Cancel") { isEditingName = false }
                                        .foregroundColor(.gray)
                                }
                            } else {
                                Text(user.username)
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundColor(.white)
                                    .onTapGesture {
                                        tempName = user.username
                                        isEditingName = true
                                    }
                                    .overlay(
                                        Text("Tap to edit")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.white.opacity(0.5))
                                            .offset(y: 22)
                                    , alignment: .bottom)
                            }

                            Text(user.email)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                } else {
                    Text("Profile")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }

                Text("Profile features coming soon...")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Spacer()

                // Logout button
                Button(action: {
                    showingLogoutConfirmation = true
                }) {
                    Text("Logout")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.red.opacity(0.3), in: RoundedRectangle(cornerRadius: 25))
                        .overlay(
                            RoundedRectangle(cornerRadius: 25)
                                .stroke(.red.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 40)
                .padding(.bottom, 100)
            }
        }
        .confirmationDialog("Are you sure you want to logout?", isPresented: $showingLogoutConfirmation) {
            Button("Logout", role: .destructive) {
                Task {
                    await handleLogout()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: selectedItem) { newItem in
            guard let newItem else { return }
            Task { await handlePickedItem(newItem) }
        }
        .onAppear {
            Task { await localStorage.refreshProfileFromServer() }
        }
    }

    private func saveName() {
        let name = tempName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isUpdatingProfile = true
        Task {
            do {
                let resp = try await APIClient.shared.updateUserProfile(displayName: name, profilePictureBase64: nil)
                await MainActor.run {
                    // Store displayName locally in the username field for display purposes
                    localStorage.updateUsername(resp.user.displayName ?? name)
                    isEditingName = false
                    isUpdatingProfile = false
                }
            } catch {
                await MainActor.run { isUpdatingProfile = false }
                print("Failed to update username: \(error)")
            }
        }
    }

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        isUpdatingProfile = true
        do {
            if let data = try await item.loadTransferable(type: Data.self) ?? itemLoadedDataFallback(item) {
                let base64 = data.base64EncodedString()
                let resp = try await APIClient.shared.updateUserProfile(profilePictureBase64: base64)
                await MainActor.run {
                    localStorage.updateProfilePicture(resp.user.profilePictureBase64)
                    isUpdatingProfile = false
                }
            } else {
                await MainActor.run { isUpdatingProfile = false }
            }
        } catch {
            await MainActor.run { isUpdatingProfile = false }
            print("Failed to upload profile image: \(error)")
        }
    }

    private func itemLoadedDataFallback(_ item: PhotosPickerItem) -> Data? {
        // Fallback mechanism if .loadTransferable fails; not always needed
        return nil
    }

    // MARK: - Logout Handler
    private func handleLogout() async {
        // Attempt to invalidate session on server
        if let sessionToken = localStorage.userProfile?.sessionToken {
            try? await AuthService.shared.logout(sessionToken: sessionToken)
        }

        // Clear local session
        localStorage.logout()
    }
}

#Preview {
    ProfileView()
}
