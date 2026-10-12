import SwiftUI

struct MerchantLedgerNetSummary: View {
    let presentation: MerchantLedgerNetPresentation
    var body: some View {
        LabeledContent {
            if let amount = presentation.amount { Text(verbatim: amount).monospacedDigit() }
            else { Text("merchant.business.amountPending").foregroundStyle(.secondary) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("merchant.business.field.personalArrivedThisMonthNet")
                Text(LocalizedStringKey(presentation.titleKey)).font(.caption).foregroundStyle(.secondary)
            }
        }.font(.subheadline)
    }
}
