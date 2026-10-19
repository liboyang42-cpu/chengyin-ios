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

/// Co-owners and administrators see the same contact route disabled; no wallet read and no payout path.
struct ClubOpsSettlementOwnerOnlyWithdraw: View {
    var body: some View {
        Section {
            Button {} label: { Text("club.ownerFunds.contact") }
                .disabled(true)
                .accessibilityIdentifier("clubOps.settlement.withdraw.ownerOnly")
            Text(LocalizedStringKey(ClubOpsWithdrawHint.ownerOnly.localizationKey), tableName: "ClubOpsCustomer").font(.footnote)
        }
    }
}

struct ClubOpsSettlementFootnote: View {
    var body: some View {
        Text("clubOps.settlement.footnote", tableName: "ClubOpsCustomer").font(.footnote).foregroundStyle(.secondary)
            .accessibilityIdentifier("clubOps.settlement.footnote")
    }
}
