import SwiftUI

/// Observable UI adapter over the independently testable generation/scope guard.
@MainActor final class TicketWalletScreenModel<Value>: ObservableObject {
    @Published private var revision: UInt64 = 0
    private let state = TicketWalletReadModel<Value>()
    var isLoading: Bool { state.isLoading }
    var loadedScope: UUID? { state.loadedScope }
    func value(scope: UUID) -> Value? { state.visibleValue(scope: scope) }
    func issue(scope: UUID) -> TicketWalletIssue? { state.visibleIssue(scope: scope) }
    func invalidate() { state.invalidate(); revision &+= 1 }
    func cancelPending() { state.cancelPending(); revision &+= 1 }
    func load(scope: UUID, currentScope: () -> UUID, operation: () async throws -> Value) async {
        revision &+= 1
        await state.load(scope: scope, currentScope: currentScope, operation: operation)
        revision &+= 1
    }
}

struct TicketWalletLoadKey: Hashable {
    let scope: UUID
    let configured: Bool
    let authenticated: Bool
    let id: Int?
    @MainActor init(reader: any TicketWalletReading, id: Int? = nil) {
        scope = reader.scope; configured = reader.isConfigured; authenticated = reader.isAuthenticated; self.id = id
    }
}

struct TicketWalletIssueView: View {
    let issue: TicketWalletIssue
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                if case .server(let text) = issue { Text(verbatim: text) }
                else { Text(LocalizedStringKey(issue.localizationKey)) }
            } icon: { Image(systemName: issue == .login ? "lock" : "exclamationmark.triangle") }
            if let retry { Button("ticketWallet.retry", action: retry).accessibilityIdentifier("ticketWallet.retry") }
        }.padding(.vertical, 8)
    }
}

struct TicketWalletTitle: View {
    let title: String?
    var body: some View {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { Text(verbatim: title) }
        else { Text("ticketWallet.untitled") }
    }
}

struct TicketWalletOptionalField: View {
    let label: LocalizedStringKey
    let value: String?
    var body: some View {
        if let value, !value.isEmpty { LabeledContent(label) { Text(verbatim: value).textSelection(.enabled) } }
    }
}
