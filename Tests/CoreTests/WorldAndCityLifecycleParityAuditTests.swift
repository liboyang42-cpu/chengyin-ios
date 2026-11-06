import XCTest
@testable import QuestifyCore

final class WorldAndCityLifecycleParityAuditTests: XCTestCase {

    func testEnvironmentBranchHostSnapshotIsolationClosedWindowAndSevereWeather() {
        let normalInput = WorldAndCityLifecycleParityAudit.EnvironmentBranchAuditInput(
            pinnedRunSnapshotID: "snap-100",
            incomingEnvironmentSnapshotID: "snap-101"
        )
        XCTAssertEqual(
            WorldAndCityLifecycleParityAudit.auditEnvironmentBranchHost(normalInput),
            .activeBranchProceeds(pinnedSnapshotID: "snap-100")
        )

        let closedWindowInput = WorldAndCityLifecycleParityAudit.EnvironmentBranchAuditInput(
            pinnedRunSnapshotID: "snap-100",
            incomingEnvironmentSnapshotID: "snap-101",
            isTimeWindowOpen: false,
            hasClosedWindowFallbackNode: true
        )
        XCTAssertEqual(
            WorldAndCityLifecycleParityAudit.auditEnvironmentBranchHost(closedWindowInput),
            .routedToClosedWindowFallback(pinnedSnapshotID: "snap-100")
        )

        let severeWeatherInput = WorldAndCityLifecycleParityAudit.EnvironmentBranchAuditInput(
            pinnedRunSnapshotID: "snap-100",
            incomingEnvironmentSnapshotID: "snap-101",
            isSevereWeatherAlertActive: true,
            triggersSafeExitOnSevereWeather: true
        )
        XCTAssertEqual(
            WorldAndCityLifecycleParityAudit.auditEnvironmentBranchHost(severeWeatherInput),
            .routedToSevereWeatherSafeExit(pinnedSnapshotID: "snap-100")
        )

        let mutatedSnapshotInput = WorldAndCityLifecycleParityAudit.EnvironmentBranchAuditInput(
            pinnedRunSnapshotID: "snap-100",
            incomingEnvironmentSnapshotID: "snap-101",
            mutatesActiveRunSnapshotInPlace: true
        )
        XCTAssertEqual(
            WorldAndCityLifecycleParityAudit.auditEnvironmentBranchHost(mutatedSnapshotInput),
            .snapshotIsolationViolated(pinnedSnapshotID: "snap-100", incomingSnapshotID: "snap-101")
        )
    }

    func testHomeReturnRestoreWildcardRejectionCooldownAndRedactedCoordinatePrivacy() {
        let wildcardInput = WorldAndCityLifecycleParityAudit.HomeReturnRestoreAuditInput(
            requestedRawScope: "ALL_GAMES"
        )
        XCTAssertEqual(
            WorldAndCityLifecycleParityAudit.auditHomeReturnRestore(wildcardInput),
            .wildcardScopeRejected(rawScope: "ALL_GAMES")
        )

        let unredactedCoordInput = WorldAndCityLifecycleParityAudit.HomeReturnRestoreAuditInput(
            requestedRawScope: "RUN",
            remainingCooldownSeconds: 0,
            diagnosticCoordinateSummary: "30.2741,120.1551"
        )
        XCTAssertEqual(
            WorldAndCityLifecycleParityAudit.auditHomeReturnRestore(unredactedCoordInput),
            .unredactedCoordinatePrivacyViolation(exposedValue: "30.2741,120.1551")
        )

        let cooldownInput = WorldAndCityLifecycleParityAudit.HomeReturnRestoreAuditInput(
            requestedRawScope: "THEME",
            remainingCooldownSeconds: 45
        )
        XCTAssertEqual(
            WorldAndCityLifecycleParityAudit.auditHomeReturnRestore(cooldownInput),
            .cooldownWaitRequired(remainingSeconds: 45, scope: .theme)
        )

        let permittedGlobalInput = WorldAndCityLifecycleParityAudit.HomeReturnRestoreAuditInput(
            requestedRawScope: "GLOBAL",
            remainingCooldownSeconds: 0
        )
        XCTAssertEqual(
            WorldAndCityLifecycleParityAudit.auditHomeReturnRestore(permittedGlobalInput),
            .restorePermitted(scope: .global, redactedCoordinateSummary: "[redacted]")
        )
    }

