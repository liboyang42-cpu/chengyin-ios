import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#else
@testable import Questify
#endif

@MainActor
final class MasterReleaseSignoffDashboardViewTests: XCTestCase {
    func testVerifiedDefaultDashboardRendersAllFifteenPillarsAndCanonicalMetrics() {
        let view = MasterReleaseSignoffDashboardView()
        _ = view.body

        XCTAssertTrue(view.snapshot.isReadyForSignoff)
        XCTAssertEqual(view.snapshot.pillars.count, 15)
        XCTAssertEqual(view.snapshot.verifiedPillarCount, 15)
        XCTAssertEqual(view.snapshot.pillars.map(\.index), Array(1...15))

        XCTAssertEqual(view.pillarsBadgeText, "15/15 Pillars Verified")
        XCTAssertEqual(view.miniProgramPagesMetricText, "99/99 Mini-Program Pages")
        XCTAssertEqual(view.wave2ScopesMetricText, "21/21 Wave-2 Scopes")
        XCTAssertEqual(view.wave3LanesMetricText, "13/13 Wave-3 Lanes")
        XCTAssertEqual(view.reformPackagesMetricText, "19/19 Reform Packages")
        XCTAssertEqual(view.mapVisualMetricText, "41/41 Map Visual Items")
        XCTAssertEqual(view.highRiskSwitchesBannerText, "All High-Risk Switches Fail-Closed")

        for pillar in view.snapshot.pillars {
            XCTAssertTrue(pillar.isVerified)
            XCTAssertTrue(pillar.isFailClosed)
            XCTAssertEqual(pillar.statusBadgeText, "VERIFIED • FAIL-CLOSED")
        }
    }

    func testPartialOrUnverifiedPillarBlocksReadyForSignoffAndUpdatesBadge() {
        var modifiedPillars = MasterReleaseSignoffDashboardSnapshot.defaultPillars
        modifiedPillars[14] = MasterSignoffPillarItem(
            id: "pillar-15-release-preflight",
            index: 15,
            title: "Release Pre-Flight, Signing & UI Readiness Contract",
            coverageSummary: "Awaiting local override",
            isVerified: false,
            isFailClosed: true
        )
        let partialSnapshot = MasterReleaseSignoffDashboardSnapshot(
            pillars: modifiedPillars,
            verifiedMiniProgramPages: 98,
            totalMiniProgramPages: 99,
            allHighRiskSwitchesFailClosed: false
        )
        let view = MasterReleaseSignoffDashboardView(snapshot: partialSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isReadyForSignoff)
        XCTAssertEqual(view.snapshot.verifiedPillarCount, 14)
        XCTAssertEqual(view.pillarsBadgeText, "14/15 Pillars Verified")
        XCTAssertEqual(view.miniProgramPagesMetricText, "98/99 Mini-Program Pages")
        XCTAssertEqual(view.highRiskSwitchesBannerText, "High-Risk Switches: REVIEW REQUIRED")
        XCTAssertEqual(view.snapshot.pillars[14].statusBadgeText, "PENDING REVIEW")
    }
}
