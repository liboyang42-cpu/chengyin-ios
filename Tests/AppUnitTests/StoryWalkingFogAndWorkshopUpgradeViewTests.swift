import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#else
@testable import Questify
#endif

@MainActor
final class StoryWalkingFogAndWorkshopUpgradeViewTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 4_000_000)

    private func makePurchasedItem(
        licenseId: String = "w18-paid-53",
        moduleId: String = "synthetic-module",
        versionId: String = "v1-0-0",
        status: String = "ACTIVE"
    ) throws -> WorkshopPurchasedItem {
        let payload: [String: Any] = [
            "licenseId": licenseId,
            "moduleId": moduleId,
            "purchasedVersionId": versionId,
            "contentHash": String(repeating: "a", count: 64),
            "status": status,
            "acquiredAt": "2026-10-19T00:00:00Z",
            "termsVersion": "terms-1",
            "termsHash": String(repeating: "b", count: 64),
            "commercialUse": "PROHIBITED",
            "adaptation": "LOCAL_ADAPTATION",
            "translation": "PROHIBITED",
            "updates": "EXACT_PURCHASED_VERSION",
            "redistribution": "PROHIBITED",
            "allowedRegions": ["synthetic-region"],
            "themeLimit": ["unlimited": false, "maximum": 1],
            "merchantLimit": ["unlimited": false, "maximum": 0],
            "runLimit": ["unlimited": false, "maximum": 10],
            "acquisition": "PAID",
            "buyerKind": "INDIVIDUAL",
            "useDuration": "PERPETUAL_PURCHASED_VERSION",
            "contentUseStatus": "PAID_INSTALL_AUTHORITY_UNAVAILABLE",
            "purchaseActionStatus": "CHANNEL_APPROVAL_REQUIRED"
        ]
        return try JSONDecoder().decode(
            WorkshopPurchasedItem.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
    }

    private func makeVersion(
        moduleId: String = "synthetic-module",
        versionId: String,
        semver: String,
        hashChar: Character,
        capabilities: Set<String>
    ) throws -> WorkshopModVersionRef {
        try WorkshopModVersionRef(
            moduleId: moduleId,
            versionId: versionId,
            packageVersion: semver,
            contentHash: String(repeating: hashChar, count: 64),
            capabilities: capabilities
        )
    }

    func testStoryWalkingAndFogSectionViewRendersStopNavigationArrivalVerificationAndFogProjection() throws {
        var bridge = try StoryWalkingNavigationHostBridge(missionID: 12)
        let stop1 = try WalkingTargetReference(kind: .storyNode, id: 3, missionID: 12)
        let readback = try StoryRouteStateReadback(missionID: 12, revision: 1, currentStop: stop1, finished: false)
        let entranceCoordinate = try MapCoordinateObservation(
            latitude: 31.23,
            longitude: 121.47,
            datum: .gcj02,
            source: .backend
        )
        let entrance = PlaceNavigationEntrance(
            label: "South Arcade Gate",
            floor: "1F",
            approachNote: "Follow courtyard lantern",
            coordinate: entranceCoordinate,
            source: "merchant-verified",
            reviewedBy: "ops-reviewer",
            updatedAt: fixedNow,
            temporarilyClosed: false,
            accessibleAlternative: nil
        )

        let transition = try bridge.ingestAuthorityReadback(readback, entrances: [entrance])
        XCTAssertEqual(transition, .startedStop(stop1))
        XCTAssertEqual(bridge.activeWalkingStop, stop1)
        XCTAssertEqual(bridge.activeEntrance, entrance)

        let policy = try PersonalFogSamplePolicy(maxAccuracyMeters: 50, maxAge: 30, maxBatch: 4)
        var fogCoordinator = try PersonalFogRoamHostCoordinator(ownerScope: "acct-53", samplePolicy: policy)
        try fogCoordinator.ingestServerTilePage(owner: "acct-53", cells: ["wtw3sj", "wtw3sk"], nextCursor: 2)
        let fix = try RoamDeviceFix(
            coordinate: RoamCoordinate(latitude: 31.23, longitude: 121.47)!,
            accuracyMeters: 12,
            measuredAt: fixedNow,
            datum: .wgs84
        )
        try fogCoordinator.recordForegroundFix(tileCode: "wtw3sm", fix: fix, now: fixedNow)

        let navigatingView = StoryWalkingAndFogSectionView(bridge: bridge, fogCoordinator: fogCoordinator)
        _ = navigatingView.body
        XCTAssertEqual(navigatingView.fogProjection.confirmedTileCodes, ["wtw3sj", "wtw3sk"])
        XCTAssertEqual(navigatingView.fogProjection.pendingPredictedTileCodes, ["wtw3sm"])
        XCTAssertFalse(navigatingView.fogProjection.revealSyncEnabled)

        XCTAssertTrue(bridge.recordWalkingArrival(for: stop1))
        XCTAssertNil(bridge.activeWalkingStop)
        XCTAssertTrue(bridge.canOpenVerification(for: stop1))

        let arrivedView = StoryWalkingAndFogSectionView(
            bridge: bridge,
            fogProjection: fogCoordinator.overlayProjection
        )
        _ = arrivedView.body
        XCTAssertEqual(arrivedView.bridge.phase, .verificationAvailable(stop1))
    }

    func testWorkshopModUpgradeSheetViewInstantiatesBreakingAndCompatibleDiffWithConfirmationGate() throws {
        let term = try WorkshopPurchasedUseTerm(makePurchasedItem())
        let installed = try makeVersion(
            versionId: "v1-0-0",
            semver: "1.0.0",
            hashChar: "a",
            capabilities: ["choice", "qr.scan"]
        )
        let breakingCandidate = try makeVersion(
            versionId: "v2-0-0",
            semver: "2.0.0",
            hashChar: "c",
            capabilities: ["choice", "geo.arrival"]
        )
        let breakingPreview = try WorkshopUpgradePreview(
            installed: installed,
            candidate: breakingCandidate,
            coverage: .covered
        )
        let breakingPresentation = WorkshopModUpgradePresentation(term: term, preview: breakingPreview)

        var capturedDraft: WorkshopUpgradeDraftRequest?
        let breakingSheet = WorkshopModUpgradeSheetView(presentation: breakingPresentation) { draft in
            capturedDraft = draft
        }
        _ = breakingSheet.body

        XCTAssertNil(capturedDraft)
        XCTAssertTrue(breakingPresentation.hasCapabilityChanges)
        XCTAssertEqual(breakingPresentation.addedCapabilities, ["geo.arrival"])
        XCTAssertEqual(breakingPresentation.removedCapabilities, ["qr.scan"])
        XCTAssertEqual(breakingPresentation.unchangedCapabilities, ["choice"])
        XCTAssertTrue(breakingPresentation.pinnedExistingRunsNotice.contains("固定保持原版本"))
        XCTAssertFalse(breakingPresentation.canConfirmUpgrade(confirmedByBuyer: false))
        XCTAssertTrue(breakingPresentation.canConfirmUpgrade(confirmedByBuyer: true))

        let compatibleCandidate = try makeVersion(
            versionId: "v1-0-1",
            semver: "1.0.1",
            hashChar: "b",
            capabilities: ["choice", "qr.scan"]
        )
        let compatiblePreview = try WorkshopUpgradePreview(
            installed: installed,
            candidate: compatibleCandidate,
            coverage: .requiresNewPurchase
        )
        let compatiblePresentation = WorkshopModUpgradePresentation(
            term: term,
            preview: compatiblePreview,
            manifestIssue: .h5DesignOnly
        )
        let compatibleSheet = WorkshopModUpgradeSheetView(presentation: compatiblePresentation)
        _ = compatibleSheet.body

        XCTAssertFalse(compatiblePresentation.hasCapabilityChanges)
        XCTAssertEqual(compatiblePresentation.manifestIssueNotice?.isH5DesignOnlyRejection, true)
        XCTAssertFalse(compatiblePresentation.canConfirmUpgrade(confirmedByBuyer: true))
    }
}
