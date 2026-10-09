import XCTest
@testable import QuestifyCore

final class MerchantStationPauseChoiceTests: XCTestCase {
    private func option(code: String = "SAFE_A", version: Int = 2, source: Int = 62, target: Int = 63, message: String = "Use the approved alternate station") -> MerchantContentValue {
        .object(["sourceNodeId": .integer(source), "nodeId": .integer(target), "planCode": .string(code),
                 "planVersion": .integer(version), "nodeName": .string("Synthetic alternate"), "playerMessage": .string(message)])
    }
    private func projection(_ choices: [MerchantContentValue] = [], state: String = "ACTIVE", sessionState: String = "RUNNING", actions: [String] = ["STATION_PAUSE"]) throws -> MerchantStationProjection {
        try .init(.object(["perspective": .string("MERCHANT"), "sessionId": .integer(90), "activityId": .integer(80),
            "revision": .integer(3), "status": .string(sessionState), "availableActions": .array(actions.map(MerchantContentValue.string)),
            "merchant": .object(["stations": .array([.object(["stationId": .integer(61), "nodeId": .integer(62), "revision": .integer(3),
                "status": .string(state), "preparationChecklist": .array([]), "pendingVerificationCount": .integer(0)])]),
                "fallbackOptions": .array(choices)])]))
    }
    private func command(_ payload: [String: MerchantContentValue], nodeID: Int = 62, revision: Int = 3) -> MerchantStationCommand {
        .init(activityID: 80, nodeID: nodeID, expectedRevision: revision, requestID: "pause-test-001", action: .pause, payload: payload)
    }
    private var minimum: [String: MerchantContentValue] { ["reasonCode": .string("STAFF"), "resumeEta": .string("2026-10-09 17:30")] }
    private func payload(selection: MerchantStationPauseChoice? = nil, in current: MerchantStationProjection, reason: String = "") throws -> [String: MerchantContentValue] {
        try MerchantStationPauseChoice.pausePayload(reasonCode: "STAFF", reason: reason, resumeEta: "2026-10-09 17:30",
                                                    selection: selection, projection: current, nodeID: 62)
    }
    func testNoFallbackWorksWithoutCandidatesAndOmitsBothFieldsRatherThanNull() throws {
        let current = try projection(), value = try payload(in: current)
        XCTAssertEqual(value, minimum); XCTAssertNil(value["fallbackPlanCode"]); XCTAssertNil(value["fallbackPlanVersion"])
        let request = command(value); XCTAssertTrue(request.pausesWithoutFallback)
        XCTAssertNoThrow(try request.validate(projection: current))
        XCTAssertEqual(try request.fields()["payload"], .object(minimum))
    }
    func testAvailableOptionsNeverImplicitlySelectTheFirstPlan() throws {
        let current = try projection([option()])
        XCTAssertEqual(MerchantStationPauseChoice.available(in: current, nodeID: 62).count, 1)
        XCTAssertEqual(try payload(in: current), minimum)
        XCTAssertNoThrow(try command(minimum).validate(projection: current))
    }
    func testSelectedFallbackPreservesExistingCodeVersionReasonAndRequestIdentity() throws {
        let current = try projection([option()]), selected = try XCTUnwrap(MerchantStationPauseChoice(option: option()))
        let value = try payload(selection: selected, in: current, reason: "Staff unavailable")
        XCTAssertEqual(value["fallbackPlanCode"], .string("SAFE_A")); XCTAssertEqual(value["fallbackPlanVersion"], .integer(2))
        XCTAssertEqual(value["reason"], .string("Staff unavailable"))
        let request = command(value); XCTAssertFalse(request.pausesWithoutFallback)
        XCTAssertNoThrow(try request.validate(projection: current))
        let fields = try request.fields()
        XCTAssertEqual(fields["expectedRevision"], .integer(3)); XCTAssertEqual(fields["requestId"], .string("pause-test-001"))
        XCTAssertEqual(fields["activityId"], .integer(80)); XCTAssertEqual(fields["nodeId"], .integer(62))
    }
    func testChoiceSurvivesReorderWithoutSwitchingToDifferentPlan() throws {
        let first = option(), second = option(code: "SAFE_B", version: 4, target: 64)
        let chosen = try XCTUnwrap(MerchantStationPauseChoice(option: second))
        let before = try payload(selection: chosen, in: projection([first, second]))
        let after = try payload(selection: chosen, in: projection([second, first]))
        XCTAssertEqual(before, after); XCTAssertEqual(after["fallbackPlanCode"], .string("SAFE_B"))
    }
    func testExplicitNoneAfterSelectionLeavesNoOldFallbackFields() throws {
        let current = try projection([option()]), chosen = try XCTUnwrap(MerchantStationPauseChoice(option: option()))
        let old = try payload(selection: chosen, in: current)
        let reset = try payload(selection: nil, in: current)
        XCTAssertNotNil(old["fallbackPlanCode"]); XCTAssertEqual(reset, minimum)
        XCTAssertTrue(command(reset).pausesWithoutFallback)
    }
    func testRemovedOrChangedChoiceDoesNotSilentlyBecomeNone() throws {
        let chosen = try XCTUnwrap(MerchantStationPauseChoice(option: option()))
        for choices in [[], [option(version: 3)], [option(target: 64)], [option(message: "New consequence")]] {
            XCTAssertThrowsError(try payload(selection: chosen, in: projection(choices)))
        }
    }
    func testForeignAndDuplicateChoicesCannotProduceASelectedPlan() throws {
        let foreign = option(source: 72), chosen = try XCTUnwrap(MerchantStationPauseChoice(option: foreign))
        XCTAssertThrowsError(try payload(selection: chosen, in: projection([foreign])))
        let exact = try XCTUnwrap(MerchantStationPauseChoice(option: option()))
        XCTAssertThrowsError(try payload(selection: exact, in: projection([option(), option()])))
    }
    func testPartialNullBlankAndInvalidVersionPayloadsAreRejected() throws {
        let invalid: [[String: MerchantContentValue]] = [
            ["fallbackPlanCode": .string("SAFE_A")], ["fallbackPlanVersion": .integer(2)],
            ["fallbackPlanCode": .null, "fallbackPlanVersion": .null],
            ["fallbackPlanCode": .string(""), "fallbackPlanVersion": .integer(2)],
            ["fallbackPlanCode": .string(" "), "fallbackPlanVersion": .integer(2)],
            ["fallbackPlanCode": .string("safe_a"), "fallbackPlanVersion": .integer(2)],
            ["fallbackPlanCode": .string("SAFE_A"), "fallbackPlanVersion": .integer(0)],
            ["fallbackPlanCode": .string("SAFE_A"), "fallbackPlanVersion": .bool(true)]]
        for fields in invalid { XCTAssertThrowsError(try command(minimum.merging(fields) { _, new in new }).fields()) }
    }
    func testUnapprovedCodeOrVersionStillFailsAgainstCurrentProjection() throws {
        for code in ["OTHER", "SAFE_A"] {
            let fields = minimum.merging(["fallbackPlanCode": .string(code), "fallbackPlanVersion": .integer(9)]) { _, new in new }
            XCTAssertThrowsError(try command(fields).validate(projection: projection([option()])))
        }
    }
    func testNoFallbackDoesNotBypassActionStationStateOrRevision() throws {
        XCTAssertThrowsError(try command(minimum).validate(projection: projection(state: "PAUSED")))
        XCTAssertThrowsError(try command(minimum).validate(projection: projection(sessionState: "PREPARING")))
        XCTAssertThrowsError(try command(minimum).validate(projection: projection(actions: [])))
        XCTAssertThrowsError(try command(minimum, nodeID: 72).validate(projection: projection()))
        XCTAssertThrowsError(try command(minimum, revision: 2).validate(projection: projection()))
    }
    func testReasonIsOptionalButPresentReasonAndCivilTimeRemainValid() throws {
        XCTAssertNoThrow(try command(minimum).fields())
        for reason in [MerchantContentValue.null, .string(""), .string(String(repeating: "x", count: 201)), .integer(3)] {
            XCTAssertThrowsError(try command(minimum.merging(["reason": reason]) { _, new in new }).fields())
        }
        let value = try payload(in: projection(), reason: "   ")
        XCTAssertNil(value["reason"])
        XCTAssertThrowsError(try command(minimum.merging(["resumeEta": .string("2026-02-30 17:30")]) { _, new in new }).fields())
    }
    func testNoFallbackCannotSmuggleTargetRefundPaymentOrMerchantFields() {
        for key in ["fallbackNodeId", "refund", "payment", "merchantId", "reward"] {
            XCTAssertThrowsError(try command(minimum.merging([key: .integer(1)]) { _, new in new }).fields())
        }
    }
    func testWarningAppliesOnlyToPauseWithoutBothFallbackFields() {
        XCTAssertFalse(MerchantStationCommand(activityID: 80, nodeID: 62, expectedRevision: 3, action: .resume).pausesWithoutFallback)
        XCTAssertTrue(command(minimum).pausesWithoutFallback)
        XCTAssertFalse(command(minimum.merging(["fallbackPlanCode": .string("SAFE_A")]) { _, new in new }).pausesWithoutFallback)
    }
}
