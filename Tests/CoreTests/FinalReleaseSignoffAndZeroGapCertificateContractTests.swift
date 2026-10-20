import XCTest
@testable import QuestifyCore

final class FinalReleaseSignoffAndZeroGapCertificateContractTests: XCTestCase {

    func testAllSixCanonicalPillarsPassZeroGapCertificate() {
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
        XCTAssertTrue(pillars.allSatisfy(\.isCertified))

        let cert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate()
        XCTAssertEqual(cert.totalPillars, 6)
        XCTAssertEqual(cert.certifiedPillars, 6)
        XCTAssertTrue(cert.isZeroGapCertified)
    }

    func testOpenBlockerRejectsZeroGapCertificate() {
        var pillars = FinalReleaseSignoffAndZeroGapCertificateContract.canonicalPillars
        pillars[3] = ReleaseCertificatePillar(
            id: "pillar-rc-gates-01-to-06",
            title: "Release Candidate Gates RC-GATE-01 through RC-GATE-06",
            completedCount: 6,
            requiredCount: 6,
            zeroOpenBlockers: false
        )

        XCTAssertFalse(pillars[3].isCertified)
        let cert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(pillars: pillars)
        XCTAssertEqual(cert.totalPillars, 6)
        XCTAssertEqual(cert.certifiedPillars, 5)
        XCTAssertFalse(cert.isZeroGapCertified)
    }

    func testIncompleteCountOrZeroRequiredCountRejectsCertificate() {
        var pillars = FinalReleaseSignoffAndZeroGapCertificateContract.canonicalPillars
        pillars[2] = ReleaseCertificatePillar(
            id: "pillar-miniprogram-99-pages",
            title: "WeChat Mini-Program 99-Page Parity Alignment (Domains B–E)",
            completedCount: 98,
            requiredCount: 99,
            zeroOpenBlockers: true
        )
        XCTAssertFalse(pillars[2].isCertified)

        let zeroRequired = ReleaseCertificatePillar(
            id: "pillar-zero-req",
            title: "Invalid Zero Requirement",
            completedCount: 0,
            requiredCount: 0,
            zeroOpenBlockers: true
        )
        XCTAssertFalse(zeroRequired.isCertified)

        let cert = FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(pillars: pillars)
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
