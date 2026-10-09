import XCTest
@testable import QuestifyCore

final class ActivityAssociatedPlaysTests: XCTestCase {
    private func detail(_ rows: Any?) throws -> ActivityDetail {
        var object: [String: Any] = ["id":11,"name":"Synthetic activity"]
        if let rows { object["memberTemplateList"] = rows }
        return try JSONDecoder().decode(ActivityDetail.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testAllowedResponseReadsOnlyThreeDisplayFieldsAndKeepsReturnedOrder() throws {
        let value = try detail([["id":8,"title":" First ","players":"2–6","duration":30.5,"answer":"Ignored","imgUrl":"https://invalid.example/private.png"],
                                ["id":8,"title":"Second","players":0,"duration":0]])
        XCTAssertEqual(value.associatedPlays.map(\.title), ["First", "Second"])
        XCTAssertEqual(value.associatedPlays[0].players, "2–6")
        XCTAssertEqual(value.associatedPlays[0].durationMinutes, 30.5)
        XCTAssertEqual(value.associatedPlays[1].players, "0")
        XCTAssertEqual(value.associatedPlays[1].durationMinutes, 0)
        XCTAssertEqual(Set(Mirror(reflecting: value.associatedPlays[0]).children.compactMap(\.label)), ["title", "players", "durationMinutes"])
    }
    func testMissingNullOrEmptyCollectionProducesNoInventedPlays() throws {
        XCTAssertTrue(try detail(nil).associatedPlays.isEmpty)
        XCTAssertTrue(try detail(NSNull()).associatedPlays.isEmpty)
        XCTAssertTrue(try detail([]).associatedPlays.isEmpty)
    }
    func testMissingOrInvalidMetadataStaysUnknownNotDefaultCountsOrDuration() throws {
        let unknown = try detail([[:], ["title":false,"players":true,"duration":"30"],
                                  ["title":" ","players":-1,"duration":-5],
                                  ["players":2.5,"duration":"NaN"]]).associatedPlays
        for row in unknown {
            XCTAssertNil(row.title); XCTAssertNil(row.players); XCTAssertNil(row.durationMinutes)
        }
    }
    func testMalformedListOrNonRecordItemRetainsSourceWholeResponseFailure() {
        XCTAssertThrowsError(try detail(["title":"Not an array"]))
        XCTAssertThrowsError(try detail(["Not an object"]))
    }
    func testGateDoesNotDecodeOrExposeEmbeddedTemplateCollection() throws {
        let access = try JSONDecoder().decode(ActivityDetailAccess.self,
            from: Data(#"{"gate":true,"clubId":81,"memberTemplateList":[{"title":"Must not be exposed"}]}"#.utf8))
        XCTAssertEqual(access, .clubRequired(clubID: 81, message: nil))
    }
    func testChangedAssociationIsPartOfExactAllowedResponseSnapshot() throws {
        let first = try detail([["title":"First","players":2,"duration":15]])
        let changed = try detail([["title":"First","players":3,"duration":15]])
        XCTAssertNotEqual(first, changed)
        XCTAssertNotEqual(ActivityDetailAccess.allowed(first), .allowed(changed))
    }
}
