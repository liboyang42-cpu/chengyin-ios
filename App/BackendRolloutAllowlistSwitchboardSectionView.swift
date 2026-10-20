import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained row modeling one fail-closed backend rollout runtime switch,
/// its default `OFF` safety posture, and its prerequisite backend/legal sign-off ticket.
public struct RolloutSwitchRow: Sendable, Equatable, Identifiable {
    public enum SwitchID: String, CaseIterable, Sendable, Equatable {
        case authSMSAndOAuth = "switch.auth.smsAndOAuth"
        case paymentsAndWalletWithdraw = "switch.commerce.paymentsAndWithdraw"
        case imSafetyAndUnreadRoutes = "switch.im.safetyAndUnreadRoutes"
        case topicLikeAndNPCAIDelete = "switch.social.topicLikeAndNPCAIDelete"
        case merchantDecorAndShopApply = "switch.merchant.decorAndShopApply"
        case reformWorldAndSceneAIGates = "switch.reform.worldAndSceneAIGates"
    }

    public enum SafetyState: String, Sendable, Equatable {
        case failClosedOff = "OFF (Fail-Closed)"
        case approvedRolloutWithTicket = "APPROVED_ON"
        case unguardedViolation = "UNGUARDED_WARNING"
    }

    public let id: String
    public let switchID: SwitchID
    public let titleText: String
    public let defaultOffEnforced: Bool
    public let prerequisiteTicketCode: String
    public let prerequisiteDescriptionText: String
    public let safetyState: SafetyState

    public init(
        id: String,
        switchID: SwitchID,
        titleText: String,
        defaultOffEnforced: Bool = true,
        prerequisiteTicketCode: String,
        prerequisiteDescriptionText: String,
        safetyState: SafetyState = .failClosedOff
    ) {
        self.id = id
        self.switchID = switchID
        self.titleText = titleText
        self.defaultOffEnforced = defaultOffEnforced
        self.prerequisiteTicketCode = prerequisiteTicketCode
        self.prerequisiteDescriptionText = prerequisiteDescriptionText
        self.safetyState = safetyState
    }

    public var isSafe: Bool {
        defaultOffEnforced && safetyState != .unguardedViolation
    }

    public var badgeText: String {
        switch safetyState {
        case .failClosedOff:
            return "默认关闭 (OFF)"
        case .approvedRolloutWithTicket:
            return "凭审批单放行"
        case .unguardedViolation:
            return "未授权开启告警"
        }
    }
}

/// Self-contained snapshot covering all 6 fail-closed runtime rollout switches and their
/// prerequisite backend/legal sign-off tickets.
public struct RolloutSwitchboardSnapshot: Sendable, Equatable {
    public let rows: [RolloutSwitchRow]

    public init(rows: [RolloutSwitchRow] = Self.defaultFailClosedSwitches()) {
        self.rows = rows
    }

    public static let defaultReady = RolloutSwitchboardSnapshot()

    public var isAllSafe: Bool {
        !rows.isEmpty && rows.allSatisfy(\.isSafe)
    }

    public var unguardedWarningCount: Int {
        rows.filter { !$0.isSafe }.count
    }

    public var summaryHeadlineText: String {
        isAllSafe
            ? "6 大高危运行时白名单开关全部处于 Fail-Closed 默认关闭保护态（\(rows.count)/\(rows.count)）"
            : "存在 \(unguardedWarningCount) 项未绑定前置审批单的运行时开关告警"
    }

    public func row(for switchID: RolloutSwitchRow.SwitchID) -> RolloutSwitchRow? {
        rows.first { $0.switchID == switchID }
    }

