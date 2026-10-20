import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained row describing a telemetry pipeline's privacy redaction and PII stripping policy.
public struct TelemetryRedactionPipelineRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let pipelineTitle: String
    public let masksBearerAndAuthTokens: Bool
    public let redactsPhoneAndIdentityNumbers: Bool
    public let quantizesOrStripsGPSCoordinates: Bool
    public let stripsChatAndDraftPayloads: Bool
    public let summary: String

    public init(
        id: String,
        pipelineTitle: String,
        masksBearerAndAuthTokens: Bool,
        redactsPhoneAndIdentityNumbers: Bool,
        quantizesOrStripsGPSCoordinates: Bool,
        stripsChatAndDraftPayloads: Bool,
        summary: String
    ) {
        self.id = id
        self.pipelineTitle = pipelineTitle
        self.masksBearerAndAuthTokens = masksBearerAndAuthTokens
        self.redactsPhoneAndIdentityNumbers = redactsPhoneAndIdentityNumbers
        self.quantizesOrStripsGPSCoordinates = quantizesOrStripsGPSCoordinates
        self.stripsChatAndDraftPayloads = stripsChatAndDraftPayloads
        self.summary = summary
    }

    public var isRedacted: Bool {
        masksBearerAndAuthTokens &&
            redactsPhoneAndIdentityNumbers &&
            quantizesOrStripsGPSCoordinates &&
            stripsChatAndDraftPayloads
    }
}

/// Self-contained snapshot for Bearer token masking, phone/ID redaction, GPS quantization in logs,
/// and chat/draft body stripping across all 4 production telemetry pipelines.
public struct TelemetryPrivacyRedactionSnapshot: Sendable, Equatable {
    public let bearerTokenMaskingEnabled: Bool
    public let phoneAndIdRedactionEnabled: Bool
    public let gpsCoordinateQuantizationEnabled: Bool
    public let chatAndDraftBodyStrippingEnabled: Bool
    public let rows: [TelemetryRedactionPipelineRow]

    public init(
        bearerTokenMaskingEnabled: Bool,
        phoneAndIdRedactionEnabled: Bool,
        gpsCoordinateQuantizationEnabled: Bool,
        chatAndDraftBodyStrippingEnabled: Bool,
        rows: [TelemetryRedactionPipelineRow]
    ) {
        self.bearerTokenMaskingEnabled = bearerTokenMaskingEnabled
        self.phoneAndIdRedactionEnabled = phoneAndIdRedactionEnabled
        self.gpsCoordinateQuantizationEnabled = gpsCoordinateQuantizationEnabled
        self.chatAndDraftBodyStrippingEnabled = chatAndDraftBodyStrippingEnabled
        self.rows = rows
    }

    public var redactedRowCount: Int {
        rows.filter(\.isRedacted).count
    }

    public var isAllRedacted: Bool {
        bearerTokenMaskingEnabled &&
            phoneAndIdRedactionEnabled &&
            gpsCoordinateQuantizationEnabled &&
            chatAndDraftBodyStrippingEnabled &&
            rows.count == 4 &&
            rows.allSatisfy(\.isRedacted)
    }

    public static let defaultReady = TelemetryPrivacyRedactionSnapshot(
        bearerTokenMaskingEnabled: true,
        phoneAndIdRedactionEnabled: true,
        gpsCoordinateQuantizationEnabled: true,
        chatAndDraftBodyStrippingEnabled: true,
        rows: [
            TelemetryRedactionPipelineRow(
                id: "network-diagnostics-pipeline",
                pipelineTitle: "网络诊断与请求追踪管线",
                masksBearerAndAuthTokens: true,
                redactsPhoneAndIdentityNumbers: true,
                quantizesOrStripsGPSCoordinates: true,
                stripsChatAndDraftPayloads: true,
                summary: "Authorization Bearer 与 Cookie 全量替换为 [REDACTED]，请求体不落盘"
            ),
            TelemetryRedactionPipelineRow(
                id: "crash-and-metric-kit-pipeline",
                pipelineTitle: "崩溃报告与 MetricKit 诊断管线",
                masksBearerAndAuthTokens: true,
                redactsPhoneAndIdentityNumbers: true,
                quantizesOrStripsGPSCoordinates: true,
                stripsChatAndDraftPayloads: true,
                summary: "脱敏手机号与证件号，私人据点与精确 GPS 坐标一律输出为 [redacted]"
            ),
            TelemetryRedactionPipelineRow(
                id: "npc-and-im-audit-pipeline",
                pipelineTitle: "NPC 对话与站内信安全遥测管线",
                masksBearerAndAuthTokens: true,
                redactsPhoneAndIdentityNumbers: true,
                quantizesOrStripsGPSCoordinates: true,
                stripsChatAndDraftPayloads: true,
                summary: "仅记录事件状态码与耗时，彻底剥离聊天正文、拒绝原因与帖子草稿内容"
            ),
            TelemetryRedactionPipelineRow(
                id: "roam-and-map-signpost-pipeline",
                pipelineTitle: "漫游与地图 OSSignposter 性能管线",
                masksBearerAndAuthTokens: true,
                redactsPhoneAndIdentityNumbers: true,
                quantizesOrStripsGPSCoordinates: true,
                stripsChatAndDraftPayloads: true,
                summary: "地图与漫游性能区间仅记录帧率与聚合计数，精确经纬度量化或脱敏"
            )
        ]
    )
}

