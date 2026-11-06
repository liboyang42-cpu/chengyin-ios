import XCTest
@testable import QuestifyCore

final class CityActionContractTests: XCTestCase {
    private func board(lifecycle: String = "OPEN") throws -> CityReadBoard {
        try JSONDecoder().decode(CityReadBoard.self, from: Data("{\"gameId\":\"g1\",\"boardId\":\"b1\",\"regionId\":\"r1\",\"seasonId\":\"s1\",\"rulesReleaseId\":\"rr1\",\"rulesHash\":\"\(String(repeating: "f", count: 64))\",\"lifecycle\":\"\(lifecycle)\",\"title\":\"Synthetic board\",\"revision\":4}".utf8))
    }
    private func participation() throws -> CityParticipation {
        try JSONDecoder().decode(CityParticipation.self, from: Data("{\"participationId\":\"p1\",\"membershipVersion\":2}".utf8))
    }
    // Synthetic numbers for contract shape only; no CITY cost/reward value is approved.
    private func quote(payer: String = "me", expires: Int64 = 2_000_000_000_000) throws -> CityActionQuote {
        try JSONDecoder().decode(CityActionQuote.self, from: Data("{\"quoteId\":\"q1\",\"quoteVersion\":3,\"action\":\"ACQUIRE_PROPERTY\",\"boardId\":\"b1\",\"targetId\":\"prop-1\",\"payerMemberId\":\"\(payer)\",\"ruleVersion\":\"synthetic\",\"memberPointsCost\":1,\"actionCost\":1,\"beneficiaryMemberIds\":[\"me\"],\"expiresAtMillis\":\(expires)}".utf8))
    }
    private let now = Date(timeIntervalSince1970: 1_900_000_000)
    private let enabled = ReformWorldCapabilities.syntheticFixture([.cityActions])

    func testPaidActionNeedsExplicitConsentFromThePayerThemself() throws {
        XCTAssertThrowsError(try CityPayerConsent(quote: quote(), confirmingMemberId: "me", confirmed: false, deviceNow: now, serverOffset: 0)) { XCTAssertEqual($0 as? CityActionIssue, .unconfirmed) }
        XCTAssertThrowsError(try CityPayerConsent(quote: quote(payer: "teammate"), confirmingMemberId: "me", confirmed: true, deviceNow: now, serverOffset: 0)) { XCTAssertEqual($0 as? CityActionIssue, .payerMismatch) }
        XCTAssertThrowsError(try CityPayerConsent(quote: quote(expires: 1_800_000_000_000), confirmingMemberId: "me", confirmed: true, deviceNow: now, serverOffset: 0)) { XCTAssertEqual($0 as? CityActionIssue, .quoteExpired) }
        let consent = try CityPayerConsent(quote: quote(), confirmingMemberId: "me", confirmed: true, deviceNow: now, serverOffset: 0)
        XCTAssertThrowsError(try CityActionIntent(kind: .acquireProperty, board: board(), lifecycle: .open, participation: participation(), targetId: "prop-1", roundSeq: 1, expectedVersion: 4, consent: nil)) { XCTAssertEqual($0 as? CityActionIssue, .unconfirmed) }
        XCTAssertThrowsError(try CityActionIntent(kind: .roll, board: board(), lifecycle: .open, participation: participation(), targetId: "b1", roundSeq: 1, expectedVersion: 4, consent: consent))
        let intent = try CityActionIntent(kind: .acquireProperty, board: board(), lifecycle: .open, participation: participation(), targetId: "prop-1", roundSeq: 1, expectedVersion: 4, consent: consent, requestId: "city-req-0001")
        let body = String(decoding: try intent.body(), as: UTF8.self)
        XCTAssertTrue(body.contains("\"payerMemberId\":\"me\"")); XCTAssertFalse(body.contains("memberPointsCost")); XCTAssertFalse(body.contains("dice"))
    }

    func testOnlyOpenBoardWithParticipationAcceptsActions() throws {
        XCTAssertThrowsError(try CityActionIntent(kind: .roll, board: board(lifecycle: "FROZEN"), lifecycle: .frozen, participation: participation(), targetId: "b1", roundSeq: 1, expectedVersion: 4, consent: nil)) { XCTAssertEqual($0 as? CityActionIssue, .boardNotOpen) }
        XCTAssertThrowsError(try CityActionIntent(kind: .roll, board: board(), lifecycle: .open, participation: nil, targetId: "b1", roundSeq: 1, expectedVersion: 4, consent: nil)) { XCTAssertEqual($0 as? CityActionIssue, .notJoined) }
        XCTAssertFalse(CityBoardLifecycle.closing.acceptsNewActions)
    }

    func testDisabledByDefaultAndExactRetryOnly() throws {
        let intent = try CityActionIntent(kind: .roll, board: board(), lifecycle: .open, participation: participation(), targetId: "b1", roundSeq: 2, expectedVersion: 4, consent: nil, requestId: "city-req-0002")
        var pending = CityPendingAction()
        XCTAssertThrowsError(try pending.begin(intent, capabilities: .disabled)) { XCTAssertEqual($0 as? CityActionIssue, .disabled) }
        try pending.begin(intent, capabilities: enabled)
        XCTAssertEqual(try pending.resolve(nil), .unknown)
        XCTAssertNoThrow(try pending.begin(intent, capabilities: enabled))
        let reroll = try CityActionIntent(kind: .roll, board: board(), lifecycle: .open, participation: participation(), targetId: "b1", roundSeq: 2, expectedVersion: 4, consent: nil, requestId: "city-req-0003")
        XCTAssertThrowsError(try pending.begin(reroll, capabilities: enabled)) { XCTAssertEqual($0 as? CityActionIssue, .busy) }
    }

