import SwiftUI
import XCTest
#if canImport(QuestifyApp)
@testable import QuestifyApp
#else
@testable import Questify
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#endif

@MainActor
final class FinalReleaseSignoffAndZeroGapCertificateViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllSixReleaseCertificatePillars() {
        let snapshot = FinalReleaseCertificateSnapshot.defaultReady
        XCTAssertTrue(snapshot.isZeroGapCertified)
        XCTAssertEqual(snapshot.certifiedPillarCount, 6)
        XCTAssertTrue(snapshot.uncertifiedPillars.isEmpty)
        XCTAssertEqual(
            snapshot.pillars.map(\.pillarTitle),
            [
                "Wave 1–3 Tickets",
                "Reform v9 W02..W20",
                "Mini-Program 99 Pages",
                "RC-GATE-01..06",
                "App Store Privacy & UGC",
                "Cloud CI & ContractChecks"
            ]
        )
        XCTAssertEqual(snapshot.statusHeadline, "零差距发布签收证书已就绪 (6/6)")
    }

    func testUncertifiedBlillarTriggersBlockedWarningState() {
        var pillars = FinalReleaseCertificateSnapshot.defaultPillars
        pillars[3] = ReleaseCertificatePillarRow(
            id: "RC-GATE-01..06",
            pillarTitle: "RC-GATE-01..06",
            scopeSummary: "六大发布候选安全与商业边界门禁",
            isCertified: false,
            blockerNote: "发现未评审写接口开关被开启"
        )
        let blockedSnapshot = FinalReleaseCertificateSnapshot(
            certificateID: "RC-BLOCKED-TEST",
            pillars: pillars
        )
        XCTAssertFalse(blockedSnapshot.isZeroGapCertified)
        XCTAssertEqual(blockedSnapshot.certifiedPillarCount, 5)
        XCTAssertEqual(blockedSnapshot.uncertifiedPillars.map(\.id), ["RC-GATE-01..06"])
        XCTAssertEqual(blockedSnapshot.statusHeadline, "存在 1 项未签收发布阻断，暂不可签发发布证书")
    }

    func testMainActorViewBodyInstantiationForReadyAndBlockedStates() {
        let readyView = FinalReleaseSignoffAndZeroGapCertificateView(snapshot: .defaultReady)
        XCTAssertTrue(readyView.snapshot.isZeroGapCertified)
        _ = readyView.body

        var blockedPillars = FinalReleaseCertificateSnapshot.defaultPillars
        blockedPillars[0] = ReleaseCertificatePillarRow(
            id: "Wave 1–3 Tickets",
            pillarTitle: "Wave 1–3 Tickets",
            scopeSummary: "待补充回归项",
            isCertified: false,
            blockerNote: "缺少签收记录"
        )
        let blockedView = FinalReleaseSignoffAndZeroGapCertificateView(
            snapshot: FinalReleaseCertificateSnapshot(pillars: blockedPillars)
        )
        XCTAssertFalse(blockedView.snapshot.isZeroGapCertified)
        _ = blockedView.body
    }
}
