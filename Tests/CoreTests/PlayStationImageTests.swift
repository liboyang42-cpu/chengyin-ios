import XCTest
@testable import QuestifyCore

/// Station image chain: station → chapter first image → route cover → texture; game cover first
/// for the game row. All identifiers and URLs are synthetic.
final class PlayStationImageTests: XCTestCase {
    private func result(_ json: String) throws -> PlayNodesResult { try JSONDecoder().decode(PlayNodesResult.self, from: Data(json.utf8)) }
    private func route(node: String, chapters: String = "[]", cover: String = "null") throws -> PlayNodesResult {
        try result(#"{"mode":1,"topicCover":"# + cover + #","chapters":"# + chapters + #","nodes":["# + node + "]}")
    }

    func testStationChainEachStep() throws {
        let chapters = #"[{"chapterId":81,"imgArr":"https://x.example/c1.jpg,https://x.example/c2.jpg"}]"#
        let cover = #""https://x.example/t.jpg""#
        var value = try route(node: #"{"nodeId":7,"chapterId":81,"imgUrl":"https://x.example/s.jpg,https://x.example/s2.jpg"}"#, chapters: chapters, cover: cover)
        XCTAssertEqual(PlayStationImageResolver.station(for: value.nodes[0], in: value), .init(source: "https://x.example/s.jpg", tier: .station))
        value = try route(node: #"{"nodeId":7,"chapterId":81,"imgUrl":null,"imgHidden":true}"#, chapters: chapters, cover: cover)
        XCTAssertEqual(PlayStationImageResolver.station(for: value.nodes[0], in: value), .init(source: "https://x.example/c1.jpg", tier: .chapter))
        value = try route(node: #"{"nodeId":7,"chapterId":99}"#, chapters: chapters, cover: cover)
        XCTAssertEqual(PlayStationImageResolver.station(for: value.nodes[0], in: value), .init(source: "https://x.example/t.jpg", tier: .route))
        value = try route(node: #"{"nodeId":7}"#)
        XCTAssertEqual(PlayStationImageResolver.station(for: value.nodes[0], in: value), .texture)
    }

    func testGameChainPrefersGameCoverThenStationChain() throws {
        let chapters = #"[{"chapterId":81,"imgArr":["https://x.example/c1.jpg"]}]"#
        var value = try route(node: #"{"nodeId":7,"chapterId":81,"storyImg":"https://x.example/g.jpg","imgUrl":"https://x.example/s.jpg"}"#, chapters: chapters)
        XCTAssertEqual(PlayStationImageResolver.game(for: value.nodes[0], in: value), .init(source: "https://x.example/g.jpg", tier: .game))
        value = try route(node: #"{"nodeId":7,"chapterId":81,"storyImg":""}"#, chapters: chapters)
        XCTAssertEqual(PlayStationImageResolver.game(for: value.nodes[0], in: value), .init(source: "https://x.example/c1.jpg", tier: .chapter))
        XCTAssertEqual(PlayStationImageResolver.game(gameCover: nil, stationImage: nil, chapterImages: [], routeCover: nil), .texture)
    }

    func testImageListShapes() {
        XCTAssertEqual(PlayStationImageResolver.list("a.jpg, b.jpg;c.jpg" as String?), ["a.jpg", "b.jpg", "c.jpg"])
        XCTAssertEqual(PlayStationImageResolver.list(#"["a.jpg","b.jpg"]"# as String?), ["a.jpg", "b.jpg"])
        XCTAssertEqual(PlayStationImageResolver.list(PlayWireValue.array([.string("a.jpg"), .string("b.jpg,c.jpg")])), ["a.jpg", "b.jpg", "c.jpg"])
    }

    func testMalformedImgArrNeverThrowsAndFallsThrough() throws {
        for bad in ["", "   ", ",,;", "[]", "[", "null"] { XCTAssertEqual(PlayStationImageResolver.list(bad as String?), [], bad) }
        XCTAssertEqual(PlayStationImageResolver.list(#"["a.jpg","#  as String?), ["a.jpg"])
        XCTAssertEqual(PlayStationImageResolver.list(PlayWireValue.object(["u": .string("a.jpg")])), [])
        XCTAssertEqual(PlayStationImageResolver.list(PlayWireValue.array([.null, .integer(3), .string("")])), [])
        XCTAssertEqual(PlayStationImageResolver.list(PlayWireValue.integer(42)), [])
        // A malformed chapter img_arr or topic cover never fails the route read.
        let value = try route(node: #"{"nodeId":7,"chapterId":81}"#, chapters: #"[{"chapterId":81,"imgArr":{"x":1}}]"#, cover: "17")
        XCTAssertEqual(value.chapters.first?.images, [])
        XCTAssertNil(value.topicCover)
        XCTAssertEqual(PlayStationImageResolver.station(for: value.nodes[0], in: value), .texture)
        let hidden = try route(node: #"{"nodeId":7,"imgUrl":5,"storyImg":[1]}"#)
        XCTAssertNil(hidden.nodes[0].imageURL); XCTAssertNil(hidden.nodes[0].storyImage)
    }

    func testOwnOriginHttpUpgradesOnly() {
        XCTAssertEqual(PlayStationImageResolver.secured("http://www.chengyinhub.com/prod-api/profile/a.jpg"), "https://www.chengyinhub.com/prod-api/profile/a.jpg")
        XCTAssertEqual(PlayStationImageResolver.secured("http://other.example/a.jpg"), "http://other.example/a.jpg")
    }
}
