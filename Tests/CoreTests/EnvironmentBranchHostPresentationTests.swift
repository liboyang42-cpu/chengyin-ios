import XCTest
@testable import QuestifyCore

final class EnvironmentBranchHostPresentationTests: XCTestCase {
    private let serverNow = Date(timeIntervalSince1970: 1_760_000_000)

    private var sampleWindow: DateInterval {
        DateInterval(
            start: Date(timeIntervalSince1970: 1_759_996_800),
            end: Date(timeIntervalSince1970: 1_760_004_000)
        )
    }

    private var outdoorBranch: ApprovedBranch {
        ApprovedBranch(
            branchID: "branch-outdoor-courtyard",
            window: sampleWindow,
            indoor: false,
            requiresOpenStore: true,
            requiredPlaceIDs: ["place-courtyard"],
            isDeterministicFallback: false
        )
    }

    private var fallbackIndoorBranch: ApprovedBranch {
        ApprovedBranch(
            branchID: "branch-indoor-fallback",
            window: nil,
            indoor: true,
            requiresOpenStore: false,
            requiredPlaceIDs: [],
            isDeterministicFallback: true
        )
    }

    func testApprovedBranchSelectionFromUsableSnapshotFormatsServerWindow() {
        let snapshot = EnvironmentSnapshot(
            snapshotID: "snap-101",
            source: "server-weather-service",
            observedAt: serverNow.addingTimeInterval(-120),
            expiresAt: serverNow.addingTimeInterval(600),
            runTimeZoneID: "Asia/Shanghai",
            weather: .clear,
            storeOpen: true,
            reachablePlaceIDs: ["place-courtyard", "place-hall"]
        )

        let presentation = EnvironmentBranchHostPresentation.resolve(
            proposedBranchID: "branch-outdoor-courtyard",
            branches: [outdoorBranch, fallbackIndoorBranch],
            snapshot: snapshot,
            serverNow: serverNow
        )

        XCTAssertEqual(presentation.mode, .activeBranch)
        XCTAssertEqual(presentation.decision, .selected(branchID: "branch-outdoor-courtyard", snapshotID: "snap-101"))
        XCTAssertEqual(presentation.activeBranchID, "branch-outdoor-courtyard")
        XCTAssertEqual(presentation.snapshotID, "snap-101")
        XCTAssertNil(presentation.fallbackReason)
        XCTAssertTrue(presentation.allowsProgression)
        XCTAssertFalse(presentation.requiresSafeExitAction)
        XCTAssertEqual(presentation.isIndoorBranch, false)
        XCTAssertTrue(presentation.windowDisplayText.contains("(Asia/Shanghai)"))
        XCTAssertTrue(presentation.windowDisplayText.contains("~"))
    }

    func testDeterministicFallbackWhenRainOrExpiredSnapshotPreventsProposal() {
        let rainySnapshot = EnvironmentSnapshot(
            snapshotID: "snap-rain",
            source: "server-weather-service",
            observedAt: serverNow.addingTimeInterval(-60),
            expiresAt: serverNow.addingTimeInterval(300),
            runTimeZoneID: "Asia/Shanghai",
            weather: .rain,
            storeOpen: true,
            reachablePlaceIDs: ["place-courtyard"]
        )

        let unmetPresentation = EnvironmentBranchHostPresentation.resolve(
            proposedBranchID: "branch-outdoor-courtyard",
            branches: [outdoorBranch, fallbackIndoorBranch],
            snapshot: rainySnapshot,
            serverNow: serverNow
        )
        XCTAssertEqual(unmetPresentation.mode, .deterministicFallback)
        XCTAssertEqual(unmetPresentation.activeBranchID, "branch-indoor-fallback")
        XCTAssertEqual(unmetPresentation.fallbackReason, .proposalConditionsUnmet)
        XCTAssertTrue(unmetPresentation.allowsProgression)
        XCTAssertFalse(unmetPresentation.requiresSafeExitAction)
        XCTAssertEqual(unmetPresentation.isIndoorBranch, true)
        XCTAssertEqual(unmetPresentation.windowDisplayText, "长期有效（无限时窗口）")

        let staleSnapshot = EnvironmentSnapshot(
            snapshotID: "snap-stale",
            source: "server-weather-service",
            observedAt: serverNow.addingTimeInterval(-900),
            expiresAt: serverNow.addingTimeInterval(-10),
            runTimeZoneID: "Asia/Shanghai",
            weather: .clear,
            storeOpen: true,
            reachablePlaceIDs: ["place-courtyard"]
        )

        let stalePresentation = EnvironmentBranchHostPresentation.resolve(
            proposedBranchID: "branch-outdoor-courtyard",
            branches: [outdoorBranch, fallbackIndoorBranch],
            snapshot: staleSnapshot,
            serverNow: serverNow
        )
        XCTAssertEqual(stalePresentation.mode, .deterministicFallback)
        XCTAssertEqual(stalePresentation.fallbackReason, .snapshotStale)
        XCTAssertEqual(stalePresentation.activeBranchID, "branch-indoor-fallback")
    }

