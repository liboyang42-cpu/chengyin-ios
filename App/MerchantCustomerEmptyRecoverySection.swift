import SwiftUI

/// Current-page presentation only; the parent rechecks the exact snapshot and
/// unsubmitted-filter state before invoking its existing read-only load path.
struct MerchantCustomerEmptyRecoverySection: View {
    let recovery: MerchantCustomerEmptyRecovery
    let canApply: Bool
    let hasUnsubmittedFilters: Bool
    let apply: () -> Void
    var body: some View {
        Section {
            Text(LocalizedStringKey("merchant.customerEmpty." + recovery.kind.rawValue + ".title"))
                .font(.headline).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("merchant.customerEmpty." + recovery.kind.rawValue)
            Text(LocalizedStringKey("merchant.customerEmpty." + recovery.kind.rawValue + ".hint"))
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let action = recovery.action {
                Button(LocalizedStringKey("merchant.customerEmpty.action." + action.rawValue), action: apply)
                    .disabled(!canApply)
                    .accessibilityIdentifier("merchant.customerEmpty.action." + action.rawValue)
                if hasUnsubmittedFilters {
                    Text("merchant.customerEmpty.applyDraftFirst").font(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
