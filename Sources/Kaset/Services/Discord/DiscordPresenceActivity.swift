import Foundation

// MARK: - DiscordPresenceSnapshot

/// What Kaset is playing right now, reduced to what Discord can show.
///
/// `Equatable` on purpose: the service only talks to Discord when this changes,
/// which keeps us well inside Discord's rate limit (5 updates per 20 seconds).
/// `elapsed` is deliberately absent — it advances every second and would defeat
/// that. The progress bar comes from the start timestamp instead.
struct DiscordPresenceSnapshot: Equatable, Sendable {
    var title: String
    var artist: String?
    var artworkURL: URL?
    var isPlaying: Bool
    var duration: TimeInterval
    var isVideo: Bool
    /// Wall-clock instant the current track started, derived from elapsed time.
    /// Rounded to a second so ordinary clock jitter is not a "change".
    var startedAt: Date?
}

// MARK: - DiscordPresenceActivity

/// Builds the `SET_ACTIVITY` payload. Pure and separate from the socket so the
/// shape can be tested without Discord running.
enum DiscordPresenceActivity {
    /// Discord rejects strings outside 2...128 bytes in these fields, and
    /// silently drops the whole activity if one is out of range.
    static let minimumFieldLength = 2
    static let maximumFieldLength = 128

    /// Activity type 2 renders as "Listening to <app>" rather than "Playing".
    static let listeningType = 2
    static let watchingType = 3

    static func payload(for snapshot: DiscordPresenceSnapshot) -> [String: Any] {
        var activity: [String: Any] = [
            "type": snapshot.isVideo ? Self.watchingType : Self.listeningType,
        ]

        if let details = Self.clamped(snapshot.title) {
            activity["details"] = details
        }
        if let state = snapshot.artist.flatMap(Self.clamped) {
            activity["state"] = state
        }

        // Only a playing track gets timestamps; a paused one would otherwise
        // show a progress bar that keeps advancing while nothing plays.
        if snapshot.isPlaying, let startedAt = snapshot.startedAt {
            var timestamps: [String: Any] = ["start": Int(startedAt.timeIntervalSince1970 * 1000)]
            if snapshot.duration > 0 {
                let end = startedAt.addingTimeInterval(snapshot.duration)
                timestamps["end"] = Int(end.timeIntervalSince1970 * 1000)
            }
            activity["timestamps"] = timestamps
        }

        var assets: [String: Any] = [:]
        if let artwork = snapshot.artworkURL?.absoluteString, artwork.count <= 256 {
            assets["large_image"] = artwork
        }
        if let large = Self.clamped(snapshot.title) {
            assets["large_text"] = large
        }
        if !snapshot.isPlaying {
            assets["small_text"] = String(localized: "Paused", comment: "Discord presence hover text")
        }
        if !assets.isEmpty {
            activity["assets"] = assets
        }

        return activity
    }

    /// Trims to Discord's byte window, padding a too-short value rather than
    /// letting the whole activity be rejected for a one-character title.
    static func clamped(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.utf8.count < Self.minimumFieldLength {
            return trimmed + " "
        }
        guard trimmed.utf8.count > Self.maximumFieldLength else { return trimmed }
        // Budget for the ellipsis itself: "…" is three UTF-8 bytes, not one.
        let ellipsis = "…"
        let budget = Self.maximumFieldLength - ellipsis.utf8.count
        var truncated = trimmed
        while truncated.utf8.count > budget, !truncated.isEmpty {
            truncated.removeLast()
        }
        return truncated + ellipsis
    }

    /// KasetPlus's own Discord application, shared by every user — this is how
    /// Discord presence is meant to work. The ID is a public identifier, not a
    /// credential (comparable to a bundle ID), and the application's name is
    /// what Discord prints on the profile, so a shared one is exactly what puts
    /// "KasetPlus" there rather than each user's own invented name. Every
    /// comparable client does the same; th-ch/youtube-music, for instance,
    /// ships `export const clientId = '1177081335727267940'`.
    ///
    /// KasetPlus's registered application; Discord prints its name, "KasetPlus",
    /// on the profile. Public identifier, safe in a public repo. (The
    /// application's *public key* is only for verifying interaction webhooks —
    /// slash commands and the like — which Rich Presence does not use, so it is
    /// deliberately not stored anywhere in this repo.)
    static let defaultApplicationID = "1550196014063943710"

    /// The ID actually used: a user override when given, otherwise the built-in
    /// one. Trimmed, because pasting from the portal often brings whitespace.
    static func effectiveApplicationID(override: String) -> String? {
        let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isValidApplicationID(trimmed) { return trimmed }
        guard trimmed.isEmpty, Self.isValidApplicationID(Self.defaultApplicationID) else { return nil }
        return Self.defaultApplicationID
    }

    /// Whether a built-in application exists, i.e. whether the Settings field is
    /// an optional override or the only way to make the feature work.
    static var hasDefaultApplicationID: Bool {
        Self.isValidApplicationID(Self.defaultApplicationID)
    }

    /// A Discord Application ID is a snowflake: 17-20 digits.
    static func isValidApplicationID(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return (17 ... 20).contains(trimmed.count) && trimmed.allSatisfy(\.isNumber)
    }
}
