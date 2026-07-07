import Foundation

/// The lifecycle of a single download (one enqueued URL — which may be a
/// single video or a whole playlist).
enum DownloadState: Equatable {
    case queued
    case fetchingInfo
    case downloading
    case merging
    case paused
    case completed
    case failed(String)
    case canceled

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .canceled: return true
        default: return false
        }
    }

    /// Actively occupying a download slot (running a yt-dlp process).
    var isActive: Bool {
        switch self {
        case .fetchingInfo, .downloading, .merging: return true
        default: return false
        }
    }

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .fetchingInfo: return "Fetching info…"
        case .downloading: return "Downloading"
        case .merging: return "Merging…"
        case .paused: return "Paused"
        case .completed: return "Completed"
        case .failed(let msg): return "Failed — \(msg)"
        case .canceled: return "Canceled"
        }
    }
}

/// Observable model for one download row. Updated live as yt-dlp reports
/// progress. A class so each row can observe just its own item.
final class DownloadItem: ObservableObject, Identifiable {
    private static var sequenceCounter = 0

    let id = UUID()
    /// Monotonic creation order — a stable tiebreaker for list sorting.
    let seq: Int
    let url: String
    let addedAt = Date()

    @Published var title: String
    @Published var state: DownloadState = .queued
    @Published var percent: Double = 0          // 0...1 for the current file
    @Published var speed: String = ""           // e.g. "3.2 MiB/s"
    @Published var eta: String = ""             // e.g. "00:31"
    @Published var outputPath: String?          // final file, for Reveal in Finder

    // Playlist context, when this item is one video of a playlist/channel.
    @Published var playlistIndex: Int?
    @Published var playlistCount: Int?
    /// Folder name for a playlist/channel batch (used as a subfolder).
    let playlistTitle: String?

    init(url: String, title: String? = nil, playlistTitle: String? = nil,
         playlistIndex: Int? = nil, playlistCount: Int? = nil) {
        DownloadItem.sequenceCounter += 1
        self.seq = DownloadItem.sequenceCounter
        self.url = url
        self.playlistTitle = playlistTitle
        self.playlistIndex = playlistIndex
        self.playlistCount = playlistCount
        // Show the given title (from playlist enumeration) or the raw URL until
        // yt-dlp reports the real one.
        self.title = title ?? DownloadItem.placeholderTitle(for: url)
    }

    var isPlaylistInProgress: Bool {
        (playlistCount ?? 0) > 1
    }

    /// YouTube video id parsed from the URL, if any (watch?v=, youtu.be/, shorts/).
    var youTubeID: String? {
        guard let comps = URLComponents(string: url) else { return nil }
        if let v = comps.queryItems?.first(where: { $0.name == "v" })?.value, !v.isEmpty {
            return v
        }
        let host = comps.host?.lowercased() ?? ""
        let parts = comps.path.split(separator: "/").map(String.init)
        if host.contains("youtu.be"), let first = parts.first { return first }
        if let idx = parts.firstIndex(of: "shorts"), idx + 1 < parts.count { return parts[idx + 1] }
        return nil
    }

    /// Thumbnail image URL derived from the video id (no network call needed to build it).
    var thumbnailURL: URL? {
        guard let id = youTubeID else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")
    }

    private static func placeholderTitle(for url: String) -> String {
        if let comps = URLComponents(string: url), let host = comps.host {
            return "\(host)…"
        }
        return url
    }
}
