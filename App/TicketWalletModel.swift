import SwiftUI

/// Observable adapter owns queued tasks; the Core model also checks the captured presentation
/// before dispatch and receipt, including async refresh operations owned by SwiftUI.
@MainActor final class TicketWalletScreenModel<Value>: ObservableObject {
    @Published private var revision: UInt64 = 0
    private let state = TicketWalletReadModel<Value>()
    private var task: Task<Void, Never>?
    var isLoading: Bool { state.isLoading }
    var loadedScope: UUID? { state.loadedScope }
    var loadedOwner: TicketWalletReadOwner? { state.loadedOwner }
    var presentation: TicketWalletReadPresentation? { state.presentation }
    func value(owner: TicketWalletReadOwner) -> Value? { state.visibleValue(owner: owner) }
    func issue(owner: TicketWalletReadOwner) -> TicketWalletIssue? { state.visibleIssue(owner: owner) }
    func invalidate() { state.invalidate(); revision &+= 1 }
    func beginPresentation(owner: TicketWalletReadOwner) -> TicketWalletReadPresentation? {
        task?.cancel(); task = nil
        let permit = state.beginPresentation(owner: owner); revision &+= 1
        return permit
    }
    func endPresentation(preservingValues: Bool = true) {
        task?.cancel(); task = nil
        state.endPresentation(preservingValues: preservingValues); revision &+= 1
    }
    func accepts(_ permit: TicketWalletReadPresentation, currentOwner: TicketWalletReadOwner) -> Bool {
        state.accepts(permit, currentOwner: currentOwner)
    }
    @discardableResult func schedule(presentation: TicketWalletReadPresentation?, currentOwner: TicketWalletReadOwner,
                  operation: @escaping @MainActor (TicketWalletReadPresentation) async -> Void) -> Task<Void, Never>? {
        guard let presentation, accepts(presentation, currentOwner: currentOwner) else { return nil }
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard !Task.isCancelled, let self, self.accepts(presentation, currentOwner: currentOwner) else { return }
            await operation(presentation)
        }
        return task
    }
    func refresh(presentation: TicketWalletReadPresentation?, currentOwner: TicketWalletReadOwner,
                 operation: @escaping @MainActor (TicketWalletReadPresentation) async -> Void) async {
        guard let pending = schedule(presentation: presentation, currentOwner: currentOwner, operation: operation) else { return }
        await withTaskCancellationHandler { await pending.value } onCancel: { pending.cancel() }
    }
    func load(presentation: TicketWalletReadPresentation, currentOwner: () -> TicketWalletReadOwner,
              operation: () async throws -> Value) async {
        guard !Task.isCancelled, accepts(presentation, currentOwner: currentOwner()) else { return }
        revision &+= 1
        await state.load(presentation: presentation, currentOwner: currentOwner, operation: operation)
        revision &+= 1
    }
}

typealias TicketWalletLoadKey = TicketWalletReadOwner

struct TicketWalletIssueView: View {
    let issue: TicketWalletIssue
    var retry: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                if case .server(let text) = issue { Text(verbatim: text) }
                else { Text(LocalizedStringKey(issue.localizationKey)) }
            } icon: { Image(systemName: issue == .login ? "lock" : "exclamationmark.triangle") }
            if let retry {
                Button("ticketWallet.retry", action: retry)
                    .buttonStyle(.bordered).controlSize(.large)
                    .accessibilityIdentifier("ticketWallet.retry")
            }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        if let value, !value.isEmpty {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label).foregroundStyle(.secondary)
                    Text(verbatim: value).textSelection(.enabled)
                }.fixedSize(horizontal: false, vertical: true)
            } else {
                LabeledContent(label) { Text(verbatim: value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}
