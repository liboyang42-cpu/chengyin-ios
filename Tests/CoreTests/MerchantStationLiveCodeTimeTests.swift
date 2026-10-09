import XCTest
@testable import QuestifyCore

final class MerchantStationLiveCodeTimeTests: XCTestCase {
    private func projection(start: String, end: String, playable: Bool = true, state: String = "ACTIVE", session: String = "RUNNING", checked: Bool = true, capacity: Int = 4) throws -> MerchantStationProjection {
        try .init(.object(["perspective": .string("MERCHANT"), "sessionId": .integer(90), "activityId": .integer(80), "revision": .integer(3), "status": .string(session),
            "merchant": .object(["stations": .array([.object(["stationId": .integer(61), "nodeId": .integer(62), "revision": .integer(3),
                "status": .string(state), "playable": .bool(playable), "capacity": .integer(capacity),
                "serviceStartAt": .string(start), "serviceEndAt": .string(end), "pendingVerificationCount": .integer(0),
                "preparationChecklist": .array([.object(["code": .string("KIT"), "label": .string("Synthetic kit"), "checked": .bool(checked)])])])])])]))
    }
    func testServerSecondsAndLegacyMinutesBothEnableReadOnlyLiveCodeEntry() throws {
        for (start, end) in [("2026-10-09 09:00:00", "2026-10-09 10:00:00"), ("2026-10-09 09:00", "2026-10-09 10:00"), ("2026-10-09 09:00:59", "2026-10-09 10:00"), ("2026-10-09 09:00", "2026-10-09 10:00:01")] {
            XCTAssertTrue(try projection(start: start, end: end).allowsLiveCode(nodeID: 62))
        }
    }
    func testMinuteKeyComparisonMatchesMiniProgramForMixedPrecision() throws {
        for (start, end) in [("2026-10-09 09:00", "2026-10-09 09:00:59"), ("2026-10-09 10:00:00", "2026-10-09 09:00"), ("2026-10-09 09:00:01", "2026-10-09 09:00:59")] {
            XCTAssertFalse(try projection(start: start, end: end).allowsLiveCode(nodeID: 62))
        }
    }
    func testInvalidCalendarSecondsOffsetAndSuffixAreNotFallbackParsed() throws {
        for start in ["2026-02-29 09:00:00", "2026-13-01 09:00:00", "2026-10-09 24:00:00", "2026-10-09 09:00:60", "2026-10-09 09:00:00Z", "2026-10-09 09:00:00+08:00", "2026-10-09 09:00:00\n", "2026-10-09 09:00\n", "2026-10-09 09:00:00.000", "2026-1-09 09:00:00"] {
            XCTAssertFalse(try projection(start: start, end: "2026-10-10 10:00:00").allowsLiveCode(nodeID: 62))
        }
    }
    func testLeapDayAndCrossDayCivilWindowDoNotUsePhoneTimezone() throws {
        XCTAssertTrue(try projection(start: "2028-02-29 23:00:00", end: "2028-03-01 01:00:00").allowsLiveCode(nodeID: 62))
    }
    func testEveryExistingProjectionGateStillApplies() throws {
        let start = "2026-10-09 09:00:00", end = "2026-10-09 10:00:00"
        XCTAssertFalse(try projection(start: start, end: end, playable: false).allowsLiveCode(nodeID: 62))
        XCTAssertFalse(try projection(start: start, end: end, state: "PAUSED").allowsLiveCode(nodeID: 62))
        XCTAssertFalse(try projection(start: start, end: end, session: "FINISHED").allowsLiveCode(nodeID: 62))
        XCTAssertFalse(try projection(start: start, end: end, checked: false).allowsLiveCode(nodeID: 62))
        XCTAssertFalse(try projection(start: start, end: end, capacity: 0).allowsLiveCode(nodeID: 62))
        XCTAssertFalse(try projection(start: start, end: end).allowsLiveCode(nodeID: 63))
    }
    func testWriteTimeValidationAndReadySerializationStillRejectSeconds() throws {
        XCTAssertTrue(MerchantStationCommand.validTime("2026-10-09 09:00"))
        XCTAssertFalse(MerchantStationCommand.validTime("2026-10-09 09:00:00"))
        XCTAssertNil(MerchantStationServiceWindow(start: "2026-10-09 09:00:00", end: "2026-10-09 10:00:00"))
        let request = MerchantStationCommand(activityID: 80, nodeID: 62, expectedRevision: 3, action: .ready, payload: [
            "capacity": .integer(4), "serviceStartAt": .string("2026-10-09 09:00:00"), "serviceEndAt": .string("2026-10-09 10:00:00"), "note": .string(""),
            "checklist": .array([.object(["code": .string("KIT"), "checked": .bool(true)])])])
        XCTAssertThrowsError(try request.fields())
    }
}
