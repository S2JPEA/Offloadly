import Foundation

struct PlaylistEntry: Equatable {
    let id: String
    let title: String
    var videoURL: String { "https://www.youtube.com/watch?v=\(id)" }
}

struct PlaylistInfo {
    let title: String
    let entries: [PlaylistEntry]
    let isChannel: Bool
    let truncated: Bool     // hit the enumeration cap; there may be more
}

/// Lists the videos in a playlist or channel URL *without downloading*, using
/// `yt-dlp --flat-playlist`. Used to create a row per video and to warn before
/// pulling down a huge channel.
enum PlaylistEnumerator {
    /// Enumeration is capped so a giant channel doesn't hang the resolve step.
    static let maxEntries = 500

    static func enumerate(url: String, ytDlp: URL,
                          completion: @escaping (PlaylistInfo?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let info = run(url: url, ytDlp: ytDlp)
            DispatchQueue.main.async { completion(info) }
        }
    }

    private static func run(url: String, ytDlp: URL) -> PlaylistInfo? {
        let lower = url.lowercased()
        let isChannel = lower.contains("/@") || lower.contains("/channel/")
            || lower.contains("/c/") || lower.contains("/user/")

        // For a bare channel URL, target its uploads tab so we get videos, not
        // the channel's sub-tabs.
        var target = url
        if isChannel,
           !["/videos", "/shorts", "/streams", "/playlists"].contains(where: lower.contains) {
            target = url.hasSuffix("/") ? url + "videos" : url + "/videos"
        }

        let process = Process()
        process.executableURL = ytDlp
        process.arguments = [
            "--ignore-config", "--no-warnings", "--flat-playlist",
            "--playlist-end", "\(maxEntries)",
            "--dump-single-json", target
        ]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"].map { "\($0):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" })
            ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // A single video returns _type "video" (or no entries) → let the caller
        // treat it as a normal single download.
        guard obj["entries"] != nil else { return nil }

        let title = (obj["title"] as? String) ?? "Playlist"
        let rawEntries = (obj["entries"] as? [[String: Any]]) ?? []
        var entries: [PlaylistEntry] = []
        for entry in rawEntries {
            guard let id = entry["id"] as? String, !id.isEmpty else { continue }
            if (entry["_type"] as? String) == "playlist" { continue } // skip nested tabs
            let entryTitle = (entry["title"] as? String) ?? id
            entries.append(PlaylistEntry(id: id, title: entryTitle))
        }
        guard !entries.isEmpty else { return nil }

        return PlaylistInfo(
            title: title,
            entries: entries,
            isChannel: isChannel,
            truncated: entries.count >= maxEntries
        )
    }
}
