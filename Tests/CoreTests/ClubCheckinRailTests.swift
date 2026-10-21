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
    func testStateTitlesAndTimeFormatting() {
        XCTAssertEqual(ClubCheckinRail.stateTitle(for: nil, recordPresent: false), "核销记录不存在")
        XCTAssertEqual(ClubCheckinRail.stateTitle(for: .forbidden), "无权查看该核销记录")
        XCTAssertEqual(ClubCheckinRail.stateTitle(for: .rejected(code: 403, message: nil)), "无权查看该核销记录")
        XCTAssertEqual(ClubCheckinRail.stateTitle(for: .rejected(code: 500, message: "err")), "核销详情加载失败")
        let rail = ClubCheckinRail(
            railStep: .integer(1),
            statusCode: .string("CONTACTED"),
            sessionTime: .string("2026-10-19T14:30:00"),
            statusTime: .string("2026-10-19 15:00:00")
        )
        XCTAssertEqual(rail.sessionTimeText, "2026-10-19 14:30")
        XCTAssertEqual(rail.statusTimeText, "2026-10-19 15:00")
    }
}
