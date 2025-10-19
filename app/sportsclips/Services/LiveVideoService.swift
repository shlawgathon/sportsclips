import Foundation
import AVFoundation

// LiveVideo streaming message models (from middleware)
struct LiveCommentaryChunk: Decodable {
    struct Metadata: Decodable {
        let src_video_url: String
        let chunk_number: Int
        let format: String
        let audio_sample_rate: Int
        let commentary_length_bytes: Int64
        let video_length_bytes: Int64
        let num_chunks_processed: Int
    }
    let type: String
    struct DataModel: Decodable {
        let video_data: String
        let metadata: Metadata
    }
    let data: DataModel
}

struct SnippetMessage: Decodable {
    struct Metadata: Decodable {
        let src_video_url: String
        let title: String?
        let description: String?
    }
    let type: String
    struct DataModel: Decodable {
        let video_data: String
        let metadata: Metadata
    }
    let data: DataModel
}

final class LiveVideoService: NSObject {
    private var task: URLSessionWebSocketTask?
    private let session: URLSession

    override init() {
        let config = URLSessionConfiguration.default
        // Disable caches explicitly for live stream
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    func connect(baseURL: URL, videoURL: String, isLive: Bool = true, onChunk: @escaping (Data, LiveCommentaryChunk.Metadata) -> Void, onSnippet: @escaping (Data, SnippetMessage.Metadata) -> Void, onError: @escaping (String) -> Void) {
        var url = baseURL
        url.append(path: "ws/live-video")
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "video_url", value: videoURL),
            .init(name: "is_live", value: isLive ? "true" : "false")
        ]
        guard let finalURL = comps.url else { onError("Bad URL"); return }
        let wsTask = session.webSocketTask(with: finalURL)
        self.task = wsTask
        wsTask.resume()
        listen(onChunk: onChunk, onSnippet: onSnippet, onError: onError)
    }

    func disconnect() {
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func listen(onChunk: @escaping (Data, LiveCommentaryChunk.Metadata) -> Void, onSnippet: @escaping (Data, SnippetMessage.Metadata) -> Void, onError: @escaping (String) -> Void) {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                onError(err.localizedDescription)
            case .success(let msg):
                switch msg {
                case .string(let text):
                    self.handleText(text, onChunk: onChunk, onSnippet: onSnippet, onError: onError)
                case .data(let data):
                    // Not expected, ignore
                    break
                @unknown default:
                    break
                }
                // Continue listening
                self.listen(onChunk: onChunk, onSnippet: onSnippet, onError: onError)
            }
        }
    }

    private func handleText(_ text: String, onChunk: @escaping (Data, LiveCommentaryChunk.Metadata) -> Void, onSnippet: @escaping (Data, SnippetMessage.Metadata) -> Void, onError: @escaping (String) -> Void) {
        guard let typeRange = text.range(of: "\"type\":\"") else { return }
        let afterType = text[typeRange.upperBound...]
        let endQuote = afterType.firstIndex(of: "\"")
        let type = endQuote.map { String(afterType[..<$0]) } ?? ""
        if type == "live_commentary_chunk" {
            if let data = try? JSONDecoder().decode(LiveCommentaryChunk.self, from: Data(text.utf8)), let raw = Data(base64Encoded: data.data.video_data) {
                onChunk(raw, data.data.metadata)
            }
        } else if type == "snippet" {
            if let data = try? JSONDecoder().decode(SnippetMessage.self, from: Data(text.utf8)), let raw = Data(base64Encoded: data.data.video_data) {
                onSnippet(raw, data.data.metadata)
            }
        } else if type == "error" {
            onError(text)
        }
    }
}
