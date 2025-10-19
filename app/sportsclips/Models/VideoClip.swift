//
//  VideoClip.swift
//  sportsclips
//
//  Video data model for clips from API
//

import Foundation

enum VideoClipError: Error {
    case missingS3Key
    case failedToFetchVideoURL
}

struct VideoClip: Identifiable, Codable {
    let id: String
    let videoURL: String
    let caption: String
    let sport: Sport
    let likes: Int
    let comments: Int
    let shares: Int
    let createdAt: Date?

    // API-related properties
    let s3Key: String?
    let title: String?
    let description: String?

    // The backend game identifier this clip belongs to (YouTube videoId or similar)
    let gameId: String?

    enum Sport: String, CaseIterable, Codable {
        case all = "All"
        case football = "Football"
        case basketball = "Basketball"
        case soccer = "Soccer"
        case baseball = "Baseball"
        case tennis = "Tennis"
        case golf = "Golf"
        case hockey = "Hockey"
        case boxing = "Boxing"
        case mma = "MMA"
        case racing = "Racing"

        var icon: String {
            switch self {
            case .all: return "flame"
            case .football: return "football"
            case .basketball: return "basketball"
            case .soccer: return "soccerball"
            case .baseball: return "baseball"
            case .tennis: return "tennisball"
            case .golf: return "golf"
            case .hockey: return "hockey.puck"
            case .boxing: return "boxing.glove"
            case .mma: return "figure.martial.arts"
            case .racing: return "car.racing"
            }
        }
    }

    // MARK: - API Integration

    /// Convert from API Clip model to VideoClip
    static func fromClip(_ clip: Clip, clipId: String) -> VideoClip {
        // Prefer backend-provided sport mapping; fallback to extracting from text
        let sport = Sport(rawValue: clip.sport) ?? extractSportFromText(clip.title + " " + clip.description)

        return VideoClip(
            id: clipId,
            videoURL: "", // Will be populated when we fetch the presigned URL
            caption: clip.description,
            sport: sport,
            likes: clip.likesCount,
            comments: clip.commentsCount,
            shares: 0, // Not provided by API
            createdAt: Date(timeIntervalSince1970: TimeInterval(clip.createdAt / 1000)),
            s3Key: clip.s3Key,
            title: clip.title,
            description: clip.description,
            gameId: clip.gameId
        )
    }

    /// Extract sport from text content
    private static func extractSportFromText(_ text: String) -> Sport {
        let lowercasedText = text.lowercased()

        if lowercasedText.contains("football") || lowercasedText.contains("nfl") {
            return .football
        } else if lowercasedText.contains("basketball") || lowercasedText.contains("nba") {
            return .basketball
        } else if lowercasedText.contains("soccer") || lowercasedText.contains("futbol") {
            return .soccer
        } else if lowercasedText.contains("baseball") || lowercasedText.contains("mlb") {
            return .baseball
        } else if lowercasedText.contains("tennis") {
            return .tennis
        } else if lowercasedText.contains("golf") {
            return .golf
        } else if lowercasedText.contains("hockey") || lowercasedText.contains("nhl") {
            return .hockey
        } else if lowercasedText.contains("boxing") {
            return .boxing
        } else if lowercasedText.contains("mma") || lowercasedText.contains("ufc") {
            return .mma
        } else if lowercasedText.contains("racing") || lowercasedText.contains("f1") {
            return .racing
        }

        return .all // Default fallback
    }

    /// Fetch presigned download URL for this video
    func fetchVideoURL() async throws -> String {
        guard let s3Key = s3Key else {
            throw VideoClipError.missingS3Key
        }
        return "https://clipstore.liftgate.io/" + s3Key
    }
}

