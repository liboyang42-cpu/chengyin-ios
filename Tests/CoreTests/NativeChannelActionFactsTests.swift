import XCTest
@testable import QuestifyCore

final class NativeChannelActionFactsTests: XCTestCase {
    func testOriginalServerFactsArePreservedWithoutTranslation() {
        let facts = NativeChannelActionFacts(source: [
            "action_type": "MUTE", "status": "ACTIVE", "reason_code": "SPAM",
            "scope_type": "CHANNEL", "scope_id": "123", "duration_sec": 3600,
            "starts_at": "2026-10-31T06:00:00Z", "expires_at": "2026-10-31T07:00:00Z"
        ])
        XCTAssertEqual(facts.type, "MUTE")
        XCTAssertEqual(facts.status, "ACTIVE")
        XCTAssertEqual(facts.reasonCode, "SPAM")
        XCTAssertEqual(facts.scopeType, "CHANNEL")
        XCTAssertEqual(facts.scopeID, "123")
        XCTAssertEqual(facts.durationSeconds, 3600)
        XCTAssertEqual(facts.startsAt, "2026-10-31T06:00:00Z")
        XCTAssertEqual(facts.expiresAt, "2026-10-31T07:00:00Z")
    }
    func testAbsentExpiryIsNotInferredToBePermanentOrExpired() {
        let facts = NativeChannelActionFacts(source: [:])
        XCTAssertNil(facts.expiresAt)
        XCTAssertNil(facts.durationSeconds)
        XCTAssertNil(facts.status)
    }
    func testMalformedAndNegativeDurationStayUnknown() {
        for raw in [NSNull(), true, -1, 1.5, "1.5", "001", "invalid"] as [Any] {
            XCTAssertNil(NativeChannelActionFacts(source: ["duration_sec": raw]).durationSeconds)
        }
        XCTAssertEqual(NativeChannelActionFacts(source: ["duration_sec": 0]).durationSeconds, 0)
    }
    func testUnknownCodesAndOriginalWhitespaceAreNotInventedOrNormalized() {
        let facts = NativeChannelActionFacts(source: ["action_type": "FUTURE_TYPE", "reason_code": " 原代码 "])
        XCTAssertEqual(facts.type, "FUTURE_TYPE")
        XCTAssertEqual(facts.reasonCode, " 原代码 ")
    }
    func testMalformedStringsAndScopeStayUnknown() {
        let facts = NativeChannelActionFacts(source: ["status": 1, "starts_at": "  ", "expires_at": NSNull(), "scope_id": -1])
        XCTAssertNil(facts.status)
        XCTAssertNil(facts.startsAt)
        XCTAssertNil(facts.expiresAt)
        XCTAssertNil(facts.scopeID)
    }
}