@MainActor
public struct ProductionTelemetryAndPrivacyRedactionSectionView: View {
    public let snapshot: TelemetryPrivacyRedactionSnapshot

    public init(snapshot: TelemetryPrivacyRedactionSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "生产遥测与日志隐私脱敏审计")
                    .font(.headline)
                    .accessibilityIdentifier("telemetryPrivacyRedaction.title")

                Text(verbatim: Self.overallStatusText(for: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(snapshot.isAllRedacted ? .green : .red)
                    .accessibilityIdentifier("telemetryPrivacyRedaction.overallStatus")

                Text(verbatim: Self.tokenMaskingStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("telemetryPrivacyRedaction.tokenMaskingStatus")

                Text(verbatim: Self.piiRedactionStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("telemetryPrivacyRedaction.piiRedactionStatus")

                Text(verbatim: Self.gpsQuantizationStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("telemetryPrivacyRedaction.gpsQuantizationStatus")

                Text(verbatim: Self.payloadStrippingStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("telemetryPrivacyRedaction.payloadStrippingStatus")
            }
            .padding(.vertical, 4)

            if snapshot.rows.isEmpty {
                Text(verbatim: "暂无生产遥测与日志脱敏管线检查项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("telemetryPrivacyRedaction.empty")
            } else {
                ForEach(snapshot.rows) { row in
                    TelemetryRedactionPipelineRowView(row: row)
                }
            }
        }
        .accessibilityIdentifier("telemetryPrivacyRedaction.section")
    }

    public static func overallStatusText(for snapshot: TelemetryPrivacyRedactionSnapshot) -> String {
        snapshot.isAllRedacted
            ? "整体状态：四大生产遥测管线隐私脱敏全部就绪（\(snapshot.redactedRowCount)/\(snapshot.rows.count)）"
            : "整体状态：检测到未脱敏的生产遥测管线或字段（\(snapshot.redactedRowCount)/\(snapshot.rows.count)）"
    }

    public static func tokenMaskingStatusText(for snapshot: TelemetryPrivacyRedactionSnapshot) -> String {
        snapshot.bearerTokenMaskingEnabled
            ? "Bearer 凭证掩码：Authorization / 会话令牌脱敏已启用"
            : "Bearer 凭证掩码：存在会话令牌明文输出风险"
    }

    public static func piiRedactionStatusText(for snapshot: TelemetryPrivacyRedactionSnapshot) -> String {
        snapshot.phoneAndIdRedactionEnabled
            ? "PII 身份脱敏：手机号与身份标识掩码已启用"
            : "PII 身份脱敏：手机号或身份标识掩码未启用"
    }

    public static func gpsQuantizationStatusText(for snapshot: TelemetryPrivacyRedactionSnapshot) -> String {
        snapshot.gpsCoordinateQuantizationEnabled
            ? "GPS 坐标保护：精确经纬度量化与私人据点抹除已启用"
            : "GPS 坐标保护：存在精确经纬度写入日志风险"
    }

    public static func payloadStrippingStatusText(for snapshot: TelemetryPrivacyRedactionSnapshot) -> String {
        snapshot.chatAndDraftBodyStrippingEnabled
            ? "正文内容剥离：聊天记录与草稿正文零落盘已核验"
            : "正文内容剥离：存在聊天或草稿正文写入遥测风险"
    }
}

@MainActor
private struct TelemetryRedactionPipelineRowView: View {
    let row: TelemetryRedactionPipelineRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: row.pipelineTitle)
                    .font(.subheadline.bold())
                Spacer()
                Text(verbatim: row.isRedacted ? "已脱敏" : "告警")
                    .font(.caption)
                    .foregroundStyle(row.isRedacted ? .green : .red)
            }

            Text(verbatim: row.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: "Token：\(row.masksBearerAndAuthTokens ? "掩码" : "未掩码") · 手机/ID：\(row.redactsPhoneAndIdentityNumbers ? "脱敏" : "未脱敏") · GPS：\(row.quantizesOrStripsGPSCoordinates ? "量化" : "明文") · 正文：\(row.stripsChatAndDraftPayloads ? "剥离" : "保留")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("telemetryPrivacyRedaction.row")
    }
}
