import SwiftUI

/// No independent cache or action: lifecycle and access belong to the current authorized detail host.
struct MerchantRedemptionProgressView: View {
    let progress: MerchantRedemptionProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("merchant.redemptionProgress.title").font(.headline)
            ForEach(progress.steps) { step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: step.state == .done ? "checkmark.circle.fill" : step.state == .current ? "circle.inset.filled" : "circle")
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey("merchant.redemptionProgress.step." + step.id))
                        Text(LocalizedStringKey("merchant.settlementProgress.stepState." + step.state.rawValue)).font(.caption)
                        if let raw = step.timestamp { MerchantSettlementTimestampText(raw: raw).font(.caption).foregroundStyle(.secondary) }
                    }
                }.fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("merchant.redemptionProgress.step." + step.id)
            }
        }.accessibilityIdentifier("merchant.redemptionProgress")
    }
}
