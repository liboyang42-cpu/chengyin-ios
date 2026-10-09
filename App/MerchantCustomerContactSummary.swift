import SwiftUI

/// Stateless: contact visibility is recomputed from the owning page's current snapshot.
/// This adds no phone, clipboard, export, or cleartext-request action.
struct MerchantCustomerContactSummary: View {
    let record: MerchantBusinessRecord
    let access: MerchantBusinessAccess
    var presentation: MerchantCustomerContactPresentation? { .init(record: record, access: access) }

    var body: some View {
        Group {
            switch presentation {
            case .maskedPhone(let phone):
                LabeledContent("merchant.customerContact.maskedPhone") {
                    Text(verbatim: phone).monospacedDigit()
                }.accessibilityIdentifier("merchant.customerContact.phone")
            case .reason(let reason):
                Text(verbatim: reason).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("merchant.customerContact.reason")
            case .unavailable:
                Text("merchant.customerContact.unavailable").foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("merchant.customerContact.unavailable")
            case nil:
                EmptyView()
            }
        }
        .font(.footnote)
        .privacySensitive()
    }
}
