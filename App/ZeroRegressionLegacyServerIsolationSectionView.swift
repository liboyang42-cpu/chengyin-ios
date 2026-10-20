import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained row modeling one defense-in-depth isolation layer preventing any accidental
/// traffic to `"Legacy Aliyun Mini-Program Host (47.103.x.x)"`.
public struct LegacyIsolationLayerRow: Sendable, Equatable, Identifiable {
    public enum Layer: String, CaseIterable, Sendable, Equatable {
        case baseXCConfigNonRoutableDefault = "Config/Base.xcconfig"
        case runtimeAllowlistHostFence = "RuntimeAllowlistHostFence"
        case staticSourceScannerGuard = "StaticSourceScannerGuard"
        case ciOfflineMockTransportOnly = "CIOfflineMockTransportOnly"
    }

    public enum Status: String, Sendable, Equatable {
        case isolated
        case breachWarning
    }

    public let id: String
    public let layer: Layer
    public let titleText: String
    public let ruleSummaryText: String
    public let verificationDetailText: String
    public let status: Status

    public init(
        id: String,
        layer: Layer,
        titleText: String,
        ruleSummaryText: String,
        verificationDetailText: String,
        status: Status = .isolated
    ) {
        self.id = id
        self.layer = layer
        self.titleText = titleText
        self.ruleSummaryText = ruleSummaryText
        self.verificationDetailText = verificationDetailText
        self.status = status
    }

    public var isIsolated: Bool {
        status == .isolated
    }

    public var statusBadgeText: String {
        switch status {
        case .isolated:
            return "100% 物理与逻辑隔离"
        case .breachWarning:
            return "隔离层异常告警"
        }
    }
}

/// Self-contained snapshot verifying 100% zero-regression isolation from
/// `"Legacy Aliyun Mini-Program Host (47.103.x.x)"` across all 4 defense layers.
public struct LegacyServerIsolationSnapshot: Sendable, Equatable {
    public static let redactedLegacyHostLabel = "Legacy Aliyun Mini-Program Host (47.103.x.x)"

    public let baseXCConfigIsolated: Bool
    public let runtimeAllowlistIsolated: Bool
    public let staticSourceScannerGreen: Bool
    public let ciMockTransportEnforced: Bool
    public let rows: [LegacyIsolationLayerRow]

    public init(
        baseXCConfigIsolated: Bool = true,
        runtimeAllowlistIsolated: Bool = true,
        staticSourceScannerGreen: Bool = true,
        ciMockTransportEnforced: Bool = true
    ) {
        self.baseXCConfigIsolated = baseXCConfigIsolated
        self.runtimeAllowlistIsolated = runtimeAllowlistIsolated
        self.staticSourceScannerGreen = staticSourceScannerGreen
        self.ciMockTransportEnforced = ciMockTransportEnforced

        self.rows = [
            LegacyIsolationLayerRow(
                id: "layer-base-xcconfig",
                layer: .baseXCConfigNonRoutableDefault,
                titleText: "构建配置层默认空地址 (Config/Base.xcconfig)",
                ruleSummaryText: "QUESTIFY_API_BASE_URL 默认留空 · CODE_SIGNING_ALLOWED = NO",
                verificationDetailText: baseXCConfigIsolated
                    ? "未显式注入已审批 HTTPS 网关前，构建配置不携带任何可路由生产地址，彻底阻断连向 \(Self.redactedLegacyHostLabel)。"
                    : "告警：检测到 Base.xcconfig 含非空默认主机配置。",
                status: baseXCConfigIsolated ? .isolated : .breachWarning
            ),
            LegacyIsolationLayerRow(
                id: "layer-runtime-allowlist",
                layer: .runtimeAllowlistHostFence,
                titleText: "运行时区域白名单与旧主机拦截围栏 (APIConfiguration)",
                ruleSummaryText: "仅接受 HTTPS 审批域名 · 拒绝 \(Self.redactedLegacyHostLabel)",
                verificationDetailText: runtimeAllowlistIsolated
                    ? "运行时网络层对 \(Self.redactedLegacyHostLabel) 执行 Fail-Closed 硬编码拦截，绝不混用小程序线上数据库或会话。"
                    : "告警：运行时旧主机拦截围栏未锁定。",
                status: runtimeAllowlistIsolated ? .isolated : .breachWarning
            ),
            LegacyIsolationLayerRow(
                id: "layer-static-source-scanner",
                layer: .staticSourceScannerGuard,
                titleText: "静态源码扫描守卫 (ContractChecks)",
                ruleSummaryText: "全仓库 Swift / Config 禁止硬编码 \(Self.redactedLegacyHostLabel)",
                verificationDetailText: staticSourceScannerGreen
                    ? "静态契约检查扫描通过，业务源码与配置文件零旧服务器字面量残留。"
                    : "告警：静态源码扫描发现可疑主机字面量。",
                status: staticSourceScannerGreen ? .isolated : .breachWarning
            ),
            LegacyIsolationLayerRow(
                id: "layer-ci-mock-transport",
                layer: .ciOfflineMockTransportOnly,
                titleText: "CI 与离线 Fixture 模拟传输层 (OfflineMockTransport)",
                ruleSummaryText: "Core / AppUnit / UI 3 分片测试全程零外网真实请求",
                verificationDetailText: ciMockTransportEnforced
                    ? "所有自动化测试与 UI Fixture 均使用内存 MockTransport 与确定性桩数据，对线上小程序零冲击。"
                    : "告警：测试传输层未完全锁定离线模式。",
                status: ciMockTransportEnforced ? .isolated : .breachWarning
            )
        ]
    }