    public static func defaultFailClosedSwitches(
        unguardedSwitchIDs: Set<RolloutSwitchRow.SwitchID> = []
    ) -> [RolloutSwitchRow] {
        func makeRow(
            id: String,
            switchID: RolloutSwitchRow.SwitchID,
            title: String,
            ticket: String,
            detail: String
        ) -> RolloutSwitchRow {
            let isUnguarded = unguardedSwitchIDs.contains(switchID)
            return RolloutSwitchRow(
                id: id,
                switchID: switchID,
                titleText: title,
                defaultOffEnforced: !isUnguarded,
                prerequisiteTicketCode: ticket,
                prerequisiteDescriptionText: detail,
                safetyState: isUnguarded ? .unguardedViolation : .failClosedOff
            )
        }

        return [
            makeRow(
                id: "switch-auth-sms-oauth",
                switchID: .authSMSAndOAuth,
                title: "短信验证码与微信 / Apple 三方登录门控 (AuthFeatureFlags)",
                ticket: "SIGN-OFF-W2-01 · IOS-I00-1",
                detail: "需完成 GET /api/userInfo 角色字段校验、Sign in with Apple 对等配置与短信通道合规审批。"
            ),
            makeRow(
                id: "switch-payments-wallet-withdraw",
                switchID: .paymentsAndWalletWithdraw,
                title: "支付下单、Apple IAP 与钱包提现开关 (paymentAndCashEnabled)",
                ticket: "SIGN-OFF-W2-03/05 · W17.4",
                detail: "数字商品通道、区域支付合规与提现风控审批通过前恒定关闭，仅开放非现金积分账本只读。"
            ),
            makeRow(
                id: "switch-im-safety-unread",
                switchID: .imSafetyAndUnreadRoutes,
                title: "站内信举报/拉黑/隐藏与全局未读角标路由 (imReport/imBlock/imDelete/imUnreadTotal)",
                ticket: "SIGN-OFF-W2-20",
                detail: "需按 CN/US 区域路由表逐项评审放行，未知响应必须经 /api/im/conversations 回读核实。"
            ),
            makeRow(
                id: "switch-topic-like-npc-delete",
                switchID: .topicLikeAndNPCAIDelete,
                title: "主题点赞与 NPC AI 记忆远端删除门控 (likeGrantEnabled / AI-DELETE)",
                ticket: "SIGN-OFF-I05 · SIGN-OFF-I08",
                detail: "需后端幂等写接口与 AI 记忆清理回读围栏完成联调签字后方可开启。"
            ),
            makeRow(
                id: "switch-merchant-decor-shop-apply",
                switchID: .merchantDecorAndShopApply,
                title: "商户门店 JSON 装修保存与 4 步入驻提交门控 (decorSave / shopApply)",
                ticket: "SIGN-OFF-W2-17/18/19",
                detail: "需后端 /api/merchant/decor/save JSON 契约与入驻审核回读接口签字确认。"
            ),
            makeRow(
                id: "switch-reform-world-scene-ai",
                switchID: .reformWorldAndSceneAIGates,
                title: "改版世界契约与场景 AI 生成总控 (ReformWorldCapabilities / SceneAIAvailability)",
                ticket: "SIGN-OFF-W02..W20 · M11",
                detail: "改版 v9 建议接口（RunAuthority / Qmod / W16 见面核验 / W19 基地恢复 / W20 城市棋盘）默认全关，NFC 永久禁用。"
            )
        ]
    }
}

/// Offline SwiftUI section view displaying the 6 fail-closed runtime switches, their default `OFF`
/// safety state, and their prerequisite backend/legal sign-off tickets using `Text(verbatim:)`
/// (`0` new localization keys) and deterministic `rolloutAllowlistSwitchboard.*` accessibility hooks.
@MainActor
public struct BackendRolloutAllowlistSwitchboardSectionView: View {
    public let snapshot: RolloutSwitchboardSnapshot
    public var onSelectRow: ((RolloutSwitchRow) -> Void)?

    public init(
        snapshot: RolloutSwitchboardSnapshot = .defaultReady,
        onSelectRow: ((RolloutSwitchRow) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelectRow = onSelectRow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "后端灰度放行与运行时白名单总控台")
                        .font(.headline)
                        .accessibilityIdentifier("rolloutAllowlistSwitchboard.header.title")
                    Text(verbatim: snapshot.summaryHeadlineText)
                        .font(.subheadline)
                        .foregroundStyle(snapshot.isAllSafe ? .green : .orange)
                        .accessibilityIdentifier("rolloutAllowlistSwitchboard.header.summary")
                }
                Spacer()
                Text(verbatim: snapshot.isAllSafe ? "默认全关安全" : "存在越权开启")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            snapshot.isAllSafe
                                ? Color.green.opacity(0.15)
                                : Color.red.opacity(0.15)
                        )
                    )
                    .accessibilityIdentifier("rolloutAllowlistSwitchboard.header.badge")
            }

            ForEach(snapshot.rows) { row in
                rowView(row)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        .accessibilityIdentifier("rolloutAllowlistSwitchboard.section")
    }

    @ViewBuilder
    private func rowView(_ row: RolloutSwitchRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: row.titleText)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("rolloutAllowlistSwitchboard.row.\(row.id).title")
                Spacer()
                Text(verbatim: row.badgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(row.isSafe ? .green : .red)
                    .accessibilityIdentifier("rolloutAllowlistSwitchboard.row.\(row.id).status")
            }

            Text(verbatim: "前置审批单：\(row.prerequisiteTicketCode)")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("rolloutAllowlistSwitchboard.row.\(row.id).ticket")

            Text(verbatim: row.prerequisiteDescriptionText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("rolloutAllowlistSwitchboard.row.\(row.id).detail")

            if let onSelectRow {
                Button(action: { onSelectRow(row) }) {
                    Text(verbatim: "查看开关审批条件")
                        .font(.caption)
                }
                .accessibilityIdentifier("rolloutAllowlistSwitchboard.row.\(row.id).action")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .accessibilityIdentifier("rolloutAllowlistSwitchboard.row.\(row.id)")
    }
}
