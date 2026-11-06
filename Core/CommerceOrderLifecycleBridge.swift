import Foundation

/// Host-facing projection of a single `CommerceOrderLine` (W06.4 / W06.6 / W06.7).
/// Keeps physical/service fulfilment strictly separate from theme entitlements and blocks
/// client-side retries when any refund request is in the non-terminal `UNKNOWN` state.
public struct CommerceOrderLineHostSummary: Equatable, Sendable {
    public let lineID: String
    public let skuID: String
    public let kind: CommerceSKUKind
    public let orderedQuantity: Int
    public let fulfilledQuantity: Int
    public let activeEntitlementCount: Int
    public let consumedEntitlementCount: Int
    public let hasUnknownRefund: Bool
    public let hasNonTerminalRefund: Bool
    /// `UNKNOWN` refunds must be resolved via server readback query, never retried by the client.
    public let allowsClientRefundRetry: Bool
    /// Fulfilment completion is computed strictly from `CommerceFulfilmentTask` records, never entitlements.
    public let isLineFulfilled: Bool

    public init(line: CommerceOrderLine) {
        self.lineID = line.lineID
        self.skuID = line.skuID
        self.kind = line.kind
        self.orderedQuantity = line.quantity
        let activeTasks = line.fulfilment.filter { $0.state != .cancelled }
        let fulfilledQty = activeTasks
            .filter { $0.state == .fulfilled }
            .map(\.quantity)
            .reduce(0, +)
        self.fulfilledQuantity = fulfilledQty
        self.activeEntitlementCount = line.entitlements.filter { $0.state == .active }.count
        self.consumedEntitlementCount = line.entitlements.filter { $0.state == .consumed }.count
        let unknownRefund = line.refunds.contains { $0.state == .unknown }
        let nonTerminalRefund = line.refunds.contains { !$0.state.isTerminal }
        self.hasUnknownRefund = unknownRefund
        self.hasNonTerminalRefund = nonTerminalRefund
        self.allowsClientRefundRetry = !unknownRefund && !nonTerminalRefund
        self.isLineFulfilled = !activeTasks.isEmpty
            && activeTasks.allSatisfy { $0.state == .fulfilled }
            && fulfilledQty == line.quantity
    }
}

/// Whole-order host snapshot derived from `CommerceOrderReadback`.
public struct CommerceOrderHostSnapshot: Equatable, Sendable {
    public let orderID: String
    public let merchantID: String
    public let projection: CommerceOrderReadback.Projection
    public let lineSummaries: [CommerceOrderLineHostSummary]
    public let requiresServerRefundQuery: Bool
    public let canRetryRefundFromClient: Bool

    public init(readback: CommerceOrderReadback) {
        self.orderID = readback.orderID
        self.merchantID = readback.merchantID
        self.projection = readback.projection
        let summaries = readback.lines.map(CommerceOrderLineHostSummary.init(line:))
        self.lineSummaries = summaries
        let anyUnknownRefund = readback.projection == .refundUnknown || summaries.contains(where: \.hasUnknownRefund)
        self.requiresServerRefundQuery = anyUnknownRefund
        self.canRetryRefundFromClient = !anyUnknownRefund && summaries.allSatisfy(\.allowsClientRefundRetry)
    }
}

/// Host evaluation of a staff redemption step (W07.3 / W07.4), separating preview check from final outcome.
public struct StaffRedemptionHostEvaluation: Equatable, Sendable {
    public let scopeDecision: MerchantStaffScopeDecision
    public let credentialLooksOpaque: Bool
    public let previewConfirmable: Bool
    public let canProceedToFinalConfirm: Bool
    public let finalOutcome: RedemptionFinalOutcome?
    public let finalReceiptID: String?
    public let isDuplicateRedemption: Bool

    public init(
        scopeDecision: MerchantStaffScopeDecision,
        credentialLooksOpaque: Bool,
        previewConfirmable: Bool,
        finalOutcome: RedemptionFinalOutcome? = nil
    ) {
        self.scopeDecision = scopeDecision
        self.credentialLooksOpaque = credentialLooksOpaque
        self.previewConfirmable = previewConfirmable
        self.canProceedToFinalConfirm = (scopeDecision == .allowed) && credentialLooksOpaque && previewConfirmable
        self.finalOutcome = finalOutcome
        switch finalOutcome {
        case .redeemed(let receiptID):
            self.finalReceiptID = receiptID
            self.isDuplicateRedemption = false
        case .alreadyRedeemed(let originalReceiptID):
            self.finalReceiptID = originalReceiptID
            self.isDuplicateRedemption = true
        case .rejected, .none:
            self.finalReceiptID = nil
            self.isDuplicateRedemption = false
        }
    }
}

