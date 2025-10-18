//
//  AuthService.swift
//  sportsclips
//
//  Authentication service for login/signup API calls
//

import Foundation

struct LoginRequest: Codable {
    let username: String
    let email: String
    let password: String
}

struct SignupRequest: Codable {
    let username: String
    let email: String
    let password: String
}

struct AuthResponse: Codable {
    let sessionToken: String
    let userId: String
    let username: String
    let email: String
}

enum AuthError: Error {
    case invalidCredentials
    case networkError
    case invalidResponse
    case serverError(String)
}

@MainActor
class AuthService {
    static let shared = AuthService()

    private init() {}

    // MARK: - Login
    func login(username: String, email: String, password: String) async throws -> AuthResponse {
        // Integrate with middleware API via APIClient
        do {
            let client = APIClient.shared
            let resp = try await client.login(username: username, password: password)
            let userId = resp.userId ?? resp.id ?? ""
            // Session is cookie-based; we persist a synthetic token derived from user id for local storage purposes
            return AuthResponse(
                sessionToken: userId,
                userId: userId,
                username: username,
                email: email
            )
        } catch {
            throw AuthError.invalidCredentials
        }
    }

    // MARK: - Signup
    func signup(username: String, email: String, password: String) async throws -> AuthResponse {
        do {
            let client = APIClient.shared
            _ = try await client.register(username: username, password: password, profilePictureBase64: nil)
            // Auto-login after register
            let loginResp = try await client.login(username: username, password: password)
            let userId = loginResp.userId ?? loginResp.id ?? ""
            return AuthResponse(
                sessionToken: userId,
                userId: userId,
                username: username,
                email: email
            )
        } catch {
            throw AuthError.serverError("Signup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Logout
    func logout(sessionToken: String) async throws {
        let client = APIClient.shared
        try await client.logout()
    }
}

