//
//  LiveVideoPlayerView.swift
//  sportsclips
//
//  Individual live video player for TikTok-style scrolling
//

import SwiftUI
import AVKit

struct LiveVideoPlayerView: View {
    let video: VideoClip
    @ObservedObject var playerManager: VideoPlayerManager
    @Binding var isLiked: Bool
    @Binding var showingCommentInput: Bool
    @State private var player: AVPlayer?

    // Live streaming
    @State private var liveService = LiveVideoService()
    @State private var queuePlayer: AVQueuePlayer?
    // Buffer chunks by their chunk_number to ensure ordered playback
    @State private var liveBufferMap: [Int: URL] = [:]
    @State private var nextExpectedChunk: Int = 1
    @State private var isLivePlaying = false
    @State private var livePollTask: Task<Void, Never>? = nil
    
    // Global live video manager to prevent audio overlap
    private let liveVideoManager = LiveVideoManager.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video player - same dimensions as video feed
                if let qp = queuePlayer, let gid = video.gameId, !gid.isEmpty {
                    VideoPlayer(player: qp)
                        .aspectRatio(9/16, contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                } else if let player = player {
                    VideoPlayer(player: player)
                        .aspectRatio(9/16, contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .allowsHitTesting(false) // Prevent all user interaction
                } else {
                    // Loading placeholder
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [.purple.opacity(0.3), .blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(
                            VStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.5)

                                Text("LIVE")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .padding(.top, 12)
                            }
                        )
                        .ignoresSafeArea()
                }
            }
            .onAppear {
                setupPlayer()
                // Silent tap: Record user interaction to enable autoplay
                VideoPlayerManager.shared.recordUserInteraction()
                
                // Register this live player with the manager
                if let gid = video.gameId, !gid.isEmpty, let qp = queuePlayer {
                    liveVideoManager.registerLivePlayer(qp, for: video.id)
                    liveVideoManager.activateLiveVideo(video.id)
                }
            }
        .onDisappear {
            // Immediately pause/mute audio when view disappears to prevent overlap
            if let gid = video.gameId, !gid.isEmpty {
                // For live videos, unregister from manager and disconnect
                liveVideoManager.unregisterLivePlayer(for: video.id)
                disconnectLive()
            } else {
                // For regular videos, use the player manager
                playerManager.pauseVideo(for: video.videoURL, videoId: video.id)
            }
        }
        }
    }


    private func setupPlayer() {
        if let gid = video.gameId, !gid.isEmpty {
            print("[LiveVideoPlayerView][DEBUG] setupPlayer live gid=\(gid)")
            // Live stream path using YouTube source URL from gameId
            // Ensure audio session is active so audio plays even with the silent switch
            VideoPlayerManager.shared.ensureAudioSessionActive()
            queuePlayer = AVQueuePlayer()
            queuePlayer?.isMuted = false
            queuePlayer?.volume = 1.0
            isLivePlaying = false
            nextExpectedChunk = 1
            liveBufferMap.removeAll()
            connectLive()
        } else {
            print("[LiveVideoPlayerView][DEBUG] setupPlayer VOD id=\(video.id)")
            // Use async variant to fetch presigned URL when video.videoURL is empty
            Task {
                let p = await playerManager.getPlayer(for: video)
                await MainActor.run { self.player = p }
                await playerManager.playVideo(for: video)
            }
        }
    }

    private func connectLive() {
        guard let gameId = video.gameId, !gameId.isEmpty else { return }
        let sourceUrl = video.videoURL
        print("[LiveVideoPlayerView][DEBUG] connectLive gameId=\(gameId) src=\(sourceUrl)")
        // Start polling for chunk references and enqueue by order
        livePollTask?.cancel()
        livePollTask = Task { [sourceUrl] in
            var lastChunk = nextExpectedChunk - 1
            while !Task.isCancelled {
                let chunks = await liveService.pollLiveChunks(streamUrl: sourceUrl, afterChunk: lastChunk, limit: 3)
                if !chunks.isEmpty {
                    print("[LiveVideoPlayerView][DEBUG] polled chunks count=\(chunks.count) lastChunkBefore=\(lastChunk)")
                    for ch in chunks {
                        print("[LiveVideoPlayerView][POLL] chunk=\(ch.chunkNumber) url=\(ch.url)")
                        if let url = URL(string: ch.url) {
                            liveBufferMap[ch.chunkNumber] = url
                            lastChunk = max(lastChunk, ch.chunkNumber)
                        }
                    }
                    print("[LiveVideoPlayerView][DEBUG] bufferSize=\(liveBufferMap.count) lastChunkAfter=\(lastChunk)")
                    flushContiguousChunksToQueue(minInitialBuffer: 2)
                }
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s
            }
        }
    }

    // Flush any contiguous sequence of buffered chunks starting from nextExpectedChunk into the queue.
    // If not yet playing, require a minimum initial buffer before starting playback.
    private func flushContiguousChunksToQueue(minInitialBuffer: Int) {
        guard let _ = queuePlayer else { return }
        // If not started, ensure we have at least the minimum buffered
        if !isLivePlaying && liveBufferMap.count < minInitialBuffer { return }

        var enqueued = 0
        while let url = liveBufferMap[nextExpectedChunk] {
            print("[LiveVideoPlayerView][ENQUEUE] chunk=\(nextExpectedChunk) url=\(url.absoluteString)")
            if let item = makeItem(url: url) {
                queuePlayer?.insert(item, after: nil)
                enqueued += 1
            }
            liveBufferMap.removeValue(forKey: nextExpectedChunk)
            nextExpectedChunk += 1
        }
        if enqueued > 0 {
            print("[LiveVideoPlayerView][DEBUG] flush enqueued=\(enqueued) nextExpected=\(nextExpectedChunk) bufferLeft=\(liveBufferMap.count) playing=\(isLivePlaying)")
        }
        if !isLivePlaying && enqueued >= minInitialBuffer {
            isLivePlaying = true
            print("[LiveVideoPlayerView][DEBUG] starting playback with minBuffer=\(minInitialBuffer)")
            
            // Set highest priority for live video playback
            VideoPlayerManager.shared.setVideoPlaybackPriority()
            
            // Activate this live video in the manager
            liveVideoManager.activateLiveVideo(video.id)
            
            queuePlayer?.play()
        }
    }

    private func disconnectLive() {
        print("[LiveVideoPlayerView][DEBUG] disconnectLive id=\(video.id) nextExpected=\(nextExpectedChunk) buffer=\(liveBufferMap.count)")
        livePollTask?.cancel()
        livePollTask = nil
        queuePlayer?.pause()
        queuePlayer?.removeAllItems()
        queuePlayer = nil
        liveBufferMap.removeAll()
        isLivePlaying = false
    }

    private func makeItem(url: URL) -> AVPlayerItem? {
        let asset = AVURLAsset(url: url)
        return AVPlayerItem(asset: asset)
    }

    private func writeChunkToTemp(data: Data, chunk: Int) -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("live_chunks_\(video.id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent(String(format: "%06d.mp4", chunk))
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            return nil
        }
    }
}

//#Preview {
//    LiveVideoPlayerView(
//        video: VideoClip.mock,
//        playerManager: VideoPlayerManager.shared,
//        isLiked: .constant(false),
//        showingCommentInput: .constant(false)
//    )
//}

