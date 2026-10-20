import SwiftUI
import XCTest
#if canImport(Questify)
@testable import Questify
#elseif canImport(QuestifyApp)
@testable import QuestifyApp
#endif
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor final class AppStoreReviewDemoAccountAndFixtureSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllFourPersonasAndOutOfCityLBSFallback() {
        let snapshot = AppStoreReviewDemoSnapshot.defaultReady
        XCTAssertTrue(snapshot.isGuideline21Ready)
        XCTAssertEqual(snapshot.scenarios.count, 4)
        XCTAssertEqual(snapshot.readyScenarioCount, 4)
        XCTAssertTrue(snapshot.guideline21NotesPrepared)
        XCTAssertTrue(snapshot.outOfCityLBSPreviewFallbackEnabled)
        XCTAssertTrue(snapshot.demoCredentialsRedactedInSource)
        XCTAssertEqual(
            snapshot.scenarios.map(\.persona),
            [.guest, .player, .merchant, .clubAdmin]
        )
        XCTAssertTrue(snapshot.scenarios.allSatisfy(\.supportsOutOfCityLBSFallback))
    }

    func testUnreadyReviewerScenarioOrDisabledLBSFallbackMarksSnapshotNotReady() {
        var customScenarios = ReviewerScenarioRow.defaultRows
        customScenarios[1] = ReviewerScenarioRow(
            id: "player-run-and-lbs-fallback",
            persona: .player,
            title: "Player — Activity Run, Orders & Out-of-City LBS Preview",
            walkthroughSummary: "Missing out-of-city LBS fallback",
            supportsOutOfCityLBSFallback: false,
            isScenarioReady: false,
            badgeText: "UNREADY"
        )
        let unreadyScenarioSnapshot = AppStoreReviewDemoSnapshot(scenarios: customScenarios)
        XCTAssertEqual(unreadyScenarioSnapshot.readyScenarioCount, 3)
        XCTAssertFalse(unreadyScenarioSnapshot.isGuideline21Ready)

        let disabledLBSSnapshot = AppStoreReviewDemoSnapshot(
            outOfCityLBSPreviewFallbackEnabled: false
        )
        XCTAssertFalse(disabledLBSSnapshot.isGuideline21Ready)

        let exposedCredentialsSnapshot = AppStoreReviewDemoSnapshot(
            demoCredentialsRedactedInSource: false
        )
        XCTAssertFalse(exposedCredentialsSnapshot.isGuideline21Ready)
    }

    func testMainActorViewBodyInstantiatesAcrossDefaultAndUnreadySnapshots() {
        let readyView = AppStoreReviewDemoAccountAndFixtureSectionView()
        _ = readyView.body
        XCTAssertTrue(readyView.snapshot.isGuideline21Ready)

        let unreadyView = AppStoreReviewDemoAccountAndFixtureSectionView(
            snapshot: AppStoreReviewDemoSnapshot(
                guideline21NotesPrepared: false,
                outOfCityLBSPreviewFallbackEnabled: false,
                demoCredentialsRedactedInSource: false
            )
        )
        _ = unreadyView.body
        XCTAssertFalse(unreadyView.snapshot.isGuideline21Ready)
    }
}
