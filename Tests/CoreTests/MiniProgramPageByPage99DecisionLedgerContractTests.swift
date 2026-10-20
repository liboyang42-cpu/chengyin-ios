import XCTest
@testable import QuestifyCore

final class MiniProgramPageByPage99DecisionLedgerContractTests: XCTestCase {
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
}
