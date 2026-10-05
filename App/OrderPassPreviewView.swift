import SwiftUI

/// The injected normal-app factory owns scoped issuance; default composition stays disabled.
@MainActor struct OrderPassPreviewView: View {
    let orderID: Int
    let coordinator: OrderLifecycleCoordinator
    @Environment(\.verificationCodeFactory) private var codeFactory
    var body: some View {
        Group {
            if let codeFactory {
                VerificationCodeView(model: codeFactory(.init(kind: .ticket, id: orderID)))
                    .id(coordinator.scope)
            } else {
                ContentUnavailableView {
                    Label("verificationCode.ticket.title", systemImage: "ticket").accessibilityIdentifier("orderLifecycle.pass.preview")
                } description: {
                    Text("verificationCode.phase.disabled").accessibilityIdentifier("verificationCode.disabled")
                }
            }
        }
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
