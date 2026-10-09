import SwiftUI

struct MerchantInsightProfileSummary: View {
    let profile: MerchantMarketingValue
    let origin: MerchantInsightOrigin?
    let open: (MerchantInsightOrigin) -> Void
    var configurationState: Bool? {
        if case .bool(let value) = profile["configured"] { return value }; return nil
    }
    var capacity: Int? {
        guard case .number = profile["capacity"], let value = profile["capacity"].integer,
              (0...9_007_199_254_740_991).contains(value) else { return nil }; return value
    }
    var demand: String? {
        guard case .string(let value) = profile["demand"], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
    var canOpen: Bool { configurationState != nil && origin != nil }
    var body: some View {
        Section("merchant.insightProfile.title") {
            if let configured = configurationState {
                Text(LocalizedStringKey(configured ? "merchant.insightProfile.configured" : "merchant.insightProfile.notConfigured"))
                    .accessibilityIdentifier("merchant.insightProfile.state")
            } else {
                Text("merchant.insightProfile.unknown").foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchant.insightProfile.unknown")
            }
            if let capacity { LabeledContent("merchant.operations.capacity", value: String(capacity)) }
            if let demand { LabeledContent("merchant.operations.demand", value: demand) }
            if canOpen, let origin {
                Button(LocalizedStringKey(configurationState == true ? "merchant.insightProfile.edit" : "merchant.insightProfile.configure")) { open(origin) }
                    .accessibilityIdentifier("merchant.insightProfile.open")
            } else {
                Text("merchant.insightProfile.unavailable").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