    func testSevereWeatherProducesSafetyPauseWithSafeExitRequirement() {
        let severeSnapshot = EnvironmentSnapshot(
            snapshotID: "snap-severe",
            source: "server-weather-service",
            observedAt: serverNow.addingTimeInterval(-30),
            expiresAt: serverNow.addingTimeInterval(300),
            runTimeZoneID: "Asia/Shanghai",
            weather: .severe,
            storeOpen: true,
            reachablePlaceIDs: ["place-courtyard"]
        )

        let presentation = EnvironmentBranchHostPresentation.resolve(
            proposedBranchID: "branch-outdoor-courtyard",
            branches: [outdoorBranch, fallbackIndoorBranch],
            snapshot: severeSnapshot,
            serverNow: serverNow
        )

        XCTAssertEqual(presentation.mode, .pausedForSafety)
        XCTAssertEqual(presentation.decision, .pausedForSafety)
        XCTAssertNil(presentation.activeBranchID)
        XCTAssertFalse(presentation.allowsProgression)
        XCTAssertTrue(presentation.requiresSafeExitAction)
        XCTAssertEqual(presentation.statusHeadline, "恶劣天气或高风险路线安全暂停")
    }

    func testMissingValidDeterministicFallbackProducesFixedNoBranchOutcome() {
        let expiredFallback = ApprovedBranch(
            branchID: "branch-expired-fallback",
            window: DateInterval(
                start: serverNow.addingTimeInterval(-7_200),
                end: serverNow.addingTimeInterval(-3_600)
            ),
            indoor: true,
            requiresOpenStore: false,
            requiredPlaceIDs: [],
            isDeterministicFallback: true
        )

        let presentation = EnvironmentBranchHostPresentation.resolve(
            proposedBranchID: "branch-unapproved",
            branches: [outdoorBranch, expiredFallback],
            snapshot: nil,
            serverNow: serverNow
        )

        XCTAssertEqual(presentation.mode, .noBranchAvailable)
        XCTAssertEqual(presentation.decision, .noBranchAvailable)
        XCTAssertNil(presentation.activeBranchID)
        XCTAssertFalse(presentation.allowsProgression)
        XCTAssertFalse(presentation.requiresSafeExitAction)
        XCTAssertEqual(presentation.statusHeadline, "当前无可用已审分支")
    }

    func testServerWindowDisplayRespectsRunTimeZoneAndFallsBackCleanly() {
        let shanghaiText = EnvironmentBranchHostPresentation.formatAbsoluteWindow(
            sampleWindow,
            runTimeZoneID: "Asia/Shanghai"
        )
        let tokyoText = EnvironmentBranchHostPresentation.formatAbsoluteWindow(
            sampleWindow,
            runTimeZoneID: "Asia/Tokyo"
        )
        XCTAssertNotEqual(shanghaiText, tokyoText)
        XCTAssertTrue(tokyoText.hasSuffix("(Asia/Tokyo)"))

        let invalidZoneText = EnvironmentBranchHostPresentation.formatAbsoluteWindow(
            sampleWindow,
            runTimeZoneID: "Invalid/Zone"
        )
        XCTAssertEqual(invalidZoneText, shanghaiText)
    }
}
