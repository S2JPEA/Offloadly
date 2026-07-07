import Foundation

/// Spawns and supervises one `yt-dlp` process, streaming its output as parsed
/// events. Not tied to any actor — callbacks are delivered on the main queue so
/// the UI layer can mutate `@Published` state directly.
final class YTDLPRunner {
    private var process: Process?
    private let ioQueue = DispatchQueue(label: "com.offloadly.ytdlp.io")
    private var buffer = Data()
    private(set) var wasCanceled = false
    private(set) var wasPaused = false

    /// When this item is one video of a playlist/channel batch, it downloads as a
    /// single video written into `folder`, prefixed by `index`.
    struct PlaylistContext {
        let folder: String
        let index: Int
    }

    /// Start a download. `onEvent` fires per parsed line; `onFinish` fires once
    /// with the process exit code (0 == success). Both are delivered on main.
    func start(
        url: String,
        settings: AppSettings,
        ytDlp: URL,
        ffmpeg: URL?,
        playlist: PlaylistContext? = nil,
        onEvent: @escaping (YTDLPEvent) -> Void,
        onFinish: @escaping (Int32) -> Void
    ) {
        let proc = Process()
        proc.executableURL = ytDlp
        proc.arguments = buildArguments(url: url, settings: settings, ffmpeg: ffmpeg, playlist: playlist)

        var env = ProcessInfo.processInfo.environment
        // Make sure common tool locations are reachable for any child processes.
        let extraPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = (env["PATH"].map { "\($0):\(extraPath)" }) ?? extraPath
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            if data.isEmpty {
                // EOF: no more output. Flush the tail and report completion.
                handle.readabilityHandler = nil
                self.ioQueue.async {
                    self.flushRemainder(onEvent)
                    self.process?.waitUntilExit()
                    let status = self.process?.terminationStatus ?? -1
                    DispatchQueue.main.async { onFinish(status) }
                }
                return
            }
            self.ioQueue.async { self.processChunk(data, onEvent) }
        }

        self.process = proc
        do {
            try proc.run()
        } catch {
            DispatchQueue.main.async {
                onEvent(.error("Could not launch yt-dlp: \(error.localizedDescription)"))
                onFinish(-1)
            }
        }
    }

    func cancel() {
        wasCanceled = true
        process?.terminate()
    }

    /// Stop the process but keep partial (.part) files so it can resume later.
    func pause() {
        wasPaused = true
        process?.terminate()
    }

    // MARK: - Argument construction

    private func buildArguments(url: String, settings: AppSettings, ffmpeg: URL?,
                                playlist: PlaylistContext?) -> [String] {
        var args: [String] = [
            "--ignore-config",       // don't inherit the user's global yt-dlp config
            "--no-color",
            "--newline",             // one progress update per line
            "--progress",            // force progress output even when piped (not a TTY)
            "--no-playlist-reverse",
            "--retries", "5",
            "--fragment-retries", "5",
            // Machine-readable progress. Title is the last field so a `|` inside
            // a title can't corrupt the numeric fields.
            "--progress-template",
            "download:PROG|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s|%(info.title)s"
        ]

        if let ffmpeg {
            args += ["--ffmpeg-location", ffmpeg.path]
        }

        args += settings.quality.formatArguments

        if settings.removeSponsorSegments {
            args += ["--sponsorblock-remove", "sponsor,selfpromo,interaction"]
        }

        // Per-item playlist video: force single, write into the batch subfolder.
        if let playlist {
            args.append("--no-playlist")
            args += ["-o", playlistItemTemplate(settings: settings, playlist: playlist)]
            args.append(url)
            return args
        }

        let classification = classify(url: url)
        if classification.forceSingleVideo {
            args.append("--no-playlist")
        }

        args += ["-o", outputTemplate(settings: settings, isPlaylist: classification.isPlaylist)]
        args.append(url)
        return args
    }

    private func playlistItemTemplate(settings: AppSettings, playlist: PlaylistContext) -> String {
        let dir = settings.downloadDirectory.path
        let prefix = String(format: "%02d - ", playlist.index)
        guard settings.playlistSubfolder else {
            return "\(dir)/\(prefix)%(title)s.%(ext)s"
        }
        let folder = Self.sanitizeFolder(playlist.folder)
        return "\(dir)/\(folder)/\(prefix)%(title)s.%(ext)s"
    }

    /// Strip path separators / problem characters from a playlist name so it's a
    /// safe single folder component.
    private static func sanitizeFolder(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Playlist" : cleaned
    }

    private struct URLClassification {
        var isPlaylist: Bool        // download expands to multiple videos
        var forceSingleVideo: Bool  // a watch URL that also carries a list= param
    }

    /// Decide how to treat the URL:
    ///  - any real `list=` (playlist URL, or a watch URL opened from a playlist)
    ///    → download the whole playlist
    ///  - auto-generated radio/"Mix" lists (`RD…`) are effectively endless, so
    ///    those fall back to just the single video
    ///  - no list → single video
    private func classify(url: String) -> URLClassification {
        let listValue = Self.queryValue("list", in: url) ?? ""
        let hasList = !listValue.isEmpty
        let isEndlessMix = listValue.uppercased().hasPrefix("RD")
        let downloadPlaylist = hasList && !isEndlessMix
        return URLClassification(
            isPlaylist: downloadPlaylist,
            forceSingleVideo: hasList && !downloadPlaylist
        )
    }

    private static func queryValue(_ name: String, in url: String) -> String? {
        guard let comps = URLComponents(string: url) else { return nil }
        return comps.queryItems?.first { $0.name.lowercased() == name }?.value
    }

    private func outputTemplate(settings: AppSettings, isPlaylist: Bool) -> String {
        let dir = settings.downloadDirectory.path
        if isPlaylist && settings.playlistSubfolder {
            return "\(dir)/%(playlist_title)s/%(playlist_index)02d - %(title)s.%(ext)s"
        }
        return "\(dir)/%(title)s.%(ext)s"
    }

    // MARK: - Output processing

    private func processChunk(_ data: Data, _ onEvent: @escaping (YTDLPEvent) -> Void) {
        buffer.append(data)
        // Treat CR the same as LF so carriage-return progress updates split too.
        var normalized = buffer
        for i in normalized.indices where normalized[i] == 0x0D { normalized[i] = 0x0A }

        let segments = normalized.split(separator: 0x0A, omittingEmptySubsequences: false)
        guard segments.count > 1 else { return }   // no complete line yet

        for seg in segments.dropLast() {
            emit(Data(seg), onEvent)
        }
        buffer = segments.last.map(Data.init) ?? Data()
    }

    private func flushRemainder(_ onEvent: @escaping (YTDLPEvent) -> Void) {
        guard !buffer.isEmpty else { return }
        emit(buffer, onEvent)
        buffer.removeAll()
    }

    private func emit(_ lineData: Data, _ onEvent: @escaping (YTDLPEvent) -> Void) {
        guard let line = String(data: lineData, encoding: .utf8) else { return }
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let event = ProgressParser.parse(line)
        if case .other = event { return }
        DispatchQueue.main.async { onEvent(event) }
    }
}
