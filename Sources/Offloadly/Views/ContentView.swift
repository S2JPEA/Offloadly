import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var manager: DownloadManager
    @EnvironmentObject private var updater: YTDLPUpdater

    var body: some View {
        VStack(spacing: 0) {
            PasteBar()

            if let warning = manager.dependencyWarning {
                DependencyBanner(message: warning)
            }
            if let suggestion = manager.clipboardSuggestion {
                ClipboardBanner(url: suggestion,
                                onAdd: manager.acceptClipboardSuggestion,
                                onDismiss: manager.dismissClipboardSuggestion)
            }
            if manager.isResolving {
                ResolvingBanner()
            }

            Divider()

            if manager.items.isEmpty {
                EmptyState()
            } else {
                downloadList
            }
        }
        .background(WindowAccessor(autosaveName: "OffloadlyMainWindow"))
        .onAppear {
            // Read/update yt-dlp state once at launch.
            updater.launch()
            // Test hook: auto-enqueue a URL on launch when asked to.
            if let testURL = ProcessInfo.processInfo.environment["OFFLOADLY_TEST_URL"],
               !testURL.isEmpty {
                manager.enqueue(testURL)
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            manager.checkClipboard()
        }
        .onDrop(of: [.url, .text], isTargeted: nil, perform: handleDrop)
        .confirmationDialog(
            confirmationTitle,
            isPresented: confirmationBinding,
            titleVisibility: .visible
        ) {
            if let batch = manager.pendingConfirmation {
                Button("Download All \(batch.count)") {
                    manager.pendingConfirmation = nil
                    manager.addBatch(batch.info.entries, playlistTitle: batch.title)
                }
                Button("Download First \(batch.cap)") {
                    manager.pendingConfirmation = nil
                    manager.addBatch(Array(batch.info.entries.prefix(batch.cap)),
                                     playlistTitle: batch.title)
                }
                Button("Cancel", role: .cancel) { manager.pendingConfirmation = nil }
            }
        } message: {
            if let batch = manager.pendingConfirmation {
                Text("“\(batch.title)” has \(batch.count)\(batch.info.truncated ? "+" : "") videos.")
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Cancel All") {
                    manager.cancelAll()
                }
                .disabled(!manager.hasCancellableItems)
                .help("Cancel all active and queued downloads")

                Button("Clear Completed") {
                    manager.clearCompleted()
                }
                .disabled(!manager.hasCompletedItems)
                .help("Remove finished downloads from the list")

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Choose download folder and quality")
            }
        }
    }

    private var confirmationTitle: String {
        (manager.pendingConfirmation?.info.isChannel ?? false)
            ? "Download this whole channel?"
            : "Download this whole playlist?"
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { manager.pendingConfirmation != nil },
            set: { if !$0 { manager.pendingConfirmation = nil } }
        )
    }

    /// Accept URLs (or plain-text URLs) dragged from a browser onto the window.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in manager.enqueue(url.absoluteString) }
                }
                handled = true
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text else { return }
                    Task { @MainActor in manager.enqueue(text) }
                }
                handled = true
            }
        }
        return handled
    }

    private var downloadList: some View {
        List {
            ForEach(manager.items) { item in
                DownloadRow(item: item)
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            }
        }
        .listStyle(.inset)
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 44, weight: .thin))
                .foregroundStyle(.secondary)
            Text("Paste a YouTube link above to start downloading")
                .foregroundStyle(.secondary)
            Text("Works with single videos and playlists")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DependencyBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.callout)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.12))
    }
}

private struct ClipboardBanner: View {
    let url: String
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(.blue)
            Text("Found a YouTube link in your clipboard")
                .font(.callout)
            Spacer()
            Button("Add", action: onAdd)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.blue.opacity(0.10))
    }
}

private struct ResolvingBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Resolving playlist…")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.secondary.opacity(0.06))
    }
}

/// Bridges to the hosting NSWindow so we can persist its frame across launches.
private struct WindowAccessor: NSViewRepresentable {
    let autosaveName: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName(autosaveName)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
