import XCTest
@testable import QuestifyCore

final class ProductionTelemetryAndPrivacyRedactionPipelineAuditTests: XCTestCase {

    func testCanonicalTelemetryPipelinesPassRedactionSafetyAudit() {
        let rules = ProductionTelemetryAndPrivacyRedactionPipelineAudit.canonicalRules
        XCTAssertEqual(rules.count, 4)
        XCTAssertEqual(
            rules.map(\.pipelineName),
            [
                "oslog-network-and-auth-events",
                "signpost-performance-intervals",
                "crash-and-hang-diagnostic-breadcrumbs",
                "durable-journal-recovery-audit-log"
            ]
        )

        let result = ProductionTelemetryAndPrivacyRedactionPipelineAudit.evaluate()
        XCTAssertEqual(result.totalPipelines, 4)
        XCTAssertEqual(result.compliantPipelines, 4)
        XCTAssertTrue(result.isTelemetryRedactionSafe)
    }

    func testBearerAndSessionTokenLeakDetectionAndRejection() {
        let unmaskedTokenRule = TelemetryPipelineRedactionRule(
            pipelineName: "oslog-network-and-auth-events",
            masksBearerAndSessionTokens: false,
            masksPhoneAndIdentityNumbers: true,
            quantizesOrStripsPreciseGPSInLogs: true,
            stripsChatAndDraftBodyContent: true
        )
        XCTAssertFalse(unmaskedTokenRule.isCompliant)

        let eval = ProductionTelemetryAndPrivacyRedactionPipelineAudit.evaluate(rules: [unmaskedTokenRule])
        XCTAssertEqual(eval.totalPipelines, 1)
        XCTAssertEqual(eval.compliantPipelines, 0)
        XCTAssertFalse(eval.isTelemetryRedactionSafe)

        XCTAssertTrue(
            ProductionTelemetryAndPrivacyRedactionPipelineAudit.containsUnmaskedBearerToken(
                "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
            )
        )
        XCTAssertFalse(
            ProductionTelemetryAndPrivacyRedactionPipelineAudit.containsUnmaskedBearerToken(
                "Authorization: [redacted]"
            )
        )
    }

    func testPhoneAndPreciseGPSLeakDetectionAndRejection() {
        let unmaskedGPSRule = TelemetryPipelineRedactionRule(
            pipelineName: "signpost-performance-intervals",
            masksBearerAndSessionTokens: true,
            masksPhoneAndIdentityNumbers: false,
            quantizesOrStripsPreciseGPSInLogs: false,
            stripsChatAndDraftBodyContent: true
        )
        XCTAssertFalse(unmaskedGPSRule.isCompliant)
        XCTAssertFalse(
            ProductionTelemetryAndPrivacyRedactionPipelineAudit.evaluate(rules: [unmaskedGPSRule]).isTelemetryRedactionSafe
        )

        XCTAssertTrue(
            ProductionTelemetryAndPrivacyRedactionPipelineAudit.containsUnmaskedPhoneOrPreciseGPS(
                "userPhone=13800138000"
            )
        )
        XCTAssertTrue(
            ProductionTelemetryAndPrivacyRedactionPipelineAudit.containsUnmaskedPhoneOrPreciseGPS(
                "fix=31.230416, 121.473701"
            )
        )
        XCTAssertFalse(
            ProductionTelemetryAndPrivacyRedactionPipelineAudit.containsUnmaskedPhoneOrPreciseGPS(
                "fix=[redacted]"
            )
        )
    }

    func testPrivateIMAndNPCChatBodyLeakDetectionAndRejection() {
        let leakyChatRule = TelemetryPipelineRedactionRule(
            pipelineName: "crash-and-hang-diagnostic-breadcrumbs",
            masksBearerAndSessionTokens: true,
            masksPhoneAndIdentityNumbers: true,
            quantizesOrStripsPreciseGPSInLogs: true,
            stripsChatAndDraftBodyContent: false
        )
        XCTAssertFalse(leakyChatRule.isCompliant)
        XCTAssertFalse(
            ProductionTelemetryAndPrivacyRedactionPipelineAudit.evaluate(rules: [leakyChatRule]).isTelemetryRedactionSafe
        )

        XCTAssertTrue(
            ProductionTelemetryAndPrivacyRedactionPipelineAudit.containsUnredactedChatOrDraftBody(
                "chatBody: Meet me at the secret checkpoint"
            )
        )
        XCTAssertFalse(
            ProductionTelemetryAndPrivacyRedactionPipelineAudit.containsUnredactedChatOrDraftBody(
                "chatBody: [redacted]"
            )
        )
    }
}
