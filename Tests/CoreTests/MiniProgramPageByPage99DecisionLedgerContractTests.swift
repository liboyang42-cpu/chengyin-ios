import XCTest
@testable import QuestifyCore

final class MiniProgramPageByPage99DecisionLedgerContractTests: XCTestCase {
    private let validFormalSHA = "50e2cf9be15999e35f566463db61908690f7c149"
    private let alternateFormalSHA = "1e72f9916c438d3fee4b7e087e002f16aeb3feaf"

    func testCanonicalGroupsSumToExactly99PagesAndPassLedgerCheck() {
        let result = MiniProgramPageByPage99DecisionLedgerContract.evaluate()
        XCTAssertEqual(result.totalPages, 99)
        XCTAssertEqual(result.strictParityPages + result.nativeSupersetPages, 99)
        XCTAssertEqual(result.strictParityPages, 68)
        XCTAssertEqual(result.nativeSupersetPages, 31)
        XCTAssertTrue(result.is99PageLedgerComplete)
        XCTAssertEqual(
            MiniProgramPageByPage99DecisionLedgerContract.canonicalGroups.map(\.id),
            [
                "group-tabbar-and-home-15",
                "group-roam-and-passport-22",
                "group-play-and-story-18",
                "group-club-team-and-coop-24",
                "group-merchant-profile-and-legal-20"
            ]
        )
        XCTAssertEqual(
            MiniProgramPageByPage99DecisionLedgerContract.canonicalGroups.map(\.totalPagesInGroup),
            [15, 22, 18, 24, 20]
        )

        // Default canonical 99 page rows must NOT bulk-pass codeStatus or wiringStatus without evidence
        let defaultRows = MiniProgramPageByPage99DecisionLedgerContract.canonical99PageRows
        XCTAssertEqual(defaultRows.count, 99)
        XCTAssertTrue(defaultRows.allSatisfy {
            $0.codeStatus == .pending
                && $0.wiringStatus == .pending
                && $0.testStatus == .notRun
                && $0.deploymentStatus == .notRun
                && !$0.isEndToEndVerified
        })
        XCTAssertFalse(MiniProgramPageByPage99DecisionLedgerContract.evaluateEndToEndVerification())
    }

    func testPageCountMismatchFrom99IsRejected() {
        var groups = MiniProgramPageByPage99DecisionLedgerContract.canonicalGroups
        groups[0] = MiniProgram99DomainDecisionGroup(
            id: "group-tabbar-and-home-15",
            groupTitle: "主导航与首页",
            strictMiniProgramParityPageCount: 10,
            nativeSupersetEnhancedPageCount: 4
        )
        let result = MiniProgramPageByPage99DecisionLedgerContract.evaluate(groups: groups)
        XCTAssertEqual(result.totalPages, 98)
        XCTAssertFalse(result.is99PageLedgerComplete)
    }

    func testBackendContractIncompatibilityIsRejected() {
        var groups = MiniProgramPageByPage99DecisionLedgerContract.canonicalGroups
        groups[2] = MiniProgram99DomainDecisionGroup(
            id: "group-play-and-story-18",
            groupTitle: "剧本游玩",
            strictMiniProgramParityPageCount: 11,
            nativeSupersetEnhancedPageCount: 7,
            backendContract100PercentCompatible: false
        )
        XCTAssertFalse(groups[2].isCompliant)
        let result = MiniProgramPageByPage99DecisionLedgerContract.evaluate(groups: groups)
        XCTAssertEqual(result.totalPages, 99)
        XCTAssertFalse(result.is99PageLedgerComplete)
    }

    func testNegativePageCountsAreRejectedEvenWhenSumEqualsTotal() {
        var groups = MiniProgramPageByPage99DecisionLedgerContract.canonicalGroups
        groups[4] = MiniProgram99DomainDecisionGroup(
            id: "group-merchant-profile-and-legal-20",
            groupTitle: "商户与个人中心",
            strictMiniProgramParityPageCount: 22,
            nativeSupersetEnhancedPageCount: -2,
            backendContract100PercentCompatible: true
        )
        XCTAssertFalse(groups[4].isCompliant)
        let result = MiniProgramPageByPage99DecisionLedgerContract.evaluate(groups: groups)
        XCTAssertEqual(result.totalPages, 99)
        XCTAssertFalse(result.is99PageLedgerComplete)
    }

