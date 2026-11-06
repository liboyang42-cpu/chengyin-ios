import XCTest
@testable import QuestifyCore

final class StoreKit2SubscriptionAndRefundLifecycleAuditTests: XCTestCase {
    func testCanonicalControlsPassStoreKit2LifecycleAudit() {
        let result = StoreKit2SubscriptionAndRefundLifecycleAudit.evaluate()
        XCTAssertEqual(result.totalControls, 4)
        XCTAssertEqual(result.compliantControls, 4)
        XCTAssertTrue(result.isStoreKit2Ready)
        XCTAssertEqual(
            StoreKit2SubscriptionAndRefundLifecycleAudit.canonicalControls.map(\.id),
            [
                "launch-transaction-updates-listener",
                "verified-jws-entitlement-grant-before-finish",
                "member-center-restore-purchases-button",
                "refund-and-revocation-downgrade-handler"
            ]
        )
    }

    func testMissingTransactionUpdatesListenerAtLaunchIsDetected() {
        var controls = StoreKit2SubscriptionAndRefundLifecycleAudit.canonicalControls
        controls[0] = StoreKit2LifecycleControlCheck(
            id: "launch-transaction-updates-listener",
            controlName: "启动监听",
            observesTransactionUpdatesAtLaunch: false,
            finishesTransactionOnlyAfterEntitlementGrant: true,
            exposesExplicitRestorePurchasesAction: true,
            handlesRevocationAndRefundGracefully: true
        )
        let result = StoreKit2SubscriptionAndRefundLifecycleAudit.evaluate(controls: controls)
        XCTAssertFalse(result.isStoreKit2Ready)
        XCTAssertEqual(result.compliantControls, 3)
    }

    func testPrematureTransactionFinishBeforeEntitlementGrantIsDetected() {
        let prematureFinish = StoreKit2LifecycleControlCheck(
            id: "verified-jws-entitlement-grant-before-finish",
            controlName: "JWS 权益入账",
            observesTransactionUpdatesAtLaunch: true,
            finishesTransactionOnlyAfterEntitlementGrant: false,
            exposesExplicitRestorePurchasesAction: true,
            handlesRevocationAndRefundGracefully: true
        )
        XCTAssertFalse(prematureFinish.isCompliant)
        let result = StoreKit2SubscriptionAndRefundLifecycleAudit.evaluate(controls: [prematureFinish])
        XCTAssertFalse(result.isStoreKit2Ready)
        XCTAssertEqual(result.compliantControls, 0)
    }

    func testMissingRestorePurchasesOrRevocationHandlingIsDetected() {
        let missingRestore = StoreKit2LifecycleControlCheck(
            id: "member-center-restore-purchases-button",
            controlName: "恢复购买入口",
            observesTransactionUpdatesAtLaunch: true,
            finishesTransactionOnlyAfterEntitlementGrant: true,
            exposesExplicitRestorePurchasesAction: false,
            handlesRevocationAndRefundGracefully: true
        )
        XCTAssertFalse(missingRestore.isCompliant)

        let missingRevocation = StoreKit2LifecycleControlCheck(
            id: "refund-and-revocation-downgrade-handler",
            controlName: "退款撤销处理",
            observesTransactionUpdatesAtLaunch: true,
            finishesTransactionOnlyAfterEntitlementGrant: true,
            exposesExplicitRestorePurchasesAction: true,
            handlesRevocationAndRefundGracefully: false
        )
        XCTAssertFalse(missingRevocation.isCompliant)

        let result = StoreKit2SubscriptionAndRefundLifecycleAudit.evaluate(controls: [missingRestore, missingRevocation])
        XCTAssertFalse(result.isStoreKit2Ready)
        XCTAssertEqual(result.compliantControls, 0)
    }
}
