import XCTest
@testable import QuestifyCore

/// Synthetic numbers for contract shape only; no CITY cost, reward or budget is approved.
@MainActor final class CityGameCoordinatorTests: XCTestCase {
    private final class Service: CityGameServing {
        var snapshotValue: CityGameSnapshot
        var quoteValue: ((CityActionKind, String) -> CityActionQuote)?
        var failSubmit = false
        var missingReceipt = false
        var decision: CityActionReceipt.Decision = .applied
        var submitted: [CityActionIntent] = []
        var snapshots = 0
        var receipts: [String: CityActionReceipt] = [:]
        init(_ snapshot: CityGameSnapshot) { snapshotValue = snapshot }
        func snapshot(for read: CityReadSnapshot) async throws -> CityGameSnapshot { snapshots += 1; return snapshotValue }
        func deltas(after cursor: CityStreamCursor) async throws -> [CityDelta] { [] }
        func quote(_ kind: CityActionKind, targetId: String, read: CityReadSnapshot) async throws -> CityActionQuote {
            try XCTUnwrap(quoteValue)(kind, targetId)
        }
        func submit(_ intent: CityActionIntent) async throws -> CityActionReceipt {
            submitted.append(intent)
            let receipt = receipts[intent.requestId] ?? CityActionReceipt(requestId: intent.requestId, boardId: intent.boardId, action: intent.kind.rawValue,
                decision: decision, currentVersion: decision == .applied ? intent.expectedVersion + 1 : intent.expectedVersion,
                reasonCode: decision == .applied || decision == .quoteChanged ? nil : "SYNTHETIC", taskAttemptKept: false)
            receipts[intent.requestId] = receipt
            if failSubmit { failSubmit = false; throw URLError(.networkConnectionLost) }
            return receipt
        }
        func receipt(for intent: CityActionIntent) async throws -> CityActionReceipt? {
            if missingReceipt { missingReceipt = false; return nil }
            return receipts[intent.requestId]
        }
    }

    private func board(_ lifecycle: String = "OPEN") -> CityReadBoard {
        CityReadBoard(gameId: "g1", boardId: "b1", regionId: "r1", seasonId: "s1", rulesReleaseId: "rr1", rulesHash: String(repeating: "f", count: 64),
                      lifecycle: lifecycle, title: "Synthetic board", revision: 4)
    }
    private func read(_ lifecycle: String = "OPEN", joined: Bool = true) -> CityReadSnapshot {
        CityReadSnapshot(board: board(lifecycle), membership: joined ? .joined : .notJoined,
                         participation: joined ? CityParticipation(participationId: "p1", membershipVersion: 2) : nil,
                         points: [CityReadPoint(pointId: "pt-a", title: "A", latitude: 1, longitude: 2, mine: false),
                                  CityReadPoint(pointId: "pt-b", title: "B", latitude: 1.001, longitude: 2.001, mine: false)])
    }
    private func property(_ id: String = "prop-a", point: String = "pt-a", role: CityPropertyRole = .operable, status: CityPropertyStatus = .available,
                          mine: Bool = false, services: [CityServiceOffer] = [], protectedUntil: Int64? = nil) -> CityPropertyState {
        CityPropertyState(propertyId: id, pointId: point, role: role, status: status, stateVersion: 7, heldByMyTeam: mine,
                          protectedUntilMillis: protectedUntil, services: services, challenge: nil, taskAttemptKept: false)
    }
    private func snapshot(lifecycle: CityBoardLifecycle = .open, points: Int64? = 5, actions: Int? = 2, limit: Int? = 2,
                          properties: [CityPropertyState]? = nil, round: Int64? = 1) -> CityGameSnapshot {
        CityGameSnapshot(contract: "CITY_GAME_SNAPSHOT_V1", scope: "CITY", boardId: "b1", seasonId: "s1", boardVersion: 4, sequence: 9,
                         lifecycle: lifecycle, roundSeq: round,
                         rules: CityRulesSummary(rulesReleaseId: "rr1", ruleVersion: "synthetic", validFromMillis: 1, validUntilMillis: nil,
                                                 actionsRemaining: actions, actionsPerRound: actions == nil ? nil : 3, holdingLimit: limit),
                         properties: properties ?? [property(), property("prop-b", point: "pt-b", role: .neutral)],
                         memberPoints: points, neutralTasksAvailable: true)
    }
    nonisolated private func quote(_ kind: CityActionKind, _ target: String, payer: String = "me", cost: Int64 = 3) -> CityActionQuote {
        CityActionQuote(quoteId: "q-\(target)", quoteVersion: 1, action: kind.rawValue, boardId: "b1", targetId: target, payerMemberId: payer,
                        ruleVersion: "synthetic", memberPointsCost: cost, actionCost: 1, beneficiaryMemberIds: ["me"],
                        expiresAtMillis: Int64((Date().timeIntervalSince1970 + 600) * 1000))
    }
    private func model(_ service: Service?, read value: CityReadSnapshot? = nil, capabilities: ReformWorldCapabilities = .syntheticFixture([.cityActions]),
                       current: @escaping () -> Bool = { true }) -> CityGameCoordinator {
        CityGameCoordinator(read: value ?? read(), service: service, capabilities: capabilities, memberId: "me", isCurrent: current)
    }

