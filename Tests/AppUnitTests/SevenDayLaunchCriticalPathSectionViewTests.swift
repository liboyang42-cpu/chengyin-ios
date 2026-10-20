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
        XCTAssertTrue(snapshot.isLaunchPathReady)
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
}
