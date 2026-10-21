import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one member subscription, order lifecycle, or refund/receipt readback pillar.
public struct MemberOrderAuditRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let scopeCode: String
    public let title: String
    public let policyDetail: String
    public let isCompliant: Bool
    public let liveChargeEnabled: Bool

    public init(
        id: String,
        scopeCode: String,
        title: String,
        policyDetail: String,
        isCompliant: Bool = true,
        liveChargeEnabled: Bool = false
    ) {
        self.id = id
        self.scopeCode = scopeCode
        self.title = title
        self.policyDetail = policyDetail
        self.isCompliant = isCompliant
        self.liveChargeEnabled = liveChargeEnabled
    }

    public var statusBadgeText: String {
        if isCompliant && !liveChargeEnabled {
            return "COMPLIANT • FAIL-CLOSED"
        }
        return "WARNING • REVIEW REQUIRED"
    }
}

/// Self-contained presentation snapshot for:
/// 1. `w2-02` member subscription & StoreKit 2 compliance
/// 2. `w2-03` 5-state order lifecycle (`pending`/`paid`/`fulfilled`/`cancelled`/`refunded`)
/// 3. `w2-04` refund/receipt readback
public struct MemberSubscriptionAndOrderSnapshot: Sendable, Equatable {
    public static let fiveOrderLifecycleStates: [String] = [
        "pending",
        "paid",
        "fulfilled",
        "cancelled",
        "refunded"
    ]

    public let rows: [MemberOrderAuditRow]
    public let supportedOrderStates: [String]
    public let storeKit2GateFailClosed: Bool
    public let refundReceiptReadbackRequired: Bool

    public init(
        rows: [MemberOrderAuditRow] = Self.defaultRows,
        supportedOrderStates: [String] = Self.fiveOrderLifecycleStates,
        storeKit2GateFailClosed: Bool = true,
        refundReceiptReadbackRequired: Bool = true
    ) {
        self.rows = rows
        self.supportedOrderStates = supportedOrderStates
        self.storeKit2GateFailClosed = storeKit2GateFailClosed
        self.refundReceiptReadbackRequired = refundReceiptReadbackRequired
    }

    public static let defaultRows: [MemberOrderAuditRow] = [
        MemberOrderAuditRow(
            id: "w2-02",
            scopeCode: "w2-02",
            title: "Member Subscription & StoreKit 2 Compliance",
            policyDetail: "Reads server membership tier and StoreKit 2 entitlement boundary; external payment links and unverified live charges stay OFF",
            isCompliant: true,
            liveChargeEnabled: false
        ),
        MemberOrderAuditRow(
            id: "w2-03",
            scopeCode: "w2-03",
            title: "5-State Order Lifecycle State Machine",
            policyDetail: "Enforces canonical transitions across pending, paid, fulfilled, cancelled, and refunded without client-synthesized payment completion",
            isCompliant: true,
            liveChargeEnabled: false
        ),
        MemberOrderAuditRow(
            id: "w2-04",
            scopeCode: "w2-04",
            title: "Authoritative Refund & Invoice Receipt Readback",
            policyDetail: "Uncertain refund or cancellation requests lock the order until fresh server receipt and points-return readback confirm settlement",
            isCompliant: true,
            liveChargeEnabled: false
        )
    ]

    public static let defaultReady = MemberSubscriptionAndOrderSnapshot()

    public var isAllCompliant: Bool {
        rows.count == 3 &&
        supportedOrderStates == Self.fiveOrderLifecycleStates &&
        storeKit2GateFailClosed &&
        refundReceiptReadbackRequired &&
        rows.allSatisfy { $0.isCompliant && !$0.liveChargeEnabled }
    }
}

/// SwiftUI Section View displaying `w2-02` member subscription & StoreKit 2 compliance,
/// `w2-03` 5-state order lifecycle, and `w2-04` refund/receipt readback using `Text(verbatim:)` throughout.
@MainActor
public struct MemberSubscriptionAndOrderInvoiceSectionView: View {
    public let snapshot: MemberSubscriptionAndOrderSnapshot

    public init(snapshot: MemberSubscriptionAndOrderSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var statusBadgeText: String {
        snapshot.isAllCompliant
            ? "Subscription & Order Gate: READY (3/3 Compliant)"
            : "Subscription & Order Gate: WARNING (Non-Compliant State)"
    }

    public var subscriptionSummaryText: String {
        snapshot.storeKit2GateFailClosed
            ? "w2-02 StoreKit 2 & Subscription Gate: FAIL-CLOSED (No unapproved external charge)"
            : "w2-02 StoreKit 2 & Subscription Gate: WARNING — unverified charge path enabled"
    }

    public var lifecycleStatesSummaryText: String {
        "w2-03 Order Lifecycle (\(snapshot.supportedOrderStates.count) states): " +
            snapshot.supportedOrderStates.joined(separator: " → ")
    }

    public var refundReceiptSummaryText: String {
        snapshot.refundReceiptReadbackRequired
            ? "w2-04 Refund & Invoice Readback: ENFORCED (UNKNOWN outcomes stay locked until server receipt)"
            : "w2-04 Refund & Invoice Readback: WARNING — readback lock bypassed"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Member Subscription, 5-State Order & Refund Readback")
                    .font(.headline)
                    .accessibilityIdentifier("memberSubscriptionOrder.title")
                Spacer()
                Text(verbatim: statusBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isAllCompliant ? Color.green : Color.orange)
                    .accessibilityIdentifier("memberSubscriptionOrder.statusBadge")
            }

            Text(verbatim: subscriptionSummaryText)
                .font(.footnote)
                .foregroundStyle(snapshot.storeKit2GateFailClosed ? Color.secondary : Color.red)
                .accessibilityIdentifier("memberSubscriptionOrder.subscriptionSummary")

            Text(verbatim: lifecycleStatesSummaryText)
                .font(.footnote.monospaced())
                .foregroundStyle(
                    snapshot.supportedOrderStates == MemberSubscriptionAndOrderSnapshot.fiveOrderLifecycleStates
                        ? Color.secondary
                        : Color.orange
                )
                .accessibilityIdentifier("memberSubscriptionOrder.lifecycleStatesSummary")

            Text(verbatim: refundReceiptSummaryText)
                .font(.footnote)
                .foregroundStyle(snapshot.refundReceiptReadbackRequired ? Color.secondary : Color.red)
                .accessibilityIdentifier("memberSubscriptionOrder.refundReceiptSummary")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "[\(row.scopeCode)] \(row.title)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: row.statusBadgeText)
                                .font(.caption2.monospaced())
                                .foregroundStyle((row.isCompliant && !row.liveChargeEnabled) ? Color.green : Color.orange)
                        }
                        Text(verbatim: row.policyDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .accessibilityIdentifier("memberSubscriptionOrder.rowList")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("memberSubscriptionOrder.section")
    }
}
