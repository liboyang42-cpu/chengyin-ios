import SwiftUI
import UIKit

private struct WithdrawalSupportReaderKey: EnvironmentKey {
    static let defaultValue: WithdrawalSupportReader? = nil
}
extension EnvironmentValues {
    var withdrawalSupportReader: WithdrawalSupportReader? {
        get { self[WithdrawalSupportReaderKey.self] }
        set { self[WithdrawalSupportReaderKey.self] = newValue }
    }
}

@MainActor struct WithdrawalSupportContactView: View {
    @Environment(\.withdrawalSupportReader) private var reader
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var configuration: WithdrawalSupportSnapshot?
    @State private var loadedScope: WalletCommerceScope?
    @State private var issue: String?
    @State private var busy = false
    @State private var generation = UUID()
    var body: some View {
        NavigationStack {
            Form {
                Text("withdrawal.support.explanation")
                if busy { ProgressView("wallet.loading") }
                if let configuration, loadedScope == reader?.scope {
                    LabeledContent("withdrawal.support.weChat") { Text(verbatim: configuration.contact.weChatID) }
                    Button("withdrawal.support.copyWeChat") { Task { await copy(configuration) } }
                        .disabled(busy).accessibilityIdentifier("withdrawal.support.copyWeChat")
                    Text("withdrawal.support.manualContact")
                } else if !busy {
                    Label("withdrawal.support.unconfigured", systemImage: "exclamationmark.bubble")
                }
                if let issue { Text(LocalizedStringKey(issue)).accessibilityIdentifier("withdrawal.support.status") }
                Button("wallet.retry") { Task { await load() } }.disabled(busy)
            }.navigationTitle("withdrawal.support.contact")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("action.close") { clear(); dismiss() } } }
        }
        .task(id: reader?.scope) { clear(); await load() }
        .onChange(of: scenePhase) { _, phase in
            clear()
            if phase == .active { Task { await load() } }
        }
        .onDisappear { clear() }
        .presentationDetents([.medium, .large])
    }
    private func clear() {
        generation = UUID(); configuration = nil; loadedScope = nil; issue = nil; busy = false
    }
    private func load() async {
        clear(); let ticket = generation; let scope = reader?.scope; busy = true
        defer { if ticket == generation { busy = false } }
        do {
            guard let reader else { throw WithdrawalSupportFailure.unavailable }
            let value = try await reader.read()
            guard ticket == generation, scope == reader.scope, !Task.isCancelled else { return }
            configuration = value; loadedScope = scope
        } catch {
            guard ticket == generation, !Task.isCancelled else { return }
            issue = "withdrawal.support.unconfigured"
        }
    }
    private func copy(_ displayed: WithdrawalSupportSnapshot) async {
        guard !busy, let reader, loadedScope == reader.scope else { return }
        let ticket = generation; let scope = reader.scope; busy = true; issue = nil
        defer { if ticket == generation { busy = false } }
        do {
            let contact = try await reader.contactForCopy(displayed)
            guard ticket == generation, scope == reader.scope, !Task.isCancelled else { return }
            // Contact only: no balance, account ID, token, draft amount, or diagnostics.
            UIPasteboard.general.setItems([["public.utf8-plain-text": contact]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
            issue = "localCopy.copied"
            UIAccessibility.post(notification: .announcement, argument: appLocalized("localCopy.copied", locale: locale))
        } catch {
            guard ticket == generation, !Task.isCancelled else { return }
            configuration = nil; loadedScope = nil; issue = "withdrawal.support.unconfigured"
        }
    }
}
