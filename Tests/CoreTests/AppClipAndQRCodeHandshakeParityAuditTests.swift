import XCTest
#if canImport(QuestifyCore)
@testable import QuestifyCore
#elseif canImport(Core)
@testable import Core
#endif

final class AppClipAndQRCodeHandshakeParityAuditTests: XCTestCase {

    func testCanonicalChecksPassAllFourPayloadKinds() {
        let result = AppClipAndQRCodeHandshakeParityAudit.evaluate()
        XCTAssertEqual(result.totalPayloads, 4)
        XCTAssertEqual(result.compliantPayloads, 4)
        XCTAssertTrue(result.coversAllPayloadKinds)
        XCTAssertTrue(result.isQRHandshakeSafe)
    }

    func testExcessiveTokenTTLOver300SecondsIsRejected() {
        var checks = AppClipAndQRCodeHandshakeParityAudit.canonicalChecks
        checks[0] = QRHandshakeSecurityCheck(
            id: "qr-team-meeting-handshake-expired",
            payloadKind: .teamMeetingHandshake,
            maxTokenTTLSeconds: 600,
            requiresSingleUseNonce: true,
            validatesHostAllowlistBeforeRoute: true
        )
        XCTAssertFalse(checks[0].isCompliant)

        let result = AppClipAndQRCodeHandshakeParityAudit.evaluate(checks: checks)
        XCTAssertEqual(result.totalPayloads, 4)
        XCTAssertEqual(result.compliantPayloads, 3)
        XCTAssertTrue(result.coversAllPayloadKinds)
        XCTAssertFalse(result.isQRHandshakeSafe)
    }

    func testMissingSingleUseNonceIsRejected() {
        var checks = AppClipAndQRCodeHandshakeParityAudit.canonicalChecks
        checks[1] = QRHandshakeSecurityCheck(
            id: "qr-merchant-store-stamp-scan-no-nonce",
            payloadKind: .merchantStoreStampScan,
            maxTokenTTLSeconds: 120,
            requiresSingleUseNonce: false,
            validatesHostAllowlistBeforeRoute: true
        )
        XCTAssertFalse(checks[1].isCompliant)

        let result = AppClipAndQRCodeHandshakeParityAudit.evaluate(checks: checks)
        XCTAssertEqual(result.compliantPayloads, 3)
        XCTAssertFalse(result.isQRHandshakeSafe)
    }

    func testMissingPayloadKindCoverageIsDetected() {
        let partialChecks = Array(AppClipAndQRCodeHandshakeParityAudit.canonicalChecks.prefix(3))
        let result = AppClipAndQRCodeHandshakeParityAudit.evaluate(checks: partialChecks)
        XCTAssertEqual(result.totalPayloads, 3)
        XCTAssertEqual(result.compliantPayloads, 3)
        XCTAssertFalse(result.coversAllPayloadKinds)
        XCTAssertFalse(result.isQRHandshakeSafe)
    }
}
