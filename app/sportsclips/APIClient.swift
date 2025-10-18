import Foundation

struct LiveVideo: Codable {
    let title: String
    let description: String
    let streamUrl: String
    let isLive: Bool
    let liveChatId: String?
    let createdAt: Int64
}

struct Clip: Codable {
    let s3Key: String
    let title: String
    let description: String
    let likesCount: Int
    let commentsCount: Int
    let embedding: [Double]?
    let createdAt: Int64
}

struct CommentItem: Codable {
    let id: String
    let comment: Comment
}

struct Comment: Codable {
    let clipId: String
    let userId: String
    let text: String
    let createdAt: Int64
}

struct LiveListItem: Codable {
    let id: String
    let live: LiveVideo
}

struct RecommendationItem: Codable {
    let id: String
    let score: Double
    let clip: Clip
}

final class APIClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        self.session = URLSession(configuration: config)
    }

    // MARK: - Helpers

    private func request<T: Decodable>(_ path: String, method: String = "GET", body: Encodable? = nil, response: T.Type) async throws -> T {
        var url = baseURL
        url.append(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "API", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"])
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func requestNoBody(_ path: String, method: String = "POST") async throws {
        var url = baseURL
        url.append(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var req = URLRequest(url: url)
        req.httpMethod = method
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func requestWithBodyNoResponse(_ path: String, method: String = "POST", body: Encodable) async throws {
        var url = baseURL
        url.append(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Auth

    struct RegisterRequest: Encodable {
        let username: String
        let password: String
        let profilePictureBase64: String?
    }
    struct LoginRequest: Encodable {
        let username: String
        let password: String
    }
    struct IdResponse: Decodable {
        let id: String?
        let userId: String?
    }

    @discardableResult
    func register(username: String, password: String, profilePictureBase64: String? = nil) async throws -> IdResponse {
        try await request("/auth/register", method: "POST", body: RegisterRequest(username: username, password: password, profilePictureBase64: profilePictureBase64), response: IdResponse.self)
    }

    @discardableResult
    func login(username: String, password: String) async throws -> IdResponse {
        try await request("/auth/login", method: "POST", body: LoginRequest(username: username, password: password), response: IdResponse.self)
    }

    func logout() async throws {
        try await requestNoBody("/auth/logout", method: "POST")
    }

    // MARK: - Live

    struct CreateLiveRequest: Encodable {
        let title: String
        let description: String
        let streamUrl: String
        let isLive: Bool
    }

    func listLives() async throws -> [LiveListItem] {
        try await request("/live", response: [LiveListItem].self)
    }

    func getLive(id: String) async throws -> LiveVideo {
        try await request("/live/\(id)", response: LiveVideo.self)
    }

    @discardableResult
    func createLive(title: String, description: String, streamUrl: String, isLive: Bool = true) async throws -> IdResponse {
        try await request("/live", method: "POST", body: CreateLiveRequest(title: title, description: description, streamUrl: streamUrl, isLive: isLive), response: IdResponse.self)
    }

    // MARK: - Clips

    struct PresignUploadRequest: Encodable {
        let key: String
        let contentType: String?
    }
    struct PresignResponse: Decodable {
        let url: String
        let key: String?
    }
    struct CreateClipRequest: Encodable {
        let s3Key: String
        let title: String
        let description: String
    }

    func presignUpload(key: String, contentType: String? = nil) async throws -> PresignResponse {
        try await request("/clips/presign-upload", method: "POST", body: PresignUploadRequest(key: key, contentType: contentType), response: PresignResponse.self)
    }

    struct UrlResponse: Decodable { let url: String }

    func presignDownload(id: String) async throws -> UrlResponse {
        try await request("/clips/presign-download/\(id)", response: UrlResponse.self)
    }

    @discardableResult
    func createClip(s3Key: String, title: String, description: String) async throws -> IdResponse {
        try await request("/clips", method: "POST", body: CreateClipRequest(s3Key: s3Key, title: title, description: description), response: IdResponse.self)
    }

    func getClip(id: String) async throws -> Clip {
        try await request("/clips/\(id)", response: Clip.self)
    }

    func likeClip(id: String) async throws {
        try await requestNoBody("/clips/\(id)/like", method: "POST")
    }

    struct CommentRequest: Encodable { let text: String }

    func postComment(clipId: String, text: String) async throws {
        try await requestWithBodyNoResponse("/clips/\(clipId)/comments", method: "POST", body: CommentRequest(text: text))
    }

    func listComments(clipId: String) async throws -> [CommentItem] {
        try await request("/clips/\(clipId)/comments", response: [CommentItem].self)
    }

    func recommendations(clipId: String) async throws -> [RecommendationItem] {
        try await request("/clips/\(clipId)/recommendations", response: [RecommendationItem].self)
    }
}

// Helper to encode unknown Encodable at runtime
private struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ encodable: Encodable) { self._encode = encodable.encode }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

/*
Usage example (SwiftUI):

let api = APIClient(baseURL: URL(string: "http://localhost:8080")!)
Task {
    _ = try await api.register(username: "alice", password: "secret")
    _ = try await api.login(username: "alice", password: "secret")
    let _ = try await api.createLive(title: "Match", description: "Quarter Finals", streamUrl: "https://example/stream.m3u8")
    let items = try await api.listLives()
    print(items)
}
*/
