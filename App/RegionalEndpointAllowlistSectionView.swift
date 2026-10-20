import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Single endpoint gate row for the regional endpoint allowlist posture inspection view.
public struct RegionalEndpointGateRow: Identifiable, Equatable, Sendable {
    public enum MarketRegion: String, CaseIterable, Equatable, Sendable {
        case cn = "CN"
        case us = "US"
    }

    public enum Disposition: String, Equatable, Sendable {
        case failClosedBlocked
        case allowedByReviewedGrant
        case forbiddenLegacyHostRejected
    }

    public let id: String
    public let endpointPath: String
    public let featureCategory: String
    public let cnDisposition: Disposition
    public let usDisposition: Disposition
    public let rationaleText: String

    public init(
        id: String,
        endpointPath: String,
        featureCategory: String,
        cnDisposition: Disposition = .failClosedBlocked,
        usDisposition: Disposition = .failClosedBlocked,
        rationaleText: String
    ) {
        self.id = id
        self.endpointPath = endpointPath
        self.featureCategory = featureCategory
        self.cnDisposition = cnDisposition
        self.usDisposition = usDisposition
        self.rationaleText = rationaleText
    }

    public func disposition(for region: MarketRegion) -> Disposition {
        switch region {
        case .cn:
            return cnDisposition
        case .us:
            return usDisposition
        }
    }

    public var isFailClosedInAllRegions: Bool {
        cnDisposition == .failClosedBlocked && usDisposition == .failClosedBlocked
    }

    public static func badgeText(for disposition: Disposition) -> String {
        switch disposition {
        case .failClosedBlocked:
            return "默认阻断 (Fail-Closed)"
        case .allowedByReviewedGrant:
            return "已审批放行"
        case .forbiddenLegacyHostRejected:
            return "旧主机严禁连接"
        }
    }
}

/// Self-contained snapshot of regional endpoint allowlist posture (`CN` vs `US` isolation,
/// `47.103.124.64` legacy host rejection, and fail-closed default blocking for sensitive routes).
public struct RegionalEndpointAllowlistSnapshot: Equatable, Sendable {
    public static let forbiddenLegacyHost = "47.103.124.64"
    public static let defaultBlockedSensitivePaths: [String] = [
        "/api/asset/withdraw",
        "/api/pay/create",
        "/api/npc/chat/delete",
        "/api/topic/like",
        "/api/user/sms/send",
        "/api/merchant/decor/save"
    ]

    public let activeRegion: RegionalEndpointGateRow.MarketRegion
    public let crossRegionIsolationEnforced: Bool
    public let rejectsForbiddenLegacyHost: Bool
    public let rows: [RegionalEndpointGateRow]

    public init(
        activeRegion: RegionalEndpointGateRow.MarketRegion = .cn,
        crossRegionIsolationEnforced: Bool = true,
        rejectsForbiddenLegacyHost: Bool = true,
        rows: [RegionalEndpointGateRow] = Self.defaultFailClosedRows()
    ) {
        self.activeRegion = activeRegion
        self.crossRegionIsolationEnforced = crossRegionIsolationEnforced
        self.rejectsForbiddenLegacyHost = rejectsForbiddenLegacyHost
        self.rows = rows
    }

    public var isPostureCompliant: Bool {
        crossRegionIsolationEnforced
            && rejectsForbiddenLegacyHost
            && rows.allSatisfy(\.isFailClosedInAllRegions)
    }

    public var isolationNoticeText: String {
        crossRegionIsolationEnforced
            ? "CN 与 US 市场路由表严格隔离，严禁跨区混用凭据或回退主机。"
            : "警告：跨市场隔离未锁定。"
    }

    public var legacyHostRejectionNoticeText: String {
        rejectsForbiddenLegacyHost
            ? "历史裸 IP 主机 \(Self.forbiddenLegacyHost) 已被硬编码拒绝，任何包含该地址的配置均直接抛错阻断。"
            : "警告：历史主机阻断未生效。"
    }

