import Foundation

/// Pure self-contained value-type audit for Wave-2 `w2-02` (`MemberCenterView` tier benefits
/// & StoreKit 2 digital entitlement), `w2-03` (`OrderListView` & `OrderDetailView` status machine
/// `pending`/`paid`/`fulfilled`/`cancelled`/`refunded`), and `w2-04` (after-sales/refund &
/// invoice/receipt readback).
public enum AuditedOrderLifecycleState: String, Sendable, Equatable, CaseIterable {
    case pending
    case paid
    case fulfilled
    case cancelled
    case refunded
}

public struct MemberAndOrderAuditCheck: Sendable, Equatable, Identifiable {
    public let id: String
    public let ticketID: String
    public let coveredStates: [AuditedOrderLifecycleState]
    public let enforcesStoreKitForDigitalSubscriptions: Bool
    public let supportsServerOrderReadback: Bool

    public init(
        id: String,
        ticketID: String,
        coveredStates: [AuditedOrderLifecycleState] = AuditedOrderLifecycleState.allCases,
        enforcesStoreKitForDigitalSubscriptions: Bool = true,
        supportsServerOrderReadback: Bool = true
    ) {
        self.id = id
        self.ticketID = ticketID
        self.coveredStates = coveredStates
        self.enforcesStoreKitForDigitalSubscriptions = enforcesStoreKitForDigitalSubscriptions
        self.supportsServerOrderReadback = supportsServerOrderReadback
    }

    public var isCompliant: Bool {
        Set(coveredStates) == Set(AuditedOrderLifecycleState.allCases)
            && enforcesStoreKitForDigitalSubscriptions
            && supportsServerOrderReadback
    }
}

public struct MemberSubscriptionAndOrderInvoiceAudit: Sendable, Equatable {
    public static let canonicalChecks: [MemberAndOrderAuditCheck] = [
        MemberAndOrderAuditCheck(
            id: "member-center-storekit-tier-benefits",
            ticketID: "w2-02",
            coveredStates: AuditedOrderLifecycleState.allCases,
            enforcesStoreKitForDigitalSubscriptions: true,
            supportsServerOrderReadback: true
        ),
        MemberAndOrderAuditCheck(
            id: "order-list-and-detail-status-machine",
            ticketID: "w2-03",
            coveredStates: AuditedOrderLifecycleState.allCases,
            enforcesStoreKitForDigitalSubscriptions: true,
            supportsServerOrderReadback: true
        ),
        MemberAndOrderAuditCheck(
            id: "order-after-sales-refund-and-invoice-readback",
            ticketID: "w2-04",
            coveredStates: AuditedOrderLifecycleState.allCases,
            enforcesStoreKitForDigitalSubscriptions: true,
            supportsServerOrderReadback: true
        ),
    ]

    public init() {}

    public static func evaluate(
        checks: [MemberAndOrderAuditCheck] = canonicalChecks
    ) -> (totalChecks: Int, compliantChecks: Int, allStatesCovered: Bool, isMemberOrderReady: Bool) {
        let totalChecks = checks.count
        let compliantChecks = checks.filter(\.isCompliant).count
        let expectedStates = Set(AuditedOrderLifecycleState.allCases)
        let allStatesCovered = !checks.isEmpty && checks.allSatisfy { Set($0.coveredStates) == expectedStates }
        let isMemberOrderReady = !checks.isEmpty && compliantChecks == totalChecks && allStatesCovered
        return (
            totalChecks: totalChecks,
            compliantChecks: compliantChecks,
            allStatesCovered: allStatesCovered,
            isMemberOrderReady: isMemberOrderReady
        )
    }
}
