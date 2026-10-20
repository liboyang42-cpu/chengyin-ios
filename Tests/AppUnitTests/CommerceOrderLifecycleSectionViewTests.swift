@testable import QuestifyApp
import QuestifyCore
import XCTest

@MainActor
final class CommerceOrderLifecycleSectionViewTests: XCTestCase {
    private let serverNow = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeOrderSnapshot(
        taskState: CommerceFulfilmentTask.State = .ready,
        refundState: CommerceRefundRequest.State? = nil
    ) throws -> CommerceOrderHostSnapshot {
        let refunds: [CommerceRefundRequest] = refundState.map {
            [CommerceRefundRequest(refundNo: "rf-1", amountMinor: 1000, quantity: 1, state: $0)]
        } ?? []
        let line = CommerceOrderLine(
            lineID: "line-1",
            skuID: "sku-combo",
            kind: .mixed,
            unitPriceMinor: 2000,
            quantity: 2,
            currency: "CNY",
            fulfilment: [CommerceFulfilmentTask(sequence: 1, mode: .pickup, quantity: 2, state: taskState)],
            entitlements: [
                CommerceEntitlement(grantSequence: 1, themeID: "theme-1", releaseID: "rel-1", state: .active),
                CommerceEntitlement(grantSequence: 2, themeID: "theme-1", releaseID: "rel-1", state: .consumed)
            ],
            refunds: refunds
        )
        let readback = try XCTUnwrap(
            CommerceOrderReadback(
                orderID: "ord-100",
                merchantID: "m-1",
                asOf: serverNow,
                payment: .paid,
                lines: [line]
            )
        )
        return CommerceOrderLifecycleBridge.summarizeOrder(readback)
    }

    func testOrderLineFulfilmentVsEntitlementSeparationAndUnknownRefundRetryLock() throws {
        let awaitingSnapshot = try makeOrderSnapshot(taskState: .ready, refundState: nil)
        let quoteChanged = CommerceOrderLifecycleBridge.requiresQuoteConfirmation(
            quotedVersion: "q1",
            quotedTotalMinor: 4000,
            serverVersion: "q2",
            serverTotalMinor: 4200
        )
        let awaitingView = CommerceOrderLifecycleSectionView(
            orderSnapshot: awaitingSnapshot,
            requiresQuoteConfirmation: quoteChanged
        )
        _ = awaitingView.body

        XCTAssertTrue(awaitingView.requiresQuoteConfirmation)
        XCTAssertEqual(awaitingView.orderSnapshot.projection, .awaitingFulfilment)
        XCTAssertFalse(awaitingView.orderSnapshot.requiresServerRefundQuery)
        XCTAssertTrue(awaitingView.orderSnapshot.canRetryRefundFromClient)
        let lineSummary = try XCTUnwrap(awaitingView.orderSnapshot.lineSummaries.first)
        XCTAssertFalse(lineSummary.isLineFulfilled)
        XCTAssertEqual(lineSummary.activeEntitlementCount, 1)
        XCTAssertEqual(lineSummary.consumedEntitlementCount, 1)
        XCTAssertNil(awaitingView.redemptionEvaluation)
        XCTAssertNil(awaitingView.rewardProjection)

        let unknownRefundSnapshot = try makeOrderSnapshot(taskState: .ready, refundState: .unknown)
        let lockedView = CommerceOrderLifecycleSectionView(
            orderSnapshot: unknownRefundSnapshot,
            requiresQuoteConfirmation: false
        )
        _ = lockedView.body

        XCTAssertEqual(lockedView.orderSnapshot.projection, .refundUnknown)
        XCTAssertTrue(lockedView.orderSnapshot.requiresServerRefundQuery)
        XCTAssertFalse(lockedView.orderSnapshot.canRetryRefundFromClient)
        XCTAssertEqual(lockedView.orderSnapshot.lineSummaries.first?.hasUnknownRefund, true)
        XCTAssertEqual(lockedView.orderSnapshot.lineSummaries.first?.allowsClientRefundRetry, false)
    }

