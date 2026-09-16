import Testing
@testable import KasetPlus

extension YouTubeWatchScriptTests {
    @Test("A new document re-applies the speed the user picked")
    func attachReappliesTargetSpeed() throws {
        let context = try self.makeObserverContext(paused: false)
        try self.evaluate(
            """
            var rateCalls = [];
            moviePlayer.setPlaybackRate = function(rate) { rateCalls.push(rate); };
            window.__kasetTargetSpeed = 1.5;
            """,
            in: context
        )

        try self.evaluate(YouTubeWatchWebView.observerScript, in: context)

        #expect(context.evaluateScript("rateCalls[0]").toDouble() == 1.5)
    }

    @Test("Without a player API the speed lands on the media element")
    func attachFallsBackToMediaPlaybackRate() throws {
        let context = try self.makeObserverContext(paused: false)
        try self.evaluate("window.__kasetTargetSpeed = 0.75;", in: context)

        try self.evaluate(YouTubeWatchWebView.observerScript, in: context)

        #expect(context.evaluateScript("video.playbackRate").toDouble() == 0.75)
    }

    @Test("A document with no target speed leaves the rate alone")
    func attachLeavesRateAloneWithoutTarget() throws {
        let context = try self.makeObserverContext(paused: false)
        try self.evaluate(
            """
            var rateCalls = [];
            moviePlayer.setPlaybackRate = function(rate) { rateCalls.push(rate); };
            """,
            in: context
        )

        try self.evaluate(YouTubeWatchWebView.observerScript, in: context)

        #expect(context.evaluateScript("rateCalls.length").toInt32() == 0)
        #expect(context.evaluateScript("video.playbackRate === undefined").toBool() == true)
    }
}
