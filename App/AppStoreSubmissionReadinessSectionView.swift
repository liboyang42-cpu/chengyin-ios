import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Single App Store review readiness check item for pre-submission verification.
public struct AppStoreReviewCheckItem: Identifiable, Equatable, Sendable {
    public enum Category: String, CaseIterable, Equatable, Sendable {
        case privacyUsageDescriptions
        case accountAndNPCAIDeletion
        case nonCashPointsAndRewards
        case ugcModerationAndCacheEviction
        case signInWithAppleParity
    }

    public enum Status: String, Equatable, Sendable {
        case verified
        case actionRequired
        case dormantByGate
    }

    public let id: String
    public let category: Category
    public let referenceCode: String
    public let titleText: String
    public let detailText: String
    public let requiredKeys: [String]
    public let status: Status

    public init(
        id: String,
        category: Category,
        referenceCode: String,
        titleText: String,
        detailText: String,
        requiredKeys: [String] = [],
        status: Status
    ) {
        self.id = id
        self.category = category
        self.referenceCode = referenceCode
        self.titleText = titleText
        self.detailText = detailText
        self.requiredKeys = requiredKeys
        self.status = status
    }

    public var isPassingForSubmission: Bool {
        status == .verified || status == .dormantByGate
    }

    public var statusBadgeText: String {
        switch status {
        case .verified:
            return "已就绪"
        case .dormantByGate:
            return "门控默认关闭"
        case .actionRequired:
            return "待补齐"
        }
    }
}

/// Self-contained snapshot of App Store submission readiness checks across privacy plist keys,
/// account/AI data deletion (`w2-01` / `I08`), non-cash virtual points (`W17.4`), UGC moderation
/// and 404/DELETED cache eviction (`I05` / `w2-13` / `w2-20`), and Sign in with Apple parity (`w2-01`).
public struct AppStoreSubmissionAuditSnapshot: Equatable, Sendable {
    public static let requiredPrivacyInfoPlistKeys: [String] = [
        "NSLocationWhenInUseUsageDescription",
        "NSCameraUsageDescription",
        "NSMicrophoneUsageDescription",
        "NSPhotoLibraryUsageDescription"
    ]

    public let bundleVersionText: String
    public let items: [AppStoreReviewCheckItem]

    public init(bundleVersionText: String, items: [AppStoreReviewCheckItem]) {
        self.bundleVersionText = bundleVersionText
        self.items = items
    }

    public var allPassingForSubmission: Bool {
        !items.isEmpty && items.allSatisfy(\.isPassingForSubmission)
    }

    public var actionRequiredCount: Int {
        items.filter { $0.status == .actionRequired }.count
    }

    public var verifiedOrGatedCount: Int {
        items.filter(\.isPassingForSubmission).count
    }

    public var summaryHeadlineText: String {
        allPassingForSubmission
            ? "App Store 提审合规检查全部通过（\(verifiedOrGatedCount)/\(items.count)）"
            : "存在 \(actionRequiredCount) 项提审阻塞项需处理（已就绪 \(verifiedOrGatedCount)/\(items.count)）"
    }

    public func item(for category: AppStoreReviewCheckItem.Category) -> AppStoreReviewCheckItem? {
        items.first { $0.category == category }
    }

