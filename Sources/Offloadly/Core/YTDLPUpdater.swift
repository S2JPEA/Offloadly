import Foundation

/// Keeps yt-dlp current when the app was built with a bundled seed. Source
/// builds normally use a Homebrew/system yt-dlp instead; in that case we report
/// the installed version and leave updates to the package manager.
final class YTDLPUpdater: ObservableObject {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case updated(String)
        case external
        case failed(String)

        var label: String {
            switch self {
            case .idle: return ""
            case .checking: return "Checking for updates…"
            case .upToDate: return "Up to date"
            case .updated(let v): return "Updated to \(v)"
            case .external: return "Installed externally — update with Homebrew"
            case .failed(let m): return "Update failed — \(m)"
            }
        }
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var installedVersion: String?
    @Published private(set) var lastChecked: Date?
    @Published private(set) var isBusy = false

    private let workQueue = DispatchQueue(label: "com.offloadly.updater")
    private let defaults = UserDefaults.standard
    private let lastCheckKey = "ytDlpLastUpdateCheck"
    private let autoInterval: TimeInterval = 60 * 60 * 24  // once per day
    private var didLaunch = false

    /// Writable working copy of yt-dlp. `BinaryLocator` prefers this path.
    static let managedBinaryURL: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Offloadly/yt-dlp")
    }()

    // MARK: - Public entry points

    /// Run once at launch: seed the managed copy, read its version, and do a
    /// throttled background update check.
    func launch() {
        if didLaunch { return }
        didLaunch = true
        lastChecked = defaults.object(forKey: lastCheckKey) as? Date
        workQueue.async { [weak self] in
            guard let self else { return }
            self.seedIfNeeded()
            if FileManager.default.isExecutableFile(atPath: Self.managedBinaryURL.path) {
                let version = self.readVersion(at: Self.managedBinaryURL)
                self.publish { self.installedVersion = version }
                if self.isAutoCheckDue() {
                    self.performUpdate()
                }
            } else {
                self.publishExternalStatus()
            }
        }
    }

    /// User-initiated "Update Now".
    func updateNow() {
        workQueue.async { [weak self] in
            guard let self else { return }
            self.seedIfNeeded()
            if FileManager.default.isExecutableFile(atPath: Self.managedBinaryURL.path) {
                self.performUpdate()
            } else {
                self.publishExternalStatus()
            }
        }
    }

    // MARK: - Seeding

    private func seedIfNeeded() {
        let fm = FileManager.default
        let managed = Self.managedBinaryURL
        try? fm.createDirectory(at: managed.deletingLastPathComponent(),
                                withIntermediateDirectories: true)

        guard let bundled = Bundle.main.resourceURL?.appendingPathComponent("yt-dlp"),
              fm.isExecutableFile(atPath: bundled.path) else {
            return  // running without a bundle (dev) — fall back to system yt-dlp
        }

        if !fm.fileExists(atPath: managed.path) {
            copyExecutable(from: bundled, to: managed)
            return
        }

        // Re-seed if the app now ships a newer floor version than the working copy.
        if let bundledV = readVersion(at: bundled),
           let managedV = readVersion(at: managed),
           bundledV > managedV {   // yt-dlp versions are YYYY.MM.DD → lexical == chronological
            copyExecutable(from: bundled, to: managed)
        }
    }

    private func copyExecutable(from src: URL, to dst: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: dst)
        do {
            try fm.copyItem(at: src, to: dst)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst.path)
        } catch {
            publish { self.status = .failed("Could not install yt-dlp") }
        }
    }

    // MARK: - Updating

    private func performUpdate() {
        let managed = Self.managedBinaryURL
        guard FileManager.default.isExecutableFile(atPath: managed.path) else {
            publish { self.status = .failed("yt-dlp not installed") }
            return
        }

        publish {
            self.status = .checking
            self.isBusy = true
        }

        let (output, code) = runCapturing(managed, ["--update"])
        let newVersion = readVersion(at: managed)

        defaults.set(Date(), forKey: lastCheckKey)

        let resolved: Status
        if code != 0 {
            resolved = .failed(Self.firstMeaningfulLine(output) ?? "exit code \(code)")
        } else if output.localizedCaseInsensitiveContains("is up to date") {
            resolved = .upToDate
        } else if output.localizedCaseInsensitiveContains("Updated yt-dlp")
                    || output.localizedCaseInsensitiveContains("Updating to") {
            resolved = .updated(newVersion ?? "")
        } else {
            resolved = .upToDate
        }

        publish {
            self.installedVersion = newVersion
            self.lastChecked = Date()
            self.status = resolved
            self.isBusy = false
        }
    }

    private func publishExternalStatus() {
        let version = BinaryLocator.ytDlp().flatMap { readVersion(at: $0) }
        publish {
            self.installedVersion = version
            self.status = version == nil ? .failed("yt-dlp not installed") : .external
            self.isBusy = false
        }
    }

    // MARK: - Helpers

    private func isAutoCheckDue() -> Bool {
        guard let last = defaults.object(forKey: lastCheckKey) as? Date else { return true }
        return Date().timeIntervalSince(last) > autoInterval
    }

    private func readVersion(at url: URL) -> String? {
        guard FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        let (out, code) = runCapturing(url, ["--version"])
        guard code == 0 else { return nil }
        let v = out.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first ?? ""
        return v.isEmpty ? nil : v
    }

    /// Runs a tool, returns combined stdout+stderr and the exit code.
    private func runCapturing(_ url: URL, _ args: [String]) -> (String, Int32) {
        let process = Process()
        process.executableURL = url
        process.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"].map { "\($0):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" })
            ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return ("Could not launch: \(error.localizedDescription)", -1)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), process.terminationStatus)
    }

    private static func firstMeaningfulLine(_ output: String) -> String? {
        output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
    }

    private func publish(_ change: @escaping () -> Void) {
        DispatchQueue.main.async(execute: change)
    }
}