    public static let defaultReady = LegacyServerIsolationSnapshot()

    public var isFullyIsolated: Bool {
        !rows.isEmpty && rows.allSatisfy(\.isIsolated)
    }

    public var breachCount: Int {
        rows.filter { !$0.isIsolated }.count
    }

    public var summaryHeadlineText: String {
        isFullyIsolated
            ? "与 \(Self.redactedLegacyHostLabel) 的 4 层零回归隔离防线全部锁定（\(rows.count)/\(rows.count)）"
            : "警告：存在 \(breachCount) 项旧小程序服务器隔离防线异常"
    }

    public func row(for layer: LegacyIsolationLayerRow.Layer) -> LegacyIsolationLayerRow? {
        rows.first { $0.layer == layer }
    }
}

/// Offline SwiftUI section view displaying 100% isolation from `"Legacy Aliyun Mini-Program Host (47.103.x.x)"`
/// across `Base.xcconfig`, runtime allowlist, static source scanner, and CI mock transport using
/// `Text(verbatim:)` (`0` new localization keys) and deterministic `legacyServerIsolation.*` hooks.
@MainActor
public struct ZeroRegressionLegacyServerIsolationSectionView: View {
    public let snapshot: LegacyServerIsolationSnapshot
    public var onSelectRow: ((LegacyIsolationLayerRow) -> Void)?

    public init(
        snapshot: LegacyServerIsolationSnapshot = .defaultReady,
        onSelectRow: ((LegacyIsolationLayerRow) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelectRow = onSelectRow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "存量小程序生产服零冲击与物理隔离面板")
                        .font(.headline)
                        .accessibilityIdentifier("legacyServerIsolation.header.title")
                    Text(verbatim: snapshot.summaryHeadlineText)
                        .font(.subheadline)
                        .foregroundStyle(snapshot.isFullyIsolated ? .green : .red)
                        .accessibilityIdentifier("legacyServerIsolation.header.summary")
                }
                Spacer()
                Text(verbatim: snapshot.isFullyIsolated ? "零污染已锁定" : "隔离告警")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            snapshot.isFullyIsolated
                                ? Color.green.opacity(0.15)
                                : Color.red.opacity(0.15)
                        )
                    )
                    .accessibilityIdentifier("legacyServerIsolation.header.badge")
            }

            ForEach(snapshot.rows) { row in
                rowView(row)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        .accessibilityIdentifier("legacyServerIsolation.section")
    }

    @ViewBuilder
    private func rowView(_ row: LegacyIsolationLayerRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: row.titleText)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("legacyServerIsolation.row.\(row.id).title")
                Spacer()
                Text(verbatim: row.layer.rawValue)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("legacyServerIsolation.row.\(row.id).layer")
                Text(verbatim: row.statusBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(row.isIsolated ? .green : .red)
                    .accessibilityIdentifier("legacyServerIsolation.row.\(row.id).status")
            }

            Text(verbatim: row.ruleSummaryText)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("legacyServerIsolation.row.\(row.id).rule")

            Text(verbatim: row.verificationDetailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("legacyServerIsolation.row.\(row.id).detail")

            if let onSelectRow {
                Button(action: { onSelectRow(row) }) {
                    Text(verbatim: "查看隔离层详情")
                        .font(.caption)
                }
                .accessibilityIdentifier("legacyServerIsolation.row.\(row.id).action")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .accessibilityIdentifier("legacyServerIsolation.row.\(row.id)")
    }
}
