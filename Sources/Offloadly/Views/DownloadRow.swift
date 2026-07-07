import SwiftUI

struct DownloadRow: View {
    @ObservedObject var item: DownloadItem
    @EnvironmentObject private var manager: DownloadManager

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            thumbnail
                .overlay(alignment: .bottomTrailing) {
                    statusIcon
                        .font(.caption2)
                        .padding(2)
                        .background(.thinMaterial, in: Circle())
                        .padding(2)
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .font(.body)

                progressArea

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            actionButtons
        }
        .padding(.vertical, 2)
    }

    // MARK: - Pieces

    private var thumbnail: some View {
        Group {
            if let url = item.thumbnailURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholderThumb
                    }
                }
            } else {
                placeholderThumb
            }
        }
        .frame(width: 60, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var placeholderThumb: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(.quaternary)
            .overlay(
                Image(systemName: item.isPlaylistInProgress ? "list.and.film" : "film")
                    .foregroundStyle(.secondary)
            )
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.state {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .canceled:
            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
        case .merging:
            Image(systemName: "square.stack.3d.up").foregroundStyle(.blue)
        case .paused:
            Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
        case .fetchingInfo, .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .downloading:
            Image(systemName: "arrow.down.circle").foregroundStyle(.blue)
        }
    }

    @ViewBuilder
    private var progressArea: some View {
        switch item.state {
        case .downloading, .merging:
            if item.state == .merging {
                ProgressView().progressViewStyle(.linear)
            } else {
                ProgressView(value: item.percent)
                    .progressViewStyle(.linear)
            }
        case .paused:
            ProgressView(value: item.percent).progressViewStyle(.linear).tint(.orange)
        case .fetchingInfo, .queued:
            ProgressView(value: 0).progressViewStyle(.linear).opacity(0.35)
        case .completed:
            ProgressView(value: 1).progressViewStyle(.linear).tint(.green)
        case .failed, .canceled:
            ProgressView(value: item.percent).progressViewStyle(.linear).tint(.gray)
        }
    }

    private var subtitle: String {
        var parts: [String] = []

        if item.isPlaylistInProgress, let i = item.playlistIndex, let c = item.playlistCount {
            parts.append("Item \(i) of \(c)")
        }

        switch item.state {
        case .downloading:
            parts.append("\(Int(item.percent * 100))%")
            if !item.speed.isEmpty { parts.append(item.speed) }
            if !item.eta.isEmpty { parts.append("ETA \(item.eta)") }
        default:
            parts.append(item.state.label)
        }
        return parts.joined(separator: "  ·  ")
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch item.state {
        case .completed:
            if item.outputPath != nil {
                iconButton("magnifyingglass", help: "Reveal in Finder") {
                    manager.revealInFinder(item)
                }
            }
            iconButton("xmark", help: "Remove") { manager.remove(item) }
        case .failed, .canceled:
            iconButton("arrow.clockwise", help: "Retry") { manager.retry(item) }
            iconButton("xmark", help: "Remove") { manager.remove(item) }
        case .paused:
            iconButton("play.fill", help: "Resume") { manager.resume(item) }
            iconButton("xmark", help: "Remove") { manager.remove(item) }
        default:
            iconButton("pause.fill", help: "Pause") { manager.pause(item) }
            iconButton("stop.fill", help: "Cancel") { manager.cancel(item) }
        }
    }

    private func iconButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}
