//
//  LiveComment.swift
//  sportsclips
//
//  Live comment model for real-time chat during live streams
//

import Foundation

struct LiveComment: Identifiable, Codable {
    let id: String
    let username: String
    let message: String
    let timestamp: Date
    
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
                username: item.0,
                message: item.1,
                timestamp: Date().addingTimeInterval(TimeInterval(-index * 5))
            )
        }
    }
}

