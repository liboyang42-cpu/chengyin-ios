import Foundation

/// Reform plan v9 §11–13 / W06.3–W06.8. Read-only projection of an order by line: physical
/// fulfilment, theme entitlements and refunds are separate facts and never stand in for each
/// other. There is no create/pay/refund route here; payment stays disabled in the App.
public enum CommerceSKUKind: String, Sendable { case physical = "PHYSICAL", onsiteService = "ONSITE_SERVICE", booking = "BOOKING", digital = "DIGITAL", mixed = "MIXED" }
public enum CommerceFulfilmentMode: String, Sendable { case pickup = "PICKUP", onsiteService = "ONSITE_SERVICE", booking = "BOOKING", delivery = "DELIVERY" }

public struct CommerceFulfilmentTask: Equatable, Sendable {
    public enum State: String, Sendable {
        case ready = "READY", accepted = "ACCEPTED", inProgress = "IN_PROGRESS", fulfilled = "FULFILLED", blocked = "BLOCKED", cancelled = "CANCELLED"
        public var isTerminal: Bool { self == .fulfilled || self == .cancelled }
    }
    public let sequence: Int
    public let mode: CommerceFulfilmentMode
    public let quantity: Int
    public let state: State
    public init(sequence: Int, mode: CommerceFulfilmentMode, quantity: Int, state: State) {
        self.sequence = sequence; self.mode = mode; self.quantity = quantity; self.state = state
    }
}

/// Theme access granted by an approved rule. Never evidence of arrival, node completion or pickup.
public struct CommerceEntitlement: Equatable, Sendable {
    public enum State: String, Sendable { case active = "ACTIVE", consumed = "CONSUMED", revoked = "REVOKED", expired = "EXPIRED" }
    public let grantSequence: Int
    public let themeID: String
    public let releaseID: String?
    public let state: State
    public init(grantSequence: Int, themeID: String, releaseID: String?, state: State) {
        self.grantSequence = grantSequence; self.themeID = themeID; self.releaseID = releaseID; self.state = state
    }
}

public struct CommerceRefundRequest: Equatable, Sendable {
    public enum State: String, Sendable {
        case requested = "REQUESTED", approved = "APPROVED", submitted = "SUBMITTED", succeeded = "SUCCEEDED", failed = "FAILED", unknown = "UNKNOWN"
        /// UNKNOWN is not terminal: it is resolved by a server-side query, never by a client retry.
        public var isTerminal: Bool { self == .succeeded || self == .failed }
    }
    public let refundNo: String
    public let amountMinor: Int
    public let quantity: Int
    public let state: State
    public init(refundNo: String, amountMinor: Int, quantity: Int, state: State) {
        self.refundNo = refundNo; self.amountMinor = amountMinor; self.quantity = quantity; self.state = state
    }
}

/// Frozen order-line snapshot: later product or rule edits never change it.
public struct CommerceOrderLine: Equatable, Sendable {
    public let lineID: String
    public let skuID: String
    public let kind: CommerceSKUKind
    public let unitPriceMinor: Int
    public let quantity: Int
    public let currency: String
    public let fulfilment: [CommerceFulfilmentTask]
    public let entitlements: [CommerceEntitlement]
    public let refunds: [CommerceRefundRequest]
    public init(lineID: String, skuID: String, kind: CommerceSKUKind, unitPriceMinor: Int, quantity: Int, currency: String,
                fulfilment: [CommerceFulfilmentTask], entitlements: [CommerceEntitlement], refunds: [CommerceRefundRequest]) {
        self.lineID = lineID; self.skuID = skuID; self.kind = kind; self.unitPriceMinor = unitPriceMinor; self.quantity = quantity
        self.currency = currency; self.fulfilment = fulfilment; self.entitlements = entitlements; self.refunds = refunds
    }
    var isWellFormed: Bool {
        guard unitPriceMinor >= 0, quantity > 0, !currency.isEmpty,
              Set(fulfilment.map(\.sequence)).count == fulfilment.count,
              Set(entitlements.map(\.grantSequence)).count == entitlements.count,
              Set(refunds.map(\.refundNo)).count == refunds.count,
              fulfilment.allSatisfy({ $0.quantity > 0 }), refunds.allSatisfy({ $0.amountMinor >= 0 && $0.quantity >= 0 })
        else { return false }
        let succeeded = refunds.filter { $0.state == .succeeded }
        return fulfilment.map(\.quantity).reduce(0, +) <= quantity
            && succeeded.map(\.quantity).reduce(0, +) <= quantity
            && succeeded.map(\.amountMinor).reduce(0, +) <= unitPriceMinor * quantity
    }
}

