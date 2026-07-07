import Foundation

/// Resolves the paths to the `yt-dlp` and `ffmpeg` executables.
///
/// Resolution order (first hit wins):
///   1. Explicit override via environment variable (handy for `swift run`).
///   2. Preferred paths — for yt-dlp, a self-updating copy in Application
///      Support when the app was built with a bundled seed.
///   3. Bundled copy in the app's Resources, when a local builder includes one.
///   4. Common Homebrew / system locations.
///   5. `PATH` lookup via `/usr/bin/env`.
enum BinaryLocator {
    static func ytDlp() -> URL? {
        locate(
            name: "yt-dlp",
            envKey: "OFFLOADLY_YTDLP_PATH",
            preferred: [YTDLPUpdater.managedBinaryURL],
            commonPaths: [
                "/opt/homebrew/bin/yt-dlp",
                "/usr/local/bin/yt-dlp"
            ]
        )
    }

    static func ffmpeg() -> URL? {
        locate(
            name: "ffmpeg",
            envKey: "OFFLOADLY_FFMPEG_PATH",
            commonPaths: [
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg"
            ]
        )
    }

    /// True when both required tools were found.
    static func missingDependencies() -> [String] {
        var missing: [String] = []
        if ytDlp() == nil { missing.append("yt-dlp") }
        if ffmpeg() == nil { missing.append("ffmpeg") }
        return missing
    }

    // MARK: - Private

    private static func locate(
        name: String,
        envKey: String,
        preferred: [URL] = [],
        commonPaths: [String]
    ) -> URL? {
        let fm = FileManager.default

        if let override = ProcessInfo.processInfo.environment[envKey],
           fm.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        for url in preferred where fm.isExecutableFile(atPath: url.path) {
            return url
        }

        if let bundled = Bundle.main.resourceURL?.appendingPathComponent(name),
           fm.isExecutableFile(atPath: bundled.path) {
            return bundled
        }

        for path in commonPaths where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        if let found = whichLookup(name) { return found }
        return nil
    }

    private static func whichLookup(_ name: String) -> URL? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }
}
