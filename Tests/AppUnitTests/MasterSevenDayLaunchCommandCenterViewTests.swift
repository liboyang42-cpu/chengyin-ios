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

@MainActor final class MasterSevenDayLaunchCommandCenterViewTests: XCTestCase {
    func testDefaultReadySnapshotUnitesAllSixCommandCenterPillars() {
        // Fail-closed default: structure is present but nothing is verified.
        let snapshot = MasterSevenDayLaunchCommandSnapshot.defaultReady
        XCTAssertFalse(snapshot.isCommandCenterLaunchReady)
        XCTAssertEqual(snapshot.pillars.count, 6)
        XCTAssertEqual(snapshot.readyPillarCount, 0)
        XCTAssertEqual(snapshot.blockedPillarCount, 6)
        XCTAssertFalse(snapshot.zeroGapCertificateIssued)
        XCTAssertFalse(snapshot.nativeSupersetPolicyEnforced)
        XCTAssertEqual(
            snapshot.pillars.map(\.pillarType),
            [
                .dayOneToSevenCriticalPath,
                .nativeSupersetOverMiniProgramPolicy,
                .finalZeroGapCertificate,
                .appStoreReviewDemoReadiness,
                .accountDeletionAndPIPLCompliance,
                .runtimeCrashCacheKeychainResilience,
            ]
        )
        XCTAssertEqual(
            snapshot.pillars.map(\.title),
            [
                "Day 1–7 Launch Critical Path",
                "Native Superset Over Mini-Program Policy",
                "Final Zero-Gap Certificate",
                "App Store Review Demo Readiness",
                "Account Deletion & PIPL Compliance",
                "Runtime Crash/Cache/Keychain Resilience",
            ]
        )
    }

    func testBlockedPillarOrWithheldCertificateMarksCommandCenterNotReady() {
        var customPillars = SevenDayCommandPillarItem.defaultPillars
        customPillars[2] = SevenDayCommandPillarItem(
            id: "final-zero-gap-certificate",
            pillarType: .finalZeroGapCertificate,
            title: "Final Zero-Gap Certificate",
            summary: "Awaiting final sign-off",
            isReady: false,
            statusBadge: "BLOCKED"
        )
        let blockedPillarSnapshot = MasterSevenDayLaunchCommandSnapshot(pillars: customPillars)
        XCTAssertEqual(blockedPillarSnapshot.readyPillarCount, 0)
        XCTAssertEqual(blockedPillarSnapshot.blockedPillarCount, 6)
        XCTAssertFalse(blockedPillarSnapshot.isCommandCenterLaunchReady)

        let withheldCertificateSnapshot = MasterSevenDayLaunchCommandSnapshot(
            zeroGapCertificateIssued: false
        )
        XCTAssertFalse(withheldCertificateSnapshot.isCommandCenterLaunchReady)

        let supersetDriftSnapshot = MasterSevenDayLaunchCommandSnapshot(
            nativeSupersetPolicyEnforced: false
        )
        XCTAssertFalse(supersetDriftSnapshot.isCommandCenterLaunchReady)
    }

    func testMainActorViewBodyInstantiatesAcrossDefaultAndBlockedSnapshots() {
        let readyView = MasterSevenDayLaunchCommandCenterView()
        _ = readyView.body
        XCTAssertFalse(readyView.snapshot.isCommandCenterLaunchReady)

        let blockedView = MasterSevenDayLaunchCommandCenterView(
            snapshot: MasterSevenDayLaunchCommandSnapshot(
                zeroGapCertificateIssued: false,
                nativeSupersetPolicyEnforced: false,
                blockedPillarCount: 2
            )
        )
        _ = blockedView.body
        XCTAssertFalse(blockedView.snapshot.isCommandCenterLaunchReady)
    }

    func testSevenDayPillarReadsFailClosedCoreResult() {
        let unverified = MasterSevenDayLaunchCommandSnapshot.from(
            sevenDayEvaluation: SevenDayLaunchCriticalPathMilestoneContract.evaluate()
        )
        XCTAssertFalse(unverified.pillars[0].isReady)
        XCTAssertEqual(unverified.pillars[0].statusBadge, "NOT_VERIFIED")
        XCTAssertFalse(unverified.isCommandCenterLaunchReady)
    }
}
