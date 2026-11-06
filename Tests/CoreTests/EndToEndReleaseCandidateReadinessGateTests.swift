import XCTest
@testable import QuestifyCore

final class EndToEndReleaseCandidateReadinessGateTests: XCTestCase {
    func testDefaultEvaluationPassesAllSixReleaseCandidateGates() {
        let report = EndToEndReleaseCandidateReadinessGate.evaluate()

        XCTAssertTrue(report.isReleaseCandidateApproved)
        XCTAssertEqual(report.passingGateCount, 6)
        XCTAssertTrue(report.failedGates.isEmpty)
        XCTAssertEqual(
            report.verdicts.map(\.gateID.rawValue),
            ["RC-GATE-01", "RC-GATE-02", "RC-GATE-03", "RC-GATE-04", "RC-GATE-05", "RC-GATE-06"]
        )
    }

    func testGate01AndGate02FailClosedOnMissingDocumentOrForbiddenLegacyHost() {
        let incompleteDocs = EndToEndReleaseCandidateReadinessGate.Gate01ThreeDocumentParityInput(
            verifiedDocuments: ["交接文档_20261020.md", "落地清单.md"],
            wave2ScopesCompleted: 21,
            wave3LanesCompleted: 13,
            reformPackagesCompleted: 19
        )
        let legacyHostInput = EndToEndReleaseCandidateReadinessGate.Gate02RegionalAndHostIsolationInput(
            market: "CN",
            apiBaseURLHost: "47.103.124.64",
            cnAndUSAllowlistsIsolated: true,
            rejectsLegacyHost4710312464: true
        )

        let report = EndToEndReleaseCandidateReadinessGate.evaluate(
            gate01: incompleteDocs,
            gate02: legacyHostInput
        )

        XCTAssertFalse(report.isReleaseCandidateApproved)
        XCTAssertEqual(report.passingGateCount, 4)
        XCTAssertEqual(
            report.failedGates,
            [.rcGate01ThreeDocumentParity, .rcGate02RegionalAndHostIsolation]
        )
    }

    func testGate03AndGate04FailClosedWhenSwitchesOrControlChecksAreViolated() {
        let unsafeSwitches = EndToEndReleaseCandidateReadinessGate.Gate03FailClosedHighRiskSwitchesInput(
            paymentAndCashDisabled: false,
            unreviewedWriteAllowlistEmpty: true,
            sceneAIDefaultNonGenerative: true,
            reformWorldCapabilitiesDisabledByDefault: true,
            meetingNFCPermanentlyDisabled: true
        )
        let missingControlCheck = EndToEndReleaseCandidateReadinessGate.Gate04LocalAndCIControlGatesInput(
            passedChecks: ["current_ci.py check", "check_scaffold.py"]
        )

        let report = EndToEndReleaseCandidateReadinessGate.evaluate(
            gate03: unsafeSwitches,
            gate04: missingControlCheck
        )

        XCTAssertFalse(report.isReleaseCandidateApproved)
        XCTAssertEqual(report.passingGateCount, 4)
        XCTAssertEqual(
            report.failedGates,
            [.rcGate03FailClosedHighRiskSwitches, .rcGate04LocalAndCIControlGates]
        )
    }

    func testGate05AndGate06FailClosedOnTypecheckErrorsMissingShardsOrUnconfiguredSigning() {
        let nonZeroTypecheck = EndToEndReleaseCandidateReadinessGate.Gate05SwiftTypecheckAndCloudShardsInput(
            swiftTypecheckErrorCount: 1,
            runnerImage: "macos-26",
            registeredShards: ["core", "app-unit", "ui-0", "ui-1"]
        )
        let unsignedPlist = EndToEndReleaseCandidateReadinessGate.Gate06AppStoreSigningAndPrivacyPlistInput(
            releaseSigningConfigured: false,
            privacyUsageDescriptionsComplete: true,
            accountAndNPCAIDeletionReady: true,
            signInWithAppleParityReady: true
        )

        let report = EndToEndReleaseCandidateReadinessGate.evaluate(
            gate05: nonZeroTypecheck,
            gate06: unsignedPlist
        )

        XCTAssertFalse(report.isReleaseCandidateApproved)
        XCTAssertEqual(report.passingGateCount, 4)
        XCTAssertEqual(
            report.failedGates,
            [.rcGate05SwiftTypecheckAndCloudShards, .rcGate06AppStoreSigningAndPrivacyPlist]
        )
    }
}
