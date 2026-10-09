import SwiftUI

struct MerchantCityQuotaSummary: View {
    let quota: MerchantCityQuota
    var canRetry = false
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let used = quota.used, let maximum = quota.maximum {
                LabeledContent("merchant.content.quota", value: "\(used) / \(maximum)")
                    .accessibilityIdentifier("merchant.cityQuota.count")
            }
            switch quota.state {
            case .available: EmptyView()
            case .none:
                Text("merchant.cityQuota.none").foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchant.cityQuota.none")
            case .full:
                Text("merchant.cityQuota.full").foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchant.cityQuota.full")
            case .unknown:
                Text("merchant.cityQuota.unknown").foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchant.cityQuota.unknown")
                if let retry {
                    Button("merchant.cityQuota.retry", action: retry).disabled(!canRetry)
                        .accessibilityIdentifier("merchant.cityQuota.retry")
                }
            }
        }.font(.subheadline)
    }
}
