import Foundation
import AVFoundation
import os

// LiveVideo streaming message models (from middleware)
struct LiveCommentaryChunk: Decodable {
    struct Metadata: Decodable {
        let src_video_url: String
        let chunk_number: Int
        let format: String
        let audio_sample_rate: Int
        let commentary_length_bytes: Int64
        let video_length_bytes: Int64
        let num_chunks_processed: Int?
    }
    let type: String
    struct DataModel: Decodable {
        let video_data: String?
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
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "sportsclips", category: "LiveVideoService")
    private var connectionId = UUID().uuidString
    // Store metadata from the last live_commentary_chunk text message to pair with the following binary frame
    private var pendingChunkMeta: LiveCommentaryChunk.Metadata? = nil

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
        connectionId = UUID().uuidString
        log.log("[conn:\(self.connectionId)] Connecting WS url=\(finalURL.absoluteString) isLive=\(isLive ? "true" : "false")")
        let wsTask = session.webSocketTask(with: finalURL)
        self.task = wsTask
        wsTask.resume()
        listen(onChunk: onChunk, onSnippet: onSnippet, onError: onError)
    }

    func disconnect() {
        log.log("[conn:\(self.connectionId)] Disconnecting WS")
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func listen(onChunk: @escaping (Data, LiveCommentaryChunk.Metadata) -> Void, onSnippet: @escaping (Data, SnippetMessage.Metadata) -> Void, onError: @escaping (String) -> Void) {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                self.log.error("[conn:\(self.connectionId)] WS receive error: \(err.localizedDescription)")
                onError(err.localizedDescription)
            case .success(let msg):
                switch msg {
                case .string(let text):
                    self.log.debug("[conn:\(self.connectionId)] <- text len=\(text.count)")
                    self.handleText(text, onChunk: onChunk, onSnippet: onSnippet, onError: onError)
                case .data(let data):
                    // Expect binary frames to immediately follow a metadata text for live chunks
                    if let meta = self.pendingChunkMeta {
                        self.log.debug("[conn:\(self.connectionId)] <- binary bytes=\(data.count) chunk=\(meta.chunk_number)")
                        onChunk(data, meta)
                        self.pendingChunkMeta = nil
                    } else {
                        self.log.debug("[conn:\(self.connectionId)] <- binary (no pending meta) bytes=\(data.count)")
                        // Unknown binary payload; ignore for now
                    }
                @unknown default:
                    self.log.debug("[conn:\(self.connectionId)] <- unknown frame")
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
            if let decoded = try? JSONDecoder().decode(LiveCommentaryChunk.self, from: Data(text.utf8)) {
                // If video_data present (legacy base64 path), decode inline; otherwise, store metadata and wait for binary frame
                if let b64 = decoded.data.video_data, let raw = Data(base64Encoded: b64) {
                    self.log.info("[conn:\(self.connectionId)] live_commentary_chunk inline bytes=\(raw.count) chunk=\(decoded.data.metadata.chunk_number) fmt=\(decoded.data.metadata.format)")
                    onChunk(raw, decoded.data.metadata)
                } else {
                    self.pendingChunkMeta = decoded.data.metadata
                    self.log.info("[conn:\(self.connectionId)] live_commentary_chunk meta-only chunk=\(decoded.data.metadata.chunk_number) fmt=\(decoded.data.metadata.format)")
                }
            } else {
                self.log.error("[conn:\(self.connectionId)] failed to decode live_commentary_chunk")
            }
        } else if type == "snippet" {
            if let data = try? JSONDecoder().decode(SnippetMessage.self, from: Data(text.utf8)), let raw = Data(base64Encoded: data.data.video_data) {
                self.log.info("[conn:\(self.connectionId)] snippet bytes=\(raw.count) title=\(data.data.metadata.title ?? "")")
                onSnippet(raw, data.data.metadata)
            } else {
                self.log.error("[conn:\(self.connectionId)] failed to decode snippet")
            }
        } else if type == "error" {
            self.log.error("[conn:\(self.connectionId)] server error: \(text)")
            onError(text)
        } else {
            self.log.debug("[conn:\(self.connectionId)] text type=\(type)")
        }
    }
}
