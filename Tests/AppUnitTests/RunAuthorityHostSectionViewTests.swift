import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#else
@testable import Questify
#endif

@MainActor
final class RunAuthorityHostSectionViewTests: XCTestCase {
    private func makeProjection(
        runId: String = "run-host-01",
        version: Int64 = 7,
        status: GameRunStatus = .active,
        nodes: [String: RunNodeStatus] = ["n1": .available, "n2": .locked]
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
        reasonCode: String? = nil
    ) throws -> RunActionReceipt {
        let reasonJSON = reasonCode.map { ",\"reasonCode\":\"\($0)\"" } ?? ""
        let raw = """
        {"runId":"\(intent.runId)","requestId":"\(intent.requestId)","decision":"\(decision)","stateVersion":\(version),"runStatus":"\(runStatus)","nodeId":"\(intent.nodeId)","nodeStatus":"\(nodeStatus)","safeToRetry":\(safeToRetry)\(reasonJSON)}
        """
        return try JSONDecoder().decode(RunActionReceipt.self, from: Data(raw.utf8))
    }

    func testDisabledStateRendersFailClosedGateAndIdleQueue() throws {
        let coordinator = RunAuthorityHostCoordinator(
            projection: try makeProjection(),
            capabilities: .disabled
        )
        let view = RunAuthorityHostSectionView(coordinator: coordinator)
        _ = view.body

        XCTAssertEqual(view.capabilityBadgeText, "RunAuthority Gate: DISABLED (Fail-Closed)")
        XCTAssertEqual(view.casVersionText, "Run run-host-01 • CAS v7")
        XCTAssertEqual(view.runStatusText, "Run Status: ACTIVE")
        XCTAssertEqual(view.conflictRecoveryText, "Recovery: Capability gate disabled; no run mutations permitted")
        XCTAssertEqual(view.pendingIdempotencyText, "Pending Intent: None (idempotency queue idle)")
        XCTAssertEqual(view.nodeSummaryText, "Nodes (2): n1=AVAILABLE, n2=LOCKED")
    }

    func testReadyAndInFlightStatesRenderPendingIdempotencyDetails() throws {
        let enabled = ReformWorldCapabilities.syntheticFixture([.runAuthority])
        let coordinator = RunAuthorityHostCoordinator(
            projection: try makeProjection(),
            capabilities: enabled
        )
        let view = RunAuthorityHostSectionView(coordinator: coordinator)
        _ = view.body

        XCTAssertEqual(view.capabilityBadgeText, "RunAuthority Gate: ENABLED")
        XCTAssertEqual(view.conflictRecoveryText, "Recovery: In sync with authoritative state v7")
        XCTAssertEqual(view.pendingIdempotencyText, "Pending Intent: None (idempotency queue idle)")

        _ = try coordinator.beginAction(
            nodeId: "n1",
            payload: .choice(optionId: "opt-alpha"),
            requestId: "req-inflight-001"
        )
        XCTAssertEqual(
            view.conflictRecoveryText,
            "Recovery: Awaiting receipt for node n1 at expected v7"
        )
        XCTAssertEqual(
            view.pendingIdempotencyText,
            "Pending Intent: CHOICE on n1 • req req-inflight-001 (expected v7)"
        )
    }

