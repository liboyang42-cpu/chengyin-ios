import XCTest
@testable import QuestifyCore

final class AppStoreReviewDemoAccountAndFixtureReadinessAuditTests: XCTestCase {
    func testCanonicalReviewerScenariosPassAppStoreReviewReadinessAudit() {
        let scenarios = AppStoreReviewDemoAccountAndFixtureReadinessAudit.canonicalScenarios
        XCTAssertEqual(scenarios.count, 4)
        XCTAssertTrue(scenarios.allSatisfy(\.isCompliant))
        XCTAssertEqual(
            scenarios.map(\.roleOrScenario),
            [
                "guest-browse-and-city-roam-preview",
                "authenticated-player-story-and-stamps",
                "merchant-store-and-insight-walkthrough",
                "club-admin-enrollment-and-settlement-walkthrough"
            ]
        )

        let result = AppStoreReviewDemoAccountAndFixtureReadinessAudit.evaluate()
        XCTAssertEqual(result.totalScenarios, 4)
        XCTAssertEqual(result.compliantScenarios, 4)
        XCTAssertTrue(result.isReviewDemoReady)
    }

    func testMissingOutOfCityLBSPreviewFallbackFailsReviewDemoReadiness() {
        var scenarios = AppStoreReviewDemoAccountAndFixtureReadinessAudit.canonicalScenarios
        scenarios[0] = AppStoreReviewerScenarioCheck(
            id: "guest-browse-and-city-roam-preview",
            roleOrScenario: "guest-browse-and-city-roam-preview",
            supportsOutOfCityLBSPreviewFallback: false,
            zeroInfiniteLoadingOrBlankScreen: true,
            hasReviewerWalkthroughNotes: true
        )

        XCTAssertFalse(scenarios[0].isCompliant)
        let result = AppStoreReviewDemoAccountAndFixtureReadinessAudit.evaluate(scenarios: scenarios)
        XCTAssertEqual(result.totalScenarios, 4)
        XCTAssertEqual(result.compliantScenarios, 3)
        XCTAssertFalse(result.isReviewDemoReady)
    }

    func testInfiniteLoadingOrBlankScreenRiskFailsReviewDemoReadiness() {
        var scenarios = AppStoreReviewDemoAccountAndFixtureReadinessAudit.canonicalScenarios
        scenarios[1] = AppStoreReviewerScenarioCheck(
            id: "authenticated-player-story-and-stamps",
            roleOrScenario: "authenticated-player-story-and-stamps",
            supportsOutOfCityLBSPreviewFallback: true,
            zeroInfiniteLoadingOrBlankScreen: false,
            hasReviewerWalkthroughNotes: true
        )

        XCTAssertFalse(scenarios[1].isCompliant)
        let result = AppStoreReviewDemoAccountAndFixtureReadinessAudit.evaluate(scenarios: scenarios)
        XCTAssertEqual(result.totalScenarios, 4)
        XCTAssertEqual(result.compliantScenarios, 3)
        XCTAssertFalse(result.isReviewDemoReady)
    }

    func testMissingReviewerWalkthroughNotesFailsReviewDemoReadiness() {
        var scenarios = AppStoreReviewDemoAccountAndFixtureReadinessAudit.canonicalScenarios
        scenarios[2] = AppStoreReviewerScenarioCheck(
            id: "merchant-store-and-insight-walkthrough",
            roleOrScenario: "merchant-store-and-insight-walkthrough",
            supportsOutOfCityLBSPreviewFallback: true,
            zeroInfiniteLoadingOrBlankScreen: true,
            hasReviewerWalkthroughNotes: false
        )

        XCTAssertFalse(scenarios[2].isCompliant)
        let result = AppStoreReviewDemoAccountAndFixtureReadinessAudit.evaluate(scenarios: scenarios)
        XCTAssertEqual(result.totalScenarios, 4)
        XCTAssertEqual(result.compliantScenarios, 3)
        XCTAssertFalse(result.isReviewDemoReady)
    }
}
