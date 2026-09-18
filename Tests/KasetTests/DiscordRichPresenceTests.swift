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

    /// Discord answers every command, and an undrained receive buffer stops it
    /// from reading ours: measured against a live Discord, the queue saturates
    /// at ~8 KB and every later presence update goes into a connection that no
    /// longer listens, with `write` still reporting success.
    @Test("Draining empties a backed-up receive buffer without blocking")
    func drainEmptiesTheReceiveBuffer() throws {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        let (ours, discord) = (descriptors[0], descriptors[1])
        defer { close(ours); close(discord) }

        // More than one read's worth, so the drain loop has to iterate.
        let responses = [UInt8](repeating: 0x7B, count: 6000)
        #expect(responses.withUnsafeBytes { write(discord, $0.baseAddress, $0.count) } == 6000)

        #expect(DiscordIPCClient.drain(descriptor: ours) == .open)

        var leftover: UInt8 = 0
        #expect(recv(ours, &leftover, 1, MSG_DONTWAIT) == -1)
        #expect(errno == EAGAIN || errno == EWOULDBLOCK)
    }

    @Test("Draining reports a closed peer instead of swallowing it")
    func drainReportsAClosedPeer() {
        var descriptors: [Int32] = [0, 0]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
        let (ours, discord) = (descriptors[0], descriptors[1])
        defer { close(ours) }

        close(discord)

        #expect(DiscordIPCClient.drain(descriptor: ours) == .closed)
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

    @Test("A paused track says so on the state line, keeping the artist")
    func pausedStateLineIsVisible() throws {
        let paused = DiscordPresenceActivity.payload(for: Self.snapshot(isPlaying: false))
        let playing = DiscordPresenceActivity.payload(for: Self.snapshot())
        let state = try #require(paused["state"] as? String)

        #expect(state.contains(DiscordPresenceActivity.pausedLabel))
        #expect(state.contains("An Artist"))
        #expect(playing["state"] as? String == "An Artist")
    }

    @Test("A paused track with no artist still says it is paused")
    func pausedWithoutArtistStillReportsPause() throws {
        let payload = DiscordPresenceActivity.payload(
            for: Self.snapshot(artist: nil, isPlaying: false)
        )
        let state = try #require(payload["state"] as? String)

        #expect(state.contains(DiscordPresenceActivity.pausedLabel))
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

    @Test("The shipped application ID is a well-formed snowflake")
    func defaultApplicationIDIsWellFormed() {
        // The only thing standing between a typo in that constant and a build
        // whose Rich Presence silently never connects.
        #expect(DiscordPresenceActivity.isValidApplicationID(DiscordPresenceActivity.defaultApplicationID))
        #expect(DiscordPresenceActivity.defaultApplicationID == "1550196014063943710")
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
