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
    let gameId: String
    let sport: String
    let likesCount: Int
    let commentsCount: Int
    let embedding: [Double]?
    let createdAt: Int64
}

struct CommentItem: Codable {
    let id: String
    let postedByUsername: String
    let postedByDisplayName: String?
    let postedByProfilePictureBase64: String?
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

// MARK: - History DTOs
struct ClipDTO: Codable {
    let id: String
    let clip: Clip
}

struct ViewHistoryItem: Codable {
    let id: String
    let viewedAt: Int64
    let clip: ClipDTO
}

struct LikeHistoryItem: Codable {
    let id: String
    let likedAt: Int64
    let clip: ClipDTO
}

struct CommentHistoryItem: Codable {
    let id: String
    let text: String
    let commentedAt: Int64
    let clip: ClipDTO
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

    // MARK: - User Profile
    struct APIUser: Codable {
        let username: String
        let profilePictureBase64: String?
        let displayName: String?
    }
    struct MeResponse: Codable {
        let id: String
        let user: APIUser
    }
    struct UpdateProfileRequest: Encodable {
        let displayName: String?
        let profilePictureBase64: String?
    }
    func getMe() async throws -> MeResponse {
        try await request("/user/me", response: MeResponse.self)
    }
    // {"detail":"The request body is not valid JSON, or some arguments were not specified properly. In particular, Error for argument '79': JSON decode error"}
    func updateUserProfile(displayName: String? = nil, profilePictureBase64: String? = nil) async throws -> MeResponse {
        try await request("/user/profile", method: "POST", body: UpdateProfileRequest(displayName: displayName, profilePictureBase64: profilePictureBase64), response: MeResponse.self)
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

    func listLiveVideos() async throws -> [LiveListItem] {
        try await request("/live-videos", response: [LiveListItem].self)
    }

    func getLive(id: String) async throws -> LiveVideo {
        try await request("/live/\(id)", response: LiveVideo.self)
    }

    @discardableResult
    func createLive(title: String, description: String, streamUrl: String, isLive: Bool = true) async throws -> IdResponse {
        try await request("/live", method: "POST", body: CreateLiveRequest(title: title, description: description, streamUrl: streamUrl, isLive: isLive), response: IdResponse.self)
    }

    // MARK: - Live Polling (Comments & Viewers)
    struct LiveCommentDTO: Codable {
        let id: String
        let clipId: String
        let userId: String
        let username: String
        let message: String
        let timestampEpochSec: Int64
    }
    struct LiveCommentsResponse: Codable { let comments: [LiveCommentDTO] }
    struct PostLiveCommentRequest: Encodable {
        let userId: String
        let username: String
        let message: String
    }
    struct ViewerHeartbeatRequest: Encodable { let viewerId: String }
    struct ViewerInfoResponse: Codable {
        let clipId: String
        let viewers: Int
    }

    func liveFetchComments(clipId: String, limit: Int = 10, afterTs: Int64? = nil) async throws -> [LiveCommentDTO] {
        var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let afterTs = afterTs { query.append(URLQueryItem(name: "afterTs", value: String(afterTs))) }
        let resp: LiveCommentsResponse = try await request("/live/\(clipId)/comments", queryItems: query, response: LiveCommentsResponse.self)
        return resp.comments
    }

    func livePostComment(clipId: String, userId: String, username: String, message: String) async throws -> LiveCommentDTO {
        try await request("/live/\(clipId)/comments", method: "POST", body: PostLiveCommentRequest(userId: userId, username: username, message: message), response: LiveCommentDTO.self)
    }

    func liveViewerInfo(clipId: String) async throws -> ViewerInfoResponse {
        try await request("/live/\(clipId)/viewers", response: ViewerInfoResponse.self)
    }

    func liveHeartbeat(clipId: String, viewerId: String) async throws -> ViewerInfoResponse {
        try await request("/live/\(clipId)/viewers/heartbeat", method: "POST", body: ViewerHeartbeatRequest(viewerId: viewerId), response: ViewerInfoResponse.self)
    }

    // MARK: - Helpers (Query)
    private func request<T: Decodable>(_ path: String, queryItems: [URLQueryItem], method: String = "GET", body: Encodable? = nil, response: T.Type) async throws -> T {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = baseURL.appendingPathComponent(trimmed).path.replacingOccurrences(of: baseURL.path, with: "")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw URLError(.badURL) }
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

    // MARK: - Domain Models
    enum APISport: String, Codable {
        case All, Football, Basketball, Soccer, Baseball, Tennis, Golf, Hockey, Boxing, MMA, Racing
    }

    struct LiveGame: Codable {
        let gameId: String
        let name: String
        let sport: APISport
        let createdAt: Int64
    }

    struct ClipListItem: Codable {
        let id: String
        let clip: Clip
    }

    struct GameListItem: Codable {
        let id: String
        let game: LiveGame
    }

    struct UrlResponse: Decodable { let url: String }

    enum ProcessingStatus: String, Codable { case Queued, Processing, Completed, Error }

    struct TrackedVideo: Codable {
        let youtubeVideoId: String
        let sourceUrl: String
        let sport: APISport
        let gameName: String
        let status: ProcessingStatus
        let lastProcessedAt: Int64?
        let createdAt: Int64
    }

    struct CatalogItem: Codable {
        let id: String
        let tracked: TrackedVideo
    }

    struct IngestResponse: Codable {
        let videoId: String
        let createdClips: Int
    }

    // MARK: - Feed & Views

    struct FeedItem: Codable {
        let id: String
        let clip: Clip
        let viewed: Bool
    }
    struct FeedResponse: Codable {
        let items: [FeedItem]
        let nextCursor: Int64?
    }

    func fetchFeed(limit: Int = 10, cursor: Int64? = nil, sport: APISport? = nil) async throws -> FeedResponse {
        var query: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor = cursor { query.append(URLQueryItem(name: "cursor", value: String(cursor))) }
        if let sport = sport { query.append(URLQueryItem(name: "sport", value: sport.rawValue)) }
        return try await request("/feed", queryItems: query, response: FeedResponse.self)
    }

    func markViewed(clipId: String) async throws {
        try await requestNoBody("/clips/\(clipId)/view", method: "POST")
    }

    // MARK: - Clips

    func listClips() async throws -> [ClipListItem] {
        try await request("/clips", response: [ClipListItem].self)
    }

    func listClipsByGame(gameId: String) async throws -> [ClipListItem] {
        try await request("/clips/by-game/\(gameId)", response: [ClipListItem].self)
    }

    func listClipsBySport(_ sport: APISport) async throws -> [ClipListItem] {
        try await request("/clips/by-sport/\(sport.rawValue)", response: [ClipListItem].self)
    }

    func presignDownload(id: String) async throws -> UrlResponse {
        try await request("/clips/presign-download/\(id)", response: UrlResponse.self)
    }

    func getClip(id: String) async throws -> Clip {
        try await request("/clips/\(id)", response: Clip.self)
    }

    func likeClip(id: String) async throws {
        try await requestNoBody("/clips/\(id)/like", method: "POST")
    }

    func unlikeClip(id: String) async throws {
        try await requestNoBody("/clips/\(id)/like", method: "DELETE")
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

    // MARK: - User History
    func viewHistory(userId: String) async throws -> [ViewHistoryItem] {
        try await request("/users/\(userId)/history/views", response: [ViewHistoryItem].self)
    }

    func likeHistory(userId: String) async throws -> [LikeHistoryItem] {
        try await request("/users/\(userId)/history/likes", response: [LikeHistoryItem].self)
    }

    func commentHistory(userId: String) async throws -> [CommentHistoryItem] {
        try await request("/users/\(userId)/history/comments", response: [CommentHistoryItem].self)
    }

    // MARK: - Games

    struct CreateGameRequest: Encodable {
        let gameId: String
        let name: String
        let sport: APISport
    }

    @discardableResult
    func createGame(gameId: String, name: String, sport: APISport) async throws -> IdResponse {
        try await request("/games", method: "POST", body: CreateGameRequest(gameId: gameId, name: name, sport: sport), response: IdResponse.self)
    }

    func listGames() async throws -> [GameListItem] {
        try await request("/games", response: [GameListItem].self)
    }

    func getGame(gameId: String) async throws -> LiveGame {
        try await request("/games/\(gameId)", response: LiveGame.self)
    }

    // MARK: - Catalog

    func catalog() async throws -> [CatalogItem] {
        try await request("/catalog", response: [CatalogItem].self)
    }
}

// MARK: - Shared Instance
extension APIClient {
    static let shared = APIClient(baseURL: URL(string: "https://middleware.liftgate.io")!)

    func baseWebSocketURL() -> URL {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        if comps.scheme == "https" { comps.scheme = "wss" }
        else if comps.scheme == "http" { comps.scheme = "ws" }
        return comps.url ?? baseURL
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
