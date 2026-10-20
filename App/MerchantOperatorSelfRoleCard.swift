import SwiftUI

/// Mini-program pages/merchant/team non-admin card (index.wxml:109-114). Built only from the
/// current access/me projection: it performs no roster or role reads, carries no grant, and
/// "进入工作台" just returns to the workbench that pushed this page.
struct MerchantOperatorSelfRoleCard: View {
    @Environment(\.dismiss) private var dismiss
    let access: MerchantBusinessAccess
    static func isShown(for access: MerchantBusinessAccess) -> Bool { !access.canManageOperators }
    var body: some View {
        Section("merchant.operatorSelf.title") {
            Text(LocalizedStringKey("merchant.business.role." + access.role)).font(.headline)
                .accessibilityIdentifier("merchant.operatorSelf.role")
            Text("merchant.operatorSelf.copy").font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("merchant.operatorSelf.openWorkbench") { dismiss() }
                .accessibilityIdentifier("merchant.operatorSelf.openWorkbench")
        }
        .accessibilityIdentifier("merchant.operatorSelf.card")
    }
}
