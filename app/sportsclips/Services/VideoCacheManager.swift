//
//  VideoCacheManager.swift
//  sportsclips
//
//  A simple state-machine based MP4 download/cache manager that prefetches
//  upcoming videos to disk and serves local file URLs for playback.
//

import Foundation
import CryptoKit
import Combine

/// Represents the cache/download state of a video asset
enum VideoCacheState: Equatable {
    case idle
    case downloading(progress: Double)
    case ready(localURL: URL)
    case failed(error: String)
}

/// A lightweight disk cache for MP4 files with basic LRU eviction.
/// - Stores files under Caches/sportsclips/videos
/// - Filenames are SHA256(url.absoluteString)
/// - Maintains a small metadata file tracking lastAccessDate
@MainActor
final class VideoCacheManager: ObservableObject {
    static let shared = VideoCacheManager()

    // Public publisher for per-id state changes for UI/consumers
    @Published private(set) var states: [String: VideoCacheState] = [:]

    // Configuration
    private let maxCacheBytes: Int64 = 512 * 1024 * 1024 // 512 MB
    private let minFreeBytesToKeep: Int64 = 200 * 1024 * 1024 // 200 MB safety margin
    private let ttlDays: Int = 7 // Optional time-based invalidation

    private let fm = FileManager.default
    private var activeTasks: [String: URLSessionDownloadTask] = [:]
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.waitsForConnectivity = true
        session = URLSession(configuration: config)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        // Periodic light cleanup
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            await self?.purgeIfNeeded()
        }
    }

    // MARK: - Public API

    func state(for id: String) -> VideoCacheState { states[id] ?? .idle }

    /// Ensures the URL is cached to disk and returns the local file URL when ready.
    /// If already cached, marks as ready and returns immediately.
    func fetchToDisk(id: String, remoteURL: URL) async throws -> URL {
        // If already ready
        if case .ready(let local) = states[id], fm.fileExists(atPath: local.path) {
            touchFile(local)
            return local
        }
        // If file already exists at path, adopt it
        let local = localURL(for: remoteURL)
        if fm.fileExists(atPath: local.path) {
            states[id] = .ready(localURL: local)
            touchFile(local)
            return local
        }
        // Start or await download
        states[id] = .downloading(progress: 0)
        let downloaded = try await download(remoteURL: remoteURL, id: id)
        states[id] = .ready(localURL: downloaded)
        await purgeIfNeeded()
        return downloaded
    }

    /// Start prefetching up to `count` next items. Non-blocking.
    func prefetch(next items: [(id: String, url: URL)], count: Int = 5) {
        let slice = Array(items.prefix(count))
        for (id, url) in slice {
            // Skip if already ready or downloading
            switch states[id] {
            case .ready, .downloading: continue
            default: break
            }
            // If already on disk, mark ready
            let local = localURL(for: url)
            if fm.fileExists(atPath: local.path) {
                states[id] = .ready(localURL: local)
                touchFile(local)
                continue
            }
            // Kick off lightweight background fetch
            states[id] = .downloading(progress: 0)
            Task.detached { [weak self] in
                guard let self else { return }
                do {
                    let file = try await self.download(remoteURL: url, id: id)
                    await MainActor.run {
                        self.states[id] = .ready(localURL: file)
                    }
                    await self.purgeIfNeeded()
                } catch {
                    await MainActor.run {
                        self.states[id] = .failed(error: error.localizedDescription)
                    }
                }
            }
        }
    }

    /// Cancel an in-flight download for id
    func cancel(id: String) {
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
        if case .downloading = states[id] {
            states[id] = .idle
        }
    }

    /// Periodically purge cache based on size, TTL, and free space.
    func purgeIfNeeded() async {
        // TTL purge first
        purgeExpired()
        // Free space check
        if let free = try? freeDiskSpace(), free < minFreeBytesToKeep {
            evictLRU(untilFreeBytes: minFreeBytesToKeep - free)
        }
        // Size cap check
        let total = directorySize(cacheDir)
        if total > maxCacheBytes {
            evictLRU(bytesToFree: total - maxCacheBytes)
        }
    }

    // MARK: - Download

    private func download(remoteURL: URL, id: String) async throws -> URL {
        let request = URLRequest(url: remoteURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        let (tempURL, response) = try await session.download(for: request, delegate: nil)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let local = localURL(for: remoteURL)
        try? fm.removeItem(at: local)
        try fm.moveItem(at: tempURL, to: local)
        setLastAccessDate(local, Date())
        return local
    }

    // MARK: - Paths and metadata

    private var cacheDir: URL {
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("sportsclips/videos", isDirectory: true)
    }

    private func filename(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined() + ".mp4"
    }

    private func localURL(for url: URL) -> URL {
        cacheDir.appendingPathComponent(filename(for: url))
    }

    // MARK: - LRU helpers

    private func setLastAccessDate(_ file: URL, _ date: Date) {
        try? fm.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
    }

    private func touchFile(_ file: URL) {
        setLastAccessDate(file, Date())
    }

    private func directorySize(_ dir: URL) -> Int64 {
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true, let size = values?.fileSize { total += Int64(size) }
        }
        return total
    }

    private func freeDiskSpace() throws -> Int64 {
        let attrs = try fm.attributesOfFileSystem(forPath: cacheDir.path)
        return (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    private func purgeExpired() {
        guard let enumerator = fm.enumerator(at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return }
        let cutoff = Date().addingTimeInterval(TimeInterval(-ttlDays * 24 * 3600))
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            if values?.isRegularFile == true, let m = values?.contentModificationDate, m < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func evictLRU(bytesToFree: Int64? = nil, untilFreeBytes: Int64? = nil) {
        // Build list sorted by last access (modification date)
        guard let files = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) else { return }
        let sorted = files.compactMap { url -> (URL, Date, Int64)? in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey])
            guard values?.isRegularFile == true else { return nil }
            let date = values?.contentModificationDate ?? Date.distantPast
            let size = Int64(values?.fileSize ?? 0)
            return (url, date, size)
        }.sorted { $0.1 < $1.1 }

        var freed: Int64 = 0
        for (url, _, size) in sorted {
            if let need = bytesToFree, freed >= need { break }
            if let until = untilFreeBytes, ((try? freeDiskSpace()) ?? 0) >= until { break }
            try? fm.removeItem(at: url)
            freed += size
        }
    }
}
