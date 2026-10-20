import XCTest
@testable import QuestifyCore

final class WaveUnifiedParityInventoryTests: XCTestCase {

    func testWave2ScopesAccountForAll21MiniProgramSlices() {
        let scopes = WaveUnifiedParityInventory.wave2Scopes
        XCTAssertEqual(scopes.count, 21)
        XCTAssertEqual(scopes.map(\.id), (1...21).map { String(format: "w2-%02d", $0) })
        XCTAssertEqual(scopes.map(\.ordinal), Array(1...21))
        XCTAssertTrue(scopes.allSatisfy { $0.isIntegrated && !$0.domain.isEmpty })
    }

    func testWave3HandoffScopesAccountForAll13CardsIncludingBK() {
        let scopes = WaveUnifiedParityInventory.wave3HandoffScopes
        XCTAssertEqual(scopes.count, 13)
        let expected = ["I00", "I01", "I02", "I03", "I04", "I05", "I06", "I07", "I08", "I09", "I10", "I11", "BK"]
        XCTAssertEqual(scopes.map(\.id), expected)
        XCTAssertTrue(scopes.allSatisfy { $0.isClosed && $0.handoffDocument.hasPrefix("docs/handoff/ios-") && $0.handoffDocument.hasSuffix("-20261019.md") })
    }

    func testReformPlanWorkPackagesCoverAllW02ThroughW20AndU01ThroughU08() {
        let workPackages = WaveUnifiedParityInventory.reformWorkPackages
        XCTAssertEqual(workPackages.count, 19)
        XCTAssertEqual(workPackages.map(\.id), (2...20).map { String(format: "W%02d", $0) })
        XCTAssertTrue(workPackages.allSatisfy { $0.defaultFailClosed && !$0.title.isEmpty })

        let tracks = Set(workPackages.map(\.track))
        XCTAssertEqual(tracks, [.agentF, .agentG, .agentH])

        let decisions = WaveUnifiedParityInventory.unifiedDecisionPackages
        XCTAssertEqual(decisions.count, 8)
        XCTAssertEqual(decisions.map(\.id), (1...8).map { String(format: "U%02d", $0) })
        XCTAssertTrue(decisions.allSatisfy { $0.track == .unifiedDecision && $0.defaultFailClosed })
    }

    func testAllHighRiskWritePaymentCashSwitchesStayFailClosedByDefault() {
        let switches = WaveUnifiedParityInventory.evaluateHighRiskSwitches()
        XCTAssertFalse(switches.isEmpty)
        for item in switches {
            XCTAssertTrue(item.isFailClosed, "Expected \(item.name) to remain fail-closed (false) by default")
            XCTAssertFalse(item.isEnabled, "Expected \(item.name) to be disabled by default")
        }
        let names = Set(switches.map(\.name))
        XCTAssertTrue(names.contains("SideQuestFeature.acceptEnabled"))
        XCTAssertTrue(names.contains("MerchantAICommerceGates.paymentAndCashEnabled"))
        XCTAssertTrue(names.contains("CommerceClientPaymentRules.paymentEnabled"))
        XCTAssertTrue(names.contains("SponsoredRewardCapabilities.cash"))
        XCTAssertTrue(names.contains("ReformWorldCapabilities.meetingNFC"))
    }

    func testVerifyReleaseReadinessInvariantsReportsCompleteAndReady() {
        let report = WaveUnifiedParityInventory.verifyReleaseReadinessInvariants()
        XCTAssertEqual(report.wave2Count, 21)
        XCTAssertEqual(report.wave3Count, 13)
        XCTAssertEqual(report.reformWorkPackageCount, 19)
        XCTAssertEqual(report.unifiedDecisionCount, 8)
        XCTAssertTrue(report.missingWave2IDs.isEmpty)
        XCTAssertTrue(report.missingWave3IDs.isEmpty)
        XCTAssertTrue(report.missingReformPackageIDs.isEmpty)
        XCTAssertTrue(report.missingUnifiedDecisionIDs.isEmpty)
        XCTAssertTrue(report.openHighRiskSwitches.isEmpty)
        XCTAssertTrue(report.allScopesAccountedFor)
        XCTAssertTrue(report.allHighRiskSwitchesFailClosed)
        XCTAssertTrue(report.isReleaseReady)
    }
}
