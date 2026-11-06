import XCTest
import SwiftUI
@testable import Questify
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor
final class ReformWorldHostWorkbenchViewTests: XCTestCase {

    func testDefaultWorkbenchInstantiationAndParityCountSummaryStrings() {
        let workbench = ReformWorldHostWorkbenchView()
        _ = workbench.body

        XCTAssertEqual(workbench.readinessReport.wave2Count, 21)
        XCTAssertEqual(workbench.readinessReport.wave3Count, 13)
        XCTAssertEqual(workbench.readinessReport.reformWorkPackageCount, 19)
        XCTAssertEqual(workbench.readinessReport.unifiedDecisionCount, 8)
        XCTAssertTrue(workbench.readinessReport.isReleaseReady)

        XCTAssertEqual(
            workbench.readinessVerdictBadgeText,
            "RELEASE READY · FAIL-CLOSED VERIFIED"
        )
        XCTAssertEqual(
            workbench.parityCountsSummaryText,
            "Wave-2: 21/21 · Wave-3: 13/13 · Reform W02–W20: 19/19 · Decisions U01–U08: 8/8"
        )
        XCTAssertEqual(
            workbench.wave2SummaryText,
            "Wave-2 Mini-Program Parity Scopes: 21 / 21 (missing: 0)"
        )
        XCTAssertEqual(
            workbench.wave3SummaryText,
            "Wave-3 Handoff Scopes (I00–I11, BK): 13 / 13 (missing: 0)"
        )
        XCTAssertEqual(
            workbench.reformPackagesSummaryText,
            "Reform Plan v9 Work Packages (W02–W20): 19 / 19 (missing: 0)"
        )
        XCTAssertEqual(
            workbench.unifiedDecisionsSummaryText,
            "Unified Decisions (U01–U08): 8 / 8 (missing: 0)"
        )
    }

    func testFailClosedSwitchesSummaryAndEmbeddedSections() {
        let workbench = ReformWorldHostWorkbenchView()
        let switchCount = workbench.highRiskSwitches.count
        XCTAssertGreaterThan(switchCount, 0)
        XCTAssertTrue(workbench.highRiskSwitches.allSatisfy(\.isFailClosed))
        XCTAssertEqual(
            workbench.failClosedSwitchesSummaryText,
            "High-Risk Write/Payment/Cash Switches: \(switchCount)/\(switchCount) FAIL-CLOSED (0 enabled)"
        )

        // Verify embedded section views are instantiated and fail-closed by default
        XCTAssertEqual(
            workbench.runAuthoritySectionView.capabilityBadgeText,
            "RunAuthority Gate: DISABLED (Fail-Closed)"
        )
        XCTAssertTrue(workbench.preflightDiagnosticsView.report.isSafeUnconfiguredCIDefault)
        XCTAssertTrue(workbench.npcAISceneGuardSectionView.isNonGenerativeBadgeVisible)
    }

    func testCustomRunAuthorityAndPreflightEmbeddingInWorkbench() throws {
        let projection = try RunAuthorityProjection(
            runId: "run-custom-99",
            stateVersion: 4,
            status: .active,
            nodes: ["node-1": .available]
        )
        let coordinator = RunAuthorityHostCoordinator(
            projection: projection,
            capabilities: .disabled
        )
        let runSection = RunAuthorityHostSectionView(coordinator: coordinator)
        let workbench = ReformWorldHostWorkbenchView(
            runAuthoritySectionView: runSection
        )
        _ = workbench.body

        XCTAssertEqual(
            workbench.runAuthoritySectionView.casVersionText,
            "Run run-custom-99 • CAS v4"
        )
        XCTAssertEqual(
            workbench.runAuthoritySectionView.conflictRecoveryText,
            "Recovery: Capability gate disabled; no run mutations permitted"
        )
    }
}
