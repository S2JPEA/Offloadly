import SwiftUI

/// The top input bar: paste/type a URL and hit Return (or the button) to
/// enqueue. Also offers a one-click grab from the clipboard.
struct PasteBar: View {
    @EnvironmentObject private var manager: DownloadManager
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)

            TextField("Paste a YouTube video or playlist link…", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(add)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Button("Download", action: add)
                .keyboardShortcut(.defaultAction)
                .disabled(DownloadManager.normalizedURL(text) == nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onAppear { focused = true }
    }

    private func add() {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard DownloadManager.normalizedURL(candidate) != nil else { return }
        manager.enqueue(candidate)
        text = ""
        focused = true
    }
}
