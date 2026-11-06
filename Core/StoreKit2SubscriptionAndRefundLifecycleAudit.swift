import Foundation

/// Pure self-contained value types auditing StoreKit 2 digital membership & entitlement lifecycle (`Guideline 3.1.1` / `3.1.2`).
public struct StoreKit2LifecycleControlCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let controlName: String
    public let observesTransactionUpdatesAtLaunch: Bool
    public let finishesTransactionOnlyAfterEntitlementGrant: Bool
    public let exposesExplicitRestorePurchasesAction: Bool
    public let handlesRevocationAndRefundGracefully: Bool

    public init(
        id: String,
        controlName: String,
        observesTransactionUpdatesAtLaunch: Bool = true,
        finishesTransactionOnlyAfterEntitlementGrant: Bool = true,
        exposesExplicitRestorePurchasesAction: Bool = true,
        handlesRevocationAndRefundGracefully: Bool = true
    ) {
        self.id = id
        self.controlName = controlName
        self.observesTransactionUpdatesAtLaunch = observesTransactionUpdatesAtLaunch
        self.finishesTransactionOnlyAfterEntitlementGrant = finishesTransactionOnlyAfterEntitlementGrant
        self.exposesExplicitRestorePurchasesAction = exposesExplicitRestorePurchasesAction
        self.handlesRevocationAndRefundGracefully = handlesRevocationAndRefundGracefully
    }

    public var isCompliant: Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !controlName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && observesTransactionUpdatesAtLaunch
            && finishesTransactionOnlyAfterEntitlementGrant
            && exposesExplicitRestorePurchasesAction
            && handlesRevocationAndRefundGracefully
    }
}

public struct StoreKit2SubscriptionAndRefundLifecycleAudit: Sendable, Equatable {
    public static let canonicalControls: [StoreKit2LifecycleControlCheck] = [
        StoreKit2LifecycleControlCheck(
            id: "launch-transaction-updates-listener",
            controlName: "应用启动即挂载 Transaction.updates 异步监听任务"
        ),
        StoreKit2LifecycleControlCheck(
            id: "verified-jws-entitlement-grant-before-finish",
            controlName: "JWS 签名验真并完成服务端/本地权益入账后方调用 Transaction.finish()"
        ),
        StoreKit2LifecycleControlCheck(
            id: "member-center-restore-purchases-button",
            controlName: "会员中心显式提供恢复购买 (AppStore.sync) 独立入口"
        ),
        StoreKit2LifecycleControlCheck(
            id: "refund-and-revocation-downgrade-handler",
            controlName: "监听 revocationDate 与退款通知并平滑回落非会员权益状态"
        )
    ]

    public let controls: [StoreKit2LifecycleControlCheck]

    public init(controls: [StoreKit2LifecycleControlCheck] = StoreKit2SubscriptionAndRefundLifecycleAudit.canonicalControls) {
        self.controls = controls
    }

    public static func evaluate(
        controls: [StoreKit2LifecycleControlCheck] = canonicalControls
    ) -> (totalControls: Int, compliantControls: Int, isStoreKit2Ready: Bool) {
        let total = controls.count
        let compliant = controls.filter(\.isCompliant).count
        let ready = total > 0 && compliant == total
        return (
            totalControls: total,
            compliantControls: compliant,
            isStoreKit2Ready: ready
        )
    }
}
