import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained row describing a web/external link container's sandbox, ATS, and token redaction policy.
public struct WebContainerPolicyRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let containerTitle: String
    public let enforcesHTTPSOnly: Bool
    public let untrustedJSBridgeDisabled: Bool
    public let redactsQueryAuthTokens: Bool
    public let h5ModPackageRejected: Bool
    public let summary: String

    public init(
        id: String,
        containerTitle: String,
        enforcesHTTPSOnly: Bool,
        untrustedJSBridgeDisabled: Bool,
        redactsQueryAuthTokens: Bool,
        h5ModPackageRejected: Bool = true,
        summary: String
    ) {
        self.id = id
        self.containerTitle = containerTitle
        self.enforcesHTTPSOnly = enforcesHTTPSOnly
        self.untrustedJSBridgeDisabled = untrustedJSBridgeDisabled
        self.redactsQueryAuthTokens = redactsQueryAuthTokens
        self.h5ModPackageRejected = h5ModPackageRejected
        self.summary = summary
    }

    public var isContainerSafe: Bool {
        enforcesHTTPSOnly &&
            untrustedJSBridgeDisabled &&
            redactsQueryAuthTokens &&
            h5ModPackageRejected
    }
}

/// Self-contained snapshot for HTTPS-only ATS compliance, untrusted JS bridge isolation,
/// H5 design-only rejection (`questify.h5`), and URL query token redaction.
public struct WebViewSandboxSnapshot: Sendable, Equatable {
    public let atsStrictHTTPSVerified: Bool
    public let untrustedJSBridgeIsolated: Bool
    public let urlQueryTokensRedacted: Bool
    public let h5RuntimeContainerAbsent: Bool
    public let rows: [WebContainerPolicyRow]

    public init(
        atsStrictHTTPSVerified: Bool,
        untrustedJSBridgeIsolated: Bool,
        urlQueryTokensRedacted: Bool,
        h5RuntimeContainerAbsent: Bool = true,
        rows: [WebContainerPolicyRow]
    ) {
        self.atsStrictHTTPSVerified = atsStrictHTTPSVerified
        self.untrustedJSBridgeIsolated = untrustedJSBridgeIsolated
        self.urlQueryTokensRedacted = urlQueryTokensRedacted
        self.h5RuntimeContainerAbsent = h5RuntimeContainerAbsent
        self.rows = rows
    }

    public var safeRowCount: Int {
        rows.filter(\.isContainerSafe).count
    }

    public var isAllSafe: Bool {
        atsStrictHTTPSVerified &&
            untrustedJSBridgeIsolated &&
            urlQueryTokensRedacted &&
            h5RuntimeContainerAbsent &&
            !rows.isEmpty &&
            rows.allSatisfy(\.isContainerSafe)
    }

    public static let defaultReady = WebViewSandboxSnapshot(
        atsStrictHTTPSVerified: true,
        untrustedJSBridgeIsolated: true,
        urlQueryTokensRedacted: true,
        h5RuntimeContainerAbsent: true,
        rows: [
            WebContainerPolicyRow(
                id: "legal-and-privacy-static-docs",
                containerTitle: "隐私政策与用户协议只读页",
                enforcesHTTPSOnly: true,
                untrustedJSBridgeDisabled: true,
                redactsQueryAuthTokens: true,
                h5ModPackageRejected: true,
                summary: "仅加载已审阅 HTTPS 静态合规文档，不注入任何原生凭证或 JS Bridge"
            ),
            WebContainerPolicyRow(
                id: "external-safari-handoff",
                containerTitle: "外部浏览器 / SFSafariViewController 跳转",
                enforcesHTTPSOnly: true,
                untrustedJSBridgeDisabled: true,
                redactsQueryAuthTokens: true,
                h5ModPackageRejected: true,
                summary: "严格校验 HTTPS 协议并剥离 URL 查询参数中的 token/session 敏感字段"
            ),
            WebContainerPolicyRow(
                id: "qmod-h5-package-guard",
                containerTitle: "工坊 H5 模组包隔离围栏 (U08)",
                enforcesHTTPSOnly: true,
                untrustedJSBridgeDisabled: true,
                redactsQueryAuthTokens: true,
                h5ModPackageRejected: true,
                summary: "questify.h5 保持设计态（h5DesignOnly），App 内不挂载任何可执行 H5 WebView 容器"
            )
        ]
    )
}