    func testStaffRedemptionPreviewVsFinalConfirmationAndDuplicateRejection() throws {
        let snapshot = try makeOrderSnapshot(taskState: .fulfilled)
        let grant = MerchantStaffScopeGrant(
            merchantID: "m-1",
            storeID: "s-1",
            userID: "staff-1",
            role: .redemptionStaff,
            heldPermissions: [.basicRead, .verify],
            validFrom: serverNow.addingTimeInterval(-60),
            validUntil: serverNow.addingTimeInterval(3600),
            status: .active,
            version: 4
        )
        let preview = RedemptionPreviewReadback(
            previewID: "pv-1",
            storeID: "s-1",
            itemTitle: "限定饮品券",
            quantityRemaining: 1,
            expiresAt: serverNow.addingTimeInterval(120)
        )

        let previewEval = CommerceOrderLifecycleBridge.evaluateRedemption(
            grant: grant,
            merchantID: "m-1",
            storeID: "s-1",
            serverNow: serverNow,
            currentVersion: 4,
            scannedCredential: "OpAqUe_CrEd-2026xYz9",
            preview: preview,
            finalOutcome: nil
        )
        let previewView = CommerceOrderLifecycleSectionView(
            orderSnapshot: snapshot,
            redemptionEvaluation: previewEval
        )
        _ = previewView.body

        XCTAssertEqual(previewView.redemptionEvaluation?.scopeDecision, .allowed)
        XCTAssertEqual(previewView.redemptionEvaluation?.canProceedToFinalConfirm, true)
        XCTAssertNil(previewView.redemptionEvaluation?.finalOutcome)
        XCTAssertEqual(previewView.redemptionEvaluation?.isDuplicateRedemption, false)

        let duplicateEval = CommerceOrderLifecycleBridge.evaluateRedemption(
            grant: grant,
            merchantID: "m-1",
            storeID: "s-1",
            serverNow: serverNow,
            currentVersion: 4,
            scannedCredential: "OpAqUe_CrEd-2026xYz9",
            preview: preview,
            finalOutcome: .alreadyRedeemed(originalReceiptID: "rcpt-origin-1")
        )
        let duplicateView = CommerceOrderLifecycleSectionView(
            orderSnapshot: snapshot,
            redemptionEvaluation: duplicateEval
        )
        _ = duplicateView.body

        XCTAssertEqual(duplicateView.redemptionEvaluation?.isDuplicateRedemption, true)
        XCTAssertEqual(duplicateView.redemptionEvaluation?.finalReceiptID, "rcpt-origin-1")

        let rejectedEval = CommerceOrderLifecycleBridge.evaluateRedemption(
            grant: grant,
            merchantID: "m-1",
            storeID: "s-2",
            serverNow: serverNow,
            currentVersion: 4,
            scannedCredential: "13800138000",
            preview: preview,
            finalOutcome: .rejected(reasonCode: "STORE_MISMATCH")
        )
        let rejectedView = CommerceOrderLifecycleSectionView(
            orderSnapshot: snapshot,
            redemptionEvaluation: rejectedEval
        )
        _ = rejectedView.body

        XCTAssertEqual(rejectedView.redemptionEvaluation?.scopeDecision, .denied(.otherStore))
        XCTAssertEqual(rejectedView.redemptionEvaluation?.credentialLooksOpaque, false)
        XCTAssertEqual(rejectedView.redemptionEvaluation?.canProceedToFinalConfirm, false)
        XCTAssertNil(rejectedView.redemptionEvaluation?.finalReceiptID)
    }

    func testSponsoredRewardPoolDisclosureAndFailClosedCapabilityGate() throws {
        let snapshot = try makeOrderSnapshot(taskState: .fulfilled)
        let unreservedGuaranteedItem = SponsoredPoolItem(
            itemID: "item-limited",
            pledgeID: "pledge-1",
            pledgeVersion: "v1",
            merchantID: "m-1",
            storeID: "s-1",
            kind: .coupon,
            allocation: .guaranteed,
            title: "完赛礼遇券",
            termsVersion: "t1",
            termsText: "凭券到店兑换",
            validFrom: serverNow,
            validUntil: serverNow.addingTimeInterval(86_400),
            remaining: 5,
            guaranteeReserved: false,
            asOf: serverNow
        )

        let failClosedProjection = CommerceOrderLifecycleBridge.evaluateSponsoredReward(
            item: unreservedGuaranteedItem,
            capabilities: .disabled,
            authorizedPledgeIDs: ["pledge-1"]
        )
        let failClosedView = CommerceOrderLifecycleSectionView(
            orderSnapshot: snapshot,
            rewardProjection: failClosedProjection
        )
        _ = failClosedView.body

        XCTAssertEqual(failClosedView.rewardProjection?.disclosure, .limitedWhileSuppliesLast)
        XCTAssertEqual(failClosedView.rewardProjection?.isPresentable, false)
        XCTAssertEqual(failClosedView.rewardProjection?.bindingRefusal, .capabilityDisabled)

        let reservedGuaranteedItem = SponsoredPoolItem(
            itemID: "item-reserved",
            pledgeID: "pledge-1",
            pledgeVersion: "v1",
            merchantID: "m-1",
            storeID: "s-1",
            kind: .coupon,
            allocation: .guaranteed,
            title: "专属保底礼遇券",
            termsVersion: "t1",
            termsText: "凭券到店兑换",
            validFrom: serverNow,
            validUntil: serverNow.addingTimeInterval(86_400),
            remaining: 5,
            guaranteeReserved: true,
            asOf: serverNow
        )
        var enabledCaps = SponsoredRewardCapabilities.disabled
        enabledCaps.nonCash = true
        enabledCaps.guaranteed = true

        let issuedVoucher = SponsoredVoucherTerms(
            voucherID: "v-1",
            termsVersion: "t1",
            validUntil: serverNow.addingTimeInterval(86_400)
        )
        let shortenedVoucher = SponsoredVoucherTerms(
            voucherID: "v-1",
            termsVersion: "t1",
            validUntil: serverNow.addingTimeInterval(3600)
        )

        let reservedProjection = CommerceOrderLifecycleBridge.evaluateSponsoredReward(
            item: reservedGuaranteedItem,
            capabilities: enabledCaps,
            authorizedPledgeIDs: ["pledge-1"],
            issuedVoucher: issuedVoucher,
            latestVoucher: shortenedVoucher
        )
        let reservedView = CommerceOrderLifecycleSectionView(
            orderSnapshot: snapshot,
            rewardProjection: reservedProjection
        )
        _ = reservedView.body

        XCTAssertEqual(reservedView.rewardProjection?.disclosure, .guaranteedReserved)
        XCTAssertEqual(reservedView.rewardProjection?.isPresentable, true)
        XCTAssertNil(reservedView.rewardProjection?.bindingRefusal)
        XCTAssertEqual(reservedView.rewardProjection?.voucherReadbackAccepted, false)
    }
}