    /// Builds a deterministic baseline snapshot verifying the 5 mandatory App Store readiness pillars.
    public static func standardReadinessSnapshot(
        bundleVersionText: String = "1.0.0",
        presentPrivacyKeys: Set<String> = Set(requiredPrivacyInfoPlistKeys),
        accountAndAIDeletionVerified: Bool = true,
        nonCashPointsPolicyVerified: Bool = true,
        ugcModerationAndEvictionVerified: Bool = true,
        signInWithAppleParityReady: Bool = true
    ) -> AppStoreSubmissionAuditSnapshot {
        let missingPrivacyKeys = requiredPrivacyInfoPlistKeys.filter { !presentPrivacyKeys.contains($0) }
        let privacyStatus: AppStoreReviewCheckItem.Status = missingPrivacyKeys.isEmpty ? .verified : .actionRequired
        let privacyDetail = missingPrivacyKeys.isEmpty
            ? "定位（前台使用）、相机、麦克风、相册权限用途说明均已配置且无后台定位常驻声明。"
            : "缺少 Info.plist 权限说明键：\(missingPrivacyKeys.joined(separator: ", "))"

        let items: [AppStoreReviewCheckItem] = [
            AppStoreReviewCheckItem(
                id: "privacy-usage-descriptions",
                category: .privacyUsageDescriptions,
                referenceCode: "Info.plist",
                titleText: "系统权限用途说明（定位 / 相机 / 麦克风 / 相册）",
                detailText: privacyDetail,
                requiredKeys: requiredPrivacyInfoPlistKeys,
                status: privacyStatus
            ),
            AppStoreReviewCheckItem(
                id: "account-npc-ai-deletion",
                category: .accountAndNPCAIDeletion,
                referenceCode: "w2-01 · I08",
                titleText: "账号注销与 NPC AI 对话记忆删除披露",
                detailText: "提供账号注销入口及 AI 叙事记忆清理与回读围栏，模型或玩家口头声明不写入权威事实。",
                status: accountAndAIDeletionVerified ? .verified : .actionRequired
            ),
            AppStoreReviewCheckItem(
                id: "non-cash-points-reward-ledger",
                category: .nonCashPointsAndRewards,
                referenceCode: "W17.4",
                titleText: "非现金虚拟积分与奖励账本合规声明",
                detailText: "奖励账本仅记录非现金会员积分与实物/卡券核销权益，客户端现金奖励与提现通道恒定关闭。",
                status: nonCashPointsPolicyVerified ? .verified : .actionRequired
            ),
            AppStoreReviewCheckItem(
                id: "ugc-moderation-cache-eviction",
                category: .ugcModerationAndCacheEviction,
                referenceCode: "I05 · w2-13 · w2-20",
                titleText: "UGC 举报拉黑治理与 404/DELETED 缓存驱逐",
                detailText: "广场动态与私信支持举报、拉黑与隐藏会话；服务端返回 404 或 DELETED 时立即从本地缓存驱逐。",
                status: ugcModerationAndEvictionVerified ? .verified : .actionRequired
            ),
            AppStoreReviewCheckItem(
                id: "sign-in-with-apple-parity",
                category: .signInWithAppleParity,
                referenceCode: "w2-01",
                titleText: "Sign in with Apple 对等登录门控",
                detailText: "在开启三方快捷登录的构建中同步提供 Sign in with Apple 登录选项与会话绑定。",
                status: signInWithAppleParityReady ? .verified : .actionRequired
            )
        ]

        return AppStoreSubmissionAuditSnapshot(
            bundleVersionText: bundleVersionText,
            items: items
        )
    }
}

/// Offline SwiftUI section presenting `AppStoreSubmissionAuditSnapshot` with deterministic
/// `appStoreReadiness.*` accessibility identifiers and `Text(verbatim:)` labels (0 new `.xcstrings` keys).
@MainActor
public struct AppStoreSubmissionReadinessSectionView: View {
    public let snapshot: AppStoreSubmissionAuditSnapshot
    public var onSelectCheckItem: ((AppStoreReviewCheckItem) -> Void)?

    public init(
        snapshot: AppStoreSubmissionAuditSnapshot = .standardReadinessSnapshot(),
        onSelectCheckItem: ((AppStoreReviewCheckItem) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelectCheckItem = onSelectCheckItem
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "App Store 提审合规自检（v\(snapshot.bundleVersionText)）")
                        .font(.headline)
                        .accessibilityIdentifier("appStoreReadiness.header.title")
                    Text(verbatim: snapshot.summaryHeadlineText)
                        .font(.subheadline)
                        .foregroundStyle(snapshot.allPassingForSubmission ? .green : .orange)
                        .accessibilityIdentifier("appStoreReadiness.header.summary")
                }
                Spacer()
                Text(verbatim: snapshot.allPassingForSubmission ? "可提审" : "需处理")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            snapshot.allPassingForSubmission
                                ? Color.green.opacity(0.15)
                                : Color.orange.opacity(0.15)
                        )
                    )
                    .accessibilityIdentifier("appStoreReadiness.header.badge")
            }

            ForEach(snapshot.items) { item in
                rowView(for: item)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        .accessibilityIdentifier("appStoreReadiness.section")
    }

    @ViewBuilder
    private func rowView(for item: AppStoreReviewCheckItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: item.titleText)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("appStoreReadiness.item.\(item.id).title")
                Spacer()
                Text(verbatim: item.referenceCode)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("appStoreReadiness.item.\(item.id).ref")
                Text(verbatim: item.statusBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.isPassingForSubmission ? .green : .red)
                    .accessibilityIdentifier("appStoreReadiness.item.\(item.id).status")
            }

            Text(verbatim: item.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("appStoreReadiness.item.\(item.id).detail")

            if !item.requiredKeys.isEmpty {
                Text(verbatim: item.requiredKeys.joined(separator: " · "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("appStoreReadiness.item.\(item.id).keys")
            }

            if let onSelectCheckItem {
                Button(action: { onSelectCheckItem(item) }) {
                    Text(verbatim: "查看合规项详情")
                        .font(.caption)
                }
                .accessibilityIdentifier("appStoreReadiness.item.\(item.id).action")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .accessibilityIdentifier("appStoreReadiness.item.\(item.id)")
    }
}
