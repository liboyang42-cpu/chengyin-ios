import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained row for StoreKit 2 subscription and refund lifecycle compliance:
/// `Transaction.updates` listener, JWS signature verification before `finish()`,
/// `Restore Purchases` (`AppStore.sync()`) compliance, and revocation/refund handling.
public struct StoreKit2ControlRow: Sendable, Equatable, Identifiable {
    public enum ControlKind: String, CaseIterable, Sendable, Equatable {
        case transactionUpdatesListener = "transactionUpdatesListener"
        case jwsVerificationBeforeFinish = "jwsVerificationBeforeFinish"
        case restorePurchasesAction = "restorePurchasesAction"
        case revocationAndRefundHandling = "revocationAndRefundHandling"
    }

    public enum Status: String, Sendable, Equatable {
        case compliant
        case warningNonCompliant
        case disabledByMarketGate
    }

    public let id: String
    public let kind: ControlKind
    public let title: String
    public let storeKitAPI: String
    public let enforcementRule: String
    public let status: Status

    public init(
        id: String,
        kind: ControlKind,
        title: String,
        storeKitAPI: String,
        enforcementRule: String,
        status: Status
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.storeKitAPI = storeKitAPI
        self.enforcementRule = enforcementRule
        self.status = status
    }

    public var badgeText: String {
        switch status {
        case .compliant:
            return "COMPLIANT"
        case .warningNonCompliant:
            return "WARNING"
        case .disabledByMarketGate:
            return "GATED"
        }
    }
}

/// Self-contained snapshot for StoreKit 2 subscription, JWS verification, restore purchases,
/// and refund/revocation lifecycle readiness.
public struct StoreKit2LifecycleSnapshot: Sendable, Equatable {
    public let verifiesJWSAndServerEntitlementBeforeFinish: Bool
    public let exposesExplicitRestorePurchasesButton: Bool
    public let rows: [StoreKit2ControlRow]

    public init(
        verifiesJWSAndServerEntitlementBeforeFinish: Bool,
        exposesExplicitRestorePurchasesButton: Bool,
        rows: [StoreKit2ControlRow]
    ) {
        self.verifiesJWSAndServerEntitlementBeforeFinish = verifiesJWSAndServerEntitlementBeforeFinish
        self.exposesExplicitRestorePurchasesButton = exposesExplicitRestorePurchasesButton
        self.rows = rows
    }

    public static let defaultReady = StoreKit2LifecycleSnapshot(
        verifiesJWSAndServerEntitlementBeforeFinish: true,
        exposesExplicitRestorePurchasesButton: true,
        rows: [
            StoreKit2ControlRow(
                id: "transaction-updates-listener",
                kind: .transactionUpdatesListener,
                title: "全局交易更新监听 (Transaction.updates)",
                storeKitAPI: "StoreKit.Transaction.updates",
                enforcementRule: "应用启动即挂载异步监听流，捕获续订、家庭共享、Ask-to-Buy 与外部购买状态",
                status: .compliant
            ),
            StoreKit2ControlRow(
                id: "jws-verification-before-finish",
                kind: .jwsVerificationBeforeFinish,
                title: "JWS 验签与服务端权益入账后调用 finish()",
                storeKitAPI: "VerificationResult<Transaction>.verified + transaction.finish()",
                enforcementRule: "严禁未验签或未完成服务端入账即调用 finish()；unverified 交易显式拦截",
                status: .compliant
            ),
            StoreKit2ControlRow(
                id: "restore-purchases-action",
                kind: .restorePurchasesAction,
                title: "显式恢复购买按钮 (Restore Purchases)",
                storeKitAPI: "AppStore.sync() + Transaction.currentEntitlements",
                enforcementRule: "遵循 App Store Review 3.1.1 提供独立恢复购买入口并与当前账号会话重校",
                status: .compliant
            ),
            StoreKit2ControlRow(
                id: "revocation-and-refund-handling",
                kind: .revocationAndRefundHandling,
                title: "退款与撤销状态回滚 (revocationDate / revocationReason)",
                storeKitAPI: "Transaction.revocationDate · beginRefundRequest(in:)",
                enforcementRule: "检测到 revocationDate 非空时立即触发服务端权威权益重读并回收对应订阅状态",
                status: .compliant
            )
        ]
    )

    public var compliantCount: Int {
        rows.filter { $0.status == .compliant }.count
    }

    public var warningCount: Int {
        rows.filter { $0.status == .warningNonCompliant }.count
    }

    public var isFullyCompliant: Bool {
        verifiesJWSAndServerEntitlementBeforeFinish
            && exposesExplicitRestorePurchasesButton
            && rows.allSatisfy { $0.status == .compliant }
    }

    public var summaryText: String {
        "合规控制项 \(compliantCount)/\(rows.count) · 告警 \(warningCount) · JWS 先验后结 \(verifiesJWSAndServerEntitlementBeforeFinish ? "开启" : "缺失")"
    }
}

/// Renders StoreKit 2 `Transaction.updates` listener, JWS verification before `finish()`,
/// `Restore Purchases` button compliance, and refund/revocation handling using `Text(verbatim:)` throughout.
@MainActor
public struct StoreKit2SubscriptionAndRefundSectionView: View {
    public let snapshot: StoreKit2LifecycleSnapshot

    public init(snapshot: StoreKit2LifecycleSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            HStack {
                Text(verbatim: "StoreKit 2 订阅与退款生命周期合规")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: snapshot.isFullyCompliant ? "4/4 合规 (STOREKIT2_OK)" : "存在不合规告警")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((snapshot.isFullyCompliant ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    .foregroundStyle(snapshot.isFullyCompliant ? Color.green : Color.orange)
                    .accessibilityIdentifier("storeKit2Lifecycle.overallBadge")
            }

            LabeledContent {
                Text(verbatim: snapshot.summaryText)
                    .font(.footnote.monospacedDigit())
            } label: {
                Text(verbatim: "生命周期控制汇总")
            }
            .accessibilityIdentifier("storeKit2Lifecycle.summary")

            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(verbatim: row.badgeText)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor(for: row.status).opacity(0.15), in: Capsule())
                            .foregroundStyle(badgeColor(for: row.status))
                    }
                    Text(verbatim: "API：\(row.storeKitAPI)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(verbatim: "规则：\(row.enforcementRule)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("storeKit2Lifecycle.row.\(row.id)")
            }
        } header: {
            Text(verbatim: "StoreKit 2 交易监听、恢复购买与退款撤销核查")
        }
        .accessibilityIdentifier("storeKit2Lifecycle.section")
    }

    private func badgeColor(for status: StoreKit2ControlRow.Status) -> Color {
        switch status {
        case .compliant:
            return .green
        case .warningNonCompliant:
            return .orange
        case .disabledByMarketGate:
            return .secondary
        }
    }
}
