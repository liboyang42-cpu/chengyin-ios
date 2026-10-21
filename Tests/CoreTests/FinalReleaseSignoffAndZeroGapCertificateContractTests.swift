import XCTest
@testable import QuestifyCore

final class FinalReleaseSignoffAndZeroGapCertificateContractTests: XCTestCase {
    private let validFormalSHA = "50e2cf9be15999e35f566463db61908690f7c149"
    private let alternateFormalSHA = "1e72f9916c438d3fee4b7e087e002f16aeb3feaf"

    private func makeFormalPillars(commitSHA: String) -> [ReleaseCertificatePillar] {
        FinalReleaseSignoffAndZeroGapCertificateContract.canonicalPillars.map { req in
            ReleaseCertificatePillar(
                id: req.id,
                title: req.title,
                completedCount: req.requiredCount,
                requiredCount: req.requiredCount,
                zeroOpenBlockers: true,
                status: .passed,
                commitSHA: commitSHA,
                evaluatedAtISO8601: "2026-10-20T22:00:00Z",
                evidenceLinks: ["docs/handoff/issue-61-response-20261020.md#\(req.id)"],
                evidenceOrigin: .formal
            )
        }
    }

    private func makeFormalEvidenceInputs(commitSHA: String) -> [ReleasePillarEvidenceInput] {
        FinalReleaseSignoffAndZeroGapCertificateContract.canonicalPillars.map { req in
            ReleasePillarEvidenceInput(
                pillarID: req.id,
                targetCommitSHA: commitSHA,
                evaluatedAtISO8601: "2026-10-20T22:00:00+08:00",
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
            expectedCommitSHA: validFormalSHA,
            evidence: []
        )
        XCTAssertFalse(emptyEval.isZeroGapCertified)
        XCTAssertEqual(emptyEval.certifiedPillars, 0)
    }

    func testExplicitEvidenceBoundToTargetSHACertifiesOnlyWhenAllPassedAndConflictFree() {
        let inputs = makeFormalEvidenceInputs(commitSHA: validFormalSHA)
        let verified = FinalReleaseSignoffAndZeroGapCertificateContract.evaluateCertificate(
            expectedCommitSHA: validFormalSHA,
            notBeforeISO8601: "2026-10-20T21:00:00+08:00",
            hasMergeConflict: false,
            evidence: inputs
        )
        XCTAssertEqual(verified.totalPillars, 6)
        XCTAssertEqual(verified.certifiedPillars, 6)
        XCTAssertTrue(verified.isZeroGapCertified)

        let staleSHA = FinalReleaseSignoffAndZeroGapCertificateContract.evaluateCertificate(
            expectedCommitSHA: alternateFormalSHA,
            hasMergeConflict: false,
            evidence: inputs
        )
        XCTAssertFalse(staleSHA.isZeroGapCertified)
        XCTAssertEqual(staleSHA.certifiedPillars, 0)

        let conflict = FinalReleaseSignoffAndZeroGapCertificateContract.evaluateCertificate(
            expectedCommitSHA: validFormalSHA,
            hasMergeConflict: true,
            evidence: inputs
        )
        XCTAssertFalse(conflict.isZeroGapCertified)

        // Expired timestamp before notBeforeISO8601 must fail closed
        let expired = FinalReleaseSignoffAndZeroGapCertificateContract.evaluateCertificate(
            expectedCommitSHA: validFormalSHA,
            notBeforeISO8601: "2026-10-20T23:00:00+08:00",
            hasMergeConflict: false,
            evidence: inputs
        )
        XCTAssertFalse(expired.isZeroGapCertified)
        XCTAssertEqual(expired.certifiedPillars, 0)
    }

    func testDuplicateOrUnknownPillarIDsAndLoweredRequiredCountAreRejected() {
        // Repeating a single arbitrary id="x" 6 times with 1/1 passed must be rejected
        let arbitraryRepeated = Array(
            repeating: ReleaseCertificatePillar(
                id: "x",
                title: "Arbitrary Pillar",
                completedCount: 1,
                requiredCount: 1,
                zeroOpenBlockers: true,
                status: .passed,
                commitSHA: validFormalSHA,
                evaluatedAtISO8601: "2026-10-20T22:00:00Z",
                evidenceLinks: ["docs/evidence"],
                evidenceOrigin: .formal
            ),
            count: 6
        )
        let arbitraryCert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: arbitraryRepeated,
            expectedCommitSHA: validFormalSHA
        )
        XCTAssertEqual(arbitraryCert.certifiedPillars, 0)
        XCTAssertFalse(arbitraryCert.isZeroGapCertified)

        // Repeating a single valid canonical pillar 6 times must also be rejected
        let firstCanonical = makeFormalPillars(commitSHA: validFormalSHA)[0]
        let canonicalRepeated = Array(repeating: firstCanonical, count: 6)
        let repeatedCert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: canonicalRepeated,
            expectedCommitSHA: validFormalSHA
        )
        XCTAssertEqual(repeatedCert.certifiedPillars, 0)
        XCTAssertFalse(repeatedCert.isZeroGapCertified)

