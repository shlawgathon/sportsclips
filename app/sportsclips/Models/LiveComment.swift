//
//  LiveComment.swift
//  sportsclips
//
//  Live comment model for real-time chat during live streams
//

import Foundation

struct LiveComment: Identifiable, Codable {
    let id: String
    let userId: String
    let username: String
    let message: String
    let timestamp: Date
    let isOwnComment: Bool
    
    // Initializer for creating new comments
    init(id: String, userId: String, username: String, message: String, timestamp: Date, isOwnComment: Bool) {
        self.id = id
        self.userId = userId
        self.username = username
        self.message = message
        self.timestamp = timestamp
        self.isOwnComment = isOwnComment
    }
    
    static var mockComments: [LiveComment] {
        let comments = [
            ("SportsNut42", "🔥🔥🔥 AMAZING!"),
            ("HoopsDreams", "No way!!!"),
            ("GameTime99", "Best play I've seen all season"),
            ("ChampionFan", "LET'S GOOO! 🏆"),
            ("ProWatcher", "Incredible skill"),
            ("TeamSpirit", "This is insane 😱"),
            ("MVPTracker", "Hall of Fame moment right here"),
            ("SportsLover", "I can't believe what I just saw"),
            ("BigFan2024", "GOAT status confirmed 🐐"),
            ("LiveWatcher", "Replay this 100 times!"),
            ("ArenaKing", "The crowd is going CRAZY!!!"),
            ("PlayMaker88", "That's how you do it 💪"),
            ("FastBreak", "Unbelievable athleticism"),
            ("ClutchMoments", "This is why we watch live"),
            ("SuperFan", "Best game ever! 🎉")
        ]
        
        return comments.enumerated().map { index, item in
            LiveComment(
                id: UUID().uuidString,
                userId: UUID().uuidString,
                username: item.0,
                message: item.1,
                timestamp: Date().addingTimeInterval(TimeInterval(-index * 5)),
                isOwnComment: false
            )
        }
    }
}

