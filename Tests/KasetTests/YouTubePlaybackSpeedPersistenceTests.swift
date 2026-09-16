import Foundation
import Testing
@testable import KasetPlus

// MARK: - YouTubePlaybackSpeedPersistenceTests

/// Playback speed survives a new video and a relaunch (#36).
@Suite("YouTube playback speed persistence", .tags(.service))
@MainActor
struct YouTubePlaybackSpeedPersistenceTests {
    private static func scratchDefaults() throws -> UserDefaults {
        let suite = "kaset.tests.speed.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suite))
    }

    @Test("A changed speed is written to the injected defaults")
    func changedSpeedPersists() throws {
        let defaults = try Self.scratchDefaults()
        let service = YouTubePlayerService(defaults: defaults)

        service.playbackSpeed = 1.5

        #expect(defaults.object(forKey: YouTubePlayerService.playbackSpeedKey) as? Double == 1.5)
    }

    @Test("A new service restores the saved speed instead of 1x")
    func savedSpeedIsRestored() throws {
        let defaults = try Self.scratchDefaults()
        defaults.set(1.75, forKey: YouTubePlayerService.playbackSpeedKey)

        #expect(YouTubePlayerService(defaults: defaults).playbackSpeed == 1.75)
    }

    @Test("Out-of-range and missing saved speeds fall back to 1x", arguments: [0.0, -1.0, 4.0])
    func unusableSavedSpeedFallsBack(saved: Double) throws {
        let defaults = try Self.scratchDefaults()
        defaults.set(saved, forKey: YouTubePlayerService.playbackSpeedKey)

        #expect(YouTubePlayerService(defaults: defaults).playbackSpeed == 1.0)
    }

    @Test("A service with no saved speed starts at 1x")
    func missingSavedSpeedStartsAtNormal() throws {
        #expect(try YouTubePlayerService(defaults: Self.scratchDefaults()).playbackSpeed == 1.0)
    }

    @Test("Re-setting the same speed does not rewrite defaults")
    func idempotentSetIsNotPersistedTwice() throws {
        let defaults = try Self.scratchDefaults()
        let service = YouTubePlayerService(defaults: defaults)
        service.playbackSpeed = 1.25
        defaults.removeObject(forKey: YouTubePlayerService.playbackSpeedKey)

        service.playbackSpeed = 1.25

        #expect(defaults.object(forKey: YouTubePlayerService.playbackSpeedKey) == nil)
    }
}