    func testEndToEndVerificationRejectsDuplicateRoutesUnknownRoutesAndMissingOrMismatchedSHA() {
        let verifiedRows = MiniProgramPageByPage99DecisionLedgerContract.canonical99PageRows.map { row in
            MiniProgram99PageDecisionLedgerRow(
                pagePath: row.pagePath,
                groupID: row.groupID,
                decisionMode: row.decisionMode,
                codeStatus: .passed,
                wiringStatus: .passed,
                testStatus: .passed,
                deploymentStatus: .passed,
                verifiedCommitSHA: validFormalSHA,
                evidenceSymbolOrPath: "docs/handoff/issue-61-response-20261020.md#\(row.pagePath)"
            )
        }
        XCTAssertTrue(
            MiniProgramPageByPage99DecisionLedgerContract.evaluateEndToEndVerification(
                rows: verifiedRows,
                expectedCommitSHA: validFormalSHA
            )
        )

        // Copying the same passed record 99 times must be rejected
        let repeated99 = Array(repeating: verifiedRows[0], count: 99)
        XCTAssertFalse(
            MiniProgramPageByPage99DecisionLedgerContract.evaluateEndToEndVerification(
                rows: repeated99,
                expectedCommitSHA: validFormalSHA
            )
        )

        // Unknown route outside the 99 canonical routes must be rejected
        var unknownRouteRows = verifiedRows
        unknownRouteRows[0] = MiniProgram99PageDecisionLedgerRow(
            pagePath: "pages/unknown/nonexistent",
            groupID: verifiedRows[0].groupID,
            decisionMode: verifiedRows[0].decisionMode,
            codeStatus: .passed,
            wiringStatus: .passed,
            testStatus: .passed,
            deploymentStatus: .passed,
            verifiedCommitSHA: validFormalSHA,
            evidenceSymbolOrPath: "docs/evidence"
        )
        XCTAssertFalse(
            MiniProgramPageByPage99DecisionLedgerContract.evaluateEndToEndVerification(
                rows: unknownRouteRows,
                expectedCommitSHA: validFormalSHA
            )
        )

        // Missing SHA evidence or mixed SHAs must be rejected
        var missingSHARows = verifiedRows
        missingSHARows[10] = MiniProgram99PageDecisionLedgerRow(
            pagePath: verifiedRows[10].pagePath,
            groupID: verifiedRows[10].groupID,
            decisionMode: verifiedRows[10].decisionMode,
            codeStatus: .passed,
            wiringStatus: .passed,
            testStatus: .passed,
            deploymentStatus: .passed,
            verifiedCommitSHA: "",
            evidenceSymbolOrPath: "docs/evidence"
        )
        XCTAssertFalse(missingSHARows[10].isEndToEndVerified)
        XCTAssertFalse(
            MiniProgramPageByPage99DecisionLedgerContract.evaluateEndToEndVerification(
                rows: missingSHARows,
                expectedCommitSHA: validFormalSHA
            )
        )

        var mixedSHARows = verifiedRows
        mixedSHARows[10] = MiniProgram99PageDecisionLedgerRow(
            pagePath: verifiedRows[10].pagePath,
            groupID: verifiedRows[10].groupID,
            decisionMode: verifiedRows[10].decisionMode,
            codeStatus: .passed,
            wiringStatus: .passed,
            testStatus: .passed,
            deploymentStatus: .passed,
            verifiedCommitSHA: alternateFormalSHA,
            evidenceSymbolOrPath: "docs/evidence"
        )
        XCTAssertFalse(
            MiniProgramPageByPage99DecisionLedgerContract.evaluateEndToEndVerification(
                rows: mixedSHARows,
                expectedCommitSHA: validFormalSHA
            )
        )
    }
}
