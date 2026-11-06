import SwiftUI

struct ClubOpsSettlementSummaryCard: View {
    let summary: ClubOpsSettlementSummary
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("clubOps.settlement.settledLabel", tableName: "ClubOpsCustomer").font(.subheadline).foregroundStyle(.secondary)
                Group {
                    if let amount = summary.settledAmountText { Text(verbatim: amount) }
                    else { Text("clubOps.settlement.amountUnverified", tableName: "ClubOpsCustomer") }
                }.font(.title.bold()).accessibilityIdentifier("club.gov.fact.settledAmountStatus")
                if summary.unverifiedSettledCount > 0 {
                    Text("clubOps.settlement.unverifiedCount \(summary.unverifiedSettledCount)", tableName: "ClubOpsCustomer")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Co-owners and administrators: no wallet read and no payout path. The mini-program shows a disabled
/// withdraw button plus 「仅主理人可发起提现」; native shows only the fact, never a dead button.
struct ClubOpsSettlementOwnerOnlyWithdraw: View {
    var body: some View {
        Section {
            Label { Text(LocalizedStringKey(ClubOpsWithdrawHint.ownerOnly.localizationKey), tableName: "ClubOpsCustomer") }
                icon: { Image(systemName: "lock") }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("clubOps.settlement.withdraw.ownerOnly")
        }
    }
}

struct ClubOpsSettlementFootnote: View {
    var body: some View {
        Text("clubOps.settlement.footnote", tableName: "ClubOpsCustomer").font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("clubOps.settlement.footnote")
    }
}
