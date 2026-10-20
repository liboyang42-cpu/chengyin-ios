import SwiftUI
import XCTest
#if canImport(QuestifyApp)
@testable import QuestifyApp
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#elseif canImport(Core)
@testable import Questify
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#else
@testable import Questify
#endif

@MainActor
final class SevenDayLaunchCriticalPathSectionViewTests: XCTestCase {

    func testDefaultReadySevenDaySnapshotCompliance() {
        let snapshot = SevenDayLaunchPlanSnapshot.defaultReady
        XCTAssertEqual(snapshot.days.count, 7)
        XCTAssertTrue(snapshot.coversAllSevenDays)
        XCTAssertFalse(snapshot.hasBlockedMilestone)
        // Fail-closed default: no evidence means not ready.
        XCTAssertFalse(snapshot.isLaunchPathReady)
        XCTAssertTrue(snapshot.days.allSatisfy { $0.status == .notVerified })
        XCTAssertTrue(snapshot.localXcconfigCheckText.contains("Config/Local.xcconfig"))
        XCTAssertTrue(snapshot.userInfoRoleContractText.contains("/api/userInfo"))
        XCTAssertTrue(snapshot.testFlightArchiveCheckText.contains("TestFlight"))
    }

    func testBlockedDayMilestoneWarningState() {
        var modifiedDays = SevenDayLaunchPlanSnapshot.defaultReady.days
        modifiedDays[0] = LaunchDayMilestoneRow(
            id: "day-1",
            dayLabel: "Day 1",
            title: "环境配置与生产 HTTPS 门禁冻结",
            deliverableSummary: "缺少生产证书配置",
            status: .blocked
        )
        let blockedSnapshot = SevenDayLaunchPlanSnapshot(
            hasBlockedMilestone: true,
            bannerSummaryText: "Day 1 环境配置存在阻塞项，需立即修复",
            days: modifiedDays
        )
        XCTAssertTrue(blockedSnapshot.coversAllSevenDays)
        XCTAssertFalse(blockedSnapshot.isLaunchPathReady)
        XCTAssertEqual(modifiedDays[0].statusBadgeText, "存在阻塞")
    }

    func testMainActorViewBodyInstantiation() {
        let readyView = SevenDayLaunchCriticalPathSectionView(snapshot: .defaultReady)
        XCTAssertEqual(readyView.snapshot, .defaultReady)
        _ = readyView.body

        let customView = SevenDayLaunchCriticalPathSectionView(
            snapshot: SevenDayLaunchPlanSnapshot(
                hasBlockedMilestone: true,
                bannerSummaryText: "等待外部联调"
            )
        )
        _ = customView.body
    }

    func testSnapshotFromCoreContractIsFailClosedWithoutEvidence() {
        let snapshot = SevenDayLaunchPlanSnapshot.from(
            milestones: SevenDayLaunchCriticalPathMilestoneContract.canonicalMilestones
        )
        XCTAssertTrue(snapshot.coversAllSevenDays)
        XCTAssertFalse(snapshot.contractFullyVerified)
        XCTAssertFalse(snapshot.isLaunchPathReady)
        XCTAssertNil(snapshot.boundCommitSHA)
        XCTAssertTrue(snapshot.days.allSatisfy { $0.status == .notVerified })
    }

    func testSnapshotFromCoreContractRequiresShaBoundEvidenceAndSignoff() {
        let sha = "0123456789abcdef0123456789abcdef01234567"
        let verified = SevenDayLaunchCriticalPathMilestoneContract.canonicalMilestones.map {
            LaunchDayMilestoneDescriptor(
                id: $0.id,
                dayNumber: $0.dayNumber,
                title: $0.title,
                requiresExternalOpsSignoff: $0.requiresExternalOpsSignoff,
                evidence: LaunchDayEvidence(
                    commitSHA: sha,
                    codeAndTestResult: .passed,
                    externalSignoffSHA: sha,
                    externalSignoffResult: .passed
                )
            )
        }
        XCTAssertTrue(SevenDayLaunchPlanSnapshot.from(milestones: verified).isLaunchPathReady)

        let noSignoff = verified.map {
            LaunchDayMilestoneDescriptor(
                id: $0.id,
                dayNumber: $0.dayNumber,
                title: $0.title,
                requiresExternalOpsSignoff: $0.requiresExternalOpsSignoff,
                evidence: LaunchDayEvidence(commitSHA: sha, codeAndTestResult: .passed)
            )
        }
        XCTAssertFalse(SevenDayLaunchPlanSnapshot.from(milestones: noSignoff).isLaunchPathReady)
    }
}
