//
//  VideoClip.swift
//  sportsclips
//
//  Video data model for clips from API
//

import Foundation

struct VideoClip: Identifiable, Codable {
    let id: String
    let videoURL: String
    let caption: String
    let sport: Sport
    let likes: Int
    let comments: Int
    let shares: Int
    let createdAt: Date?
    
    enum Sport: String, CaseIterable, Codable {
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
        case all = "All"
        
        var icon: String {
            switch self {
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
            case .all: return "flame"
            }
        }
    }
    
    // For preview/testing purposes
    static var mock: VideoClip {
        VideoClip(
            id: UUID().uuidString,
            videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
            caption: "Amazing sports moment! 🔥",
            sport: .football,
            likes: 12500,
            comments: 432,
            shares: 89,
            createdAt: Date()
        )
    }
    
    static var mockArray: [VideoClip] {
        let sports: [Sport] = [.football, .basketball, .soccer, .baseball, .tennis, .golf, .hockey, .boxing, .mma, .racing]
        return (0..<10).map { index in
            VideoClip(
                id: UUID().uuidString,
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                caption: "Epic \(sports[index % sports.count].rawValue.lowercased()) clip #\(index + 1) with amazing action! Watch till the end 🏆",
                sport: sports[index % sports.count],
                likes: Int.random(in: 1000...50000),
                comments: Int.random(in: 50...1000),
                shares: Int.random(in: 10...500),
                createdAt: Date()
            )
        }
    }
}

