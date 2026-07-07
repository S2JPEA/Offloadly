import SwiftUI
import AppKit

@main
struct OffloadlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: AppSettings
    @StateObject private var manager: DownloadManager
    @StateObject private var updater = YTDLPUpdater()

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _manager = StateObject(wrappedValue: DownloadManager(settings: settings))
    }

    var body: some Scene {
        Window("Downloads", id: "main") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(manager)
                .environmentObject(updater)
                .frame(minWidth: 560, minHeight: 440)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add from Clipboard") {
                    if let url = DownloadManager.youTubeURLFromClipboard() {
                        manager.enqueue(url)
                    }
                }
                .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra("Offloadly", systemImage: "arrow.down.circle.fill") {
            MenuBarContent()
                .environmentObject(manager)
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environmentObject(updater)
        }
    }
}

/// Ensures the app behaves as a normal foreground GUI app when launched from a
/// hand-assembled bundle (rather than an Xcode target).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in the menu bar when the window is closed.
        false
    }
}
