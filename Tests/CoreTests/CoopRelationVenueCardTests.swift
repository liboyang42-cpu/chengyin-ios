import XCTest
@testable import QuestifyCore

/// Mini-program relation venue card (cy-merchant-card variant=venue) fields, w2-17.
final class CoopRelationVenueCardTests: XCTestCase {
    private func discovery(_ merchants: [CoopFlowJSON], clubs: [CoopFlowJSON] = []) throws -> CoopRelationDiscovery {
        try CoopRelationDiscovery(.object(["relations": .array([]), "discovery": .object(["merchants": .array(merchants), "clubs": .array(clubs)])]))
    }
    private func merchant(_ id: Int, _ extra: [String: CoopFlowJSON]) -> CoopFlowJSON {
        .object(["id": .id(id), "memberId": .id(id + 100), "name": .string("Merchant \(id)")].merging(extra) { $1 })
    }
    func testVenueTagsHoursAndSuitTypesFollowSourceCard() throws {
        let row = try XCTUnwrap(discovery([merchant(8, ["chargeType": .id(1), "capacity": .string("12"), "businessTime": .string(" 10:00-22:00 "),
            "availableTime": .string("ignored"), "suitActivityTypes": .string("剧本、桌游/ 团建,"), "coopOpen": .id(1)])]).merchants.first)
        XCTAssertEqual(row.venueTags, [.paidVenue, .capacity(12)])
        XCTAssertEqual(row.hours, "10:00-22:00")
        XCTAssertEqual(row.suitText, "剧本 · 桌游 · 团建")
        let free = try XCTUnwrap(discovery([merchant(9, ["chargeType": .string("0"), "capacity": .id(0), "availableTime": .string("Weekends")])]).merchants.first)
        XCTAssertEqual(free.venueTags, [.freeVenue])
        XCTAssertEqual(free.hours, "Weekends")
        XCTAssertNil(free.suitText)
    }
    func testClosedForCooperationVenuesAreHiddenNotInvalid() throws {
        let value = try discovery([merchant(8, ["coopOpen": .id(0)]), merchant(9, ["coopOpen": .null]), merchant(10, ["coopOpen": .bool(false)])])
        XCTAssertEqual(value.merchants.map(\.rowID), [9, 10])
        XCTAssertFalse(value.hasInvalidRows(.merchants))
        XCTAssertEqual(value.invalidMerchantCount, 0)
    }
    func testClubsCarryNoVenueFields() throws {
        let club = try XCTUnwrap(discovery([], clubs: [.object(["id": .id(5), "name": .string("Club"), "chargeType": .id(1), "coopOpen": .id(0)])]).clubs.first)
        XCTAssertTrue(club.venueTags.isEmpty)
        XCTAssertFalse(club.coopClosed)
    }
}