    func testCityActionSelfPayerEnforcementAndVersionConflictPreservation() {
        let thirdPartyPayerInput = WorldAndCityLifecycleParityAudit.CityActionAndDeltaAuditInput(
            actorMemberID: 701,
            payerMemberID: 999,
            localBoardVersion: 10,
            incomingDeltaFromVersion: 10,
            incomingDeltaToVersion: 11
        )
        XCTAssertEqual(
            WorldAndCityLifecycleParityAudit.auditCityActionAndDelta(thirdPartyPayerInput),
            .thirdPartyPayerRejected(actorMemberID: 701, payerMemberID: 999)
        )

        let unconfirmedQuoteInput = WorldAndCityLifecycleParityAudit.CityActionAndDeltaAuditInput(
            actorMemberID: 701,
            payerMemberID: 701,
            hasExplicitQuoteConfirmation: false,
            localBoardVersion: 10,
            incomingDeltaFromVersion: 10,
            incomingDeltaToVersion: 11
        )
        XCTAssertEqual(
            WorldAndCityLifecycleParityAudit.auditCityActionAndDelta(unconfirmedQuoteInput),
            .missingQuoteConfirmation
        )

        let conflictPreservedInput = WorldAndCityLifecycleParityAudit.CityActionAndDeltaAuditInput(
            lifecycleState: .conflictRecovery,
            actorMemberID: 701,
            payerMemberID: 701,
            errorCode: "VERSION_CONFLICT",
            preservesLocalTaskAttemptOnConflict: true,
            localBoardVersion: 10,
            incomingDeltaFromVersion: 10,
            incomingDeltaToVersion: 11
        )
        XCTAssertEqual(
            WorldAndCityLifecycleParityAudit.auditCityActionAndDelta(conflictPreservedInput),
            .versionConflictPreservedTaskAttempt(localVersion: 10)
        )
    }

    func testCityDeltaContiguousStreamAndGapSnapshotReload() {
        let contiguousInput = WorldAndCityLifecycleParityAudit.CityActionAndDeltaAuditInput(
            actorMemberID: 512,
            payerMemberID: 512,
            localBoardVersion: 42,
            incomingDeltaFromVersion: 42,
            incomingDeltaToVersion: 43
        )
        XCTAssertEqual(
            WorldAndCityLifecycleParityAudit.auditCityActionAndDelta(contiguousInput),
            .contiguousDeltaApplied(newBoardVersion: 43)
        )

        let gapInput = WorldAndCityLifecycleParityAudit.CityActionAndDeltaAuditInput(
            lifecycleState: .reloadingSnapshot,
            actorMemberID: 512,
            payerMemberID: 512,
            localBoardVersion: 42,
            incomingDeltaFromVersion: 45,
            incomingDeltaToVersion: 46
        )
        XCTAssertEqual(
            WorldAndCityLifecycleParityAudit.auditCityActionAndDelta(gapInput),
            .snapshotReloadRequired(localVersion: 42, incomingFromVersion: 45)
        )
    }

    func testUnifiedWorldAndCityLifecycleReport() {
        let report = WorldAndCityLifecycleParityAudit.WorldAndCityLifecycleReport(
            environmentBranchVerdict: WorldAndCityLifecycleParityAudit.auditEnvironmentBranchHost(
                .init(pinnedRunSnapshotID: "snap-1", incomingEnvironmentSnapshotID: "snap-2")
            ),
            homeReturnRestoreVerdict: WorldAndCityLifecycleParityAudit.auditHomeReturnRestore(
                .init(requestedRawScope: "RUN")
            ),
            cityActionAndDeltaVerdict: WorldAndCityLifecycleParityAudit.auditCityActionAndDelta(
                .init(
                    actorMemberID: 88,
                    payerMemberID: 88,
                    localBoardVersion: 5,
                    incomingDeltaFromVersion: 5,
                    incomingDeltaToVersion: 6
                )
            )
        )
        XCTAssertTrue(report.isCompliant)
    }
}
