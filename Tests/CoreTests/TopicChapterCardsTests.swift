import XCTest
@testable import QuestifyCore

/// Route detail chapter cards (2026-11-19): picture fallback, minute rounding, ending exclusion, toggle.
final class TopicChapterCardsTests: XCTestCase {
    private func chapters(_ json: String) throws -> [TopicChapter] {
        let raw = "{\"id\":7,\"name\":\"Synthetic route\",\"imgUrl\":\"https://cdn.example.test/cover.jpg,https://cdn.example.test/b.jpg\",\"chaptersList\":\(json)}"
        return try JSONDecoder().decode(TopicDetail.self, from: Data(raw.utf8)).chapters
    }

    func testPictureUsesFirstChapterImageThenRouteCover() throws {
        let list = try chapters(#"[{"id":1,"name":"A","templateCount":1,"totalTime":60,"imgArr":"https://cdn.example.test/a1.jpg, https://cdn.example.test/a2.jpg"},{"id":2,"name":"B","templateCount":1,"totalTime":60,"imgArr":"[\"https://cdn.example.test/b1.jpg\"]"},{"id":3,"name":"C","templateCount":1,"totalTime":60,"imgArr":["","https://cdn.example.test/c1.jpg"]},{"id":4,"name":"D","templateCount":1,"totalTime":60,"imgArr":""}]"#)
        let cards = TopicChapterCards.cards(chapters: list, routeCover: "https://cdn.example.test/cover.jpg,https://cdn.example.test/b.jpg")
        XCTAssertEqual(cards.map(\.imageSource), ["https://cdn.example.test/a1.jpg", "https://cdn.example.test/b1.jpg", "https://cdn.example.test/c1.jpg", "https://cdn.example.test/cover.jpg"])
        XCTAssertNil(TopicChapterCards.cards(chapters: [list[3]], routeCover: nil).first?.imageSource)
        XCTAssertEqual(TopicChapterCards.imageList(#"[{"url":"u.png"}]"#), ["u.png"])
        XCTAssertEqual(TopicChapterCards.imageList("null"), [])
    }

    func testMinutesRoundSecondsAndFallBackToTemplateDurations() throws {
        let list = try chapters(#"[{"id":1,"name":"A","templateCount":3,"totalTime":1800},{"id":2,"name":"B","templateCount":1,"totalTime":1649},{"id":3,"name":"C","templateCount":1,"totalTime":20},{"id":4,"name":"D","templateCount":2,"totalTime":0,"nodes":[{"id":41,"cmsMemberTemplate":{"id":9,"duration":10}},{"id":42,"cmsMemberTemplate":{"id":8,"duration":15}}]},{"id":5,"name":"E","templateCount":2,"totalTime":0}]"#)
        XCTAssertEqual(list.map(TopicChapterCards.minutes), [30, 27, 1, 25, nil])
        let cards = TopicChapterCards.cards(chapters: list, routeCover: nil)
        XCTAssertEqual(cards[0].gameCount, 3)
        XCTAssertEqual(cards[0].minutes, 30)
        XCTAssertNil(cards[4].minutes, "Unknown duration is hidden, never written as zero")
    }

    func testEndingsAreExcludedAndOrderFollowsSortID() throws {
        let list = try chapters(#"[{"id":3,"sortId":3,"name":"结局 · 黎明","templateCount":2,"totalTime":600},{"id":2,"sortId":2,"name":"Second","templateCount":1,"totalTime":600,"description":"  Harbour  "},{"id":1,"sortId":1,"name":"First","templateCount":1,"totalTime":600,"description":"null"},{"id":4,"sortId":4,"name":"Epilogue","templateCount":0,"totalTime":0},{"id":5,"sortId":5,"name":"Walk","templateCount":0,"totalTime":300}]"#)
        let cards = TopicChapterCards.cards(chapters: list, routeCover: nil)
        XCTAssertEqual(cards.map(\.id), [1, 2, 5])
        XCTAssertEqual(cards.map(\.description), [nil, "Harbour", nil])
        XCTAssertNil(cards[2].gameCount)
        XCTAssertEqual(cards[2].minutes, 5)
    }

    func testToggleOpensOneCardAtATime() {
        XCTAssertEqual(TopicChapterCards.toggle(open: nil, tapped: 1), 1)
        XCTAssertNil(TopicChapterCards.toggle(open: 1, tapped: 1))
        XCTAssertEqual(TopicChapterCards.toggle(open: 1, tapped: 2), 2)
    }
}
