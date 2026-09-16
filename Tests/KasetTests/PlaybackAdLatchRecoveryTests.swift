import JavaScriptCore
import Testing
@testable import KasetPlus

// MARK: - PlaybackAdLatchRecoveryTests

/// `isAdShowing()` decides "the ad ended but content hasn't come back yet" by
/// comparing the player's video id against the URL's `v` parameter. Once
/// YouTube Music's native queue advances without navigating (#248), the URL
/// keeps naming the *previous* track, so an ad across that boundary latched the
/// ad flag on permanently — and every `guard !self.isShowingAd` gate with it.
@Suite("Playback ad latch recovery", .tags(.service))
struct PlaybackAdLatchRecoveryTests {
    private func makeContext(url: String) throws -> JSContext {
        let context = try #require(JSContext())
        context.evaluateScript("""
        var window = globalThis;
        var fakeNow = 1000;
        Date.now = function() { return fakeNow; };
        window.location = { href: '\(url)' };
        var URL = function(value) {
            this.searchParams = {
                get: key => value.match(new RegExp('[?&]' + key + '=([^&]*)'))?.[1] || null
            };
        };
        var videoEl = { __kasetBoundVideoId: '' };
        var playerData = { video_id: 'song1' };
        var presenting = 1;
        var musicPlayer = { playerApi: {
            getPresentingPlayerType: function() { return presenting; },
            getVideoData: function() { return playerData; }
        } };
        var document = {
            getElementById: function() { return null; },
            querySelector: function(selector) {
                return selector === 'ytmusic-player' ? musicPlayer : videoEl;
            }
        };
        """)
        context.evaluateScript(PlaybackAdDetectionScript.detection)
        try #require(context.exception == nil, "\(context.exception?.toString() ?? "")")
        return context
    }

    private func isAd(_ context: JSContext) -> Bool {
        context.evaluateScript("isAdShowing()").toBool()
    }

    @Test("An ad clears once content returns on the same track")
    func adClearsOnSameTrack() throws {
        let context = try self.makeContext(url: "https://music.youtube.com/watch?v=song1")
        #expect(!self.isAd(context))
        context.evaluateScript("presenting = 2; playerData = { video_id: 'ad1' };")
        #expect(self.isAd(context))
        context.evaluateScript("""
        presenting = 1;
        playerData = { video_id: 'song1' };
        videoEl.__kasetBoundVideoId = 'song1';
        """)
        #expect(!self.isAd(context))
    }

    @Test("An ad clears on a URL that carries no video id")
    func adClearsWithoutVideoIdInURL() throws {
        let context = try self.makeContext(url: "https://music.youtube.com/library")
        context.evaluateScript("presenting = 2; playerData = { video_id: 'ad1' };")
        #expect(self.isAd(context))
        context.evaluateScript("""
        presenting = 1;
        playerData = { video_id: 'song1' };
        videoEl.__kasetBoundVideoId = 'song1';
        """)
        #expect(!self.isAd(context))
    }

    @Test("An ad across a gapless handoff clears once the new track settles")
    func adClearsAfterGaplessHandoff() throws {
        let context = try self.makeContext(url: "https://music.youtube.com/watch?v=song1")
        context.evaluateScript("presenting = 2; playerData = { video_id: 'ad1' };")
        #expect(self.isAd(context))

        // The ad ends and YouTube's own queue has already moved to song2. No
        // navigation happened, so window.location still says v=song1.
        context.evaluateScript("""
        presenting = 1;
        playerData = { video_id: 'song2' };
        videoEl.__kasetBoundVideoId = 'song2';
        """)
        // Briefly still "ad": indistinguishable from the gap between two
        // creatives of one pod, which is exactly what the wait is for.
        #expect(self.isAd(context))

        // Past that grace it is unambiguously content. Before the fix this
        // stayed true forever.
        context.evaluateScript("fakeNow += 8000;")
        #expect(!self.isAd(context))
    }

    @Test("A second creative in the same pod is still an ad after the grace")
    func consecutiveCreativesStayAds() throws {
        let context = try self.makeContext(url: "https://music.youtube.com/watch?v=song1")
        context.evaluateScript("presenting = 2; playerData = { video_id: 'creative-one' };")
        #expect(self.isAd(context))

        // Next creative: ad signals clear for a moment, then the pod resumes.
        context.evaluateScript("""
        presenting = 1;
        playerData = { video_id: 'creative-two' };
        videoEl.__kasetBoundVideoId = 'creative-two';
        """)
        #expect(self.isAd(context))
        context.evaluateScript("presenting = 2;")
        #expect(self.isAd(context))
    }
}
