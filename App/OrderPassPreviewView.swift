import SwiftUI

/// No credential input, QR rendering, remote image, scanner permission or issuance call.
@MainActor struct OrderPassPreviewView: View {
    let orderID: Int
    let coordinator: OrderLifecycleCoordinator
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "ticket").font(.largeTitle).accessibilityHidden(true)
                    Text("orderLifecycle.pass.noCode").font(.title2.bold())
                    if let detail = coordinator.detail, detail.id == orderID {
                        Text(LocalizedStringKey("orderLifecycle.pass." + OrderPassAvailability(detail: detail).rawValue))
                    } else { Text("orderLifecycle.issue.stale") }
                    Text("orderLifecycle.pass.serverAuthority").font(.footnote).foregroundStyle(.secondary)
                }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
            }
            Section("orderLifecycle.pass.verification") {
                Text("orderLifecycle.pass.verificationHint")
                Text("orderLifecycle.hardOff").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .appNavigationTitle("orderLifecycle.pass.title")
        .accessibilityIdentifier("orderLifecycle.pass.preview")
    }
}

/// Receipt preview preserves chapter/station choice without treating it as success.
/// This screen accepts metadata only; selection cannot consume an entitlement.
struct OrderVerificationPreviewView: View {
    let receipt: OrderVerificationReceipt
    @State private var selected: Int?
    var body: some View {
        List {
            Section {
                Text("orderLifecycle.verification.preview").font(.headline)
                Text(LocalizedStringKey("orderLifecycle.verification." + receipt.outcome.rawValue))
                    .accessibilityIdentifier("orderLifecycle.verification.outcome")
                if let message = receipt.message, !message.isEmpty { Text(verbatim: message) }
            }
            if receipt.outcome == .needsChoice {
                Section(receipt.choiceKind == .station ? "orderLifecycle.verification.stations" : "orderLifecycle.verification.chapters") {
                    if receipt.choices.isEmpty { Text("orderLifecycle.verification.emptyChoice") }
                    ForEach(receipt.choices) { choice in
                        Button {
                            guard receipt.containsChoice(choice.id) else { return }
                            selected = choice.id
                        } label: {
                            HStack {
                                if let name = choice.name, !name.isEmpty { Text(verbatim: name) }
                                else { Text(verbatim: "#\(choice.id)") }
                                Spacer(minLength: 8)
                                if selected == choice.id { Image(systemName: "checkmark").accessibilityHidden(true) }
                            }.fixedSize(horizontal: false, vertical: true)
                        }.accessibilityAddTraits(selected == choice.id ? [.isSelected] : [])
                            .accessibilityIdentifier("orderLifecycle.verification.choice.\(choice.id)")
                    }
                }
            }
            Section {
                Text("orderLifecycle.verification.role")
                Text("orderLifecycle.hardOff").font(.footnote).foregroundStyle(.secondary)
                Button("orderLifecycle.verification.disabled", action: {}).disabled(true)
                    .accessibilityIdentifier("orderLifecycle.verification.disabled")
            }
        }.appNavigationTitle("orderLifecycle.pass.verification")
    }
}
