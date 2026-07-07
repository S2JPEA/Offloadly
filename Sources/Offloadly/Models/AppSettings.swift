import Foundation

enum DownloadQuality: String, CaseIterable, Identifiable {
    case best = "Best available"
    case p1080 = "1080p"
    case p720 = "720p"
    case audioMP3 = "Audio only (MP3)"

    var id: String { rawValue }

    /// yt-dlp `-f` format selector plus any extra args this quality needs.
    var formatArguments: [String] {
        switch self {
        case .best:
            return ["-f", "bv*+ba/b", "--merge-output-format", "mp4"]
        case .p1080:
            return ["-f", "bv*[height<=1080]+ba/b[height<=1080]", "--merge-output-format", "mp4"]
        case .p720:
            return ["-f", "bv*[height<=720]+ba/b[height<=720]", "--merge-output-format", "mp4"]
        case .audioMP3:
            return ["-f", "ba/b", "-x", "--audio-format", "mp3"]
        }
    }
}

/// Persisted user preferences, backed by UserDefaults. A single shared
/// instance is injected into the environment and read by the download engine.
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard

    private enum Key {
        static let downloadDir = "downloadDirectoryPath"
        static let quality = "downloadQuality"
        static let maxConcurrent = "maxConcurrentDownloads"
        static let sponsorBlock = "removeSponsorSegments"
        static let playlistSubfolder = "playlistSubfolder"
    }

    @Published var downloadDirectory: URL {
        didSet { defaults.set(downloadDirectory.path, forKey: Key.downloadDir) }
    }

    @Published var quality: DownloadQuality {
        didSet { defaults.set(quality.rawValue, forKey: Key.quality) }
    }

    @Published var maxConcurrent: Int {
        didSet { defaults.set(maxConcurrent, forKey: Key.maxConcurrent) }
    }

    @Published var removeSponsorSegments: Bool {
        didSet { defaults.set(removeSponsorSegments, forKey: Key.sponsorBlock) }
    }

    @Published var playlistSubfolder: Bool {
        didSet { defaults.set(playlistSubfolder, forKey: Key.playlistSubfolder) }
    }

    init() {
        // Download directory: saved path, else ~/Downloads, else home.
        if let saved = defaults.string(forKey: Key.downloadDir), !saved.isEmpty {
            downloadDirectory = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            downloadDirectory = FileManager.default
                .urls(for: .downloadsDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
        }

        // Optional override for the download folder (used by tests / power users).
        // Assigned inside init, so it doesn't trigger persistence.
        if let overrideDir = ProcessInfo.processInfo.environment["OFFLOADLY_DOWNLOAD_DIR"],
           !overrideDir.isEmpty {
            downloadDirectory = URL(fileURLWithPath: overrideDir, isDirectory: true)
        }

        if let raw = defaults.string(forKey: Key.quality),
           let q = DownloadQuality(rawValue: raw) {
            quality = q
        } else {
            quality = .best
        }

        let storedConcurrency = defaults.integer(forKey: Key.maxConcurrent)
        maxConcurrent = storedConcurrency == 0 ? 2 : storedConcurrency

        removeSponsorSegments = defaults.bool(forKey: Key.sponsorBlock)
        // Default the playlist subfolder toggle to on when unset.
        if defaults.object(forKey: Key.playlistSubfolder) == nil {
            playlistSubfolder = true
        } else {
            playlistSubfolder = defaults.bool(forKey: Key.playlistSubfolder)
        }
    }
}
