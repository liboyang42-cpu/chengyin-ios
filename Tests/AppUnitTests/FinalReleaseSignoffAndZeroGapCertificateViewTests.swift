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
        testDefaultUnverifiedSnapshotFailsClosedUntilEvidenceIsSupplied()
    }

    func testUncertifiedBlillarTriggersBlockedWarningState() {
        testUncertifiedPillarOrMismatchedSHATriggersBlockedWarningState()
    }

    func testMainActorViewBodyInstantiationForReadyAndBlockedStates() {
        testMainActorViewBodyInstantiationForDefaultUnverifiedAndPreviewFixtureStates()
    }

    func testDefaultUnverifiedSnapshotFailsClosedUntilEvidenceIsSupplied() {
        let defaultSnapshot = FinalReleaseCertificateSnapshot.defaultUnverified
        XCTAssertFalse(defaultSnapshot.isZeroGapCertified)
        XCTAssertEqual(defaultSnapshot.certifiedPillarCount, 0)
        XCTAssertEqual(defaultSnapshot.uncertifiedPillars.count, 6)
        XCTAssertEqual(
            defaultSnapshot.pillars.map(\.pillarTitle),
            [
                "Wave 1–3 Tickets",
                "Reform v9 W02..W20",
                "Mini-Program 99 Pages",
                "RC-GATE-01..06",
                "App Store Privacy & UGC",
                "Cloud CI & ContractChecks"
            ]
        )
        XCTAssertEqual(defaultSnapshot.statusHeadline, "未验证/未签收：存在 6 项待核验阻断，暂不可签发发布证书")

        let previewFixture = FinalReleaseCertificateSnapshot.previewReadyFixture
        XCTAssertTrue(previewFixture.isZeroGapCertified)
        XCTAssertEqual(previewFixture.certifiedPillarCount, 6)
        XCTAssertEqual(previewFixture.statusHeadline, "发布签收证据已齐备 (6/6)")
    }

    func testUncertifiedPillarOrMismatchedSHATriggersBlockedWarningState() {
        var pillars = FinalReleaseCertificateSnapshot.previewFixturePillars
        pillars[3] = ReleaseCertificatePillarRow(
            id: "RC-GATE-01..06",
            pillarTitle: "RC-GATE-01..06",
            scopeSummary: "六大发布候选安全与商业边界门禁",
            isCertified: false,
            statusText: "FAILED",
            commitSHA: "fixture-preview-sha",
            evidenceLink: "docs/evidence",
            blockerNote: "发现未评审写接口开关被开启"
        )
        let blockedSnapshot = FinalReleaseCertificateSnapshot(
            certificateID: "RC-BLOCKED-TEST",
            targetCommitSHA: "fixture-preview-sha",
            pillars: pillars
        )
        XCTAssertFalse(blockedSnapshot.isZeroGapCertified)
        XCTAssertEqual(blockedSnapshot.certifiedPillarCount, 5)
        XCTAssertEqual(blockedSnapshot.uncertifiedPillars.map(\.id), ["RC-GATE-01..06"])
        XCTAssertEqual(blockedSnapshot.statusHeadline, "未验证/未签收：存在 1 项待核验阻断，暂不可签发发布证书")
    }

    func testMainActorViewBodyInstantiationForDefaultUnverifiedAndPreviewFixtureStates() {
        let defaultView = FinalReleaseSignoffAndZeroGapCertificateView()
        XCTAssertFalse(defaultView.snapshot.isZeroGapCertified)
        _ = defaultView.body

        let previewView = FinalReleaseSignoffAndZeroGapCertificateView(snapshot: .previewReadyFixture)
        XCTAssertTrue(previewView.snapshot.isZeroGapCertified)
        _ = previewView.body
    }
}
