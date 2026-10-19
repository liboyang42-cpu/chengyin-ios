import XCTest
@testable import QuestifyCore

final class ClubCheckinRailTests: XCTestCase {
    private func reached(_ step: ClubGovernanceValue, status: ClubGovernanceValue = .string("VERIFIED")) -> [Bool] {
        ClubCheckinRail(railStep: step, statusCode: status).stops.map(\.reached)
    }
    func testStopsLightThroughServerStepInSourceOrder() {
        let rail = ClubCheckinRail(railStep: .integer(2), statusCode: .string("VERIFIED"))
        XCTAssertEqual(rail.stops.map(\.step), [.signed, .contacted, .verified, .reviewed])
        XCTAssertEqual(rail.stops.map(\.reached), [true, true, true, false])
        XCTAssertEqual(rail.stops.map(\.current), [false, false, true, false])
        XCTAssertFalse(rail.refunded)
        XCTAssertEqual(reached(.integer(0)), [true, false, false, false])
        XCTAssertEqual(reached(.integer(3)), [true, true, true, true])
    }
    func testRefundedOrUnknownStepLightsNothing() {
        let refunded = ClubCheckinRail(railStep: .integer(-1), statusCode: .string("REFUNDED"))
        XCTAssertEqual(refunded.stops.map(\.reached), [false, false, false, false])
        XCTAssertTrue(refunded.refunded)
        for value: ClubGovernanceValue in [.null, .string("2"), .decimal(1.5), .bool(true)] {
            XCTAssertEqual(reached(value), [false, false, false, false])
            XCTAssertTrue(ClubCheckinRail(railStep: value, statusCode: .null).stops.allSatisfy { !$0.current })
        }
    }
    func testOutOfRangeStepHasNoCurrentStop() {
        let rail = ClubCheckinRail(railStep: .integer(9), statusCode: .null)
        XCTAssertEqual(rail.stops.map(\.reached), [true, true, true, true])
        XCTAssertFalse(rail.stops.contains { $0.current })
    }
}
