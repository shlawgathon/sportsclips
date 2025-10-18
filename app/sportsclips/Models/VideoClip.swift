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
    
    // For preview/testing purposes
    static var mock: VideoClip {
        VideoClip(
            id: UUID().uuidString,
            videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
            caption: "Incredible touchdown pass in the final seconds of the championship game! The quarterback showed amazing composure under pressure, delivering a perfect spiral to the wide receiver who made an unbelievable catch in the end zone. This moment will go down in history as one of the greatest plays ever witnessed in football. The crowd went absolutely wild! 🏈🔥",
            sport: .football,
            likes: 12500,
            comments: 432,
            shares: 89,
            createdAt: Date()
        )
    }
    
    static var mockArray: [VideoClip] {
        let sports: [Sport] = [.football, .basketball, .soccer, .baseball, .tennis, .golf, .hockey, .boxing, .mma, .racing]
        let longCaptions = [
            "Incredible touchdown pass in the final seconds of the championship game! The quarterback showed amazing composure under pressure, delivering a perfect spiral to the wide receiver who made an unbelievable catch in the end zone. This moment will go down in history as one of the greatest plays ever witnessed in football. The crowd went absolutely wild! 🏈🔥",
            "Slam dunk contest winner with the most creative dunk ever seen! The player jumped over a car, did a 360-degree spin, and threw it down with authority. The judges were speechless and the entire arena erupted in cheers. This will be remembered as the greatest dunk in basketball history! 🏀💥",
            "World Cup final goal that changed everything! In the 89th minute, with the score tied, the striker received a perfect cross and executed a bicycle kick that found the top corner of the net. The goalkeeper had no chance as the ball sailed past him into the goal. The entire stadium went silent for a moment before exploding in celebration! ⚽🎉",
            "Perfect game in the World Series! The pitcher threw 27 consecutive strikeouts, something that has never been done before in the history of baseball. Every single batter that stepped up to the plate was sent back to the dugout. The crowd was on their feet for the entire game, witnessing history in the making! ⚾👑",
            "Championship point in the Wimbledon final! After a grueling 5-set match that lasted over 4 hours, the final point was decided by an incredible rally that had 47 shots. Both players were exhausted but gave everything they had. The winning shot was a perfect drop shot that just barely cleared the net! 🎾🏆",
            "Hole-in-one on the 18th hole to win the Masters! The golfer was trailing by one stroke when he stepped up to the tee. With the pressure of millions watching, he hit the perfect shot that rolled directly into the cup. The crowd erupted and the golfer fell to his knees in disbelief! ⛳🎯",
            "Stanley Cup winning goal in overtime! The game was tied 2-2 after regulation and went into sudden death overtime. In the 3rd overtime period, the forward received a pass and fired a wrist shot that found the top corner of the net. The entire team rushed the ice to celebrate their first championship in 50 years! 🏒🥅",
            "Knockout punch in the heavyweight championship fight! The challenger was behind on points when he landed a devastating right hook in the 12th round. The champion went down and couldn't get back up before the 10-count. The underdog had done the impossible and became the new world champion! 🥊💪",
            "Submission victory in the UFC title fight! The fighter was losing the match when he managed to lock in a rear naked choke in the final round. The champion had no choice but to tap out, giving the challenger the victory and the belt. The crowd was shocked as the new champion celebrated his incredible comeback! 🥋🏅",
            "Formula 1 championship decided on the final lap! The two drivers were separated by just 0.1 seconds going into the last corner. The leader made a small mistake and the second-place driver took advantage, passing him on the inside and crossing the finish line first. The championship was decided by the smallest margin in F1 history! 🏎️🏁"
        ]
        
        return (0..<10).map { index in
            VideoClip(
                id: UUID().uuidString,
                videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                caption: longCaptions[index % longCaptions.count],
                sport: sports[index % sports.count],
                likes: Int.random(in: 1000...50000),
                comments: Int.random(in: 50...1000),
                shares: Int.random(in: 10...500),
                createdAt: Date()
            )
        }
    }
}

