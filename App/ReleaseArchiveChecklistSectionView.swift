import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained gate item for TestFlight & App Store Connect archive readiness.
public struct ReleaseArchiveGateItem: Identifiable, Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case ready
        case blocked
        case pendingOperator
    }

    public let id: String
    public let settingKey: String
    public let currentValue: String
    public let status: Status
    public let requirementNote: String

    public init(
        id: String,
        settingKey: String,
        currentValue: String,
        status: Status,
        requirementNote: String
    ) {
        self.id = id
        self.settingKey = settingKey
        self.currentValue = currentValue
        self.status = status
        self.requirementNote = requirementNote
    }

    public var badgeText: String {
        switch status {
        case .ready:
            return "READY"
        case .blocked:
            return "BLOCKED"
        case .pendingOperator:
            return "PENDING"
        }
    }
}

/// Self-contained snapshot of TestFlight / App Store Connect archive readiness gates.
public struct ReleaseArchiveChecklistSnapshot: Equatable, Sendable {
    public static let forbiddenLegacyOriginHost = "47.103.124.64"

    public let localXcconfigPresent: Bool
    public let items: [ReleaseArchiveGateItem]

    public init(
        localXcconfigPresent: Bool,
        items: [ReleaseArchiveGateItem]
    ) {
        self.localXcconfigPresent = localXcconfigPresent
        self.items = items
    }

    /// Evaluates build settings and CLI verification status into a deterministic archive checklist.
    public static func evaluate(
        localXcconfigPresent: Bool = false,
        codeSigningAllowed: String = "NO",
        developmentTeam: String = "",
        bundleIdentifier: String = "invalid.example.questify.ios",
        market: String = "",
        apiBaseURL: String = "",
        sessionRealm: String = "",
        cliChecksPassed: Bool = true
    ) -> ReleaseArchiveChecklistSnapshot {
        let signingReady = codeSigningAllowed.uppercased() == "YES"
        let teamReady = !developmentTeam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let trimmedBundle = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let bundleReady = !trimmedBundle.isEmpty && !trimmedBundle.hasPrefix("invalid.")
        let trimmedMarket = market.trimmingCharacters(in: .whitespacesAndNewlines)
        let marketReady = trimmedMarket == "CN" || trimmedMarket == "GLOBAL"
        let trimmedURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesForbiddenIP = trimmedURL.contains(forbiddenLegacyOriginHost)
        let urlReady = trimmedURL.hasPrefix("https://") && !usesForbiddenIP
        let trimmedRealm = sessionRealm.trimmingCharacters(in: .whitespacesAndNewlines)
        let realmReady = !trimmedRealm.isEmpty

        let items: [ReleaseArchiveGateItem] = [
            ReleaseArchiveGateItem(
                id: "local-xcconfig",
                settingKey: "Config/Local.xcconfig",
                currentValue: localXcconfigPresent ? "已配置本地签名覆盖" : "未创建（使用 Base.xcconfig 默认无签名配置）",
                status: localXcconfigPresent ? .ready : .pendingOperator,
                requirementNote: "归档前需在本地创建不入库的 Config/Local.xcconfig"
            ),
            ReleaseArchiveGateItem(
                id: "code-signing",
                settingKey: "CODE_SIGNING_ALLOWED",
                currentValue: codeSigningAllowed.isEmpty ? "NO" : codeSigningAllowed,
                status: signingReady ? .ready : .pendingOperator,
                requirementNote: "TestFlight 归档必须显式开启签名 (YES)"
            ),
            ReleaseArchiveGateItem(
                id: "development-team",
                settingKey: "DEVELOPMENT_TEAM",
                currentValue: teamReady ? developmentTeam : "未设置",
                status: teamReady ? .ready : .pendingOperator,
                requirementNote: "需填入 Apple Developer Team ID"
            ),
            ReleaseArchiveGateItem(
                id: "bundle-identifier",
                settingKey: "PRODUCT_BUNDLE_IDENTIFIER",
                currentValue: trimmedBundle.isEmpty ? "未设置" : trimmedBundle,
                status: bundleReady ? .ready : .blocked,
                requirementNote: "禁止使用 invalid.example.* 占位包名归档"
            ),
            ReleaseArchiveGateItem(
                id: "questify-market",
                settingKey: "QUESTIFY_MARKET",
                currentValue: trimmedMarket.isEmpty ? "未设置" : trimmedMarket,
                status: marketReady ? .ready : .pendingOperator,
                requirementNote: "必须显式指定 CN 或 GLOBAL 市场配置"
            ),
            ReleaseArchiveGateItem(
                id: "api-base-url",
                settingKey: "QUESTIFY_API_BASE_URL != 47.103.124.64",
                currentValue: trimmedURL.isEmpty ? "未设置" : trimmedURL,
                status: usesForbiddenIP ? .blocked : (urlReady ? .ready : .pendingOperator),
                requirementNote: "必须为受审 HTTPS 域名且严禁指向历史 IP 47.103.124.64"
            ),
            ReleaseArchiveGateItem(
                id: "session-realm",
                settingKey: "QUESTIFY_SESSION_REALM",
                currentValue: trimmedRealm.isEmpty ? "未设置" : trimmedRealm,
                status: realmReady ? .ready : .pendingOperator,
                requirementNote: "必须绑定隔离会话命名空间 (QUESTIFY_SESSION_REALM)"
            ),
            ReleaseArchiveGateItem(
                id: "cli-verification",
                settingKey: "Pre-archive CLI Verification",
                currentValue: cliChecksPassed ? "check_scaffold.py + check_swift_syntax.py 通过" : "待执行或未通过",
                status: cliChecksPassed ? .ready : .blocked,
                requirementNote: "归档前结构完整性与语法校验必须 0 错误通过"
            )
        ]

        return ReleaseArchiveChecklistSnapshot(
            localXcconfigPresent: localXcconfigPresent,
            items: items
        )
    }