    func testReceiptOutcomesKeepTaskAndNeverAutoRequote() throws {
        func receipt(_ decision: String, version: Int64, reason: String? = nil, kept: Bool = false, requestId: String = "city-req-0004") throws -> CityActionReceipt {
            let reasonField = reason.map { ",\"reasonCode\":\"\($0)\"" } ?? ""
            return try JSONDecoder().decode(CityActionReceipt.self, from: Data("{\"requestId\":\"\(requestId)\",\"boardId\":\"b1\",\"action\":\"ACQUIRE_PROPERTY\",\"decision\":\"\(decision)\",\"currentVersion\":\(version),\"taskAttemptKept\":\(kept)\(reasonField)}".utf8))
        }
        let consent = try CityPayerConsent(quote: quote(), confirmingMemberId: "me", confirmed: true, deviceNow: now, serverOffset: 0)
        let intent = try CityActionIntent(kind: .acquireProperty, board: board(), lifecycle: .open, participation: participation(), targetId: "prop-1", roundSeq: 1, expectedVersion: 4, consent: consent, requestId: "city-req-0004")
        var pending = CityPendingAction()
        try pending.begin(intent, capabilities: enabled)
        XCTAssertThrowsError(try pending.resolve(receipt("APPLIED", version: 5, requestId: "city-req-9999")))
        XCTAssertEqual(try pending.resolve(receipt("VERSION_CONFLICT", version: 6, kept: true)), .refresh(taskAttemptKept: true))
        try pending.begin(intent, capabilities: enabled)
        XCTAssertEqual(try pending.resolve(receipt("QUOTE_CHANGED", version: 4)), .requote)
        try pending.begin(intent, capabilities: enabled)
        XCTAssertEqual(try pending.resolve(receipt("EFFECT_ALREADY_APPLIED", version: 5, reason: "SAME_EFFECT")), .alreadyApplied)
        try pending.begin(intent, capabilities: enabled)
        XCTAssertEqual(try pending.resolve(receipt("BLOCKED", version: 4, reason: "MERCHANT_PAUSED")), .blocked("MERCHANT_PAUSED"))
    }

    func testChallengeStateMachine() {
        XCTAssertTrue(CityChallengeState.offered.canAdvance(to: .accepted))
        XCTAssertFalse(CityChallengeState.offered.canAdvance(to: .resolved))
        XCTAssertTrue(CityChallengeState.accepted.canAdvance(to: .suspended))
        XCTAssertFalse(CityChallengeState.resolved.canAdvance(to: .cancelled))
        XCTAssertFalse(CityChallengeState.expired.canAdvance(to: .expired))
    }

    private func delta(_ seq: Int64, id: String? = nil, version: Int64 = 4, board: String = "b1", season: String = "s1") throws -> CityDelta {
        try JSONDecoder().decode(CityDelta.self, from: Data("{\"eventId\":\"\(id ?? "e\(seq)")\",\"boardId\":\"\(board)\",\"seasonId\":\"\(season)\",\"aggregate\":\"prop-1\",\"type\":\"PROPERTY_CHANGED\",\"sequence\":\(seq),\"boardVersion\":\(version)}".utf8))
    }

    func testDeltaStreamDedupesReordersAndRefetchesOnGap() throws {
        var stream = CityDeltaStream(cursor: try CityStreamCursor(board: board(), sequence: 10))
        XCTAssertEqual(stream.ingest([try delta(12), try delta(11)]), .applied([try delta(11), try delta(12)]))
        XCTAssertEqual(stream.cursor.sequence, 12)
        XCTAssertEqual(stream.ingest([try delta(12), try delta(9)]), .unchanged)
        XCTAssertEqual(stream.ingest([try delta(14)]), .snapshotRequired)
        XCTAssertEqual(stream.ingest([try delta(13, season: "s2")]), .snapshotRequired)
        XCTAssertEqual(stream.ingest([try delta(13), try delta(13, id: "other")]), .snapshotRequired)
        XCTAssertEqual(stream.ingest([try delta(13, version: 3)]), .snapshotRequired)
        XCTAssertEqual(stream.cursor.sequence, 12)
    }

    func testOlderSnapshotDoesNotRewindCursor() throws {
        var stream = CityDeltaStream(cursor: try CityStreamCursor(board: board(), sequence: 10))
        XCTAssertFalse(stream.reset(to: try CityStreamCursor(board: board(), sequence: 9)))
        XCTAssertTrue(stream.reset(to: try CityStreamCursor(board: board(), sequence: 20)))
        XCTAssertTrue(stream.reset(to: try CityStreamCursor(boardId: "b2", seasonId: "s2", rulesReleaseId: "rr2", boardVersion: 1, sequence: 0)))
    }
}
