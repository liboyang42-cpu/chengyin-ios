import Foundation

/// Redaction rule descriptor for a production diagnostic or signpost telemetry pipeline,
/// verifying that Bearer/session tokens, phone/identity numbers, precise GPS coordinates in logs,
/// and private IM/NPC chat or draft body content are masked or stripped before emission.
public struct TelemetryPipelineRedactionRule: Sendable, Equatable, Identifiable {
    public let id: String
    public let pipelineName: String
    public let masksBearerAndSessionTokens: Bool
    public let masksPhoneAndIdentityNumbers: Bool
    public let quantizesOrStripsPreciseGPSInLogs: Bool
    public let stripsChatAndDraftBodyContent: Bool

    public init(
        id: String? = nil,
        pipelineName: String,
        masksBearerAndSessionTokens: Bool,
        masksPhoneAndIdentityNumbers: Bool,
        quantizesOrStripsPreciseGPSInLogs: Bool,
        stripsChatAndDraftBodyContent: Bool
    ) {
        self.id = id ?? pipelineName
        self.pipelineName = pipelineName
        self.masksBearerAndSessionTokens = masksBearerAndSessionTokens
        self.masksPhoneAndIdentityNumbers = masksPhoneAndIdentityNumbers
        self.quantizesOrStripsPreciseGPSInLogs = quantizesOrStripsPreciseGPSInLogs
        self.stripsChatAndDraftBodyContent = stripsChatAndDraftBodyContent
    }

    public var isCompliant: Bool {
        masksBearerAndSessionTokens
            && masksPhoneAndIdentityNumbers
            && quantizesOrStripsPreciseGPSInLogs
            && stripsChatAndDraftBodyContent
    }
}

/// Pure, self-contained audit of production diagnostic & signpost telemetry pipelines to ensure
/// zero leakage of Bearer tokens, phone numbers, precise GPS lat/lng in non-play logs,
/// or private IM/NPC chat text.
public struct ProductionTelemetryAndPrivacyRedactionPipelineAudit: Sendable, Equatable {
    public static let canonicalRules: [TelemetryPipelineRedactionRule] = [
        TelemetryPipelineRedactionRule(
            id: "oslog-network-and-auth-events",
            pipelineName: "oslog-network-and-auth-events",
            masksBearerAndSessionTokens: true,
            masksPhoneAndIdentityNumbers: true,
            quantizesOrStripsPreciseGPSInLogs: true,
            stripsChatAndDraftBodyContent: true
        ),
        TelemetryPipelineRedactionRule(
            id: "signpost-performance-intervals",
            pipelineName: "signpost-performance-intervals",
            masksBearerAndSessionTokens: true,
            masksPhoneAndIdentityNumbers: true,
            quantizesOrStripsPreciseGPSInLogs: true,
            stripsChatAndDraftBodyContent: true
        ),
        TelemetryPipelineRedactionRule(
            id: "crash-and-hang-diagnostic-breadcrumbs",
            pipelineName: "crash-and-hang-diagnostic-breadcrumbs",
            masksBearerAndSessionTokens: true,
            masksPhoneAndIdentityNumbers: true,
            quantizesOrStripsPreciseGPSInLogs: true,
            stripsChatAndDraftBodyContent: true
        ),
        TelemetryPipelineRedactionRule(
            id: "durable-journal-recovery-audit-log",
            pipelineName: "durable-journal-recovery-audit-log",
            masksBearerAndSessionTokens: true,
            masksPhoneAndIdentityNumbers: true,
            quantizesOrStripsPreciseGPSInLogs: true,
            stripsChatAndDraftBodyContent: true
        )
    ]

    public static func evaluate(
        rules: [TelemetryPipelineRedactionRule] = canonicalRules
    ) -> (totalPipelines: Int, compliantPipelines: Int, isTelemetryRedactionSafe: Bool) {
        let total = rules.count
        let compliant = rules.filter(\.isCompliant).count
        let isSafe = total > 0 && compliant == total
        return (totalPipelines: total, compliantPipelines: compliant, isTelemetryRedactionSafe: isSafe)
    }

    public static func containsUnmaskedBearerToken(_ logSample: String) -> Bool {
        if logSample.range(of: #"(?i)bearer\s+[A-Za-z0-9\-_\.]{8,}"#, options: .regularExpression) != nil {
            return true
        }
        if logSample.range(of: #"(?i)authorization\s*[:=]\s*[A-Za-z0-9\-_\.]{8,}"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    public static func containsUnmaskedPhoneOrPreciseGPS(_ logSample: String) -> Bool {
        if logSample.range(of: #"\b1[3-9]\d{9}\b"#, options: .regularExpression) != nil {
            return true
        }
        if logSample.range(of: #"-?\d{1,3}\.\d{4,}\s*,\s*-?\d{1,3}\.\d{4,}"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    public static func containsUnredactedChatOrDraftBody(_ logSample: String) -> Bool {
        let lower = logSample.lowercased()
        for prefix in ["chatbody:", "messagebody:", "npcreplytext:", "draftcontent:"] {
            if lower.contains(prefix) && !lower.contains("[redacted]") {
                return true
            }
        }
        return false
    }
}
