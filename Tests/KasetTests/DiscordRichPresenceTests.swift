import Foundation
import Testing
@testable import KasetPlus

// MARK: - DiscordRichPresenceTests

/// The IPC wire format and the activity payload, tested without Discord running.
@Suite("Discord Rich Presence", .tags(.service))
struct DiscordRichPresenceTests {
    // MARK: - Framing

    @Test("A frame is an 8-byte little-endian header followed by the body")
    func frameEncoding() throws {
        let body = Data(#"{"v":1}"#.utf8)
        let frame = DiscordIPCClient.encodeFrame(opcode: .handshake, body: body)

        #expect(frame.count == 8 + body.count)
        #expect(Array(frame.prefix(4)) == [0, 0, 0, 0])
        #expect(Array(frame[4 ..< 8]) == [UInt8(body.count), 0, 0, 0])
        #expect(frame.suffix(body.count) == body)
    }

    @Test("Frame opcodes round-trip through the header")
    func headerRoundTrip() throws {
        let frame = DiscordIPCClient.encodeFrame(opcode: .frame, body: Data(repeating: 0x7B, count: 300))
        let header = try #require(DiscordIPCClient.decodeHeader(frame.prefix(8)))

        #expect(header.opcode == DiscordIPCClient.Opcode.frame.rawValue)
        #expect(header.length == 300)
    }

    @Test("An implausible frame length is rejected rather than allocated")
    func oversizedHeaderIsRejected() {
        var header = Data()
        withUnsafeBytes(of: UInt32(1).littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32.max.littleEndian) { header.append(contentsOf: $0) }

        #expect(DiscordIPCClient.decodeHeader(header) == nil)
    }

    @Test("A short header is rejected")
    func shortHeaderIsRejected() {
        #expect(DiscordIPCClient.decodeHeader(Data([0, 0, 0, 0])) == nil)
    }

    @Test("Socket candidates cover Discord's ten IPC slots in the user temp dir")
    func socketCandidates() {
        let paths = DiscordIPCClient.socketPaths()

        #expect(paths.count == 10)
        #expect(paths.first?.hasSuffix("discord-ipc-0") == true)
        #expect(paths.last?.hasSuffix("discord-ipc-9") == true)
        #expect(paths.allSatisfy { $0.hasPrefix(NSTemporaryDirectory()) })
    }

    // MARK: - Activity payload

    private static func snapshot(
        title: String = "A Song",
        artist: String? = "An Artist",
        isPlaying: Bool = true,
        duration: TimeInterval = 180,
        isVideo: Bool = false,
        startedAt: Date? = Date(timeIntervalSince1970: 1_000_000)
    ) -> DiscordPresenceSnapshot {
        DiscordPresenceSnapshot(
            title: title,
            artist: artist,
            artworkURL: URL(string: "https://example.com/art.jpg"),
            isPlaying: isPlaying,
            duration: duration,
            isVideo: isVideo,
            startedAt: startedAt
        )
    }

    @Test("Music is published as a Listening activity, video as Watching")
    func activityType() {
        let music = DiscordPresenceActivity.payload(for: Self.snapshot())
        let video = DiscordPresenceActivity.payload(for: Self.snapshot(isVideo: true))

        #expect(music["type"] as? Int == DiscordPresenceActivity.listeningType)
        #expect(video["type"] as? Int == DiscordPresenceActivity.watchingType)
    }

    @Test("A playing track carries start and end timestamps in milliseconds")
    func playingCarriesTimestamps() throws {
        let payload = DiscordPresenceActivity.payload(for: Self.snapshot())
        let timestamps = try #require(payload["timestamps"] as? [String: Any])

        #expect(timestamps["start"] as? Int == 1_000_000_000)
        #expect(timestamps["end"] as? Int == 1_000_180_000)
    }

    @Test("A paused track carries no timestamps, so no bar keeps advancing")
    func pausedDropsTimestamps() {
        let payload = DiscordPresenceActivity.payload(for: Self.snapshot(isPlaying: false))

        #expect(payload["timestamps"] == nil)
    }

    @Test("A track with unknown duration gets a start but no end")
    func unknownDurationOmitsEnd() throws {
        let payload = DiscordPresenceActivity.payload(for: Self.snapshot(duration: 0))
        let timestamps = try #require(payload["timestamps"] as? [String: Any])

        #expect(timestamps["start"] != nil)
        #expect(timestamps["end"] == nil)
    }

    @Test("The payload survives JSON serialization")
    func payloadIsSerializable() throws {
        let payload = DiscordPresenceActivity.payload(for: Self.snapshot())

        #expect(JSONSerialization.isValidJSONObject(payload))
        #expect(throws: Never.self) { try JSONSerialization.data(withJSONObject: payload) }
    }

    // MARK: - Field clamping

    @Test("A too-long field is truncated inside Discord's 128-byte window")
    func longFieldIsTruncated() throws {
        let clamped = try #require(DiscordPresenceActivity.clamped(String(repeating: "a", count: 400)))

        #expect(clamped.utf8.count <= DiscordPresenceActivity.maximumFieldLength)
        #expect(clamped.hasSuffix("…"))
    }

    @Test("A one-character field is padded rather than dropping the activity")
    func shortFieldIsPadded() throws {
        let clamped = try #require(DiscordPresenceActivity.clamped("A"))

        #expect(clamped.utf8.count >= DiscordPresenceActivity.minimumFieldLength)
    }

    @Test("An empty or whitespace field yields nil", arguments: ["", "   ", "\n"])
    func emptyFieldIsNil(value: String) {
        #expect(DiscordPresenceActivity.clamped(value) == nil)
    }

    // MARK: - Application ID

    @Test("A snowflake-shaped Application ID is accepted", arguments: [
        "123456789012345678", "12345678901234567", "12345678901234567890",
    ])
    func validApplicationID(value: String) {
        #expect(DiscordPresenceActivity.isValidApplicationID(value))
    }

    @Test("Anything else is rejected", arguments: [
        "", "abc", "1234", "12345678901234567890123", "1234567890123456a",
    ])
    func invalidApplicationID(value: String) {
        #expect(!DiscordPresenceActivity.isValidApplicationID(value))
    }

    @Test("A user override wins over the built-in application")
    func overrideWinsOverDefault() {
        #expect(DiscordPresenceActivity.effectiveApplicationID(override: "123456789012345678")
            == "123456789012345678")
        // Pasting from the portal routinely brings whitespace along.
        #expect(DiscordPresenceActivity.effectiveApplicationID(override: "  123456789012345678\n")
            == "123456789012345678")
    }

    @Test("A blank override falls back to the built-in application, if there is one")
    func blankOverrideUsesDefault() {
        let effective = DiscordPresenceActivity.effectiveApplicationID(override: "   ")

        if DiscordPresenceActivity.hasDefaultApplicationID {
            #expect(effective == DiscordPresenceActivity.defaultApplicationID)
        } else {
            // No application registered for the project yet: the feature stays
            // inert rather than handshaking with a bogus ID.
            #expect(effective == nil)
        }
    }

    @Test("A malformed override never silently falls back to the built-in one")
    func malformedOverrideIsNotIgnored() {
        // Falling back here would connect as KasetPlus while the user believes
        // they are using their own application — confusing, and it hides typos.
        #expect(DiscordPresenceActivity.effectiveApplicationID(override: "not-an-id") == nil)
        #expect(DiscordPresenceActivity.effectiveApplicationID(override: "1234") == nil)
    }

    @Test("The built-in application ID, when set, is a valid snowflake")
    func defaultApplicationIDIsWellFormed() {
        // Guards the one-line edit that lands the real ID: a typo there would
        // otherwise only show up as a silent handshake rejection at runtime.
        let value = DiscordPresenceActivity.defaultApplicationID
        #expect(value.isEmpty || DiscordPresenceActivity.isValidApplicationID(value))
    }

    // MARK: - Snapshot throttling

    @Test("The start instant is stable across ticks of the same track")
    func startInstantIsStable() throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        // Four seconds later, four seconds further into the track: same start.
        let first = try #require(DiscordRichPresenceService.startInstant(
            elapsed: 10, isPlaying: true, now: base
        ))
        let second = try #require(DiscordRichPresenceService.startInstant(
            elapsed: 14, isPlaying: true, now: base.addingTimeInterval(4)
        ))

        #expect(first == second)
    }

    @Test("A seek moves the start instant, so the presence updates")
    func seekMovesStartInstant() throws {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let before = try #require(DiscordRichPresenceService.startInstant(elapsed: 10, isPlaying: true, now: base))
        let after = try #require(DiscordRichPresenceService.startInstant(elapsed: 90, isPlaying: true, now: base))

        #expect(before != after)
    }

    @Test("A paused or nonsensical elapsed time yields no start instant")
    func noStartInstantWhenPaused() {
        #expect(DiscordRichPresenceService.startInstant(elapsed: 10, isPlaying: false) == nil)
        #expect(DiscordRichPresenceService.startInstant(elapsed: .nan, isPlaying: true) == nil)
        #expect(DiscordRichPresenceService.startInstant(elapsed: -5, isPlaying: true) == nil)
    }
}
