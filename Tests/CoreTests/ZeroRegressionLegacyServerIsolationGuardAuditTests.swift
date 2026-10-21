import XCTest
@testable import QuestifyCore

final class ZeroRegressionLegacyServerIsolationGuardAuditTests: XCTestCase {
    func testCanonicalFourLayersPassLegacyServerIsolationAudit() {
        let result = ZeroRegressionLegacyServerIsolationGuardAudit.evaluate()
        XCTAssertEqual(
            ZeroRegressionLegacyServerIsolationGuardAudit.blockedLegacyOctets,
            [47, 103, 124, 64]
        )
        XCTAssertEqual(ZeroRegressionLegacyServerIsolationGuardAudit.canonicalLayers.count, 4)
        XCTAssertEqual(result.totalLayers, 4)
        XCTAssertEqual(result.compliantLayers, 4)
        XCTAssertTrue(result.isLegacyServerIsolated)
    }

    func testRawIPv4HostLiteralAllowanceRejectsIsolation() {
        var layers = ZeroRegressionLegacyServerIsolationGuardAudit.canonicalLayers
        layers[0] = LegacyServerIsolationCheck(
            id: "config-base-xcconfig-defaults",
            layerName: "Config/Base.xcconfig Approved Domain Defaults",
            blocksRawIPv4HostLiterals: false,
            enforcesApprovedHTTPSDomainOnly: true,
            zeroImpactOnLiveMiniProgramServer: true
        )

        let result = ZeroRegressionLegacyServerIsolationGuardAudit.evaluate(layers: layers)
        XCTAssertFalse(layers[0].isCompliant)
        XCTAssertEqual(result.totalLayers, 4)
        XCTAssertEqual(result.compliantLayers, 3)
        XCTAssertFalse(result.isLegacyServerIsolated)
    }

    func testUnapprovedOrNonHTTPSEndpointRejectsIsolation() {
        var layers = ZeroRegressionLegacyServerIsolationGuardAudit.canonicalLayers
        layers[1] = LegacyServerIsolationCheck(
            id: "regional-endpoint-allowlist-gate",
            layerName: "RegionalEndpointAllowlist Runtime Host Gate",
            blocksRawIPv4HostLiterals: true,
            enforcesApprovedHTTPSDomainOnly: false,
            zeroImpactOnLiveMiniProgramServer: true
        )

        let result = ZeroRegressionLegacyServerIsolationGuardAudit.evaluate(layers: layers)
        XCTAssertFalse(layers[1].isCompliant)
        XCTAssertEqual(result.totalLayers, 4)
        XCTAssertEqual(result.compliantLayers, 3)
        XCTAssertFalse(result.isLegacyServerIsolated)
    }

    func testLiveMiniProgramServerImpactRiskRejectsIsolation() {
        var layers = ZeroRegressionLegacyServerIsolationGuardAudit.canonicalLayers
        layers[3] = LegacyServerIsolationCheck(
            id: "ci-fixture-loopback-and-mock-transport",
            layerName: "CI Fixture Short-Circuit & Mock URLProtocol Transport",
            blocksRawIPv4HostLiterals: true,
            enforcesApprovedHTTPSDomainOnly: true,
            zeroImpactOnLiveMiniProgramServer: false
        )

        let result = ZeroRegressionLegacyServerIsolationGuardAudit.evaluate(layers: layers)
        XCTAssertFalse(layers[3].isCompliant)
        XCTAssertEqual(result.totalLayers, 4)
        XCTAssertEqual(result.compliantLayers, 3)
        XCTAssertFalse(result.isLegacyServerIsolated)
    }
}
