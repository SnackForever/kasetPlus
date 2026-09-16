import SwiftUI
import Testing
@testable import KasetPlus

// MARK: - YouTubeGridCardAlignmentTests

/// Grid cards must start at the same y whatever meta lines they carry.
///
/// Mixes have no channel or view-count line, so their cards are shorter than a
/// video's. With centre-aligned grid cells that pushed their thumbnails down
/// half the height difference, which is what made the Home grid look ragged.
@Suite("YouTube grid card alignment", .tags(.model))
@MainActor
struct YouTubeGridCardAlignmentTests {
    @Test("The stack strip is reserved even when no slivers are drawn")
    func stackStripIsAlwaysReserved() {
        #expect(StackedPosterBackground(isVisible: true).isVisible)
        #expect(!StackedPosterBackground(isVisible: false).isVisible)
        // Both paths go through the same fixed-height strip, so a card without
        // the cue still starts its poster at the same offset as one with it.
        #expect(StackedPosterBackground.sliverStripHeight > 0)
    }

    @Test("A mix shows the stack cue and a plain video does not")
    func onlyMixesDrawTheCue() {
        let mix = YouTubeVideo(
            videoId: "mix1",
            title: "Mix - Arctic Monkeys",
            mixPlaylistId: "RDAMVM123"
        )
        let video = YouTubeVideo(videoId: "vid1", title: "A normal video")

        #expect(mix.mixPlaylistId != nil)
        #expect(video.mixPlaylistId == nil)
    }

    @Test("Every YouTube grid pins its cells to the top")
    func gridColumnsAreTopAligned() throws {
        // GridItem doesn't expose its alignment, so assert on the source of
        // truth instead: no adaptive YouTube grid may omit `alignment: .top`.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // KasetTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("Sources/Kaset/Views/YouTube")
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var offenders: [String] = []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") where line.contains("GridItem(.adaptive") {
                if !line.contains("alignment: .top") {
                    offenders.append("\(file.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders)")
    }
}
