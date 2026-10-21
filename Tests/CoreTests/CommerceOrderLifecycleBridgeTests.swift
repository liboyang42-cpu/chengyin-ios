import XCTest
@testable import QuestifyCore

final class CommerceOrderLifecycleBridgeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeLine(
        id: String = "line-1",
        quantity: Int = 2,
        tasks: [CommerceFulfilmentTask] = [],
        entitlements: [CommerceEntitlement] = [],
        refunds: [CommerceRefundRequest] = []
    ) -> CommerceOrderLine {
        CommerceOrderLine(
            lineID: id,
            skuID: "sku-1",
            kind: .mixed,
            unitPriceMinor: 1500,
            quantity: quantity,
            currency: "CNY",
            fulfilment: tasks,
            entitlements: entitlements,
            refunds: refunds
        )
    }

    func testPerLineFulfilmentAndEntitlementStaySeparateInHostSnapshot() throws {
        let grantActive = CommerceEntitlement(grantSequence: 1, themeID: "theme-1", releaseID: "rel-1", state: .active)
        let grantConsumed = CommerceEntitlement(grantSequence: 2, themeID: "theme-1", releaseID: "rel-1", state: .consumed)
        let readyTask = CommerceFulfilmentTask(sequence: 1, mode: .pickup, quantity: 2, state: .ready)
        let unfulfilledLine = makeLine(tasks: [readyTask], entitlements: [grantActive, grantConsumed])

        let readback = try XCTUnwrap(
            CommerceOrderReadback(orderID: "ord-1", merchantID: "m-1", asOf: t0, payment: .paid, lines: [unfulfilledLine])
        )
        let snapshot = CommerceOrderLifecycleBridge.summarizeOrder(readback)
        XCTAssertEqual(snapshot.projection, .awaitingFulfilment)
        let summary = try XCTUnwrap(snapshot.lineSummaries.first)
        XCTAssertEqual(summary.activeEntitlementCount, 1)
        XCTAssertEqual(summary.consumedEntitlementCount, 1)
        XCTAssertEqual(summary.fulfilledQuantity, 0)
        XCTAssertFalse(summary.isLineFulfilled)

        let fulfilledTask = CommerceFulfilmentTask(sequence: 1, mode: .pickup, quantity: 2, state: .fulfilled)
        let fulfilledReadback = try XCTUnwrap(
            CommerceOrderReadback(orderID: "ord-1", merchantID: "m-1", asOf: t0.addingTimeInterval(10), payment: .paid, lines: [makeLine(tasks: [fulfilledTask], entitlements: [grantConsumed])])
        )
        let fulfilledSnapshot = CommerceOrderLifecycleBridge.summarizeOrder(fulfilledReadback)
        XCTAssertEqual(fulfilledSnapshot.projection, .fulfilled)
        XCTAssertTrue(try XCTUnwrap(fulfilledSnapshot.lineSummaries.first).isLineFulfilled)
        XCTAssertTrue(CommerceOrderLifecycleBridge.acceptOrderReadback(current: readback, incoming: fulfilledReadback))
        XCTAssertFalse(CommerceOrderLifecycleBridge.acceptOrderReadback(current: fulfilledReadback, incoming: readback))
    }

    func testUnknownRefundBlocksClientRetryAndRequiresServerQuery() throws {
        let unknownRefund = CommerceRefundRequest(refundNo: "rf-1", amountMinor: 1500, quantity: 1, state: .unknown)
        XCTAssertFalse(unknownRefund.state.isTerminal)

        let readback = try XCTUnwrap(
            CommerceOrderReadback(orderID: "ord-2", merchantID: "m-1", asOf: t0, payment: .paid, lines: [makeLine(refunds: [unknownRefund])])
        )
        let snapshot = CommerceOrderLifecycleBridge.summarizeOrder(readback)
        XCTAssertEqual(snapshot.projection, .refundUnknown)
        XCTAssertTrue(snapshot.requiresServerRefundQuery)
        XCTAssertFalse(snapshot.canRetryRefundFromClient)
        XCTAssertFalse(try XCTUnwrap(snapshot.lineSummaries.first).allowsClientRefundRetry)
    }

    func testQuoteChangeRequiresConfirmationAndPaymentReturnOnlyQueries() {
        XCTAssertFalse(
            CommerceOrderLifecycleBridge.requiresQuoteConfirmation(
                quotedVersion: "v1",
                quotedTotalMinor: 3000,
                serverVersion: "v1",
                serverTotalMinor: 3000
            )
        )
        XCTAssertTrue(
            CommerceOrderLifecycleBridge.requiresQuoteConfirmation(
                quotedVersion: "v1",
                quotedTotalMinor: 3000,
                serverVersion: "v2",
                serverTotalMinor: 3000
            )
        )
        XCTAssertTrue(
            CommerceOrderLifecycleBridge.requiresQuoteConfirmation(
                quotedVersion: "v1",
                quotedTotalMinor: 3000,
                serverVersion: "v1",
                serverTotalMinor: 2800
            )
        )
        XCTAssertEqual(
            CommerceOrderLifecycleBridge.actionOnPaymentReturn(orderID: "ord-9"),
            .queryOrder(orderID: "ord-9")
        )
        XCTAssertFalse(CommerceClientPaymentRules.paymentEnabled)
    }

    func testStaffScopeAndRedemptionPreviewVersusFinalOutcomeSplit() {
        let grant = MerchantStaffScopeGrant(
            merchantID: "m-1",
            storeID: "s-1",
            userID: "u-1",
            role: .redemptionStaff,
            heldPermissions: [.basicRead, .verify],
            validFrom: t0.addingTimeInterval(-60),
            validUntil: t0.addingTimeInterval(3600),
            status: .active,
            version: 4
        )
        let preview = RedemptionPreviewReadback(
            previewID: "pv-1",
            storeID: "s-1",
            itemTitle: "Drink Voucher",
            quantityRemaining: 1,
            expiresAt: t0.addingTimeInterval(60)
        )

        let allowedEval = CommerceOrderLifecycleBridge.evaluateRedemption(
            grant: grant,
            merchantID: "m-1",
            storeID: "s-1",
            serverNow: t0,
            currentVersion: 4,
            scannedCredential: "Zk3_q9-LmW2xP7rT",
            preview: preview,
            finalOutcome: .alreadyRedeemed(originalReceiptID: "rcpt-orig-1")
        )
        XCTAssertEqual(allowedEval.scopeDecision, .allowed)
        XCTAssertTrue(allowedEval.credentialLooksOpaque)
        XCTAssertTrue(allowedEval.previewConfirmable)
        XCTAssertTrue(allowedEval.canProceedToFinalConfirm)
        XCTAssertEqual(allowedEval.finalReceiptID, "rcpt-orig-1")
        XCTAssertTrue(allowedEval.isDuplicateRedemption)

        let staleVersionEval = CommerceOrderLifecycleBridge.evaluateRedemption(
            grant: grant,
            merchantID: "m-1",
            storeID: "s-1",
            serverNow: t0,
            currentVersion: 5,
            scannedCredential: "13800138000",
            preview: preview,
            finalOutcome: nil
        )
        XCTAssertEqual(staleVersionEval.scopeDecision, .denied(.staleVersion))
        XCTAssertFalse(staleVersionEval.credentialLooksOpaque)
        XCTAssertFalse(staleVersionEval.canProceedToFinalConfirm)
        XCTAssertNil(staleVersionEval.finalReceiptID)
    }

    func testSponsoredRewardLimitedDisclosureAndFrozenVoucherTerms() {
        let unreservedGuaranteed = SponsoredPoolItem(
            itemID: "item-1",
            pledgeID: "pledge-1",
            pledgeVersion: "pv-1",
            merchantID: "m-1",
            storeID: "s-1",
            kind: .coupon,
            allocation: .guaranteed,
            title: "Tea Coupon",
            termsVersion: "tv-1",
            termsText: "Valid on weekdays",
            validFrom: t0,
            validUntil: t0.addingTimeInterval(86_400),
            remaining: 5,
            guaranteeReserved: false,
            asOf: t0
        )
        var caps = SponsoredRewardCapabilities()
        caps.nonCash = true
        caps.guaranteed = true

        let issued = SponsoredVoucherTerms(voucherID: "v-1", termsVersion: "tv-1", validUntil: t0.addingTimeInterval(86_400))
        let shortened = SponsoredVoucherTerms(voucherID: "v-1", termsVersion: "tv-1", validUntil: t0.addingTimeInterval(3600))

        let unreservedProjection = CommerceOrderLifecycleBridge.evaluateSponsoredReward(
            item: unreservedGuaranteed,
            capabilities: caps,
            authorizedPledgeIDs: ["pledge-1"],
            targetIsOfficialMap: false,
            issuedVoucher: issued,
            latestVoucher: shortened
        )
        XCTAssertEqual(unreservedProjection.disclosure, .limitedWhileSuppliesLast)
        XCTAssertFalse(unreservedProjection.isPresentable)
        XCTAssertFalse(unreservedProjection.voucherReadbackAccepted)
        XCTAssertEqual(unreservedProjection.bindingRefusal, .guaranteeUnreserved)

        let reservedItem = SponsoredPoolItem(
            itemID: "item-2",
            pledgeID: "pledge-1",
            pledgeVersion: "pv-1",
            merchantID: "m-1",
            storeID: "s-1",
            kind: .coupon,
            allocation: .guaranteed,
            title: "Tea Coupon",
            termsVersion: "tv-1",
            termsText: "Valid on weekdays",
            validFrom: t0,
            validUntil: t0.addingTimeInterval(86_400),
            remaining: 5,
            guaranteeReserved: true,
            asOf: t0
        )
        let extended = SponsoredVoucherTerms(voucherID: "v-1", termsVersion: "tv-1", validUntil: t0.addingTimeInterval(172_800))
        let reservedProjection = CommerceOrderLifecycleBridge.evaluateSponsoredReward(
            item: reservedItem,
            capabilities: caps,
            authorizedPledgeIDs: ["pledge-1"],
            targetIsOfficialMap: false,
            issuedVoucher: issued,
            latestVoucher: extended
        )
        XCTAssertEqual(reservedProjection.disclosure, .guaranteedReserved)
        XCTAssertTrue(reservedProjection.isPresentable)
        XCTAssertTrue(reservedProjection.voucherReadbackAccepted)
        XCTAssertNil(reservedProjection.bindingRefusal)
    }
}
