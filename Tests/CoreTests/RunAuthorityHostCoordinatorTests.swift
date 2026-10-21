import XCTest
@testable import QuestifyCore

final class RunAuthorityHostCoordinatorTests: XCTestCase {
    private func makeProjection(
        runId: String = "run-1",
        version: Int64 = 4,
        status: GameRunStatus = .active,
        nodes: [String: RunNodeStatus] = ["n1": .available, "n2": .locked, "n3": .inProgress]
    ) throws -> RunAuthorityProjection {
        try RunAuthorityProjection(runId: runId, stateVersion: version, status: status, nodes: nodes)
    }

    private func makeReceipt(
        for intent: RunActionIntent,
        decision: String,
        version: Int64,
        runStatus: String = "ACTIVE",
        nodeStatus: String = "SUCCEEDED",
        safeToRetry: Bool = false,
        reasonCode: String? = nil,
        requestId: String? = nil
    ) throws -> RunActionReceipt {
        let reasonJSON = reasonCode.map { ",\"reasonCode\":\"\($0)\"" } ?? ""
        let raw = """
        {"runId":"\(intent.runId)","requestId":"\(requestId ?? intent.requestId)","decision":"\(decision)","stateVersion":\(version),"runStatus":"\(runStatus)","nodeId":"\(intent.nodeId)","nodeStatus":"\(nodeStatus)","safeToRetry":\(safeToRetry)\(reasonJSON)}
        """
        return try JSONDecoder().decode(RunActionReceipt.self, from: Data(raw.utf8))
    }

    func testDefaultDisabledCapabilitiesBlockAllCoordinatorOperations() throws {
        let coordinator = RunAuthorityHostCoordinator(
            projection: try makeProjection(),
            capabilities: .disabled
        )
        XCTAssertFalse(coordinator.isEnabled)
        XCTAssertEqual(coordinator.state, .disabled)

        XCTAssertThrowsError(
            try coordinator.beginAction(nodeId: "n1", payload: .choice(optionId: "opt-1"), requestId: "req-disabled-01")
        ) { error in
            XCTAssertEqual(error as? RunAuthorityIssue, .invalid)
        }
        XCTAssertNil(coordinator.pendingIntent)
        XCTAssertEqual(coordinator.projection.stateVersion, 4)
    }

    func testCASStateVersionChecksRefuseStaleVersionLockedNodeAndPausedOrTerminalRuns() throws {
        let enabled = ReformWorldCapabilities.syntheticFixture([.runAuthority])
        let coordinator = RunAuthorityHostCoordinator(projection: try makeProjection(), capabilities: enabled)

        // Stale expectedStateVersion is refused with .staleVersion
        XCTAssertThrowsError(
            try coordinator.beginAction(
                nodeId: "n1",
                expectedStateVersion: 3,
                payload: .choice(optionId: "opt-1"),
                requestId: "req-stale-0001"
            )
        ) { error in
            XCTAssertEqual(error as? RunAuthorityIssue, .staleVersion)
        }

        // Locked node is refused with .invalid
        XCTAssertThrowsError(
            try coordinator.beginAction(
                nodeId: "n2",
                payload: .choice(optionId: "opt-1"),
                requestId: "req-locked-001"
            )
        ) { error in
            XCTAssertEqual(error as? RunAuthorityIssue, .invalid)
        }

        // Paused and terminal runs refuse actions with .terminal
        for nonActive in [GameRunStatus.paused, .completed, .abandoned, .expired] {
            let halted = RunAuthorityHostCoordinator(
                projection: try makeProjection(status: nonActive),
                capabilities: enabled
            )
            XCTAssertThrowsError(
                try halted.beginAction(
                    nodeId: "n1",
                    payload: .choice(optionId: "opt-1"),
                    requestId: "req-halted-001"
                )
            ) { error in
                XCTAssertEqual(error as? RunAuthorityIssue, .terminal)
            }
        }
    }

    func testConflictRecoveryTransitionsToRefreshRequiredAndAdoptsServerSnapshot() throws {
        let enabled = ReformWorldCapabilities.syntheticFixture([.runAuthority])
        let coordinator = RunAuthorityHostCoordinator(projection: try makeProjection(), capabilities: enabled)

        let intent = try coordinator.beginAction(
            nodeId: "n1",
            payload: .arrival(evidenceRef: "ev-arrival-1"),
            requestId: "req-conflict-01"
        )
        XCTAssertEqual(coordinator.state, .inFlight(intent))

        let conflictReceipt = try makeReceipt(
            for: intent,
            decision: "VERSION_CONFLICT",
            version: 6,
            nodeStatus: "AVAILABLE",
            safeToRetry: true
        )
        let outcome = try coordinator.resolve(conflictReceipt)
        XCTAssertEqual(outcome, .refreshRequired(serverVersion: 6))
        XCTAssertEqual(coordinator.state, .refreshRequired(serverVersion: 6))
        XCTAssertNil(coordinator.pendingIntent)
        XCTAssertEqual(coordinator.projection.stateVersion, 4)

        // Late snapshot (version <= 4) is ignored
        XCTAssertFalse(try coordinator.adoptSnapshot(version: 4, status: .active, nodes: ["n1": .available]))
        XCTAssertEqual(coordinator.state, .refreshRequired(serverVersion: 6))

        // Fresh server snapshot (version 6) updates projection and returns coordinator to .ready
        XCTAssertTrue(
            try coordinator.adoptSnapshot(
                version: 6,
                status: .active,
                nodes: ["n1": .available, "n2": .available]
            )
        )
        XCTAssertEqual(coordinator.projection.stateVersion, 6)
        XCTAssertEqual(coordinator.state, .ready)
    }

