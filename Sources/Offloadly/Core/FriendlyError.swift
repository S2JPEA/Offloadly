import Foundation

/// Turns raw yt-dlp error text into a short, human message for the UI.
enum FriendlyError {
    static func map(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Download failed" }
        let lower = raw.lowercased()

        if lower.contains("confirm your age") || lower.contains("age-restricted")
            || lower.contains("inappropriate for some users") {
            return "Age-restricted — sign-in required"
        }
        if lower.contains("private video") || lower.contains("this video is private") {
            return "This video is private"
        }
        if lower.contains("members-only") || lower.contains("join this channel") {
            return "Members-only video"
        }
        if lower.contains("not available in your country")
            || lower.contains("not available in your location")
            || lower.contains("geo") && lower.contains("restrict") {
            return "Not available in your region"
        }
        if lower.contains("premieres in") || lower.contains("this live event will begin")
            || lower.contains("premiere") {
            return "Premiere hasn't started yet"
        }
        if lower.contains("removed") || lower.contains("video unavailable")
            || lower.contains("has been terminated") {
            return "Video unavailable"
        }
        if lower.contains("sign in to confirm you’re not a bot")
            || lower.contains("sign in to confirm you're not a bot") {
            return "YouTube asked to verify you’re not a bot — try again later"
        }
        if lower.contains("unable to download") && lower.contains("network")
            || lower.contains("timed out") || lower.contains("connection")
            || lower.contains("getaddrinfo") {
            return "Network error — check your connection"
        }
        if lower.contains("requested format is not available") {
            return "Requested quality isn’t available for this video"
        }

        // Fall back to the first line of the raw error, trimmed to a sane length.
        let firstLine = raw.components(separatedBy: .newlines)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? raw
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        return trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed
    }
}
