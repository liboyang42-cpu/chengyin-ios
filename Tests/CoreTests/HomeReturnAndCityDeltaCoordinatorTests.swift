import XCTest
@testable import QuestifyCore

@MainActor final class HomeReturnAndCityDeltaCoordinatorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)
    private let enabledCapabilities = ReformWorldCapabilities.syntheticFixture([.homeReturnRestore, .cityActions])

    private func makeHome(version: Int64 = 3, active: Bool = true) throws -> PrivateHomeSnapshot {
        let json = active
            ? "{\"version\":\(version),\"status\":\"ACTIVE\",\"changedAt\":1,\"effectiveAt\":1,\"label\":\"SecretBase\",\"latitude\":12.345,\"longitude\":45.678,\"datum\":\"WGS84\"}"
            : "{\"version\":\(version),\"status\":\"DELETED\"}"
        return try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(json.utf8))
    }

    private func makePolicy() throws -> HomeReturnPolicy {
        try JSONDecoder().decode(
            HomeReturnPolicy.self,
            from: Data("{\"policyVersion\":\"synthetic-v1\",\"maxAccuracyMeters\":50,\"maxFixAgeSeconds\":30}".utf8)
        )
    }

    private func makeRestoreReceipt(
        requestId: String = "restore-req-0001",
        proofId: String = "proof-1",
        decision: String,
        current: Int64,
        maximum: Int64,
        accountVersion: Int64,
        retryAfterSeconds: Int? = nil
    ) throws -> HomeRestoreReceipt {
        let retryFragment = retryAfterSeconds.map { ",\"retryAfterSeconds\":\($0)" } ?? ""
        let raw = "{\"requestId\":\"\(requestId)\",\"proofId\":\"\(proofId)\",\"decision\":\"\(decision)\",\"current\":\(current),\"maximum\":\(maximum),\"accountVersion\":\(accountVersion)\(retryFragment)}"
        return try JSONDecoder().decode(HomeRestoreReceipt.self, from: Data(raw.utf8))
    }

    private func makeBoard(
        boardId: String = "b1",
        seasonId: String = "s1",
        lifecycle: String = "OPEN",
        revision: Int64 = 4
    ) throws -> CityReadBoard {
        let rulesHash = String(repeating: "a", count: 64)
        let raw = "{\"gameId\":\"g1\",\"boardId\":\"\(boardId)\",\"regionId\":\"r1\",\"seasonId\":\"\(seasonId)\",\"rulesReleaseId\":\"rr1\",\"rulesHash\":\"\(rulesHash)\",\"lifecycle\":\"\(lifecycle)\",\"title\":\"Synthetic board\",\"revision\":\(revision)}"
        return try JSONDecoder().decode(CityReadBoard.self, from: Data(raw.utf8))
    }

    private func makeParticipation(id: String = "p1", version: Int64 = 2) throws -> CityParticipation {
        try JSONDecoder().decode(
            CityParticipation.self,
            from: Data("{\"participationId\":\"\(id)\",\"membershipVersion\":\(version)}".utf8)
        )
    }

    private func makeQuote(
        quoteId: String = "q1",
        quoteVersion: Int64 = 3,
        action: String = "ACQUIRE_PROPERTY",
        boardId: String = "b1",
        targetId: String = "prop-1",
        payer: String = "me",
        expiresAtMillis: Int64 = 2_000_000_000_000
    ) throws -> CityActionQuote {
        let raw = "{\"quoteId\":\"\(quoteId)\",\"quoteVersion\":\(quoteVersion),\"action\":\"\(action)\",\"boardId\":\"\(boardId)\",\"targetId\":\"\(targetId)\",\"payerMemberId\":\"\(payer)\",\"ruleVersion\":\"synthetic\",\"memberPointsCost\":1,\"actionCost\":1,\"beneficiaryMemberIds\":[\"me\"],\"expiresAtMillis\":\(expiresAtMillis)}"
        return try JSONDecoder().decode(CityActionQuote.self, from: Data(raw.utf8))
    }

    private func makeActionReceipt(
        requestId: String,
        action: String = "ACQUIRE_PROPERTY",
        decision: String,
        currentVersion: Int64,
        reasonCode: String? = nil,
        taskAttemptKept: Bool = false
    ) throws -> CityActionReceipt {
        let reasonFragment = reasonCode.map { ",\"reasonCode\":\"\($0)\"" } ?? ""
        let raw = "{\"requestId\":\"\(requestId)\",\"boardId\":\"b1\",\"action\":\"\(action)\",\"decision\":\"\(decision)\",\"currentVersion\":\(currentVersion),\"taskAttemptKept\":\(taskAttemptKept)\(reasonFragment)}"
        return try JSONDecoder().decode(CityActionReceipt.self, from: Data(raw.utf8))
    }

    private func makeDelta(
        sequence: Int64,
        eventId: String? = nil,
        boardVersion: Int64 = 4,
        boardId: String = "b1",
        seasonId: String = "s1"
    ) throws -> CityDelta {
        let resolvedId = eventId ?? "e\(sequence)"
        let raw = "{\"eventId\":\"\(resolvedId)\",\"boardId\":\"\(boardId)\",\"seasonId\":\"\(seasonId)\",\"aggregate\":\"prop-1\",\"type\":\"PROPERTY_CHANGED\",\"sequence\":\(sequence),\"boardVersion\":\(boardVersion)}"
        return try JSONDecoder().decode(CityDelta.self, from: Data(raw.utf8))
    }

    func testDefaultCapabilitiesStayDisabledAndDescriptionsStayRedacted() throws {
        let combined = HomeReturnAndCityDeltaCoordinator()
        XCTAssertEqual(combined.capabilities, .disabled)
        XCTAssertEqual(combined.homeReturn.phase, .disabled)

        let city = try combined.configureCity(
            board: makeBoard(),
            lifecycle: .open,
            participation: makeParticipation(),
            initialSequence: 5
        )
        XCTAssertEqual(city.phase, .disabled)
        XCTAssertFalse(city.canAcceptNewActions)

        let scope = HomeResourceScope.global(resourceType: "stamina")
        let result = combined.homeReturn.evaluatePreflight(
            home: try makeHome(),
            status: .fix(accuracyMeters: 8, capturedAt: now),
            policy: try makePolicy(),
            scope: scope,
            now: now,
            requestId: "home-req-0001"
        )
        XCTAssertEqual(result, .failure(HomeReturnFailurePresentation(failure: .disabled, scope: scope)))

        let enabledHome = HomeReturnRestoreCoordinator(capabilities: enabledCapabilities)
        let okResult = enabledHome.evaluatePreflight(
            home: try makeHome(),
            status: .fix(accuracyMeters: 8, capturedAt: now),
            policy: try makePolicy(),
            scope: scope,
            now: now,
            requestId: "home-req-0002"
        )
        guard case .success(let check) = okResult else {
            return XCTFail("Expected preflight success")
        }

        let descriptions = [
            String(describing: combined),
            String(reflecting: combined),
            String(describing: enabledHome),
            String(reflecting: enabledHome),
            String(describing: enabledHome.phase),
            String(describing: check),
            String(describing: HomeReturnFailurePresentation(failure: .lowAccuracy, scope: scope)),
        ]
        for text in descriptions {
            XCTAssertTrue(text.contains("[redacted]"), "Expected redacted description: \(text)")
            XCTAssertFalse(text.contains("12.345"))
            XCTAssertFalse(text.contains("45.678"))
            XCTAssertFalse(text.contains("SecretBase"))
        }
    }

    func testHomeReturnPreflightFailurePresentationAndResourceScopeRejectsAllGames() throws {
        XCTAssertEqual(
            try HomeReturnRestoreCoordinator.makeResourceScope(scopeType: "GLOBAL", resourceType: "stamina"),
            .global(resourceType: "stamina")
        )
        XCTAssertEqual(
            try HomeReturnRestoreCoordinator.makeResourceScope(scopeType: "RUN", scopeId: "run-9", resourceType: "energy"),
            .run(runId: "run-9", resourceType: "energy")
        )
        XCTAssertEqual(
            try HomeReturnRestoreCoordinator.makeResourceScope(scopeType: "THEME", scopeId: "theme-3", resourceType: "hint"),
            .theme(themeId: "theme-3", resourceType: "hint")
        )

        for forbiddenScope in ["ALL_GAMES", "ALL", "all_games", "*"] {
            XCTAssertThrowsError(
                try HomeReturnRestoreCoordinator.makeResourceScope(scopeType: forbiddenScope, resourceType: "stamina")
            ) { error in
                XCTAssertEqual(error as? HomeReturnFailure, .invalid)
            }
        }
        XCTAssertThrowsError(
            try HomeReturnRestoreCoordinator.makeResourceScope(scopeType: "GLOBAL", scopeId: "unexpected", resourceType: "stamina")
        )
        XCTAssertThrowsError(
            try HomeReturnRestoreCoordinator.makeResourceScope(scopeType: "RUN", scopeId: nil, resourceType: "stamina")
        )

        let coordinator = HomeReturnRestoreCoordinator(capabilities: enabledCapabilities)
        let scope = HomeResourceScope.run(runId: "run-1", resourceType: "stamina")
        let policy = try makePolicy()
        let activeHome = try makeHome()

        let servicesOff = coordinator.evaluatePreflight(
            home: activeHome,
            status: .servicesOff,
            policy: policy,
            scope: scope,
            now: now,
            requestId: "home-req-0010"
        )
        XCTAssertEqual(servicesOff, .failure(.init(failure: .locationOff, scope: scope)))
        XCTAssertEqual(coordinator.lastFailure?.retryableNow, false)
        XCTAssertEqual(coordinator.lastFailure?.requiresSettingsAction, true)

        let denied = coordinator.evaluatePreflight(
            home: activeHome,
            status: .denied,
            policy: policy,
            scope: scope,
            now: now,
            requestId: "home-req-0011"
        )
        XCTAssertEqual(denied, .failure(.init(failure: .permissionDenied, scope: scope)))
        XCTAssertEqual(coordinator.lastFailure?.retryableNow, false)
        XCTAssertEqual(coordinator.lastFailure?.requiresSettingsAction, true)

        let lowAccuracy = coordinator.evaluatePreflight(
            home: activeHome,
            status: .fix(accuracyMeters: 55, capturedAt: now),
            policy: policy,
            scope: scope,
            now: now,
            requestId: "home-req-0012"
        )
        XCTAssertEqual(lowAccuracy, .failure(.init(failure: .lowAccuracy, scope: scope)))
        XCTAssertEqual(coordinator.lastFailure?.retryableNow, true)
        XCTAssertEqual(coordinator.lastFailure?.requiresSettingsAction, false)

        let staleFix = coordinator.evaluatePreflight(
            home: activeHome,
            status: .fix(accuracyMeters: 12, capturedAt: now.addingTimeInterval(-31)),
            policy: policy,
            scope: scope,
            now: now,
            requestId: "home-req-0013"
        )
        XCTAssertEqual(staleFix, .failure(.init(failure: .staleFix, scope: scope)))
        XCTAssertEqual(coordinator.lastFailure?.retryableNow, true)

        let deletedHome = coordinator.evaluatePreflight(
            home: try makeHome(active: false),
            status: .fix(accuracyMeters: 12, capturedAt: now),
            policy: policy,
            scope: scope,
            now: now,
            requestId: "home-req-0014"
        )
        XCTAssertEqual(deletedHome, .failure(.init(failure: .noHome, scope: scope)))
        XCTAssertEqual(coordinator.lastFailure?.retryableNow, false)
    }

    func testHomeReturnProofAndRestoreLifecycleEnforcesVersionExpiryMaximumAndCooldown() throws {
        let coordinator = HomeReturnRestoreCoordinator(capabilities: enabledCapabilities)
        let scope = HomeResourceScope.global(resourceType: "stamina")
        let policy = try makePolicy()
        let home = try makeHome(version: 3)

        let preflightResult = coordinator.evaluatePreflight(
            home: home,
            status: .fix(accuracyMeters: 6, capturedAt: now),
            policy: policy,
            scope: scope,
            now: now,
            requestId: "home-req-0020"
        )
        guard case .success(let check) = preflightResult else {
            return XCTFail("Expected preflight to succeed")
        }
        XCTAssertEqual(coordinator.phase, .preflightReady(check))

        // Mismatched home version on proof fails with .homeChanged.
        XCTAssertThrowsError(
            try coordinator.acceptProof(
                proofId: "proof-1",
                homeVersion: 4,
                scope: scope,
                expiresAtMillis: 1_900_060_000_000
            )
        ) { error in
            XCTAssertEqual(error as? HomeReturnFailure, .homeChanged)
        }

        let proof = try coordinator.acceptProof(
            proofId: "proof-1",
            homeVersion: 3,
            scope: scope,
            expiresAtMillis: 1_900_060_000_000
        )
        XCTAssertEqual(coordinator.phase, .proofVerified(proof))

        let request = try coordinator.beginRestore(
            currentHomeVersion: 3,
            expectedAccountVersion: 7,
            deviceNow: now,
            serverOffset: 0,
            requestId: "restore-req-0001"
        )
        XCTAssertEqual(coordinator.phase, .restoring(request))

        // Unknown outcome (nil receipt) keeps pendingRequest and marks retryableNow == true.
        let unknownPhase = try coordinator.resolveRestore(nil)
        XCTAssertEqual(unknownPhase, .failed(.init(failure: .unknown, scope: scope)))
        XCTAssertEqual(coordinator.lastFailure?.retryableNow, true)
        XCTAssertEqual(coordinator.pendingRequest, request)

        // While a restore request is pending, a different requestId is refused, but the exact requestId retries.
        XCTAssertThrowsError(
            try coordinator.beginRestore(
                currentHomeVersion: 3,
                expectedAccountVersion: 7,
                deviceNow: now,
                serverOffset: 0,
                requestId: "restore-req-0002"
            )
        )
        XCTAssertEqual(
            try coordinator.beginRestore(
                currentHomeVersion: 3,
                expectedAccountVersion: 7,
                deviceNow: now,
                serverOffset: 0,
                requestId: "restore-req-0001"
            ),
            request
        )

        // Cooldown decision reports retryAfterSeconds and is not immediately retryable.
        let cooldownReceipt = try makeRestoreReceipt(
            decision: "COOLDOWN",
            current: 4,
            maximum: 10,
            accountVersion: 7,
            retryAfterSeconds: 120
        )
        let cooldownPhase = try coordinator.resolveRestore(cooldownReceipt)
        XCTAssertEqual(cooldownPhase, .failed(.init(failure: .cooldown(retryAfterSeconds: 120), scope: scope)))
        XCTAssertEqual(coordinator.lastFailure?.retryAfterSeconds, 120)
        XCTAssertEqual(coordinator.lastFailure?.retryableNow, false)

        // Re-begin with a fresh requestId and resolve RESTORED at exact server maximum.
        _ = try coordinator.beginRestore(
            currentHomeVersion: 3,
            expectedAccountVersion: 7,
            deviceNow: now,
            serverOffset: 0,
            requestId: "restore-req-0003"
        )
        let overMaxReceipt = try makeRestoreReceipt(
            requestId: "restore-req-0003",
            decision: "RESTORED",
            current: 11,
            maximum: 10,
            accountVersion: 8
        )
        XCTAssertThrowsError(try coordinator.resolveRestore(overMaxReceipt)) { error in
            XCTAssertEqual(error as? HomeReturnFailure, .invalid)
        }

        let validReceipt = try makeRestoreReceipt(
            requestId: "restore-req-0003",
            decision: "RESTORED",
            current: 10,
            maximum: 10,
            accountVersion: 8
        )
        let restoredPhase = try coordinator.resolveRestore(validReceipt)
        XCTAssertEqual(
            restoredPhase,
            .restored(current: 10, maximum: 10, accountVersion: 8, scope: scope)
        )
        XCTAssertNil(coordinator.pendingRequest)
        XCTAssertNil(coordinator.verifiedProof)
        XCTAssertNil(coordinator.lastFailure)
    }

    func testCityBoardLifecycleOpenGateAndExplicitSelfPayerQuoteConfirmation() throws {
        // Non-OPEN boards refuse quotes and new actions.
        let frozenCoordinator = try CityActionAndDeltaCoordinator(
            board: makeBoard(lifecycle: "FROZEN"),
            lifecycle: .frozen,
            participation: makeParticipation(),
            capabilities: enabledCapabilities
        )
        XCTAssertFalse(frozenCoordinator.canAcceptNewActions)
        XCTAssertThrowsError(try frozenCoordinator.stageQuote(makeQuote())) { error in
            XCTAssertEqual(error as? CityActionIssue, .boardNotOpen)
        }
        XCTAssertThrowsError(
            try frozenCoordinator.beginAction(kind: .roll, targetId: "b1", roundSeq: 1, requestId: "city-req-0010")
        ) { error in
            XCTAssertEqual(error as? CityActionIssue, .boardNotOpen)
        }

        // Unjoined member refuses quotes and new actions.
        let unjoinedCoordinator = try CityActionAndDeltaCoordinator(
            board: makeBoard(),
            lifecycle: .open,
            participation: nil,
            capabilities: enabledCapabilities
        )
        XCTAssertFalse(unjoinedCoordinator.canAcceptNewActions)
        XCTAssertThrowsError(try unjoinedCoordinator.stageQuote(makeQuote())) { error in
            XCTAssertEqual(error as? CityActionIssue, .notJoined)
        }

        // Open + joined coordinator enforces explicit self-payer confirmation for paid actions.
        let coordinator = try CityActionAndDeltaCoordinator(
            board: makeBoard(),
            lifecycle: .open,
            participation: makeParticipation(),
            capabilities: enabledCapabilities
        )
        XCTAssertTrue(coordinator.canAcceptNewActions)
        XCTAssertThrowsError(
            try coordinator.beginAction(kind: .acquireProperty, targetId: "prop-1", roundSeq: 1, requestId: "city-req-0011")
        ) { error in
            XCTAssertEqual(error as? CityActionIssue, .unconfirmed)
        }

        // Teammate payer quote cannot be confirmed by "me".
        try coordinator.stageQuote(makeQuote(payer: "teammate"))
        XCTAssertThrowsError(
            try coordinator.confirmQuote(confirmingMemberId: "me", confirmed: true, deviceNow: now)
        ) { error in
            XCTAssertEqual(error as? CityActionIssue, .payerMismatch)
        }

        // Expired quote cannot be confirmed.
        try coordinator.stageQuote(makeQuote(payer: "me", expiresAtMillis: 1_800_000_000_000))
        XCTAssertThrowsError(
            try coordinator.confirmQuote(confirmingMemberId: "me", confirmed: true, deviceNow: now)
        ) { error in
            XCTAssertEqual(error as? CityActionIssue, .quoteExpired)
        }

        // Valid quote requires confirmed == true by the payer themself.
        let validQuote = try makeQuote(payer: "me")
        try coordinator.stageQuote(validQuote)
        XCTAssertEqual(coordinator.phase, .awaitingQuoteConfirmation(validQuote))
        XCTAssertThrowsError(
            try coordinator.confirmQuote(confirmingMemberId: "me", confirmed: false, deviceNow: now)
        ) { error in
            XCTAssertEqual(error as? CityActionIssue, .unconfirmed)
        }

        let consent = try coordinator.confirmQuote(confirmingMemberId: "me", confirmed: true, deviceNow: now)
        XCTAssertEqual(consent.payerMemberId, "me")

        // Staged quote for ACQUIRE_PROPERTY cannot be used to dispatch an unpaid roll action.
        XCTAssertThrowsError(
            try coordinator.beginAction(kind: .roll, targetId: "b1", roundSeq: 1, requestId: "city-req-0012")
        ) { error in
            XCTAssertEqual(error as? CityActionIssue, .invalid)
        }

        let intent = try coordinator.beginAction(
            kind: .acquireProperty,
            targetId: "prop-1",
            roundSeq: 1,
            requestId: "city-req-0013"
        )
        XCTAssertEqual(coordinator.phase, .inFlight(intent))
        let bodyString = String(decoding: try intent.body(), as: UTF8.self)
        XCTAssertTrue(bodyString.contains("\"payerMemberId\":\"me\""))
        XCTAssertFalse(bodyString.contains("memberPointsCost"))
    }

    func testCitySingleInFlightExactRetryFenceAndReceiptResolution() throws {
        let coordinator = try CityActionAndDeltaCoordinator(
            board: makeBoard(),
            lifecycle: .open,
            participation: makeParticipation(),
            capabilities: enabledCapabilities
        )
        try coordinator.stageQuote(makeQuote())
        try coordinator.confirmQuote(confirmingMemberId: "me", confirmed: true, deviceNow: now)
        let intent = try coordinator.beginAction(
            kind: .acquireProperty,
            targetId: "prop-1",
            roundSeq: 2,
            requestId: "city-req-0020"
        )
        XCTAssertFalse(coordinator.canAcceptNewActions)

        // Unknown outcome keeps the same action in flight.
        XCTAssertEqual(try coordinator.resolveAction(nil), .unknown)
        XCTAssertEqual(coordinator.phase, .inFlight(intent))

        // Exact retry succeeds and preserves the original requestId; a new requestId is rejected as .busy.
        XCTAssertEqual(try coordinator.retryInFlight(), intent)
        XCTAssertThrowsError(
            try coordinator.beginAction(
                kind: .acquireProperty,
                targetId: "prop-1",
                roundSeq: 2,
                requestId: "city-req-0021"
            )
        ) { error in
            XCTAssertEqual(error as? CityActionIssue, .busy)
        }
        XCTAssertThrowsError(try coordinator.stageQuote(makeQuote(quoteId: "q2"))) { error in
            XCTAssertEqual(error as? CityActionIssue, .busy)
        }

        // QUOTE_CHANGED settles to .requote and never auto-accepts a new price.
        let quoteChangedReceipt = try makeActionReceipt(
            requestId: "city-req-0020",
            decision: "QUOTE_CHANGED",
            currentVersion: 4
        )
        XCTAssertEqual(try coordinator.resolveAction(quoteChangedReceipt), .requote)
        XCTAssertEqual(coordinator.phase, .settled(.requote))
        XCTAssertNil(coordinator.pendingQuote)
        XCTAssertNil(coordinator.confirmedConsent)

        // VERSION_CONFLICT with taskAttemptKept == true preserves the completed task and marks snapshot reload.
        let rollIntent = try coordinator.beginAction(
            kind: .roll,
            targetId: "b1",
            roundSeq: 2,
            requestId: "city-req-0022"
        )
        XCTAssertEqual(coordinator.phase, .inFlight(rollIntent))
        let conflictReceipt = try makeActionReceipt(
            requestId: "city-req-0022",
            action: "ROLL_ROUND",
            decision: "VERSION_CONFLICT",
            currentVersion: 6,
            taskAttemptKept: true
        )
        XCTAssertEqual(try coordinator.resolveAction(conflictReceipt), .refresh(taskAttemptKept: true))
        XCTAssertTrue(coordinator.needsSnapshotReload)
        XCTAssertFalse(coordinator.canAcceptNewActions)
    }

    func testCityDeltaStreamOrderingDeduplicationAndSnapshotFallback() throws {
        let coordinator = try CityActionAndDeltaCoordinator(
            board: makeBoard(revision: 4),
            lifecycle: .open,
            participation: makeParticipation(),
            initialSequence: 10,
            capabilities: enabledCapabilities
        )

        // Out-of-order contiguous page [12, 11] is reordered and applied as [11, 12].
        let d11 = try makeDelta(sequence: 11, boardVersion: 5)
        let d12 = try makeDelta(sequence: 12, boardVersion: 6)
        XCTAssertEqual(coordinator.ingestDeltas([d12, d11]), .applied([d11, d12]))
        XCTAssertEqual(coordinator.deltaStream.cursor.sequence, 12)
        XCTAssertEqual(coordinator.deltaStream.cursor.boardVersion, 6)
        XCTAssertEqual(coordinator.lastAppliedDeltas, [d11, d12])

        // Duplicate or stale deltas return .unchanged.
        let d9 = try makeDelta(sequence: 9, boardVersion: 4)
        XCTAssertEqual(coordinator.ingestDeltas([d12, d9]), .unchanged)
        XCTAssertTrue(coordinator.lastAppliedDeltas.isEmpty)

        // Sequence gap triggers .snapshotRequired and blocks new actions until snapshot reload.
        let gapDelta = try makeDelta(sequence: 14, boardVersion: 7)
        XCTAssertEqual(coordinator.ingestDeltas([gapDelta]), .snapshotRequired)
        XCTAssertEqual(coordinator.phase, .snapshotRequired)
        XCTAssertTrue(coordinator.needsSnapshotReload)
        XCTAssertFalse(coordinator.canAcceptNewActions)

        // Older snapshot is ignored and does not rewind the cursor.
        XCTAssertFalse(
            try coordinator.applySnapshot(
                board: makeBoard(revision: 5),
                lifecycle: .open,
                participation: makeParticipation(),
                sequence: 11
            )
        )
        XCTAssertEqual(coordinator.deltaStream.cursor.sequence, 12)
        XCTAssertTrue(coordinator.needsSnapshotReload)

        // Newer snapshot resets the cursor, clears needsSnapshotReload, and restores .idle phase.
        XCTAssertTrue(
            try coordinator.applySnapshot(
                board: makeBoard(revision: 8),
                lifecycle: .open,
                participation: makeParticipation(),
                sequence: 20
            )
        )
        XCTAssertEqual(coordinator.deltaStream.cursor.sequence, 20)
        XCTAssertEqual(coordinator.deltaStream.cursor.boardVersion, 8)
        XCTAssertFalse(coordinator.needsSnapshotReload)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(coordinator.canAcceptNewActions)

        // Challenge state machine transitions.
        try coordinator.advanceChallenge(challengeId: "ch-1", to: .offered)
        try coordinator.advanceChallenge(challengeId: "ch-1", to: .accepted)
        try coordinator.advanceChallenge(challengeId: "ch-1", to: .evidenceReady)
        try coordinator.advanceChallenge(challengeId: "ch-1", to: .resolved)
        XCTAssertEqual(coordinator.challengeStates["ch-1"], .resolved)
        XCTAssertThrowsError(try coordinator.advanceChallenge(challengeId: "ch-1", to: .cancelled)) { error in
            XCTAssertEqual(error as? CityActionIssue, .illegalTransition)
        }
    }
}
