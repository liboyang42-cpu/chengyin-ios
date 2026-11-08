import XCTest
@testable import QuestifyCore

final class PlayQATextActionReceiptTests: XCTestCase {
    private func pending(action: String = "SUBMIT_QA", input: PlayWireValue = .string("  Synthetic answer😀  "),
                         key: String = "synthetic-original-key", version: Int = 2) -> PlayAdvancedPending {
        .init(sessionID: 1, version: version, key: key, action: action, payload: ["input": input])
    }
    private var raw: PlayWireValue {
        .object(["sessionId": .string("1"), "idempotencyKey": .string("synthetic-original-key"),
                 "view": .object(["sessionId": .int(1), "activityId": .int(41), "topicId": .int(71),
                                  "nodeId": .int(701), "version": .int(3), "status": .string("RUNNING"),
                                  "playKit": .object(["qa": .object(["passed": .bool(false)])])])])
    }
    private func decode(_ raw: PlayWireValue, pending: PlayAdvancedPending? = nil) throws -> PlayQATextActionReceipt {
        try .init(raw, pending: pending ?? self.pending(), activityID: 41, topicID: 71, nodeID: 701)
    }
    private func changing(_ key: String, to value: PlayWireValue, inView: Bool = false) -> PlayWireValue {
        var object = raw.object!
        if inView { var view = object["view"]!.object!; view[key] = value; object["view"] = .object(view) }
        else { object[key] = value }
        return .object(object)
    }
    func testQueryContainsOnlyOriginalIdentityAndPreservesOriginalRequest() throws {
        let original = pending()
        XCTAssertEqual(try PlayQATextActionReceipt.query(for: original), ["sessionId": "1", "idempotencyKey": original.key])
        XCTAssertEqual(original.payload["input"]?.text, "  Synthetic answer😀  ")
        XCTAssertEqual(original.version, 2)
    }
    func testMatchedReceiptPreservesServerFailureAndWholeView() throws {
        let receipt = try decode(raw)
        XCTAssertEqual(receipt.view, raw["view"])
        XCTAssertEqual(receipt.view["playKit"]["qa"]["passed"].bool, false)
    }
    func testOuterSessionMustBeExactCanonicalString() {
        for value: PlayWireValue in [.int(1), .string("01"), .string(" 1"), .string("2"), .null] {
            XCTAssertThrowsError(try decode(changing("sessionId", to: value)))
        }
    }
    func testReceiptKeyMustMatchOriginalBytes() {
        for key in ["other", "synthetic-original-key ", "SYNTHETIC-ORIGINAL-KEY"] {
            XCTAssertThrowsError(try decode(changing("idempotencyKey", to: .string(key))))
        }
    }
    func testInnerIdentityMismatchCannotClearUnknown() {
        for field in ["sessionId", "activityId", "topicId", "nodeId"] {
            XCTAssertThrowsError(try decode(changing(field, to: .int(99), inView: true)))
        }
    }
    func testNonAdvancingOrMalformedViewIsRejected() {
        for value: PlayWireValue in [.int(2), .int(1), .string("3"), .null] {
            XCTAssertThrowsError(try decode(changing("version", to: value, inView: true)))
        }
        XCTAssertThrowsError(try decode(changing("view", to: .null)))
        XCTAssertThrowsError(try decode(changing("status", to: .string(""), inView: true)))
    }
    func testNoOtherQAOrChallengeTypeIsClaimed() {
        XCTAssertFalse(PlayQATextActionReceipt.owns(nil))
        XCTAssertFalse(PlayQATextActionReceipt.owns(pending(action: "SUBMIT_REACTION")))
        XCTAssertFalse(PlayQATextActionReceipt.owns(.init(sessionID: 1, version: 2, key: "key", action: "SUBMIT_QA", payload: ["selected": .array([])])))
        XCTAssertFalse(PlayQATextActionReceipt.owns(.init(sessionID: 1, version: 2, key: "key", action: "SUBMIT_QA", payload: ["input": .string("x"), "selected": .array([])])))
        XCTAssertTrue(PlayQATextActionReceipt.owns(pending(input: .null)), "Malformed text requests still cannot fall into replay")
    }
    func testOnlyOriginalOrdinaryTextSegmentSelectsReceiptIntegration() {
        XCTAssertTrue(PlayQATextActionReceipt.matchesTextMode(.object(["mode": .string("TYPE")])))
        XCTAssertTrue(PlayQATextActionReceipt.matchesTextMode(.object([:])))
        for mode in ["HANGMAN", "PICK", "SHOT", "UNKNOWN"] {
            XCTAssertFalse(PlayQATextActionReceipt.matchesTextMode(.object(["mode": .string(mode)])))
        }
        XCTAssertFalse(PlayQATextActionReceipt.matchesTextMode(.null))
    }
    func testInvalidOriginalRequestNeverBuildsAReadQuery() {
        for original in [pending(input: .null), pending(input: .string(" \n")), pending(input: .string(String(repeating: "😀", count: 2049))),
                         pending(key: ""), pending(key: String(repeating: "😀", count: 33)), pending(version: -1), pending(action: "SUBMIT_SORT")] {
            XCTAssertThrowsError(try PlayQATextActionReceipt.query(for: original))
        }
    }
    func testReceiptNotFoundConflictAndTransportFailureStayUnknown() {
        let errors: [Error] = [PlayExperienceError.rejected(404, "not found"), PlayExperienceError.rejected(409, "conflict"),
                               PlayExperienceError.disabled, PlayExperienceError.malformed, PlayExperienceError.unknownResult,
                               APIError.invalidRequest, CancellationError()]
        for error in errors { XCTAssertEqual(PlayQATextActionReceipt.failurePhase(error, ownerIsCurrent: true), "unknown") }
    }
    func testAccountWithdrawalOrUnauthorizedCannotDiscloseReceipt() {
        XCTAssertEqual(PlayQATextActionReceipt.failurePhase(PlayExperienceError.rejected(404, nil), ownerIsCurrent: false), "stale")
        XCTAssertEqual(PlayQATextActionReceipt.failurePhase(PlayExperienceError.unauthorized, ownerIsCurrent: true), "stale")
        XCTAssertEqual(PlayQATextActionReceipt.failurePhase(APIError.unauthorized, ownerIsCurrent: true), "stale")
    }
}