    func testProjectionValidationRejectsLeaksAndInventedFacts() throws {
        try snapshot().validate(against: read())
        // Property on a point the player cannot see.
        XCTAssertThrowsError(try snapshot(properties: [property(point: "pt-hidden")]).validate(against: read()))
        // Neutral goals cannot be held or sell services.
        XCTAssertThrowsError(try snapshot(properties: [property(role: .neutral, status: .held)]).validate(against: read()))
        // Protected requires a published protection end; available cannot carry services.
        XCTAssertThrowsError(try snapshot(properties: [property(status: .protected)]).validate(against: read()))
        XCTAssertThrowsError(try snapshot(properties: [property(services: [CityServiceOffer(serviceId: "s1", title: "S", memberPointsFee: 1)])]).validate(against: read()))
        // Half-published budget and over-limit holdings are invalid.
        XCTAssertThrowsError(try CityGameSnapshot(contract: "CITY_GAME_SNAPSHOT_V1", scope: "CITY", boardId: "b1", seasonId: "s1", boardVersion: 4, sequence: 1,
            lifecycle: .open, roundSeq: 1, rules: CityRulesSummary(rulesReleaseId: "rr1", ruleVersion: "x", validFromMillis: 1, validUntilMillis: nil,
            actionsRemaining: 1, actionsPerRound: nil, holdingLimit: nil), properties: [], memberPoints: nil, neutralTasksAvailable: true).validate(against: read()))
        XCTAssertThrowsError(try snapshot(limit: 1, properties: [property(status: .held, mine: true), property("prop-c", point: "pt-b", status: .held, mine: true)]).validate(against: read()))
        // Another board/release or a non-member with "my team" facts.
        XCTAssertThrowsError(try snapshot().validate(against: CityReadSnapshot(board: CityReadBoard(gameId: "g1", boardId: "b2", regionId: "r1", seasonId: "s1",
            rulesReleaseId: "rr1", rulesHash: String(repeating: "f", count: 64), lifecycle: "OPEN", title: "B", revision: 1), membership: .joined,
            participation: CityParticipation(participationId: "p1", membershipVersion: 1), points: read().points))) { XCTAssertEqual($0 as? CityGameProjectionIssue, .boardMismatch) }
        XCTAssertThrowsError(try snapshot().validate(against: read(joined: false)))
        // Unpublished facts stay nil rather than defaulting.
        try snapshot(points: nil, actions: nil, limit: nil).validate(against: read())
    }

    func testEndpointAllowlistIsEmptyAndCapabilityIsOffByDefault() async {
        for market in RegionalMarket.allCases {
            XCTAssertFalse(CityGameEndpointAllowlist.playable(market: market))
            XCTAssertTrue(CityGameOperation.allCases.allSatisfy { !CityGameEndpointAllowlist.allows($0, market: market) })
        }
        let service = Service(snapshot())
        let off = model(service, capabilities: .disabled)
        XCTAssertEqual(off.phase, .disabled)
        await off.load()
        XCTAssertEqual(service.snapshots, 0)
        XCTAssertEqual(model(nil).phase, .disabled)
    }

    func testPaidActionNeedsReviewAndSendsOnlyAfterConfirmation() async throws {
        let service = Service(snapshot()); service.quoteValue = { self.quote($0, $1) }
        let game = model(service)
        await game.load()
        XCTAssertEqual(game.phase, .ready)
        let target = try XCTUnwrap(game.snapshot?.properties.first)
        XCTAssertEqual(game.actions(for: target), [.acceptTask, .acquireProperty])
        await game.prepare(.acquireProperty, property: target)
        XCTAssertEqual(game.phase, .review); XCTAssertEqual(game.review?.quote?.memberPointsCost, 3)
        game.cancelReview()
        XCTAssertTrue(service.submitted.isEmpty)
        await game.prepare(.acquireProperty, property: target)
        await game.confirm()
        XCTAssertEqual(service.submitted.count, 1)
        let body = String(decoding: try service.submitted[0].body(), as: UTF8.self)
        XCTAssertTrue(body.contains("\"payerMemberId\":\"me\"")); XCTAssertFalse(body.contains("memberPointsCost"))
        XCTAssertEqual(game.lastOutcome, .applied(version: 8)); XCTAssertEqual(game.phase, .ready)
    }

