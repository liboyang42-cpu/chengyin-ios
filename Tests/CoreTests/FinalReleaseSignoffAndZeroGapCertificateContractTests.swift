import XCTest
@testable import QuestifyCore

final class FinalReleaseSignoffAndZeroGapCertificateContractTests: XCTestCase {

    func testCanonicalSixPillarsIssueZeroGapCertificate() {
        testDefaultCanonicalPillarsAreUnverifiedAndNeverSelfApprove()
    }

    func testOpenBlockerRejectsZeroGapCertificate() {
        testOpenBlockerPendingNotRunOrMissingEvidenceRejectsCertificate()
    }

    func testDefaultCanonicalPillarsAreUnverifiedAndNeverSelfApprove() {
        let pillars = FinalReleaseSignoffAndZeroGapCertificateContract.canonicalPillars
        XCTAssertEqual(pillars.count, 6)
        XCTAssertEqual(
            pillars.map(\.id),
            [
                "pillar-wave1-to-wave3-tickets",
                "pillar-reform-v9-w02-to-w20",
                "pillar-miniprogram-99-pages",
                "pillar-rc-gates-01-to-06",
                "pillar-appstore-privacy-and-ugc",
                "pillar-cloud-ci-and-contract-checks"
            ]
        )
        XCTAssertTrue(pillars.allSatisfy { !$0.isCertified && $0.status == .notRun && !$0.zeroOpenBlockers })

        let defaultCert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate()
        XCTAssertEqual(defaultCert.totalPillars, 6)
        XCTAssertEqual(defaultCert.certifiedPillars, 0)
        XCTAssertFalse(defaultCert.isZeroGapCertified)

        let emptyEval = FinalReleaseSignoffAndZeroGapCertificateContract.evaluateCertificate(
            expectedCommitSHA: "50e2cf9be15999e35f566463db61908690f7c149",
            evidence: []
        )
        XCTAssertFalse(emptyEval.isZeroGapCertified)
        XCTAssertEqual(emptyEval.certifiedPillars, 0)
    }

