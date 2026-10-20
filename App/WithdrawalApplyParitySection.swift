import SwiftUI

/// Mini-program parity for subpackageMember/tixian: the platform does not pay out, so the
/// "withdrawal application" page only names the offline support method and opens the
/// existing reviewed support contact sheet. It sends nothing and collects no bank details.
struct WithdrawalApplyParitySection: View {
    @Binding var showContact: Bool
    var theme: WithdrawalThemeStyle = .member
    var roleGate: WithdrawalRoleGatePresentation = .allowed
    var body: some View {
        Section("withdrawal.apply.title") {
            if theme == .merchant {
                Text(verbatim: theme.badgeTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("withdrawal.apply.themeBadge")
            }
            LabeledContent("withdrawal.apply.method") { Text("withdrawal.apply.method.value") }
                .accessibilityIdentifier("withdrawal.apply.method")
            if let notice = roleGate.noticeText {
                Text(verbatim: notice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("withdrawal.apply.roleNotice")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("withdrawal.apply.note.title").font(.subheadline.weight(.semibold))
                Text("withdrawal.apply.note.detail").font(.footnote).foregroundStyle(.secondary)
            }.accessibilityElement(children: .combine).accessibilityIdentifier("withdrawal.apply.note")
            Button("withdrawal.apply.contact") { showContact = true }
                .buttonStyle(.borderedProminent)
                .disabled(roleGate == .denied)
                .accessibilityIdentifier("withdrawal.apply.contact")
        }
    }
}