    func testTeammatePayerQuoteIsRefusedAndInsufficientPointsNeverSend() async throws {
        let service = Service(snapshot(points: 0)); service.quoteValue = { self.quote($0, $1, payer: "teammate") }
        let game = model(service); await game.load()
        let target = try XCTUnwrap(game.snapshot?.properties.first)
        await game.prepare(.acquireProperty, property: target)
        XCTAssertEqual(game.notice, .payerMismatch); XCTAssertNil(game.review)
        service.quoteValue = { self.quote($0, $1) }
        await game.prepare(.acquireProperty, property: target)
        XCTAssertFalse(game.reviewAffordable)
        await game.confirm()
        XCTAssertEqual(game.notice, .insufficientPoints); XCTAssertTrue(service.submitted.isEmpty)
        // Neutral goals remain available at zero points.
        let neutral = try XCTUnwrap(game.snapshot?.properties.last)
        game.cancelReview()
        XCTAssertEqual(game.actions(for: neutral), [.acceptTask])
    }

    func testUnknownOutcomeIsReadBackAndRetryKeepsTheSameRequest() async throws {
        let service = Service(snapshot()); service.failSubmit = true; service.missingReceipt = true
        let game = model(service); await game.load()
        let neutral = try XCTUnwrap(game.snapshot?.properties.last)
        await game.prepare(.acceptTask, property: neutral)
        await game.confirm()
        XCTAssertEqual(game.phase, .unknown); XCTAssertTrue(game.canRetryExact)
        let requestId = try XCTUnwrap(game.pendingIntent?.requestId)
        // A fresh snapshot never settles the unknown outcome.
        await game.load(); XCTAssertEqual(game.phase, .unknown)
        await game.readBack()
        XCTAssertEqual(game.notice, .noReceiptYet); XCTAssertEqual(game.phase, .unknown)
        await game.retryExact()
        XCTAssertEqual(service.submitted.map(\.requestId), [requestId, requestId])
        XCTAssertEqual(game.lastOutcome, .applied(version: 8)); XCTAssertNil(game.pendingIntent)
    }

    func testChangedQuoteRequiresANewReviewAndBlockedAreShown() async throws {
        let service = Service(snapshot()); service.quoteValue = { self.quote($0, $1) }; service.decision = .quoteChanged
        let game = model(service); await game.load()
        let target = try XCTUnwrap(game.snapshot?.properties.first)
        await game.prepare(.acquireProperty, property: target); await game.confirm()
        XCTAssertEqual(game.lastOutcome, .requote); XCTAssertNil(game.review); XCTAssertEqual(service.submitted.count, 1)
        service.decision = .blocked
        await game.prepare(.acceptTask, property: target); await game.confirm()
        XCTAssertEqual(game.lastOutcome, .blocked("SYNTHETIC"))
    }

    func testFrozenPausedSafetyAndBudgetGateEveryChoice() async throws {
        let frozen = model(Service(snapshot(lifecycle: .frozen)), read: read("FROZEN")); await frozen.load()
        XCTAssertEqual(frozen.boardNotice, .boardNotOpen); XCTAssertFalse(frozen.canRoll)
        XCTAssertTrue(try XCTUnwrap(frozen.snapshot).properties.allSatisfy { frozen.actions(for: $0).isEmpty })
        let fee = CityServiceOffer(serviceId: "svc", title: "S", memberPointsFee: 1), hidden = CityServiceOffer(serviceId: "svc2", title: "T", memberPointsFee: nil)
        let paused = model(Service(snapshot(properties: [property(status: .paused, services: [fee]), property("prop-b", point: "pt-b", status: .safetyBlocked)]))); await paused.load()
        let pausedProps = try XCTUnwrap(paused.snapshot).properties
        XCTAssertTrue(pausedProps.allSatisfy { paused.actions(for: $0).isEmpty }); XCTAssertFalse(paused.canAcceptService(fee, on: pausedProps[0]))
        let held = model(Service(snapshot(properties: [property(status: .held, services: [fee, hidden])]))); await held.load()
        let heldProp = try XCTUnwrap(held.snapshot?.properties.first)
        XCTAssertEqual(held.actions(for: heldProp), [.acceptTask, .startChallenge])
        XCTAssertTrue(held.canAcceptService(fee, on: heldProp)); XCTAssertFalse(held.canAcceptService(hidden, on: heldProp))
        let spent = model(Service(snapshot(actions: 0))); await spent.load()
        XCTAssertFalse(spent.canRoll); XCTAssertTrue(try XCTUnwrap(spent.snapshot).properties.allSatisfy { spent.actions(for: $0).isEmpty })
        let unpublished = model(Service(snapshot(limit: nil))); await unpublished.load()
        XCTAssertEqual(unpublished.actions(for: try XCTUnwrap(unpublished.snapshot?.properties.first)), [.acceptTask])
    }

    func testSessionChangeInvalidatesEverything() async throws {
        var current = true
        let service = Service(snapshot()); service.failSubmit = true
        let game = model(service, current: { current }); await game.load()
        game.prepareRoll(); await game.confirm()
        XCTAssertEqual(game.phase, .unknown)
        current = false
        await game.retryExact()
        XCTAssertEqual(game.phase, .invalidated); XCTAssertNil(game.pendingIntent); XCTAssertNil(game.snapshot)
        XCTAssertEqual(service.submitted.count, 1)
    }
}
