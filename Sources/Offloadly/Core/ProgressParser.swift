import Foundation

/// A single meaningful event parsed from one line of yt-dlp output.
enum YTDLPEvent: Equatable {
    case progress(percent: Double, speed: String, eta: String, title: String?)
    case destination(path: String)      // a stream/final file path
    case merging(path: String?)         // ffmpeg is muxing streams into `path`
    case alreadyDownloaded(path: String)
    case fetchingInfo
    case playlistItem(index: Int, count: Int)
    case error(String)
    case other
}

/// Turns raw yt-dlp stdout/stderr lines into structured events.
///
/// The runner passes `--progress-template "download:PROG|%(progress._percent_str)s|
/// %(progress._speed_str)s|%(progress._eta_str)s"`, so download progress arrives
/// as easy-to-split `PROG|...` lines rather than human-formatted text.
enum ProgressParser {
    static func parse(_ rawLine: String) -> YTDLPEvent {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return .other }

        if line.hasPrefix("PROG|") {
            return parseProgress(line)
        }

        // Errors (yt-dlp prefixes with "ERROR:").
        if let range = line.range(of: "ERROR:") {
            let msg = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            return .error(msg.isEmpty ? "Download failed" : msg)
        }

        // Playlist position: "[download] Downloading item 2 of 15"
        //                     "[download] Downloading video 2 of 15"
        if let item = parsePlaylistItem(line) {
            return item
        }

        if line.contains("has already been downloaded") {
            let path = extractLeadingPath(from: line, suffix: "has already been downloaded")
            return .alreadyDownloaded(path: path)
        }

        if line.hasPrefix("[Merger]") || line.hasPrefix("[VideoConvertor]") {
            return .merging(path: quotedPath(in: line))
        }

        if line.hasPrefix("[ExtractAudio] Destination:") || line.contains("[download] Destination:") {
            if let path = afterDestination(line) {
                return .destination(path: path)
            }
        }

        if line.hasPrefix("[youtube") || line.hasPrefix("[info]") ||
           line.contains("Extracting URL") || line.contains("Downloading webpage") {
            return .fetchingInfo
        }

        return .other
    }

    // MARK: - Helpers

    private static func parseProgress(_ line: String) -> YTDLPEvent {
        // PROG|<percent>|<speed>|<eta>|<title…>  — title is last and may itself
        // contain "|", so rejoin everything past field 3 back into the title.
        let parts = line.components(separatedBy: "|")
        guard parts.count >= 4 else { return .other }

        let percentToken = parts[1].trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "%", with: "")
        let percent = (Double(percentToken) ?? 0) / 100.0

        let speed = normalize(parts[2])
        let eta = normalize(parts[3])

        var title: String?
        if parts.count >= 5 {
            let t = parts[4...].joined(separator: "|").trimmingCharacters(in: .whitespaces)
            title = (t.isEmpty || t == "NA") ? nil : t
        }
        return .progress(percent: percent, speed: speed, eta: eta, title: title)
    }

    private static func normalize(_ token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t == "N/A" || t.contains("Unknown") { return "" }
        return t
    }

    private static func parsePlaylistItem(_ line: String) -> YTDLPEvent? {
        guard line.contains("Downloading item") || line.contains("Downloading video") else {
            return nil
        }
        // Grab the two integers around "of".
        let numbers = line
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
        guard numbers.count >= 2 else { return nil }
        return .playlistItem(index: numbers[0], count: numbers[1])
    }

    private static func afterDestination(_ line: String) -> String? {
        guard let range = line.range(of: "Destination:") else { return nil }
        let path = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        return path.isEmpty ? nil : path
    }

    private static func quotedPath(in line: String) -> String? {
        guard let first = line.firstIndex(of: "\""),
              let last = line.lastIndex(of: "\""),
              first < last else { return nil }
        let path = String(line[line.index(after: first)..<last])
        return path.isEmpty ? nil : path
    }

    private static func extractLeadingPath(from line: String, suffix: String) -> String {
        var s = line
        if let bracket = s.range(of: "] ") {
            s = String(s[bracket.upperBound...])
        }
        if let range = s.range(of: suffix) {
            s = String(s[..<range.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespaces)
    }
}
