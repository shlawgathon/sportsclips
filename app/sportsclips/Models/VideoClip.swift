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
        // Extract sport from title/description or use a default mapping
        let sport = extractSportFromText(clip.title + " " + clip.description)
        
        return VideoClip(
            id: clipId,
            videoURL: "", // Will be populated when we fetch the presigned URL
            caption: clip.description,
            sport: sport,
            likes: clip.likesCount,
            comments: clip.commentsCount,
            shares: 0, // Not provided by API
            createdAt: Date(timeIntervalSince1970: TimeInterval(clip.createdAt)),
            s3Key: clip.s3Key,
            title: clip.title,
            description: clip.description
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
        guard s3Key != nil else {
            throw VideoClipError.missingS3Key
        }
        
        let apiClient = APIClient.shared
        let response = try await apiClient.presignDownload(id: id)
        return response.url
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
            createdAt: Date(),
            s3Key: "uploads/mock-video.mp4",
            title: "Championship Touchdown",
            description: "Incredible touchdown pass in the final seconds of the championship game! The quarterback showed amazing composure under pressure, delivering a perfect spiral to the wide receiver who made an unbelievable catch in the end zone. This moment will go down in history as one of the greatest plays ever witnessed in football. The crowd went absolutely wild! 🏈🔥"
        )
    }
    
    static var mockArray: [VideoClip] {
        let sports: [Sport] = [.football, .basketball, .soccer, .baseball, .tennis, .golf, .hockey, .boxing, .mma, .racing]
        
        // Create 2 captions for each sport (20 total videos)
        let sportCaptions: [Sport: [String]] = [
            .football: [
                "Incredible touchdown pass in the final seconds of the championship game! The quarterback showed amazing composure under pressure, delivering a perfect spiral to the wide receiver who made an unbelievable catch in the end zone. This moment will go down in history as one of the greatest plays ever witnessed in football. The crowd went absolutely wild! 🏈🔥",
                "Game-winning field goal from 65 yards out! With just 3 seconds left on the clock, the kicker stepped up and booted the longest field goal in NFL history. The ball sailed through the uprights as time expired, securing the victory and sending the entire stadium into a frenzy! 🏈⚡"
            ],
            .basketball: [
                "Slam dunk contest winner with the most creative dunk ever seen! The player jumped over a car, did a 360-degree spin, and threw it down with authority. The judges were speechless and the entire arena erupted in cheers. This will be remembered as the greatest dunk in basketball history! 🏀💥",
                "Buzzer-beater three-pointer to win the championship! Down by 2 with 0.3 seconds left, the point guard caught the inbound pass, turned, and launched a desperation shot from half court. The ball swished through the net as the buzzer sounded, crowning them as champions! 🏀🎯"
            ],
            .soccer: [
                "World Cup final goal that changed everything! In the 89th minute, with the score tied, the striker received a perfect cross and executed a bicycle kick that found the top corner of the net. The goalkeeper had no chance as the ball sailed past him into the goal. The entire stadium went silent for a moment before exploding in celebration! ⚽🎉",
                "Free kick masterpiece from 35 yards out! The midfielder stepped up to take the free kick and curled the ball over the wall and into the top corner. The goalkeeper was left rooted to the spot as the ball found the perfect angle to nestle into the net! ⚽✨"
            ],
            .baseball: [
                "Perfect game in the World Series! The pitcher threw 27 consecutive strikeouts, something that has never been done before in the history of baseball. Every single batter that stepped up to the plate was sent back to the dugout. The crowd was on their feet for the entire game, witnessing history in the making! ⚾👑",
                "Walk-off grand slam in the bottom of the 9th! Down by 3 runs with the bases loaded, the cleanup hitter stepped up and crushed a fastball deep into the left field stands. The entire team rushed home plate to celebrate the incredible comeback victory! ⚾💥"
            ],
            .tennis: [
                "Championship point in the Wimbledon final! After a grueling 5-set match that lasted over 4 hours, the final point was decided by an incredible rally that had 47 shots. Both players were exhausted but gave everything they had. The winning shot was a perfect drop shot that just barely cleared the net! 🎾🏆",
                "Between-the-legs winner at the US Open! The player was running back to retrieve a lob when they hit an incredible between-the-legs shot that landed perfectly in the corner. The crowd erupted as the opponent could only watch in amazement! 🎾🔥"
            ],
            .golf: [
                "Hole-in-one on the 18th hole to win the Masters! The golfer was trailing by one stroke when he stepped up to the tee. With the pressure of millions watching, he hit the perfect shot that rolled directly into the cup. The crowd erupted and the golfer fell to his knees in disbelief! ⛳🎯",
                "Eagle putt from 60 feet to force a playoff! Needing to make the putt to stay alive, the golfer read the green perfectly and rolled the ball along the perfect line. The ball dropped into the cup as the crowd went wild, forcing an extra hole! ⛳⚡"
            ],
            .hockey: [
                "Stanley Cup winning goal in overtime! The game was tied 2-2 after regulation and went into sudden death overtime. In the 3rd overtime period, the forward received a pass and fired a wrist shot that found the top corner of the net. The entire team rushed the ice to celebrate their first championship in 50 years! 🏒🥅",
                "Hat trick in the playoffs! The star forward scored three goals in a single game, including a spectacular breakaway goal where he deked the goalie and slid the puck between the pads. The arena was electric as fans threw their hats onto the ice! 🏒🎩"
            ],
            .boxing: [
                "Knockout punch in the heavyweight championship fight! The challenger was behind on points when he landed a devastating right hook in the 12th round. The champion went down and couldn't get back up before the 10-count. The underdog had done the impossible and became the new world champion! 🥊💪",
                "Upset victory in the lightweight division! The underdog fighter used incredible footwork and speed to outmaneuver the champion. In the 8th round, he landed a perfect combination that sent the champion to the canvas for the first time in his career! 🥊⚡"
            ],
            .mma: [
                "Submission victory in the UFC title fight! The fighter was losing the match when he managed to lock in a rear naked choke in the final round. The champion had no choice but to tap out, giving the challenger the victory and the belt. The crowd was shocked as the new champion celebrated his incredible comeback! 🥋🏅",
                "Spinning back kick knockout! The fighter executed a perfect spinning back kick that connected flush with the opponent's jaw. The impact was so devastating that the opponent was out before he hit the canvas. The referee immediately stopped the fight! 🥋💥"
            ],
            .racing: [
                "Formula 1 championship decided on the final lap! The two drivers were separated by just 0.1 seconds going into the last corner. The leader made a small mistake and the second-place driver took advantage, passing him on the inside and crossing the finish line first. The championship was decided by the smallest margin in F1 history! 🏎️🏁",
                "Last-lap pass for the win! The driver was in second place going into the final lap when he made a daring move on the inside of turn 3. The two cars were side by side through the next few corners before the challenger finally pulled ahead to take the checkered flag! 🏎️⚡"
            ]
        ]
        
        var videos: [VideoClip] = []
        
        // Create 2 videos for each sport (20 total)
        for sport in sports {
            guard let captions = sportCaptions[sport] else { continue }
            
            for (index, caption) in captions.enumerated() {
                videos.append(VideoClip(
                    id: UUID().uuidString,
                    videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
                    caption: caption,
                    sport: sport,
                    likes: Int.random(in: 1000...50000),
                    comments: Int.random(in: 50...1000),
                    shares: Int.random(in: 10...500),
                    createdAt: Date(),
                    s3Key: "uploads/mock-\(sport.rawValue.lowercased())-\(index).mp4",
                    title: "\(sport.rawValue) Highlight \(index + 1)",
                    description: caption
                ))
            }
        }
        
        return videos
    }
}