    func testCASConflictStateRendersRefreshRequiredAndRecoversOnServerSnapshot() throws {
        let enabled = ReformWorldCapabilities.syntheticFixture([.runAuthority])
        let coordinator = RunAuthorityHostCoordinator(
            projection: try makeProjection(),
            capabilities: enabled
        )
        let view = RunAuthorityHostSectionView(coordinator: coordinator)

        let intent = try coordinator.beginAction(
            nodeId: "n1",
            payload: .arrival(evidenceRef: "ev-geo-01"),
            requestId: "req-cas-conf-01"
        )
        let conflictReceipt = try makeReceipt(
            for: intent,
            decision: "VERSION_CONFLICT",
            version: 9,
            nodeStatus: "AVAILABLE",
            safeToRetry: true
        )
        _ = try coordinator.resolve(conflictReceipt)

        XCTAssertEqual(
            view.conflictRecoveryText,
            "Recovery: CAS conflict — refresh required from server v9"
        )
        XCTAssertEqual(view.pendingIdempotencyText, "Pending Intent: None (idempotency queue idle)")
        XCTAssertEqual(view.casVersionText, "Run run-host-01 • CAS v7")

        XCTAssertTrue(
            try coordinator.adoptSnapshot(
                version: 9,
                status: .active,
                nodes: ["n1": .available, "n2": .available]
            )
        )
        XCTAssertEqual(view.casVersionText, "Run run-host-01 • CAS v9")
        XCTAssertEqual(view.conflictRecoveryText, "Recovery: In sync with authoritative state v9")
        XCTAssertEqual(view.nodeSummaryText, "Nodes (2): n1=AVAILABLE, n2=AVAILABLE")
    }

    func testUnknownOutcomeAndPayloadConflictAndRejectedStatesRenderDeterministicGuidance() throws {
        let enabled = ReformWorldCapabilities.syntheticFixture([.runAuthority])
        let coordinator = RunAuthorityHostCoordinator(
            projection: try makeProjection(),
            capabilities: enabled
        )
        let view = RunAuthorityHostSectionView(coordinator: coordinator)

        let intent = try coordinator.beginAction(
            nodeId: "n1",
            payload: .scan(evidenceRef: "qr-ev-01"),
            requestId: "req-unknown-001"
        )
        _ = try coordinator.resolve(nil)

        XCTAssertEqual(
            view.conflictRecoveryText,
            "Recovery: Outcome unknown — retry same requestId req-unknown-001 or read receipt"
        )
        XCTAssertEqual(
            view.pendingIdempotencyText,
            "Pending Intent: SCAN_CONFIRM on n1 • req req-unknown-001 (expected v7)"
        )

        let mismatchedIntent = try RunActionIntent(
            runId: "run-host-01",
            nodeId: "n1",
            expectedStateVersion: 7,
            payload: .scan(evidenceRef: "qr-ev-mutated"),
            requestId: "req-unknown-001"
        )
        XCTAssertThrowsError(try coordinator.retryPending(mismatchedIntent))
        XCTAssertEqual(
            view.conflictRecoveryText,
            "Recovery: Payload conflict — requestId reused with mismatched intent"
        )

        // Verify rejected state and empty node summary presentation
        let rejectedCoordinator = RunAuthorityHostCoordinator(
            projection: try makeProjection(nodes: ["n1": .available]),
            capabilities: enabled
        )
        let rejectedIntent = try rejectedCoordinator.beginAction(
            nodeId: "n1",
            payload: .choice(optionId: "opt-reject"),
            requestId: "req-rejected-01"
        )
        let rejectedReceipt = try makeReceipt(
            for: rejectedIntent,
            decision: "REJECTED",
            version: 7,
            nodeStatus: "AVAILABLE",
            safeToRetry: false,
            reasonCode: "NODE_COOLDOWN"
        )
        _ = try rejectedCoordinator.resolve(rejectedReceipt)
        let rejectedView = RunAuthorityHostSectionView(coordinator: rejectedCoordinator)
        XCTAssertEqual(
            rejectedView.conflictRecoveryText,
            "Recovery: Server rejected action (NODE_COOLDOWN)"
        )

        let emptyNodesCoordinator = RunAuthorityHostCoordinator(
            projection: try makeProjection(nodes: [:]),
            capabilities: enabled
        )
        let emptyNodesView = RunAuthorityHostSectionView(coordinator: emptyNodesCoordinator)
        XCTAssertEqual(emptyNodesView.nodeSummaryText, "Nodes: 0 tracked")
    }
}