    func testExplicitEvidenceBoundToTargetSHACertifiesOnlyWhenAllPassedAndConflictFree() {
        let sha = "50e2cf9be15999e35f566463db61908690f7c149"
        let inputs = FinalReleaseSignoffAndZeroGapCertificateContract.canonicalPillars.map { req in
            ReleasePillarEvidenceInput(
                pillarID: req.id,
                targetCommitSHA: sha,
                evaluatedAtISO8601: "2026-10-20T22:00:00+08:00",
                status: .passed,
                completedCount: req.requiredCount,
                requiredCount: req.requiredCount,
                openBlockerCount: 0,
                hasMergeConflict: false,
                evidenceLinks: ["docs/handoff/issue-61-response-20261020.md#\(req.id)"]
            )
        }
        let verified = FinalReleaseSignoffAndZeroGapCertificateContract.evaluateCertificate(
            expectedCommitSHA: sha,
            hasMergeConflict: false,
            evidence: inputs
        )
        XCTAssertEqual(verified.totalPillars, 6)
        XCTAssertEqual(verified.certifiedPillars, 6)
        XCTAssertTrue(verified.isZeroGapCertified)

        let staleSHA = FinalReleaseSignoffAndZeroGapCertificateContract.evaluateCertificate(
            expectedCommitSHA: "different-target-sha",
            hasMergeConflict: false,
            evidence: inputs
        )
        XCTAssertFalse(staleSHA.isZeroGapCertified)
        XCTAssertEqual(staleSHA.certifiedPillars, 0)

        let conflict = FinalReleaseSignoffAndZeroGapCertificateContract.evaluateCertificate(
            expectedCommitSHA: sha,
            hasMergeConflict: true,
            evidence: inputs
        )
        XCTAssertFalse(conflict.isZeroGapCertified)

        // Expired timestamp before notBeforeISO8601 must fail closed
        let expired = FinalReleaseSignoffAndZeroGapCertificateContract.evaluateCertificate(
            expectedCommitSHA: sha,
            notBeforeISO8601: "2026-10-20T23:00:00+08:00",
            hasMergeConflict: false,
            evidence: inputs
        )
        XCTAssertFalse(expired.isZeroGapCertified)
        XCTAssertEqual(expired.certifiedPillars, 0)

        // Preview/fixture SHA must be rejected by formal certificate evaluation
        let previewAttempt = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: FinalReleaseSignoffAndZeroGapCertificateContract.previewFixturePillars(),
            expectedCommitSHA: "fixture-preview-sha"
        )
        XCTAssertFalse(previewAttempt.isZeroGapCertified)
    }

    func testOpenBlockerPendingNotRunOrMissingEvidenceRejectsCertificate() {
        var pillars = FinalReleaseSignoffAndZeroGapCertificateContract.previewFixturePillars(commitSHA: "1e72f9916c438d3fee4b7e087e002f16aeb3feaf")
        pillars[3] = ReleaseCertificatePillar(
            id: "pillar-rc-gates-01-to-06",
            title: "Release Candidate Gates RC-GATE-01 through RC-GATE-06",
            completedCount: 6,
            requiredCount: 6,
            zeroOpenBlockers: false,
            status: .passed,
            commitSHA: "1e72f9916c438d3fee4b7e087e002f16aeb3feaf",
            evaluatedAtISO8601: "2026-10-20T22:00:00Z",
            evidenceLinks: ["docs/evidence"]
        )

        XCTAssertFalse(pillars[3].isCertified)
        let cert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: pillars,
            expectedCommitSHA: "1e72f9916c438d3fee4b7e087e002f16aeb3feaf"
        )
        XCTAssertEqual(cert.totalPillars, 6)
        XCTAssertEqual(cert.certifiedPillars, 5)
        XCTAssertFalse(cert.isZeroGapCertified)

        for nonPassingStatus in [ReleaseCheckStatus.failed, .pending, .notRun] {
            let statusPillar = ReleaseCertificatePillar(
                id: "pillar-status-\(nonPassingStatus.rawValue)",
                title: "Non-passing status test",
                completedCount: 6,
                requiredCount: 6,
                zeroOpenBlockers: true,
                status: nonPassingStatus,
                commitSHA: "1e72f9916c438d3fee4b7e087e002f16aeb3feaf",
                evaluatedAtISO8601: "2026-10-20T22:00:00Z",
                evidenceLinks: ["docs/evidence"]
            )
            XCTAssertFalse(statusPillar.isCertified)
        }

        let missingLinkPillar = ReleaseCertificatePillar(
            id: "pillar-missing-link",
            title: "Missing evidence link",
            completedCount: 6,
            requiredCount: 6,
            zeroOpenBlockers: true,
            status: .passed,
            commitSHA: "1e72f9916c438d3fee4b7e087e002f16aeb3feaf",
            evaluatedAtISO8601: "2026-10-20T22:00:00Z",
            evidenceLinks: []
        )
        XCTAssertFalse(missingLinkPillar.isCertified)

        let invalidTimestampPillar = ReleaseCertificatePillar(
            id: "pillar-bad-time",
            title: "Invalid timestamp",
            completedCount: 6,
            requiredCount: 6,
            zeroOpenBlockers: true,
            status: .passed,
            commitSHA: "1e72f9916c438d3fee4b7e087e002f16aeb3feaf",
            evaluatedAtISO8601: "not-an-iso-timestamp",
            evidenceLinks: ["docs/evidence"]
        )
        XCTAssertFalse(invalidTimestampPillar.isCertified)
    }

    func testIncompleteCountOrZeroRequiredCountRejectsCertificate() {
        var pillars = FinalReleaseSignoffAndZeroGapCertificateContract.previewFixturePillars(commitSHA: "1e72f9916c438d3fee4b7e087e002f16aeb3feaf")
        pillars[2] = ReleaseCertificatePillar(
            id: "pillar-miniprogram-99-pages",
            title: "WeChat Mini-Program 99-Page Parity Alignment (Domains B–E)",
            completedCount: 98,
            requiredCount: 99,
            zeroOpenBlockers: true,
            status: .passed,
            commitSHA: "1e72f9916c438d3fee4b7e087e002f16aeb3feaf",
            evaluatedAtISO8601: "2026-10-20T22:00:00Z",
            evidenceLinks: ["docs/evidence"]
        )
        XCTAssertFalse(pillars[2].isCertified)

        let zeroRequired = ReleaseCertificatePillar(
            id: "pillar-zero-req",
            title: "Invalid Zero Requirement",
            completedCount: 0,
            requiredCount: 0,
            zeroOpenBlockers: true,
            status: .passed,
            commitSHA: "1e72f9916c438d3fee4b7e087e002f16aeb3feaf",
            evaluatedAtISO8601: "2026-10-20T22:00:00Z",
            evidenceLinks: ["docs/evidence"]
        )
        XCTAssertFalse(zeroRequired.isCertified)

        let cert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: pillars,
            expectedCommitSHA: "1e72f9916c438d3fee4b7e087e002f16aeb3feaf"
        )
        XCTAssertEqual(cert.totalPillars, 6)
        XCTAssertEqual(cert.certifiedPillars, 5)
        XCTAssertFalse(cert.isZeroGapCertified)
    }

    func testEmptyPillarsListRejectsZeroGapCertificate() {
        let cert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(pillars: [])
        XCTAssertEqual(cert.totalPillars, 0)
        XCTAssertEqual(cert.certifiedPillars, 0)
        XCTAssertFalse(cert.isZeroGapCertified)
    }
}