public struct CommerceOrderReadback: Equatable, Sendable {
    /// Only the server's own payment record. A client payment-return page never produces `.paid`.
    public enum ServerPayment: String, Sendable { case unpaid = "UNPAID", paid = "PAID", paidUnfulfillable = "PAID_UNFULFILLABLE", unknown = "UNKNOWN" }
    public enum Projection: String, Sendable {
        case awaitingPayment, paymentUnknown, unfulfillable, awaitingFulfilment, partiallyFulfilled, fulfilled, blocked, refundInProgress, refundUnknown
    }
    public let orderID: String
    public let merchantID: String
    public let asOf: Date
    public let payment: ServerPayment
    public let lines: [CommerceOrderLine]
    public init?(orderID: String, merchantID: String, asOf: Date, payment: ServerPayment, lines: [CommerceOrderLine]) {
        guard !orderID.isEmpty, !merchantID.isEmpty, !lines.isEmpty, Set(lines.map(\.lineID)).count == lines.count,
              lines.allSatisfy(\.isWellFormed), Set(lines.map(\.currency)).count == 1 else { return nil }
        self.orderID = orderID; self.merchantID = merchantID; self.asOf = asOf; self.payment = payment; self.lines = lines
    }

    /// Whole-order status is a projection of lines (W06.6); entitlements are deliberately excluded.
    public var projection: Projection {
        switch payment {
        case .unpaid: return .awaitingPayment
        case .unknown: return .paymentUnknown
        case .paidUnfulfillable: return .unfulfillable
        case .paid: break
        }
        let refunds = lines.flatMap(\.refunds)
        if refunds.contains(where: { $0.state == .unknown }) { return .refundUnknown }
        if refunds.contains(where: { !$0.state.isTerminal }) { return .refundInProgress }
        let tasks = lines.flatMap(\.fulfilment).filter { $0.state != .cancelled }
        if tasks.contains(where: { $0.state == .blocked }) { return .blocked }
        let done = tasks.filter { $0.state == .fulfilled }.count
        if tasks.isEmpty || done == 0 { return .awaitingFulfilment }
        let fullyCovered = lines.allSatisfy { line in
            line.fulfilment.filter { $0.state == .fulfilled }.map(\.quantity).reduce(0, +) == line.quantity
        }
        return done == tasks.count && fullyCovered ? .fulfilled : .partiallyFulfilled
    }

    /// Fences a late or replayed readback: the snapshot of each line is frozen; succeeded refunds,
    /// fulfilled tasks and consumed/revoked entitlements never revert; asOf never goes back.
    public static func acceptsReadback(old: CommerceOrderReadback, new: CommerceOrderReadback) -> Bool {
        guard new.orderID == old.orderID, new.merchantID == old.merchantID, new.asOf >= old.asOf, new.lines.count == old.lines.count else { return false }
        if old.payment == .paid || old.payment == .paidUnfulfillable, new.payment == .unpaid { return false }
        for oldLine in old.lines {
            guard let line = new.lines.first(where: { $0.lineID == oldLine.lineID }),
                  line.skuID == oldLine.skuID, line.kind == oldLine.kind, line.unitPriceMinor == oldLine.unitPriceMinor,
                  line.quantity == oldLine.quantity, line.currency == oldLine.currency else { return false }
            for task in oldLine.fulfilment where task.state.isTerminal {
                guard line.fulfilment.first(where: { $0.sequence == task.sequence })?.state == task.state else { return false }
            }
            for refund in oldLine.refunds where refund.state.isTerminal {
                guard line.refunds.first(where: { $0.refundNo == refund.refundNo }) == refund else { return false }
            }
            for grant in oldLine.entitlements where grant.state != .active {
                guard line.entitlements.first(where: { $0.grantSequence == grant.grantSequence })?.state == grant.state else { return false }
            }
        }
        return true
    }
}

/// W06.3 / W06.5 client rules. Returning from any payment surface only schedules an order query;
/// a changed server quote must be shown for explicit confirmation, never silently accepted.
public enum CommerceClientPaymentRules {
    public enum ReturnAction: Equatable, Sendable { case queryOrder(orderID: String) }
    public static func onPaymentSurfaceReturned(orderID: String) -> ReturnAction { .queryOrder(orderID: orderID) }
    public static func quoteNeedsConfirmation(quotedVersion: String, quotedTotalMinor: Int, serverVersion: String, serverTotalMinor: Int) -> Bool {
        quotedVersion != serverVersion || quotedTotalMinor != serverTotalMinor
    }
    /// Payment and cash collection are not enabled in this client.
    public static let paymentEnabled = false
}
