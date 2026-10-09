import XCTest
@testable import QuestifyCore

final class RoamPlaceReadStatusTests: XCTestCase {
    private func place(_ fields: [String: Any] = [:]) throws -> RoamPlace {
        var value: [String: Any] = ["id":11,"type":2,"name":"Synthetic place"]
        value.merge(fields) { _, new in new }
        return try JSONDecoder().decode(RoamPlace.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func testStrictBooleanFactsRetainTheirIndependentValues() throws {
        for found in [true, false] {
            for pending in [true, false] {
                let value = try place(["found":found,"pendingRedeem":pending])
                XCTAssertEqual(value.found, found); XCTAssertEqual(value.pendingRedeem, pending)
                XCTAssertEqual(value.readStatus.discovered, found ? .yes : .no)
                XCTAssertEqual(value.readStatus.pendingRedemption, pending ? .yes : .no)
            }
        }
    }
    func testMissingNullNumericAndStringFactsStayUnknownWithoutDroppingPublicRow() throws {
        let invalid: [Any] = [NSNull(), 0, 1, "true", "false", "1", [], ["value":true]]
        XCTAssertEqual(try place().readStatus, .init(found: nil, pendingRedeem: nil))
        for raw in invalid {
            let value = try place(["found":raw,"pendingRedeem":raw])
            XCTAssertNil(value.found); XCTAssertNil(value.pendingRedeem)
            XCTAssertEqual(value.readStatus.discovered, .unknown)
            XCTAssertEqual(value.readStatus.pendingRedemption, .unknown)
            XCTAssertTrue(value.isSupported)
        }
    }
    func testOneUnknownFactCannotRewriteTheOtherKnownFact() throws {
        let first = try place(["found":true,"pendingRedeem":"true"])
        XCTAssertEqual(first.readStatus.discovered, .yes)
        XCTAssertEqual(first.readStatus.pendingRedemption, .unknown)
        let second = try place(["pendingRedeem":true])
        XCTAssertEqual(second.readStatus.discovered, .unknown)
        XCTAssertEqual(second.readStatus.pendingRedemption, .yes)
    }
    func testApparentlyConflictingFactsAreNotRepairedByClientBusinessRules() throws {
        let value = try place(["found":false,"pendingRedeem":true])
        XCTAssertEqual(value.readStatus.discovered, .no)
        XCTAssertEqual(value.readStatus.pendingRedemption, .yes)
    }
    func testStatusReplacementChangesExactRowSnapshot() throws {
        let old = try place(["found":false,"pendingRedeem":false])
        let changed = try place(["found":true,"pendingRedeem":true])
        XCTAssertEqual(old.id, changed.id); XCTAssertNotEqual(old, changed)
        XCTAssertNotEqual(RoamMapItem.place(old), RoamMapItem.place(changed))
    }
    func testOptionalStatusDoesNotAdmitInvalidOrUnsupportedPoints() throws {
        XCTAssertFalse(try place(["id":0,"found":true,"pendingRedeem":true]).isSupported)
        XCTAssertFalse(try place(["type":99,"found":true,"pendingRedeem":true]).isSupported)
    }
}