        // Lowering requiredCount below canonical requirement (e.g. 1/1 instead of 99/99) must be rejected
        var loweredPillars = makeFormalPillars(commitSHA: validFormalSHA)
        loweredPillars[2] = ReleaseCertificatePillar(
            id: "pillar-miniprogram-99-pages",
            title: "WeChat Mini-Program 99-Page Baseline Subset (Domains B–E)",
            completedCount: 1,
            requiredCount: 1,
            zeroOpenBlockers: true,
            status: .passed,
            commitSHA: validFormalSHA,
            evaluatedAtISO8601: "2026-10-20T22:00:00Z",
            evidenceLinks: ["docs/evidence"],
            evidenceOrigin: .formal
        )
        XCTAssertFalse(loweredPillars[2].isCertified)
        let loweredCert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: loweredPillars,
            expectedCommitSHA: validFormalSHA
        )
        XCTAssertEqual(loweredCert.certifiedPillars, 5)
        XCTAssertFalse(loweredCert.isZeroGapCertified)
    }

    func testOmittedTargetSHAOrMixedSHAsAndInvalidNotBeforeCutoffAreRejected() {
        let formalPillars = makeFormalPillars(commitSHA: validFormalSHA)

        // Omitting expectedCommitSHA must fail closed
        let omittedTargetSHA = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: formalPillars
        )
        XCTAssertEqual(omittedTargetSHA.certifiedPillars, 0)
        XCTAssertFalse(omittedTargetSHA.isZeroGapCertified)

        // Mixing two valid 40-hex SHAs across pillars must fail closed
        var mixedPillars = formalPillars
        mixedPillars[5] = ReleaseCertificatePillar(
            id: mixedPillars[5].id,
            title: mixedPillars[5].title,
            completedCount: mixedPillars[5].requiredCount,
            requiredCount: mixedPillars[5].requiredCount,
            zeroOpenBlockers: true,
            status: .passed,
            commitSHA: alternateFormalSHA,
            evaluatedAtISO8601: "2026-10-20T22:00:00Z",
            evidenceLinks: ["docs/evidence"],
            evidenceOrigin: .formal
        )
        let mixedCert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: mixedPillars,
            expectedCommitSHA: validFormalSHA
        )
        XCTAssertEqual(mixedCert.certifiedPillars, 5)
        XCTAssertFalse(mixedCert.isZeroGapCertified)

        // Explicitly passing an invalid non-nil notBeforeISO8601 must be rejected, never ignored
        let invalidNotBeforeEval = FinalReleaseSignoffAndZeroGapCertificateContract.evaluateCertificate(
            expectedCommitSHA: validFormalSHA,
            notBeforeISO8601: "not-a-valid-iso8601-cutoff",
            hasMergeConflict: false,
            evidence: makeFormalEvidenceInputs(commitSHA: validFormalSHA)
        )
        XCTAssertEqual(invalidNotBeforeEval.certifiedPillars, 0)
        XCTAssertFalse(invalidNotBeforeEval.isZeroGapCertified)

        let invalidNotBeforeIssue = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: formalPillars,
            expectedCommitSHA: validFormalSHA,
            notBeforeISO8601: "invalid-cutoff"
        )
        XCTAssertEqual(invalidNotBeforeIssue.certifiedPillars, 0)
        XCTAssertFalse(invalidNotBeforeIssue.isZeroGapCertified)
    }

    func testPreviewFixturePillarsRemainBlockedEvenWhenSuppliedReal40HexSHA() {
        let spoofedPreviewPillars = FinalReleaseSignoffAndZeroGapCertificateContract.previewFixturePillars(
            commitSHA: validFormalSHA,
            evaluatedAtISO8601: "2026-10-20T22:00:00Z"
        )
        XCTAssertTrue(spoofedPreviewPillars.allSatisfy { $0.isPreviewFixture && !$0.isCertified })

        let spoofedCert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: spoofedPreviewPillars,
            expectedCommitSHA: validFormalSHA
        )
        XCTAssertEqual(spoofedCert.certifiedPillars, 0)
        XCTAssertFalse(spoofedCert.isZeroGapCertified)
    }

    func testOpenBlockerPendingNotRunOrMissingEvidenceRejectsCertificate() {
        var pillars = makeFormalPillars(commitSHA: alternateFormalSHA)
        pillars[3] = ReleaseCertificatePillar(
            id: "pillar-rc-gates-01-to-06",
            title: "Release Candidate Gates RC-GATE-01 through RC-GATE-06",
            completedCount: 6,
            requiredCount: 6,
            zeroOpenBlockers: false,
            status: .passed,
            commitSHA: alternateFormalSHA,
            evaluatedAtISO8601: "2026-10-20T22:00:00Z",
            evidenceLinks: ["docs/evidence"]
        )

        XCTAssertFalse(pillars[3].isCertified)
        let cert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: pillars,
            expectedCommitSHA: alternateFormalSHA
        )
        XCTAssertEqual(cert.totalPillars, 6)
        XCTAssertEqual(cert.certifiedPillars, 5)
        XCTAssertFalse(cert.isZeroGapCertified)

        for nonPassingStatus in [ReleaseCheckStatus.failed, .pending, .notRun] {
            let statusPillar = ReleaseCertificatePillar(
                id: "pillar-rc-gates-01-to-06",
                title: "Non-passing status test",
                completedCount: 6,
                requiredCount: 6,
                zeroOpenBlockers: true,
                status: nonPassingStatus,
                commitSHA: alternateFormalSHA,
                evaluatedAtISO8601: "2026-10-20T22:00:00Z",
                evidenceLinks: ["docs/evidence"]
            )
            XCTAssertFalse(statusPillar.isCertified)
        }

        let missingLinkPillar = ReleaseCertificatePillar(
            id: "pillar-rc-gates-01-to-06",
            title: "Missing evidence link",
            completedCount: 6,
            requiredCount: 6,
            zeroOpenBlockers: true,
            status: .passed,
            commitSHA: alternateFormalSHA,
            evaluatedAtISO8601: "2026-10-20T22:00:00Z",
            evidenceLinks: []
        )
        XCTAssertFalse(missingLinkPillar.isCertified)

        let invalidTimestampPillar = ReleaseCertificatePillar(
            id: "pillar-rc-gates-01-to-06",
            title: "Invalid timestamp",
            completedCount: 6,
            requiredCount: 6,
            zeroOpenBlockers: true,
            status: .passed,
            commitSHA: alternateFormalSHA,
            evaluatedAtISO8601: "not-an-iso-timestamp",
            evidenceLinks: ["docs/evidence"]
        )
        XCTAssertFalse(invalidTimestampPillar.isCertified)
    }

    func testIncompleteCountOrZeroRequiredCountRejectsCertificate() {
        var pillars = makeFormalPillars(commitSHA: alternateFormalSHA)
        pillars[2] = ReleaseCertificatePillar(
            id: "pillar-miniprogram-99-pages",
            title: "WeChat Mini-Program 99-Page Baseline Subset (Domains B–E)",
            completedCount: 98,
            requiredCount: 99,
            zeroOpenBlockers: true,
            status: .passed,
            commitSHA: alternateFormalSHA,
            evaluatedAtISO8601: "2026-10-20T22:00:00Z",
            evidenceLinks: ["docs/evidence"]
        )
        XCTAssertFalse(pillars[2].isCertified)

        let zeroRequired = ReleaseCertificatePillar(
            id: "pillar-rc-gates-01-to-06",
            title: "Invalid Zero Requirement",
            completedCount: 0,
            requiredCount: 0,
            zeroOpenBlockers: true,
            status: .passed,
            commitSHA: alternateFormalSHA,
            evaluatedAtISO8601: "2026-10-20T22:00:00Z",
            evidenceLinks: ["docs/evidence"]
        )
        XCTAssertFalse(zeroRequired.isCertified)

        let cert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: pillars,
            expectedCommitSHA: alternateFormalSHA
        )
        XCTAssertEqual(cert.totalPillars, 6)
        XCTAssertEqual(cert.certifiedPillars, 5)
        XCTAssertFalse(cert.isZeroGapCertified)
    }

    func testEmptyPillarsListRejectsZeroGapCertificate() {
        let cert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: [],
            expectedCommitSHA: validFormalSHA
        )
        XCTAssertEqual(cert.totalPillars, 0)
        XCTAssertEqual(cert.certifiedPillars, 0)
        XCTAssertFalse(cert.isZeroGapCertified)
    }
}
