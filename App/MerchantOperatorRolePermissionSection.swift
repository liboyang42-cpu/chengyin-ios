import SwiftUI

/// Used directly by the existing invite/change-role form. No reads or writes.
struct MerchantOperatorRolePermissionSection: View {
    let role: MerchantBusinessRecord
    private var presentation: MerchantOperatorRolePresentation? { try? .init(record: role) }

    var body: some View {
        Section("merchant.business.permissions") {
            if let presentation {
                if presentation.entries.isEmpty {
                    Text("merchant.operatorRole.empty").foregroundStyle(.secondary)
                        .accessibilityIdentifier("merchant.operatorRole.empty")
                } else {
                    ForEach(presentation.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(LocalizedStringKey(entry.titleKey)).font(.subheadline.bold())
                            Text(LocalizedStringKey(entry.detailKey)).font(.footnote).foregroundStyle(.secondary)
                            if entry.description == nil {
                                permissionCode(entry.code)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("merchant.operatorRole.permission." + entry.code)
                    }
                    DisclosureGroup("merchant.operatorRole.codes") {
                        ForEach(presentation.entries) { entry in permissionCode(entry.code) }
                    }.accessibilityIdentifier("merchant.operatorRole.codes")
                }
                Text("merchant.operatorRole.scope").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("merchant.operatorRole.unavailable").foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchant.operatorRole.unavailable")
            }
        }
        // A different selection must not retain a previous role's disclosure state.
        .id(role.id)
    }

    @ViewBuilder private func permissionCode(_ code: String) -> some View {
        if code.isEmpty { Text("merchant.operatorRole.emptyCode").font(.caption) }
        else { Text(verbatim: code).font(.caption.monospaced()).textSelection(.enabled) }
    }
}
