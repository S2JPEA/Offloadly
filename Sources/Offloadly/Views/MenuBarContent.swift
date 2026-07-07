import SwiftUI
import AppKit

/// The menu shown from the menu-bar icon: quick paste-and-download plus window
/// controls, so you can grab a link without bringing the app forward first.
struct MenuBarContent: View {
    @EnvironmentObject private var manager: DownloadManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Paste Link & Download") { pasteAndDownload() }
            .keyboardShortcut("v", modifiers: [.command, .shift])

        if activeCount > 0 {
            Divider()
            Text("\(activeCount) downloading…")
        }

        Divider()

        Button("Open Offloadly") { showWindow() }
        Button("Quit Offloadly") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var activeCount: Int {
        manager.items.filter { !$0.state.isTerminal }.count
    }

    private func pasteAndDownload() {
        if let url = DownloadManager.youTubeURLFromClipboard() {
            manager.enqueue(url)
        } else if let text = NSPasteboard.general.string(forType: .string) {
            manager.enqueue(text)
        }
        showWindow()
    }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
