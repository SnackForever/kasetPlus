import Foundation
import Testing
@testable import KasetPlus

// MARK: - PlaylistParserAlbumHeaderTests

/// Album headers carry the release year in their subtitle ("Album • 2026").
/// Shape captured live with `swift run api-explorer browse MPREb_…` (#37).
@Suite("Playlist parser album header", .tags(.parser))
struct PlaylistParserAlbumHeaderTests {
    private static func albumResponse(
        subtitleRuns: [[String: Any]],
        description: String? = nil
    ) -> [String: Any] {
        var header: [String: Any] = [
            "title": ["runs": [["text": "Wonderful"]]],
            "subtitle": ["runs": subtitleRuns],
            "secondSubtitle": ["runs": [
                ["text": "9 songs"], ["text": " • "], ["text": "41 minutes"],
            ]],
            "straplineTextOne": ["runs": [["text": "XANIYA"]]],
        ]
        if let description {
            header["description"] = [
                "musicDescriptionShelfRenderer": [
                    "description": ["runs": [["text": description]]],
                ],
            ]
        }
        return [
            "contents": [
                "twoColumnBrowseResultsRenderer": [
                    "secondaryContents": [
                        "sectionListRenderer": [
                            "contents": [["musicResponsiveHeaderRenderer": header]],
                        ],
                    ],
                ],
            ],
        ]
    }

    private static func albumSubtitle() -> [[String: Any]] {
        [["text": "Album"], ["text": " • "], ["text": "2026"]]
    }

    @Test("The release year is taken from the header subtitle")
    func releaseYearIsParsed() {
        let detail = PlaylistParser.parsePlaylistDetail(
            Self.albumResponse(subtitleRuns: Self.albumSubtitle()),
            playlistId: "MPREb_16sVAAmmwQu"
        )

        #expect(detail.year == "2026")
        #expect(detail.title == "Wonderful")
    }

    @Test("The year is not mistaken for the artist")
    func yearIsNotTheAuthor() {
        let detail = PlaylistParser.parsePlaylistDetail(
            Self.albumResponse(subtitleRuns: Self.albumSubtitle()),
            playlistId: "MPREb_16sVAAmmwQu"
        )

        #expect(detail.author?.name == "XANIYA")
    }

    @Test("A subtitle without a year leaves it nil")
    func missingYearIsNil() {
        let detail = PlaylistParser.parsePlaylistDetail(
            Self.albumResponse(subtitleRuns: [["text": "Playlist"]]),
            playlistId: "VLPL123"
        )

        #expect(detail.year == nil)
    }

    @Test("Implausible four-digit runs are not treated as a year", arguments: ["1899", "2201", "12345", "20x6"])
    func implausibleYearIsRejected(text: String) {
        let detail = PlaylistParser.parsePlaylistDetail(
            Self.albumResponse(subtitleRuns: [["text": "Album"], ["text": " • "], ["text": text]]),
            playlistId: "MPREb_16sVAAmmwQu"
        )

        #expect(detail.year == nil)
    }

    @Test("A description shelf in the header reaches the detail")
    func descriptionIsParsed() {
        let detail = PlaylistParser.parsePlaylistDetail(
            Self.albumResponse(subtitleRuns: Self.albumSubtitle(), description: "A record about records."),
            playlistId: "MPREb_16sVAAmmwQu"
        )

        #expect(detail.description == "A record about records.")
    }
}
