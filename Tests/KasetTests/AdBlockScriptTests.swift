import Foundation
import Testing
@testable import KasetPlus

@Suite("Ad-block script contracts", .serialized, .tags(.service))
@MainActor
struct AdBlockScriptTests {
    /// YouTube Music ships no inline `ytInitialPlayerResponse`: the JSON.parse
    /// hook is the only thing that prunes its ads (ADR-0039).
    @Test("Pruning covers the fetched player response and stays masked as native")
    func prunesTheFetchedPlayerResponse() {
        let script = AdBlockService.adBlockScript

        #expect(script.contains("JSON.parse = parseHook"))
        #expect(script.contains("mask(parseHook, _parse)"))
        // Rebuilding the fetched Response was measured to blank the player.
        #expect(!script.contains("new Response("))
        for adKey in ["adPlacements", "playerAds", "adSlots"] {
            #expect(script.contains("'\(adKey)'"))
        }
    }

    @Test("Content rules are valid and never block the innertube API")
    func contentRulesStayPlaybackSafe() throws {
        let rules = try JSONSerialization.jsonObject(
            with: Data(AdBlockService.contentRulesJSON.utf8)
        ) as? [[String: Any]]

        #expect(rules?.isEmpty == false)
        // Network-blocking the player endpoint stalls playback instead of the ad.
        #expect(!AdBlockService.contentRulesJSON.contains("youtubei"))
    }
}
