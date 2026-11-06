import XCTest
@testable import QuestifyCore

/// w2-07 second pass: node intro templates, session chips and node card footers from `pages/topic/index`.
final class TopicXcxNodeFactsTests: XCTestCase {
    private func topic(_ chapters: [[String: Any]]) throws -> TopicDetail {
        try JSONDecoder().decode(TopicDetail.self, from: JSONSerialization.data(withJSONObject: ["id": 31, "name": "Synthetic route", "chaptersList": chapters]))
    }

    func testNodeTemplatesKeepRouteOrderAndFirstOccurrence() throws {
        let t1: [String: Any] = ["id": 5, "title": "Riddle", "players": "2-4", "duration": 0]
        let t2: [String: Any] = ["id": 6, "title": "Photo"]
        let value = try topic([["id": 1, "name": "A", "nodes": [["id": 1, "name": "N1", "cmsMemberTemplate": t1], ["id": 2, "name": "N2", "cmsMemberTemplate": t2]]],
                               ["id": 2, "name": "B", "nodes": [["id": 3, "name": "N3", "cmsMemberTemplate": t1]]]])
        let templates = TopicXcxFacts.nodeTemplates(value)
        XCTAssertEqual(templates.map(\.id), [5, 6])
        XCTAssertEqual(TopicXcxFacts.templateMinutes(templates[0]), "0")
        XCTAssertEqual(TopicXcxFacts.templateMinutes(templates[1]), "--")
    }

    func testSessionChipUsesChinaCalendarAndHidesMidnight() {
        XCTAssertEqual(TopicXcxFacts.sessionChip("2025-12-13 19:30:00"), .init(weekday: 6, monthDay: "12.13", time: "19:30"))
        XCTAssertEqual(TopicXcxFacts.sessionChip("2025-12-14"), .init(weekday: 0, monthDay: "12.14", time: nil))
        XCTAssertNil(TopicXcxFacts.sessionChip("soon"))
    }

    func testNodeFootUsesFirstMerchantAndCount() throws {
        let merchant: ([String: Any]) = ["memberId": 9, "mmsMerchant": ["id": 3, "name": "Synthetic cafe"]]
        let other: ([String: Any]) = ["memberId": 10, "mmsMerchant": ["id": 4, "name": "Synthetic bakery"]]
        let value = try topic([["id": 1, "name": "A", "nodes": [["id": 1, "name": "Gate", "registrationMerchantList": [merchant, other]], ["id": 2, "name": "Park"]]]])
        let nodes = value.chapters[0].nodes
        XCTAssertEqual(TopicXcxFacts.nodeFoot(nodes[0]), .init(merchant: "Synthetic cafe", node: "Gate", merchantCount: 2))
        XCTAssertNil(TopicXcxFacts.nodeFoot(nodes[1]).merchant)
    }
}