    func testPendingIntentIdempotencyReusesRequestIdSurfacesPayloadConflictAndSurvivesNewerSnapshotUntilReceiptRead() throws {
        let enabled = ReformWorldCapabilities.syntheticFixture([.runAuthority])
        let coordinator = RunAuthorityHostCoordinator(projection: try makeProjection(), capabilities: enabled)

        let intent = try coordinator.beginAction(
            nodeId: "n1",
            payload: .scan(evidenceRef: "qr-scan-01"),
            requestId: "req-idem-00001"
        )
        XCTAssertEqual(try coordinator.resolve(nil), .unknown)
        XCTAssertEqual(coordinator.state, .unknownOutcome(intent))
        XCTAssertEqual(coordinator.pendingIntent, intent)

        // Exact retry reuses the same requestId and payload
        let retried = try coordinator.retryPending(intent)
        XCTAssertEqual(retried.requestId, "req-idem-00001")
        XCTAssertEqual(coordinator.state, .inFlight(intent))

        // Different payload under the same requestId is rejected as .payloadConflict
        let mutated = try RunActionIntent(
            runId: "run-1",
            nodeId: "n1",
            expectedStateVersion: 4,
            payload: .scan(evidenceRef: "qr-scan-02"),
            requestId: "req-idem-00001"
        )
        XCTAssertThrowsError(try coordinator.retryPending(mutated)) { error in
            XCTAssertEqual(error as? RunAuthorityIssue, .payloadConflict)
        }
        XCTAssertEqual(coordinator.state, .payloadConflict)
        XCTAssertEqual(coordinator.pendingIntent, intent)

        // Newer snapshot is adopted, but the pending intent survives until its receipt is read back
        XCTAssertTrue(
            try coordinator.adoptSnapshot(
                version: 5,
                status: .active,
                nodes: ["n1": .succeeded, "n2": .available]
            )
        )
        XCTAssertEqual(coordinator.projection.stateVersion, 5)
        XCTAssertEqual(coordinator.pendingIntent, intent)
        XCTAssertEqual(coordinator.state, .unknownOutcome(intent))

        let appliedReceipt = try makeReceipt(for: intent, decision: "APPLIED", version: 5)
        try coordinator.clearPending(after: appliedReceipt)
        XCTAssertNil(coordinator.pendingIntent)
        XCTAssertEqual(coordinator.state, .ready)
    }

    func testTypedInteractionKindsValidateAnswerUTF16LimitAndForbidClientRewardFields() throws {
        let enabled = ReformWorldCapabilities.syntheticFixture([.runAuthority])
        let payloads: [RunActionPayload] = [
            .choice(optionId: "opt-a"),
            .answer(text: String(repeating: "a", count: 500)),
            .arrival(evidenceRef: "geo-ev-1"),
            .scan(evidenceRef: "scan-ev-1"),
            .itemUse(entitlementId: "ent-1"),
            .npcClue(clueId: "clue-1")
        ]

        for (index, payload) in payloads.enumerated() {
            let coordinator = RunAuthorityHostCoordinator(projection: try makeProjection(), capabilities: enabled)
            let intent = try coordinator.beginAction(
                nodeId: "n1",
                payload: payload,
                requestId: String(format: "req-kind-%05d", index)
            )
            let bodyString = String(decoding: try intent.body(), as: UTF8.self)
            for forbidden in RunAuthorityHostCoordinator.forbiddenClientFields {
                XCTAssertFalse(bodyString.lowercased().contains("\"\(forbidden)\""))
            }
        }

        // Answer > 500 UTF-16 code units throws .oversize
        let coordinator = RunAuthorityHostCoordinator(projection: try makeProjection(), capabilities: enabled)
        XCTAssertThrowsError(
            try coordinator.beginAction(
                nodeId: "n1",
                payload: .answer(text: String(repeating: "x", count: 501)),
                requestId: "req-oversize-1"
            )
        ) { error in
            XCTAssertEqual(error as? RunAuthorityIssue, .oversize)
        }
    }
}
