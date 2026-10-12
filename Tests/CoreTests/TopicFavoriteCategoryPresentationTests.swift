import XCTest
@testable import QuestifyCore

final class TopicFavoriteCategoryPresentationTests: XCTestCase {
    private func decode(_ categoryJSON: String? = nil) throws -> TopicSummary {
        let category = categoryJSON.map { ",\"sysCategoryList\":" + $0 } ?? ""
        return try JSONDecoder().decode(TopicSummary.self, from: Data((#"{"id":7,"name":"Saved topic","likeNum":3,"locationCount":8"# + category + "}").utf8))
    }
    func testMissingNullAndEmptyCategoriesKeepOldTopicFields() throws {
        for json in [nil, "null", "[]"] as [String?] {
            let topic = try decode(json)
            XCTAssertEqual(topic.id, 7)
            XCTAssertEqual(topic.name, "Saved topic")
            XCTAssertEqual(topic.likeCount, 3)
            XCTAssertEqual(topic.locationCount, 8)
            XCTAssertEqual(topic.categoryNames, [])
            XCTAssertNil(topic.favoriteCategoryText)
        }
    }
    func testSourceOrderAndDuplicatesAreNotReclassified() throws {
        let topic = try decode(#"[{"categoryName":"City walk"},{"categoryName":"城市探索"},{"categoryName":"City walk"}]"#)
        XCTAssertEqual(topic.categoryNames, ["City walk", "城市探索", "City walk"])
        XCTAssertEqual(topic.favoriteCategoryText, "City walk · 城市探索 · City walk")
    }
    func testMissingNullBlankAndNonStringNamesDoNotInventClassification() throws {
        let topic = try decode(#"[null,{}, {"categoryName":null},{"categoryName":42},{"categoryName":true},{"categoryName":""},{"categoryName":" \n\t "},{"id":9,"name":"Not the source field"},{"categoryName":"Actual type"}]"#)
        XCTAssertEqual(topic.categoryNames, ["Actual type"])
        XCTAssertEqual(topic.favoriteCategoryText, "Actual type")
    }
    func testMalformedOptionalCategoryListDoesNotInvalidateOldTopic() throws {
        for json in [#"{"categoryName":"Not a list"}"#, #""Not a list""#, "42", "true", #"["wrong row type"]"#] {
            let topic = try decode(json)
            XCTAssertEqual(topic.id, 7)
            XCTAssertEqual(topic.locationCount, 8)
            XCTAssertNil(topic.favoriteCategoryText)
        }
    }
    func testVisibleSourceTextRetainsUnicodeAndOriginalBytes() throws {
        let topic = try decode(#"[{"categoryName":"  漫步 🗺️  "},{"categoryName":"é"},{"categoryName":"e\u0301"}]"#)
        XCTAssertEqual(topic.categoryNames.map { Data($0.utf8) }, ["  漫步 🗺️  ", "é", "e\u{0301}"].map { Data($0.utf8) })
        XCTAssertEqual(topic.favoriteCategoryText, "  漫步 🗺️   · é · e\u{0301}")
    }
    func testCategoryNamesCannotReplaceRequiredTopicIdentityOrFallbackFromIDs() throws {
        let topic = try JSONDecoder().decode(TopicSummary.self, from: Data(#"{"id":7,"categoryIds":"1,2","sysCategoryList":[{"id":1},{"categoryId":2,"description":"Not a category name"}]}"#.utf8))
        XCTAssertNil(topic.favoriteCategoryText)
        XCTAssertThrowsError(try JSONDecoder().decode(TopicSummary.self, from: Data(#"{"id":0,"sysCategoryList":[{"categoryName":"Real label"}]}"#.utf8)))
    }
}