    public static let unsignedWorkspaceDefault = evaluate()

    public var isArchiveReady: Bool {
        localXcconfigPresent && items.allSatisfy { $0.status == .ready }
    }

    public var readyCount: Int {
        items.filter { $0.status == .ready }.count
    }

    public var blockedCount: Int {
        items.filter { $0.status == .blocked }.count
    }

    public var pendingCount: Int {
        items.filter { $0.status == .pendingOperator }.count
    }

    public var summaryText: String {
        "就绪 \(readyCount)/\(items.count) · 待配置 \(pendingCount) · 阻断 \(blockedCount)"
    }
}

/// Renders the TestFlight & App Store Connect archive readiness checklist using `Text(verbatim:)` throughout.
@MainActor
public struct ReleaseArchiveChecklistSectionView: View {
    public let snapshot: ReleaseArchiveChecklistSnapshot

    public init(snapshot: ReleaseArchiveChecklistSnapshot = .unsignedWorkspaceDefault) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            HStack {
                Text(verbatim: "TestFlight 归档总状态")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: snapshot.isArchiveReady ? "可归档 (ARCHIVE_READY)" : "禁止归档 (HOLD)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((snapshot.isArchiveReady ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    .foregroundStyle(snapshot.isArchiveReady ? Color.green : Color.orange)
                    .accessibilityIdentifier("releaseArchiveChecklist.overallBadge")
            }

            LabeledContent {
                Text(verbatim: snapshot.summaryText)
                    .font(.footnote.monospacedDigit())
            } label: {
                Text(verbatim: "门禁统计")
            }
            .accessibilityIdentifier("releaseArchiveChecklist.summary")

            ForEach(snapshot.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: item.settingKey)
                            .font(.subheadline.monospaced().weight(.medium))
                        Spacer()
                        Text(verbatim: item.badgeText)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor(for: item.status).opacity(0.15), in: Capsule())
                            .foregroundStyle(badgeColor(for: item.status))
                    }
                    Text(verbatim: "当前值：\(item.currentValue)")
                        .font(.caption.monospaced())
                    Text(verbatim: item.requirementNote)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("releaseArchiveChecklist.item.\(item.id)")
            }
        } header: {
            Text(verbatim: "TestFlight 与 App Store Connect 归档核查单")
        }
        .accessibilityIdentifier("releaseArchiveChecklist.section")
    }

    private func badgeColor(for status: ReleaseArchiveGateItem.Status) -> Color {
        switch status {
        case .ready:
            return .green
        case .pendingOperator:
            return .orange
        case .blocked:
            return .red
        }
    }
}
