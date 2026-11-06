import XCTest
@testable import QuestifyCore

final class BackendSyncAndContractGateAuditTests: XCTestCase {
    func testAllFourBackendSyncAndContractGatePillarsAreRegistered() {
        let pillars = BackendSyncAndContractGateAudit.pillars
        XCTAssertEqual(pillars.map(\.pillarID), [
            .bkBackendSync,
            .w221MapCoreEntry,
            .contractChecksSuite,
            .currentCIManifestGate
        ])
        XCTAssertTrue(pillars.allSatisfy(\.isFailClosedByDefault))

        let bk = BackendSyncAndContractGateAudit.descriptor(for: .bkBackendSync)
        XCTAssertEqual(bk?.verifiedContracts, [
            "GET /api/config/public",
            "AccountProfile.career",
            "RoamSubpagePresentation:E06-17",
            "ClubSeriesScheduleReadback:BK-SCHEDULE",
            "PlayArrivalAccuracy:BK-GPS"
        ])

        let w221 = BackendSyncAndContractGateAudit.descriptor(for: .w221MapCoreEntry)
        XCTAssertEqual(w221?.verifiedContracts, ["MapCoreEntryHostRouter", "--uitesting-map-core-entry"])
    }

    func testPassingEvaluationRequiresAllBKContractsPythonSuitesAndCleanManifest() {
        let evaluation = BackendSyncAndContractGateAudit.evaluate(
            verifiedBKContracts: Set(BackendSyncAndContractGateAudit.requiredBKContracts),
            executedPythonSuites: Set(BackendSyncAndContractGateAudit.requiredPythonContractCheckSuites),
            currentCICheckPassed: true,
            checkScaffoldPassed: true,
            mapCoreEntryLaunchFlagSupported: true
        )
        XCTAssertTrue(evaluation.isPassing)
        XCTAssertTrue(evaluation.missingBKContracts.isEmpty)
        XCTAssertTrue(evaluation.missingContractCheckSuites.isEmpty)
        XCTAssertFalse(evaluation.hasManifestDrift)
        XCTAssertFalse(evaluation.hasScaffoldViolation)
        XCTAssertTrue(evaluation.mapCoreEntryLaunchFlagVerified)
    }

    func testMissingPythonContractCheckSuiteOrBKContractFailsClosed() {
        var suites = Set(BackendSyncAndContractGateAudit.requiredPythonContractCheckSuites)
        suites.remove("test_release_and_audit_contracts")

        var bkContracts = Set(BackendSyncAndContractGateAudit.requiredBKContracts)
        bkContracts.remove("PlayArrivalAccuracy:BK-GPS")

        let evaluation = BackendSyncAndContractGateAudit.evaluate(
            verifiedBKContracts: bkContracts,
            executedPythonSuites: suites,
            currentCICheckPassed: true,
            checkScaffoldPassed: true,
            mapCoreEntryLaunchFlagSupported: true
        )
        XCTAssertFalse(evaluation.isPassing)
        XCTAssertEqual(evaluation.missingBKContracts, ["PlayArrivalAccuracy:BK-GPS"])
        XCTAssertEqual(evaluation.missingContractCheckSuites, ["test_release_and_audit_contracts"])
    }

    func testManifestDriftOrScaffoldFailureRejectsGate() {
        let driftEvaluation = BackendSyncAndContractGateAudit.evaluate(
            verifiedBKContracts: Set(BackendSyncAndContractGateAudit.requiredBKContracts),
            executedPythonSuites: Set(BackendSyncAndContractGateAudit.requiredPythonContractCheckSuites),
            currentCICheckPassed: false,
            checkScaffoldPassed: true,
            mapCoreEntryLaunchFlagSupported: true
        )
        XCTAssertFalse(driftEvaluation.isPassing)
        XCTAssertTrue(driftEvaluation.hasManifestDrift)
        XCTAssertFalse(driftEvaluation.hasScaffoldViolation)

        let scaffoldEvaluation = BackendSyncAndContractGateAudit.evaluate(
            verifiedBKContracts: Set(BackendSyncAndContractGateAudit.requiredBKContracts),
            executedPythonSuites: Set(BackendSyncAndContractGateAudit.requiredPythonContractCheckSuites),
            currentCICheckPassed: true,
            checkScaffoldPassed: false,
            mapCoreEntryLaunchFlagSupported: false
        )
        XCTAssertFalse(scaffoldEvaluation.isPassing)
        XCTAssertTrue(scaffoldEvaluation.hasScaffoldViolation)
        XCTAssertFalse(scaffoldEvaluation.mapCoreEntryLaunchFlagVerified)
    }
}