    public static func defaultFailClosedRows() -> [RegionalEndpointGateRow] {
        [
            RegionalEndpointGateRow(
                id: "asset-withdraw",
                endpointPath: "/api/asset/withdraw",
                featureCategory: "资产提现",
                rationaleText: "未审批资金提现写接口，CN/US 默认关闭。"
            ),
            RegionalEndpointGateRow(
                id: "pay-create",
                endpointPath: "/api/pay/create",
                featureCategory: "支付下单",
                rationaleText: "数字商品与支付通道待合规审批，客户端恒定阻断。"
            ),
            RegionalEndpointGateRow(
                id: "npc-chat-delete",
                endpointPath: "/api/npc/chat/delete",
                featureCategory: "NPC 记忆清理",
                rationaleText: "需独立白名单授权后方可发起服务端会话清理。"
            ),
            RegionalEndpointGateRow(
                id: "topic-like",
                endpointPath: "/api/topic/like",
                featureCategory: "主题点赞",
                rationaleText: "写操作默认关闭，防止未授权静默提交。"
            ),
            RegionalEndpointGateRow(
                id: "user-sms-send",
                endpointPath: "/api/user/sms/send",
                featureCategory: "短信验证码发送",
                rationaleText: "短信通道按区域白名单显式受控，默认阻断。"
            ),
            RegionalEndpointGateRow(
                id: "merchant-decor-save",
                endpointPath: "/api/merchant/decor/save",
                featureCategory: "商户装修保存",
                rationaleText: "商户装修写接口未进入当前发布白名单，默认阻断。"
            )
        ]
    }
}

/// Offline SwiftUI section rendering `RegionalEndpointAllowlistSnapshot` using `Text(verbatim:)`
/// throughout (0 new `.xcstrings` keys) and deterministic `regionalAllowlist.*` accessibility hooks.
@MainActor
public struct RegionalEndpointAllowlistSectionView: View {
    public let snapshot: RegionalEndpointAllowlistSnapshot
    public var onSelectRow: ((RegionalEndpointGateRow) -> Void)?

    public init(
        snapshot: RegionalEndpointAllowlistSnapshot = RegionalEndpointAllowlistSnapshot(),
        onSelectRow: ((RegionalEndpointGateRow) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelectRow = onSelectRow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "区域路由白名单与默认阻断态势（当前：\(snapshot.activeRegion.rawValue)）")
                        .font(.headline)
                        .accessibilityIdentifier("regionalAllowlist.header.title")
                    Text(verbatim: snapshot.isolationNoticeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("regionalAllowlist.header.isolation")
                }
                Spacer()
                Text(verbatim: snapshot.isPostureCompliant ? "Fail-Closed 合规" : "存在风险")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            snapshot.isPostureCompliant
                                ? Color.green.opacity(0.15)
                                : Color.red.opacity(0.15)
                        )
                    )
                    .accessibilityIdentifier("regionalAllowlist.header.badge")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "禁用旧主机拦截规则（\(RegionalEndpointAllowlistSnapshot.forbiddenLegacyHost)）")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("regionalAllowlist.legacyHost.title")
                Text(verbatim: snapshot.legacyHostRejectionNoticeText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("regionalAllowlist.legacyHost.detail")
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
            .accessibilityIdentifier("regionalAllowlist.legacyHost.banner")

            ForEach(snapshot.rows) { row in
                gateRowView(row)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        .accessibilityIdentifier("regionalAllowlist.section")
    }

    @ViewBuilder
    private func gateRowView(_ row: RegionalEndpointGateRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: row.endpointPath)
                    .font(.subheadline.monospaced().weight(.medium))
                    .accessibilityIdentifier("regionalAllowlist.row.\(row.id).path")
                Spacer()
                Text(verbatim: row.featureCategory)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("regionalAllowlist.row.\(row.id).category")
            }

            HStack(spacing: 10) {
                Text(verbatim: "CN: \(RegionalEndpointGateRow.badgeText(for: row.cnDisposition))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(row.cnDisposition == .failClosedBlocked ? .orange : .primary)
                    .accessibilityIdentifier("regionalAllowlist.row.\(row.id).cnStatus")
                Text(verbatim: "US: \(RegionalEndpointGateRow.badgeText(for: row.usDisposition))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(row.usDisposition == .failClosedBlocked ? .orange : .primary)
                    .accessibilityIdentifier("regionalAllowlist.row.\(row.id).usStatus")
            }

            Text(verbatim: row.rationaleText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("regionalAllowlist.row.\(row.id).rationale")

            if let onSelectRow {
                Button(action: { onSelectRow(row) }) {
                    Text(verbatim: "检查路由门控")
                        .font(.caption)
                }
                .accessibilityIdentifier("regionalAllowlist.row.\(row.id).action")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .accessibilityIdentifier("regionalAllowlist.row.\(row.id)")
    }
}
