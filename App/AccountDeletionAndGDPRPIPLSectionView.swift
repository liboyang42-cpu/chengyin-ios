import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained row describing a step in the App Store Guideline 5.1.1(v), GDPR, and PIPL
/// in-app account deletion workflow (`w2-01` `AccountCancelView`).
public struct AccountDeletionStepRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let stepTitle: String
    public let inAppDirectExecution: Bool
    public let checksUnsettledOrdersAndWallet: Bool
    public let purgesKeychainAndLocalStoresImmediately: Bool
    public let summary: String

    public init(
        id: String,
        stepTitle: String,
        inAppDirectExecution: Bool,
        checksUnsettledOrdersAndWallet: Bool,
        purgesKeychainAndLocalStoresImmediately: Bool,
        summary: String
    ) {
        self.id = id
        self.stepTitle = stepTitle
        self.inAppDirectExecution = inAppDirectExecution
        self.checksUnsettledOrdersAndWallet = checksUnsettledOrdersAndWallet
        self.purgesKeychainAndLocalStoresImmediately = purgesKeychainAndLocalStoresImmediately
        self.summary = summary
    }

    public var isStepCompliant: Bool {
        inAppDirectExecution &&
            checksUnsettledOrdersAndWallet &&
            purgesKeychainAndLocalStoresImmediately
    }
}

/// Self-contained snapshot for App Store Guideline 5.1.1(v) in-app account deletion entry
/// (`w2-01` `AccountCancelView`), unsettled order/wallet precheck, and immediate Keychain + local store purge.
public struct AccountDeletionPIPLSnapshot: Sendable, Equatable {
    public let guideline511vInAppEntryAvailable: Bool
    public let unsettledOrderAndWalletPrecheckEnabled: Bool
    public let immediateKeychainAndLocalPurgeVerified: Bool
    public let noCustomerServiceCallRequiredForDeletion: Bool
    public let rows: [AccountDeletionStepRow]

    public init(
        guideline511vInAppEntryAvailable: Bool,
        unsettledOrderAndWalletPrecheckEnabled: Bool,
        immediateKeychainAndLocalPurgeVerified: Bool,
        noCustomerServiceCallRequiredForDeletion: Bool = true,
        rows: [AccountDeletionStepRow]
    ) {
        self.guideline511vInAppEntryAvailable = guideline511vInAppEntryAvailable
        self.unsettledOrderAndWalletPrecheckEnabled = unsettledOrderAndWalletPrecheckEnabled
        self.immediateKeychainAndLocalPurgeVerified = immediateKeychainAndLocalPurgeVerified
        self.noCustomerServiceCallRequiredForDeletion = noCustomerServiceCallRequiredForDeletion
        self.rows = rows
    }

    public var compliantRowCount: Int {
        rows.filter(\.isStepCompliant).count
    }

    public var isAllCompliant: Bool {
        guideline511vInAppEntryAvailable &&
            unsettledOrderAndWalletPrecheckEnabled &&
            immediateKeychainAndLocalPurgeVerified &&
            noCustomerServiceCallRequiredForDeletion &&
            !rows.isEmpty &&
            rows.allSatisfy(\.isStepCompliant)
    }

    public static let defaultReady = AccountDeletionPIPLSnapshot(
        guideline511vInAppEntryAvailable: true,
        unsettledOrderAndWalletPrecheckEnabled: true,
        immediateKeychainAndLocalPurgeVerified: true,
        noCustomerServiceCallRequiredForDeletion: true,
        rows: [
            AccountDeletionStepRow(
                id: "in-app-entry-account-cancel-view",
                stepTitle: "1. App 内置账号注销入口 (w2-01 AccountCancelView)",
                inAppDirectExecution: true,
                checksUnsettledOrdersAndWallet: true,
                purgesKeychainAndLocalStoresImmediately: true,
                summary: "设置页直达 AccountCancelView，无需跳转外部网页或强制拨打客服电话（符合 Guideline 5.1.1(v)）"
            ),
            AccountDeletionStepRow(
                id: "unsettled-order-and-wallet-precheck",
                stepTitle: "2. 未完结订单、钱包分润与主理人职责预检",
                inAppDirectExecution: true,
                checksUnsettledOrdersAndWallet: true,
                purgesKeychainAndLocalStoresImmediately: true,
                summary: "注销前核验进行中订单、待结算余额与俱乐部主理人交接状态，清晰展示阻断原因"
            ),
            AccountDeletionStepRow(
                id: "explicit-confirmation-and-receipt",
                stepTitle: "3. 二次显式确认与服务端注销回执",
                inAppDirectExecution: true,
                checksUnsettledOrdersAndWallet: true,
                purgesKeychainAndLocalStoresImmediately: true,
                summary: "明确告知 GDPR / PIPL 个人信息删除范围与不可恢复后果，仅在收到服务端确认回执后完成注销"
            ),
            AccountDeletionStepRow(
                id: "keychain-and-local-store-purge",
                stepTitle: "4. Keychain 凭证与本地持久化缓存即时销毁",
                inAppDirectExecution: true,
                checksUnsettledOrdersAndWallet: true,
                purgesKeychainAndLocalStoresImmediately: true,
                summary: "立即清除 Keychain 会话令牌、区域 Session Realm、NPC 聊天本地记录与离线草稿缓存"
            )
        ]
    )
}