/// Host evaluation of a sponsored reward pool item and issued voucher readback (W17 / S15–S18 / M11).
public struct SponsoredRewardHostProjection: Equatable, Sendable {
    public let itemID: String
    public let disclosure: SponsoredPoolItem.Disclosure
    public let isPresentable: Bool
    public let voucherReadbackAccepted: Bool
    public let bindingRefusal: SponsoredRewardBinding.Refusal?

    public init(
        itemID: String,
        disclosure: SponsoredPoolItem.Disclosure,
        isPresentable: Bool,
        voucherReadbackAccepted: Bool,
        bindingRefusal: SponsoredRewardBinding.Refusal?
    ) {
        self.itemID = itemID
        self.disclosure = disclosure
        self.isPresentable = isPresentable
        self.voucherReadbackAccepted = voucherReadbackAccepted
        self.bindingRefusal = bindingRefusal
    }
}

/// Reform plan v9 W06 / W07 / W17 host bridge uniting order-line lifecycle readback,
/// store-scoped staff redemption verification, and sponsored reward pool / voucher fences.
public enum CommerceOrderLifecycleBridge {
    /// Summarizes a `CommerceOrderReadback` into per-line fulfilment vs entitlement facts and refund guards.
    public static func summarizeOrder(_ readback: CommerceOrderReadback) -> CommerceOrderHostSnapshot {
        CommerceOrderHostSnapshot(readback: readback)
    }

    /// Enforces the monotonic order readback fence (frozen line snapshot, terminal tasks/refunds/entitlements).
    public static func acceptOrderReadback(current: CommerceOrderReadback, incoming: CommerceOrderReadback) -> Bool {
        CommerceOrderReadback.acceptsReadback(old: current, new: incoming)
    }

    /// Requires explicit user confirmation whenever server quote version or total minor amount changes (W06.3).
    public static func requiresQuoteConfirmation(
        quotedVersion: String,
        quotedTotalMinor: Int,
        serverVersion: String,
        serverTotalMinor: Int
    ) -> Bool {
        CommerceClientPaymentRules.quoteNeedsConfirmation(
            quotedVersion: quotedVersion,
            quotedTotalMinor: quotedTotalMinor,
            serverVersion: serverVersion,
            serverTotalMinor: serverTotalMinor
        )
    }

    /// Returning from a payment surface only schedules an order query; payment remains disabled client-side (W06.5).
    public static func actionOnPaymentReturn(orderID: String) -> CommerceClientPaymentRules.ReturnAction {
        CommerceClientPaymentRules.onPaymentSurfaceReturned(orderID: orderID)
    }

    /// Evaluates staff scope (merchant, store, version, validity, role prohibitions) alongside
    /// opaque credential format check and preview vs final redemption outcome split (W07.3 / W07.4).
    public static func evaluateRedemption(
        grant: MerchantStaffScopeGrant,
        merchantID: String,
        storeID: String,
        serverNow: Date,
        currentVersion: Int,
        scannedCredential: String,
        preview: RedemptionPreviewReadback,
        finalOutcome: RedemptionFinalOutcome? = nil
    ) -> StaffRedemptionHostEvaluation {
        let decision = MerchantStaffScopeCheck.decide(
            grant,
            permission: .verify,
            merchantID: merchantID,
            storeID: storeID,
            serverNow: serverNow,
            currentVersion: currentVersion
        )
        let opaque = RedemptionCredentialFormat.looksOpaque(scannedCredential)
        let confirmable = preview.confirmable(forStore: storeID, serverNow: serverNow)
        return StaffRedemptionHostEvaluation(
            scopeDecision: decision,
            credentialLooksOpaque: opaque,
            previewConfirmable: confirmable,
            finalOutcome: finalOutcome
        )
    }

    /// Projects a sponsored pool item's limited-quantity disclosure, capability gate, binding refusal,
    /// and frozen voucher terms readback protection (W17 / S15–S18 / M11).
    public static func evaluateSponsoredReward(
        item: SponsoredPoolItem,
        capabilities: SponsoredRewardCapabilities = .disabled,
        authorizedPledgeIDs: Set<String> = [],
        targetIsOfficialMap: Bool = false,
        issuedVoucher: SponsoredVoucherTerms? = nil,
        latestVoucher: SponsoredVoucherTerms? = nil
    ) -> SponsoredRewardHostProjection {
        let voucherOK: Bool
        if let issuedVoucher, let latestVoucher {
            voucherOK = SponsoredVoucherTerms.acceptsReadback(issued: issuedVoucher, later: latestVoucher)
        } else {
            voucherOK = true
        }
        let refusal = SponsoredRewardBinding.refusal(
            item: item,
            authorizedPledgeIDs: authorizedPledgeIDs,
            capabilities: capabilities,
            targetIsOfficialMap: targetIsOfficialMap
        )
        return SponsoredRewardHostProjection(
            itemID: item.itemID,
            disclosure: item.disclosure,
            isPresentable: item.isPresentable(capabilities),
            voucherReadbackAccepted: voucherOK,
            bindingRefusal: refusal
        )
    }
}
