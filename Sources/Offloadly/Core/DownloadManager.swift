import Foundation
import AppKit

/// Owns the download queue: validates URLs, expands playlists/channels into
/// per-video items, enforces the concurrency limit, and translates yt-dlp
/// events into live model updates.
@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var items: [DownloadItem] = []
    /// Non-nil when a required tool is missing; surfaced as a banner in the UI.
    @Published var dependencyWarning: String?
    /// Number of playlist/channel URLs currently being resolved (for a spinner).
    @Published private(set) var resolvingCount = 0
    /// A large playlist/channel awaiting the user's confirm/cap choice.
    @Published var pendingConfirmation: PendingBatch?
    /// A YouTube link found on the clipboard, offered as a one-tap add.
    @Published var clipboardSuggestion: String?

    private let settings: AppSettings
    private var runners: [UUID: YTDLPRunner] = [:]
    private var lastError: [UUID: String] = [:]
    private var activeCount = 0
    private var lastClipboardSuggestion: String?

    /// Ask before expanding a batch bigger than this.
    private let largePlaylistThreshold = 20
    /// Default "download first N" cap offered for large batches.
    private let largePlaylistCap = 20

    struct PendingBatch: Identifiable {
        let id = UUID()
        let info: PlaylistInfo
        let cap: Int
        var count: Int { info.entries.count }
        var title: String { info.title }
    }

    init(settings: AppSettings) {
        self.settings = settings
        let missing = BinaryLocator.missingDependencies()
        if !missing.isEmpty {
            dependencyWarning = "Missing \(missing.joined(separator: " and "))."
                + " Install with: brew install \(missing.joined(separator: " "))"
        }
        Notifier.requestAuthorization()
    }

    var hasCompletedItems: Bool {
        items.contains { $0.state == .completed }
    }

    var hasCancellableItems: Bool {
        items.contains { !$0.state.isTerminal }
    }

    var isResolving: Bool { resolvingCount > 0 }

    // MARK: - Enqueue

    func enqueue(_ rawURL: String) {
        guard let url = Self.normalizedURL(rawURL) else { return }

        // Single video → download directly. Playlist/channel → resolve first.
        guard Self.isBatchURL(url), let ytDlp = BinaryLocator.ytDlp() else {
            addSingle(url)
            return
        }

        resolvingCount += 1
        PlaylistEnumerator.enumerate(url: url, ytDlp: ytDlp) { [weak self] info in
            guard let self else { return }
            self.resolvingCount = max(0, self.resolvingCount - 1)
            guard let info, !info.entries.isEmpty else {
                // Not actually a playlist, or enumeration failed → treat as single.
                self.addSingle(url)
                return
            }
            if info.entries.count > self.largePlaylistThreshold {
                self.pendingConfirmation = PendingBatch(info: info, cap: self.largePlaylistCap)
            } else {
                self.addBatch(info.entries, playlistTitle: info.title)
            }
        }
    }

    private func addSingle(_ url: String) {
        items.insert(DownloadItem(url: url), at: 0)
        startNextIfPossible()
    }

    func addBatch(_ entries: [PlaylistEntry], playlistTitle: String) {
        let total = entries.count
        let newItems = entries.enumerated().map { offset, entry in
            DownloadItem(
                url: entry.videoURL,
                title: entry.title,
                playlistTitle: playlistTitle,
                playlistIndex: offset + 1,
                playlistCount: total
            )
        }
        items.insert(contentsOf: newItems, at: 0)
        startNextIfPossible()
    }

    // MARK: - Item operations

    func cancel(_ item: DownloadItem) {
        if let runner = runners[item.id] {
            runner.cancel()
        } else if !item.state.isTerminal {
            item.state = .canceled
            reorder()
            updateBadge()
        }
    }

    func cancelAll() {
        for item in items where !item.state.isTerminal {
            cancel(item)
        }
    }

    func pause(_ item: DownloadItem) {
        if let runner = runners[item.id] {
            runner.pause()              // finish() marks it .paused, keeping partials
        } else if item.state == .queued {
            item.state = .paused
            reorder()
            updateBadge()
        }
    }

    func resume(_ item: DownloadItem) {
        guard item.state == .paused else { return }
        item.state = .queued
        startNextIfPossible()
    }

    func retry(_ item: DownloadItem) {
        guard item.state.isTerminal else { return }
        resetProgress(item)
        item.state = .queued
        lastError[item.id] = nil
        startNextIfPossible()
    }

    func remove(_ item: DownloadItem) {
        runners[item.id]?.cancel()
        runners[item.id] = nil
        items.removeAll { $0.id == item.id }
        updateBadge()
    }

    func clearCompleted() {
        items.removeAll { $0.state == .completed }
    }

    func revealInFinder(_ item: DownloadItem) {
        guard let path = item.outputPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - Clipboard suggestion

    func checkClipboard() {
        guard let url = Self.youTubeURLFromClipboard() else { return }
        guard url != lastClipboardSuggestion else { return }
        guard !items.contains(where: { $0.url == url }) else { return }
        lastClipboardSuggestion = url
        clipboardSuggestion = url
    }

    func acceptClipboardSuggestion() {
        if let url = clipboardSuggestion { enqueue(url) }
        clipboardSuggestion = nil
    }

    func dismissClipboardSuggestion() {
        clipboardSuggestion = nil
    }

    // MARK: - Scheduling

    private func startNextIfPossible() {
        while activeCount < max(1, settings.maxConcurrent),
              let next = items.first(where: { $0.state == .queued }) {
            start(next)
        }
        reorder()
        updateBadge()
    }

    /// Keep active downloads at the top: active → queued → paused → finished,
    /// preserving creation order within each group.
    private func reorder() {
        items.sort { lhs, rhs in
            let rl = Self.rank(lhs.state), rr = Self.rank(rhs.state)
            return rl != rr ? rl < rr : lhs.seq < rhs.seq
        }
    }

    private static func rank(_ state: DownloadState) -> Int {
        switch state {
        case .fetchingInfo, .downloading, .merging: return 0
        case .queued: return 1
        case .paused: return 2
        case .completed: return 3
        case .failed, .canceled: return 4
        }
    }

    private func start(_ item: DownloadItem) {
        guard let ytDlp = BinaryLocator.ytDlp() else {
            item.state = .failed("yt-dlp not found")
            return
        }
        let ffmpeg = BinaryLocator.ffmpeg()
        let runner = YTDLPRunner()
        runners[item.id] = runner
        activeCount += 1
        item.state = .fetchingInfo

        let playlist = item.playlistTitle.map {
            YTDLPRunner.PlaylistContext(folder: $0, index: item.playlistIndex ?? 1)
        }

        runner.start(
            url: item.url,
            settings: settings,
            ytDlp: ytDlp,
            ffmpeg: ffmpeg,
            playlist: playlist,
            onEvent: { [weak self, weak item] event in
                MainActor.assumeIsolated {
                    guard let self, let item else { return }
                    self.handle(event, for: item)
                }
            },
            onFinish: { [weak self, weak item] status in
                MainActor.assumeIsolated {
                    guard let self, let item else { return }
                    self.finish(item, runner: runner, status: status)
                }
            }
        )
    }

    // MARK: - Event handling

    private func handle(_ event: YTDLPEvent, for item: DownloadItem) {
        switch event {
        case .fetchingInfo:
            if item.state == .queued || item.state == .fetchingInfo {
                item.state = .fetchingInfo
            }
        case .playlistItem(let index, let count):
            item.playlistIndex = index
            item.playlistCount = count
        case .progress(let percent, let speed, let eta, let title):
            if item.state != .merging { item.state = .downloading }
            item.percent = percent
            item.speed = speed
            item.eta = eta
            if let title, !title.isEmpty { item.title = title }
        case .destination(let path):
            item.outputPath = path
        case .merging(let path):
            item.state = .merging
            if let path { item.outputPath = path }
        case .alreadyDownloaded(let path):
            item.outputPath = path
            item.percent = 1
        case .error(let msg):
            lastError[item.id] = msg
        case .other:
            break
        }
    }

    private func finish(_ item: DownloadItem, runner: YTDLPRunner, status: Int32) {
        activeCount = max(0, activeCount - 1)
        runners[item.id] = nil

        if runner.wasPaused {
            item.state = .paused
        } else if runner.wasCanceled {
            item.state = .canceled
        } else if status == 0 {
            item.state = .completed
            item.percent = 1
            item.speed = ""
            item.eta = ""
            // One notification per standalone video (playlists would spam).
            if item.playlistTitle == nil {
                Notifier.downloadFinished(title: item.title)
            }
        } else {
            item.state = .failed(FriendlyError.map(lastError[item.id]))
        }
        startNextIfPossible()
    }

    private func resetProgress(_ item: DownloadItem) {
        item.percent = 0
        item.speed = ""
        item.eta = ""
    }

    // MARK: - Dock badge

    private func updateBadge() {
        let count = items.filter { $0.state == .queued || $0.state.isActive }.count
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    // MARK: - URL classification / validation

    /// A URL that expands to multiple videos (playlist page, a watch URL with a
    /// real `list=`, or a channel) and should be enumerated before downloading.
    static func isBatchURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        let listValue = URLComponents(string: url)?
            .queryItems?.first { $0.name.lowercased() == "list" }?.value ?? ""
        let hasRealList = !listValue.isEmpty && !listValue.uppercased().hasPrefix("RD")
        let isChannel = lower.contains("/@") || lower.contains("/channel/")
            || lower.contains("/c/") || lower.contains("/user/")
        let isPlaylistPage = lower.contains("/playlist")
        let isWatch = lower.contains("watch?v=")
        return hasRealList || isPlaylistPage || (isChannel && !isWatch)
    }

    static func normalizedURL(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.lowercased().hasPrefix("http") {
            s = "https://" + s
        }
        guard let comps = URLComponents(string: s),
              let host = comps.host,
              host.contains(".") else { return nil }
        return s
    }

    /// Returns a YouTube-looking URL from the clipboard, if present.
    static func youTubeURLFromClipboard() -> String? {
        guard let text = NSPasteboard.general.string(forType: .string) else { return nil }
        guard let url = normalizedURL(text) else { return nil }
        let lower = url.lowercased()
        guard lower.contains("youtube.com") || lower.contains("youtu.be") else { return nil }
        return url
    }
}