@MainActor
public struct AccountDeletionAndGDPRPIPLSectionView: View {
    public let snapshot: AccountDeletionPIPLSnapshot

    public init(snapshot: AccountDeletionPIPLSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "账号注销与 GDPR / PIPL 合规审计 (Guideline 5.1.1(v))")
                    .font(.headline)
                    .accessibilityIdentifier("accountDeletionPIPL.title")

                Text(verbatim: Self.overallStatusText(for: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(snapshot.isAllCompliant ? .green : .red)
                    .accessibilityIdentifier("accountDeletionPIPL.overallStatus")

                Text(verbatim: Self.entryStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("accountDeletionPIPL.entryStatus")

                Text(verbatim: Self.precheckStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("accountDeletionPIPL.precheckStatus")

                Text(verbatim: Self.localPurgeStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("accountDeletionPIPL.localPurgeStatus")
            }
            .padding(.vertical, 4)

            if snapshot.rows.isEmpty {
                Text(verbatim: "暂无账号注销与数据清除检查项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("accountDeletionPIPL.empty")
            } else {
                ForEach(snapshot.rows) { row in
                    AccountDeletionStepRowView(row: row)
                }
            }
        }
        .accessibilityIdentifier("accountDeletionPIPL.section")
    }

    public static func overallStatusText(for snapshot: AccountDeletionPIPLSnapshot) -> String {
        snapshot.isAllCompliant
            ? "整体状态：Guideline 5.1.1(v) 与 GDPR / PIPL 注销闭环全部合规（\(snapshot.compliantRowCount)/\(snapshot.rows.count)）"
            : "整体状态：检测到违反 Guideline 5.1.1(v) 或数据清除不完整的风险（\(snapshot.compliantRowCount)/\(snapshot.rows.count)）"
    }

    public static func entryStatusText(for snapshot: AccountDeletionPIPLSnapshot) -> String {
        snapshot.guideline511vInAppEntryAvailable && snapshot.noCustomerServiceCallRequiredForDeletion
            ? "注销入口合规：App 内 AccountCancelView 可直接发起，无强制人工客服门槛"
            : "注销入口告警：缺少 App 内置注销入口或存在人工客服阻断"
    }

    public static func precheckStatusText(for snapshot: AccountDeletionPIPLSnapshot) -> String {
        snapshot.unsettledOrderAndWalletPrecheckEnabled
            ? "资产与订单预检：未完结订单、钱包余额与俱乐部职责核验已启用"
            : "资产与订单预检：未完结订单或钱包预检未启用"
    }

    public static func localPurgeStatusText(for snapshot: AccountDeletionPIPLSnapshot) -> String {
        snapshot.immediateKeychainAndLocalPurgeVerified
            ? "本地数据销毁：Keychain 令牌、Session Realm 与本地缓存即时抹除已核验"
            : "本地数据销毁：Keychain 或本地缓存存在残留风险"
    }
}

@MainActor
private struct AccountDeletionStepRowView: View {
    let row: AccountDeletionStepRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: row.stepTitle)
                    .font(.subheadline.bold())
                Spacer()
                Text(verbatim: row.isStepCompliant ? "合规" : "告警")
                    .font(.caption)
                    .foregroundStyle(row.isStepCompliant ? .green : .red)
            }

            Text(verbatim: row.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: "App 内直达：\(row.inAppDirectExecution ? "是" : "否") · 订单/钱包预检：\(row.checksUnsettledOrdersAndWallet ? "已开启" : "未开启") · Keychain 抹除：\(row.purgesKeychainAndLocalStoresImmediately ? "即时" : "缺失")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("accountDeletionPIPL.row")
    }
}
