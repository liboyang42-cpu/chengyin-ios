import SwiftUI

/// Insert only inside ProfileReadScreen's accepted owned detail. Refresh and permission
/// retirement remain with that original reader/container; expanding makes no request.
@MainActor struct ProfileOrderRefundReadSection: View {
    let order: ProfileOrder
    let requestedID: Int
    let reader: any ProfileReading
    private var current: Bool {
        ProfileOrderRefundReadFacts.matchesAccount(requestedID: requestedID, recordID: order.id,
            memberID: order.memberID, identity: reader.identity, configured: reader.isConfigured)
    }
    private var facts: ProfileOrderRefundReadFacts {
        .init(amount: order.refundAmount, applicationCode: order.refundApplicationStatus,
              payoutCode: order.refundPayoutStatus, manualCase: order.manualRefundCaseStatus,
              deadline: order.refundDeadlineDisplay)
    }
    var body: some View {
        Section {
            if current {
                DisclosureGroup {
                    if !facts.hasReturnedFacts { Text("orderRefundRead.notProvided", tableName: "OrderRefundRead") }
                    LabeledContent {
                        if let amount = facts.amountText {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: amount).monospacedDigit()
                                Text("activity.currencyUnconfirmed").font(.caption)
                            }
                        } else { Text("orderRefundRead.amountUnknown", tableName: "OrderRefundRead") }
                    } label: { Text("profile.orders.refundAmount") }
                    LabeledContent {
                        Text(LocalizedStringKey(facts.payout.titleKey), tableName: "OrderRefundRead")
                    } label: { Text("orderRefundRead.payoutStatus", tableName: "OrderRefundRead") }
                    LabeledContent {
                        if let code = facts.applicationCode { Text(verbatim: String(code)).monospacedDigit() }
                        else { Text("profile.orders.unknown") }
                    } label: { Text("profile.orders.refundApplicationCode") }
                    LabeledContent {
                        if let code = facts.payoutCode { Text(verbatim: String(code)).monospacedDigit() }
                        else { Text("profile.orders.unknown") }
                    } label: { Text("profile.orders.refundCode") }
                    if let manualCase = facts.manualCase {
                        LabeledContent { Text(verbatim: manualCase) } label: { Text("profile.orders.manualRefund") }
                    }
                    if let deadline = facts.deadline {
                        LabeledContent { Text(verbatim: deadline) } label: { Text("profile.orders.refundDeadline") }
                    }
                    Text("orderRefundRead.caution", tableName: "OrderRefundRead").font(.footnote).foregroundStyle(.secondary)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("orderRefundRead.title", tableName: "OrderRefundRead")
                        if facts.hasReturnedFacts { Text(LocalizedStringKey(facts.payout.titleKey), tableName: "OrderRefundRead").font(.caption) }
                        else { Text("orderRefundRead.notProvided", tableName: "OrderRefundRead").font(.caption) }
                    }
                }.accessibilityIdentifier("profile.order.refundRead")
            } else {
                Text("profile.unavailable").accessibilityIdentifier("profile.order.refundRead.unavailable")
            }
        }
    }
}
