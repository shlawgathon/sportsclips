//
//  ProfileView.swift
//  sportsclips
//
//  User profile with tabbed history views
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
    @State private var selectedTabIndex = 0

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [.black, .purple.opacity(0.2), .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top section with profile info and logout button
                VStack(spacing: 20) {
                    // Logout button in top right
                    HStack {
                        Spacer()
                        Button(action: {
                            showingLogoutConfirmation = true
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                
                                Text("Logout")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.red.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(.red.opacity(0.4), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)

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
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                        .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 2))
                                } else {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 32))
                                                .foregroundColor(.white.opacity(0.6))
                                        )
                                        .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 2))
                                }

                                PhotosPicker(selection: $selectedItem, matching: .images) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(6)
                                        .background(Color.blue, in: Circle())
                                        .overlay(Circle().stroke(.white.opacity(0.4), lineWidth: 1))
                                }
                                .offset(x: 4, y: 4)
                                .disabled(isUpdatingProfile)
                            }

                            VStack(spacing: 8) {
                                if isEditingName {
                                    HStack(spacing: 8) {
                                        ZStack(alignment: .trailing) {
                                            TextField("Display name", text: $tempName)
                                                .textFieldStyle(PlainTextFieldStyle())
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .padding(.trailing, 40) // Make room for character count
                                                .background(Color.white.opacity(0.1))
                                                .cornerRadius(8)
                                                .foregroundColor(.white)
                                                .onChange(of: tempName) { newValue in
                                                    // Limit to 30 characters
                                                    if newValue.count > 30 {
                                                        tempName = String(newValue.prefix(30))
                                                    }
                                                }
                                            
                                            // Character count inside the text field
                                            Text("\(tempName.count)/30")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundColor(.white.opacity(0.5))
                                                .padding(.trailing, 8)
                                        }

                                        Button(action: saveName) {
                                            if isUpdatingProfile { 
                                                ProgressView().tint(.white) 
                                            } else { 
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundColor(.green)
                                            }
                                        }
                                        .disabled(isUpdatingProfile || tempName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                                        Button(action: { isEditingName = false }) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 16, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .padding(.horizontal, 40)
                                } else {
                                    HStack(spacing: 8) {
                                        Text(user.username)
                                            .font(.system(size: 24, weight: .bold))
                                            .foregroundColor(.white)
                                        
                                        Button(action: {
                                            tempName = user.username
                                            isEditingName = true
                                        }) {
                                            Image(systemName: "pencil")
                                                .font(.system(size: 16, weight: .medium))
                                                .foregroundColor(.white.opacity(0.7))
                                        }
                                    }
                                    .padding(.horizontal, 40)
                                }

                                Text(user.email)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                    } else {
                        Text("Profile")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .padding(.bottom, 20)

                // Segmented control for tabs
                LiquidGlassSegmentedControl(
                    selectedIndex: $selectedTabIndex,
                    items: [
                        SegmentedItem(icon: "heart.fill", title: "Likes", tag: 0),
                        SegmentedItem(icon: "message.fill", title: "Comments", tag: 1),
                        SegmentedItem(icon: "eye.fill", title: "Views", tag: 2)
                    ],
                    onSelectionChanged: { index in
                        selectedTabIndex = index
                    }
                )
                .frame(height: 56)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                // Tab content
                TabView(selection: $selectedTabIndex) {
                    LikeHistoryView()
                        .tag(0)
                    
                    CommentHistoryView()
                        .tag(1)
                    
                    ViewHistoryView()
                        .tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
        }
        .confirmationDialog("Confirm Logout", isPresented: $showingLogoutConfirmation) {
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
