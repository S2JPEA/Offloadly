import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var updater: YTDLPUpdater

    var body: some View {
        Form {
            Section("Downloads") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Save to")
                        Text(settings.downloadDirectory.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Choose…", action: chooseFolder)
                }

                Picker("Quality", selection: $settings.quality) {
                    ForEach(DownloadQuality.allCases) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }

                Stepper(
                    "Simultaneous downloads: \(settings.maxConcurrent)",
                    value: $settings.maxConcurrent,
                    in: 1...5
                )
            }

            Section("Options") {
                Toggle("Put each playlist in its own folder", isOn: $settings.playlistSubfolder)
                Toggle("Remove sponsor segments (SponsorBlock)", isOn: $settings.removeSponsorSegments)
            }

            Section("Downloader (yt-dlp)") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version \(updater.installedVersion ?? "—")")
                        Text(updateSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        updater.updateNow()
                    } label: {
                        if updater.isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Update Now")
                        }
                    }
                    .disabled(updater.isBusy)
                }
                Text("YouTube changes often; keeping yt-dlp updated keeps downloads working. Source builds use the yt-dlp installed on your Mac, so update it with Homebrew.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var updateSubtitle: String {
        if !updater.status.label.isEmpty {
            return updater.status.label
        }
        if let last = updater.lastChecked {
            let formatter = RelativeDateTimeFormatter()
            return "Checked \(formatter.localizedString(for: last, relativeTo: Date()))"
        }
        return "Not checked yet"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = settings.downloadDirectory
        if panel.runModal() == .OK, let url = panel.url {
            settings.downloadDirectory = url
        }
    }
}