@MainActor
public struct WebViewAndExternalSafariSandboxSectionView: View {
    public let snapshot: WebViewSandboxSnapshot

    public init(snapshot: WebViewSandboxSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "网页容器与外部链接沙箱安全审计")
                    .font(.headline)
                    .accessibilityIdentifier("webViewSandbox.title")

                Text(verbatim: Self.overallStatusText(for: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(snapshot.isAllSafe ? .green : .red)
                    .accessibilityIdentifier("webViewSandbox.overallStatus")

                Text(verbatim: Self.atsStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("webViewSandbox.atsStatus")

                Text(verbatim: Self.jsBridgeStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("webViewSandbox.jsBridgeStatus")

                Text(verbatim: Self.tokenRedactionStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("webViewSandbox.tokenRedactionStatus")
            }
            .padding(.vertical, 4)

            if snapshot.rows.isEmpty {
                Text(verbatim: "暂无网页容器与外部链接沙箱检查项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("webViewSandbox.empty")
            } else {
                ForEach(snapshot.rows) { row in
                    WebContainerPolicyRowView(row: row)
                }
            }
        }
        .accessibilityIdentifier("webViewSandbox.section")
    }

    public static func overallStatusText(for snapshot: WebViewSandboxSnapshot) -> String {
        snapshot.isAllSafe
            ? "整体状态：网页与外部链接沙箱策略全部安全就绪（\(snapshot.safeRowCount)/\(snapshot.rows.count)）"
            : "整体状态：检测到不安全的网页容器或外部链接策略（\(snapshot.safeRowCount)/\(snapshot.rows.count)）"
    }

    public static func atsStatusText(for snapshot: WebViewSandboxSnapshot) -> String {
        snapshot.atsStrictHTTPSVerified
            ? "HTTPS / ATS 合规：强制 HTTPS 且无 NSAllowsArbitraryLoads 豁免"
            : "HTTPS / ATS 合规：存在非 HTTPS 或 ATS 豁免风险"
    }

    public static func jsBridgeStatusText(for snapshot: WebViewSandboxSnapshot) -> String {
        let bridge = snapshot.untrustedJSBridgeIsolated ? "未授信 JS Bridge 已隔离" : "存在未隔离 JS Bridge"
        let h5 = snapshot.h5RuntimeContainerAbsent ? "H5 容器未挂载" : "H5 容器异常开启"
        return "脚本与容器隔离：\(bridge) · \(h5)"
    }

    public static func tokenRedactionStatusText(for snapshot: WebViewSandboxSnapshot) -> String {
        snapshot.urlQueryTokensRedacted
            ? "URL 凭证脱敏：查询参数 token / ticket 剥离已启用"
            : "URL 凭证脱敏：存在查询参数泄漏凭证风险"
    }
}

@MainActor
private struct WebContainerPolicyRowView: View {
    let row: WebContainerPolicyRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: row.containerTitle)
                    .font(.subheadline.bold())
                Spacer()
                Text(verbatim: row.isContainerSafe ? "安全" : "告警")
                    .font(.caption)
                    .foregroundStyle(row.isContainerSafe ? .green : .red)
            }

            Text(verbatim: row.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: "HTTPS：\(row.enforcesHTTPSOnly ? "强制" : "未强制") · JS Bridge：\(row.untrustedJSBridgeDisabled ? "已禁用" : "未禁用") · Token 脱敏：\(row.redactsQueryAuthTokens ? "已开启" : "未开启")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("webViewSandbox.row")
    }
}
