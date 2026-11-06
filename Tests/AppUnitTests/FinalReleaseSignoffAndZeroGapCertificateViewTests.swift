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
    private let validFormalSHA = "50e2cf9be15999e35f566463db61908690f7c149"

    private func makeFormalEvidence(commitSHA: String) -> [ReleasePillarEvidenceInput] {
        FinalReleaseSignoffAndZeroGapCertificateContract.canonicalPillars.map { req in
            ReleasePillarEvidenceInput(
                pillarID: req.id,
                targetCommitSHA: commitSHA,
                evaluatedAtISO8601: "2026-10-20T22:00:00Z",
                status: .passed,
                completedCount: req.requiredCount,
                requiredCount: req.requiredCount,
                openBlockerCount: 0,
                hasMergeConflict: false,
                evidenceLinks: ["docs/handoff/issue-61-response-20261020.md#\(req.id)"],
                evidenceOrigin: .formal
            )
        }
    }

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

        // Preview fixture must also remain uncertified under Core evaluation, even if given a real 40-hex SHA
        let previewFixture = FinalReleaseCertificateSnapshot.previewReadyFixture
        XCTAssertFalse(previewFixture.isZeroGapCertified)
        XCTAssertEqual(previewFixture.certifiedPillarCount, 0)

        let spoofedPreviewSnapshot = FinalReleaseCertificateSnapshot(
            certificateID: "RC-SPOOFED-PREVIEW",
            targetCommitSHA: validFormalSHA,
            corePillars: FinalReleaseSignoffAndZeroGapCertificateContract.previewFixturePillars(commitSHA: validFormalSHA)
        )
        XCTAssertFalse(spoofedPreviewSnapshot.isZeroGapCertified)
        XCTAssertEqual(spoofedPreviewSnapshot.certifiedPillarCount, 0)

        // Only formal Core-evaluated evidence bound to a valid 40-hex SHA certifies the snapshot
        let formalSnapshot = FinalReleaseCertificateSnapshot.fromFormalEvidence(
            certificateID: "RC-FORMAL-PASS",
            expectedCommitSHA: validFormalSHA,
            notBeforeISO8601: "2026-10-20T21:00:00Z",
            hasMergeConflict: false,
            evidence: makeFormalEvidence(commitSHA: validFormalSHA)
        )
        XCTAssertTrue(formalSnapshot.isZeroGapCertified)
        XCTAssertEqual(formalSnapshot.certifiedPillarCount, 6)
        XCTAssertEqual(formalSnapshot.statusHeadline, "发布签收证据已齐备 (6/6)")
    }

    func testUncertifiedPillarOrMismatchedSHATriggersBlockedWarningState() {
        var evidence = makeFormalEvidence(commitSHA: validFormalSHA)
        evidence[3] = ReleasePillarEvidenceInput(
            pillarID: "pillar-rc-gates-01-to-06",
            targetCommitSHA: validFormalSHA,
            evaluatedAtISO8601: "2026-10-20T22:00:00Z",
            status: .failed,
            completedCount: 5,
            requiredCount: 6,
            openBlockerCount: 1,
            hasMergeConflict: false,
            evidenceLinks: ["docs/evidence"],
            evidenceOrigin: .formal
        )
        let blockedSnapshot = FinalReleaseCertificateSnapshot.fromFormalEvidence(
            certificateID: "RC-BLOCKED-TEST",
            expectedCommitSHA: validFormalSHA,
            evidence: evidence
        )
        XCTAssertFalse(blockedSnapshot.isZeroGapCertified)
        XCTAssertEqual(blockedSnapshot.certifiedPillarCount, 5)
        XCTAssertEqual(blockedSnapshot.uncertifiedPillars.map(\.id), ["pillar-rc-gates-01-to-06"])
        XCTAssertEqual(blockedSnapshot.statusHeadline, "未验证/未签收：存在 1 项待核验阻断，暂不可签发发布证书")

        let invalidCutoffSnapshot = FinalReleaseCertificateSnapshot.fromFormalEvidence(
            certificateID: "RC-BAD-CUTOFF",
            expectedCommitSHA: validFormalSHA,
            notBeforeISO8601: "bad-cutoff",
            evidence: makeFormalEvidence(commitSHA: validFormalSHA)
        )
        XCTAssertFalse(invalidCutoffSnapshot.isZeroGapCertified)
        XCTAssertEqual(invalidCutoffSnapshot.certifiedPillarCount, 0)
    }

    func testMainActorViewBodyInstantiationForDefaultUnverifiedAndPreviewFixtureStates() {
        let defaultView = FinalReleaseSignoffAndZeroGapCertificateView()
        XCTAssertFalse(defaultView.snapshot.isZeroGapCertified)
        _ = defaultView.body

        let previewView = FinalReleaseSignoffAndZeroGapCertificateView(snapshot: .previewReadyFixture)
        XCTAssertFalse(previewView.snapshot.isZeroGapCertified)
        _ = previewView.body
    }
}
