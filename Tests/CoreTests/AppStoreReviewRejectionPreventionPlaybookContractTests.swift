import XCTest
#if canImport(QuestifyCore)
@testable import QuestifyCore
#elseif canImport(Core)
@testable import Core
#endif

final class AppStoreReviewRejectionPreventionPlaybookContractTests: XCTestCase {

    func testCanonicalEightGuidelinesPassRejectionDefense() {
        let result = AppStoreReviewRejectionPreventionPlaybookContract.evaluate()
        XCTAssertEqual(result.totalRules, 8)
        XCTAssertEqual(result.defendedRules, 8)
        XCTAssertTrue(result.isRejectionDefenseComplete)

        let codes = AppStoreReviewRejectionPreventionPlaybookContract.canonicalRules.map(\.guidelineCode)
        XCTAssertEqual(
            codes,
            [
                "Guideline 2.1",
                "Guideline 1.2",
                "Guideline 3.1.1",
                "Guideline 4.8",
                "Guideline 5.1.1(i)",
                "Guideline 5.1.1(v)",
                "Guideline 5.1.2",
                "ITMS-91053"
            ]
        )
    }

    func testMissingInAppTechnicalDefenseIsDetected() {
        var rules = AppStoreReviewRejectionPreventionPlaybookContract.canonicalRules
        rules[1] = AppStoreRejectionDefenseRule(
            id: "guideline-1-2-ugc-safety",
            guidelineCode: "Guideline 1.2",
            hasInAppTechnicalDefense: false,
            hasAutomatedXCTestCoverage: true,
            hasReviewerNotesExplanation: true
        )
        XCTAssertFalse(rules[1].isDefended)

        let result = AppStoreReviewRejectionPreventionPlaybookContract.evaluate(rules: rules)
        XCTAssertEqual(result.totalRules, 8)
        XCTAssertEqual(result.defendedRules, 7)
        XCTAssertFalse(result.isRejectionDefenseComplete)
    }

    func testMissingAutomatedXCTestCoverageIsDetected() {
        var rules = AppStoreReviewRejectionPreventionPlaybookContract.canonicalRules
        rules[5] = AppStoreRejectionDefenseRule(
            id: "guideline-5-1-1-v-account-deletion-in-app",
            guidelineCode: "Guideline 5.1.1(v)",
            hasInAppTechnicalDefense: true,
            hasAutomatedXCTestCoverage: false,
            hasReviewerNotesExplanation: true
        )
        XCTAssertFalse(rules[5].isDefended)

        let result = AppStoreReviewRejectionPreventionPlaybookContract.evaluate(rules: rules)
        XCTAssertEqual(result.defendedRules, 7)
        XCTAssertFalse(result.isRejectionDefenseComplete)
    }

    func testMissingReviewerNotesExplanationIsDetected() {
        var rules = AppStoreReviewRejectionPreventionPlaybookContract.canonicalRules
        rules[2] = AppStoreRejectionDefenseRule(
            id: "guideline-3-1-1-in-app-purchase-physical-goods",
            guidelineCode: "Guideline 3.1.1",
            hasInAppTechnicalDefense: true,
            hasAutomatedXCTestCoverage: true,
            hasReviewerNotesExplanation: false
        )
        XCTAssertFalse(rules[2].isDefended)

        let result = AppStoreReviewRejectionPreventionPlaybookContract.evaluate(rules: rules)
        XCTAssertEqual(result.defendedRules, 7)
        XCTAssertFalse(result.isRejectionDefenseComplete)
    }
}
