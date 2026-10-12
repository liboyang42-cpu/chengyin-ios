import SwiftUI

@MainActor final class MerchantPersonalIncomeSource: Identifiable {
    let id = UUID()
    let reader: any MerchantBusinessReading
    let scope: MerchantBusinessScope
    let authorization: UUID?
    let baseline: MerchantBusinessSnapshot
    let row: MerchantBusinessRecord
    private let currentSnapshot: () -> MerchantBusinessSnapshot?
    init?(row: MerchantBusinessRecord, reader: any MerchantBusinessReading, currentSnapshot: @escaping () -> MerchantBusinessSnapshot?) {
        guard reader.isConfigured, let scope = reader.scope, let baseline = currentSnapshot(),
              MerchantPersonalIncomeEligibility.matches(row: row, snapshot: baseline) else { return nil }
        self.reader = reader; self.scope = scope; authorization = reader.authorizationGeneration
        self.baseline = baseline; self.row = row; self.currentSnapshot = currentSnapshot
    }
    var current: Bool {
        reader.isConfigured && reader.scope == scope && reader.authorizationGeneration == authorization
            && currentSnapshot() == baseline
    }
    func revalidate() async throws {
        guard current else { throw MerchantBusinessFailure.stale }
        // Existing snapshot includes fresh merchant access and the owned detail read.
        let latest = try await reader.snapshot(baseline.document.query)
        try Task.checkCancellation()
        guard current, latest.access == baseline.access,
              MerchantPersonalIncomeEligibility.matches(row: row, snapshot: latest) else { throw MerchantBusinessFailure.stale }
    }
}

@MainActor final class MerchantPersonalIncomeGate: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var failed = false
    @Published private(set) var approved = false
    private var generation = UUID()
    private var approvedScope: WalletCommerceScope?
    private var approvedReader: ObjectIdentifier?
    func cancel() { generation = UUID(); busy = false; failed = false; approved = false; approvedScope = nil; approvedReader = nil }
    func permits(source: MerchantPersonalIncomeSource, wallet: WalletCommerceReader) -> Bool {
        approved && source.current && wallet.isConfigured && wallet.scope == approvedScope
            && ObjectIdentifier(wallet) == approvedReader && wallet.scope?.accountID == source.scope.accountID
    }
    func open(source: MerchantPersonalIncomeSource, currentWallet: @escaping () -> WalletCommerceReader) async {
        cancel(); let ticket = generation, wallet = currentWallet()
        guard source.current, wallet.isConfigured, let scope = wallet.scope, scope.accountID == source.scope.accountID else { failed = true; return }
        busy = true
        defer { if generation == ticket { busy = false } }
        do {
            try await source.revalidate()
            guard !Task.isCancelled, generation == ticket, source.current,
                  currentWallet() === wallet, wallet.isConfigured, wallet.scope == scope else { return }
            approvedScope = scope; approvedReader = ObjectIdentifier(wallet); approved = true
        } catch {
            guard !Task.isCancelled, generation == ticket else { return }
            failed = true
        }
    }
}

/// A retained pre-selection binding may adopt the first source once, never a later one.
@MainActor func merchantPersonalIncomePresentation(_ source: Binding<MerchantPersonalIncomeSource?>) -> Binding<MerchantPersonalIncomeSource?> {
    var captured = source.wrappedValue?.id
    return Binding(get: {
        guard let current = source.wrappedValue else { return nil }
        if captured == nil { captured = current.id }
        return current.id == captured ? current : nil
    }, set: { next in
        guard next == nil, let captured, source.wrappedValue?.id == captured else { return }
        source.wrappedValue = nil
    })
}

@MainActor struct MerchantPersonalIncomeEntry: View {
    let row: MerchantBusinessRecord
    let reader: any MerchantBusinessReading
    let currentSnapshot: () -> MerchantBusinessSnapshot?
    @Environment(\.merchantPersonalIncomeDestination) private var destination
    @Environment(\.scenePhase) private var scenePhase
    @State private var source: MerchantPersonalIncomeSource?
    private var presentation: Binding<MerchantPersonalIncomeSource?> {
        merchantPersonalIncomePresentation($source)
    }
    var body: some View {
        if let snapshot = currentSnapshot(), MerchantPersonalIncomeEligibility.matches(row: row, snapshot: snapshot), let destination {
            Button("merchant.personalIncome.open") {
                guard source == nil else { return }
                source = .init(row: row, reader: reader, currentSnapshot: currentSnapshot)
            }.accessibilityIdentifier("merchant.personalIncome.open")
            .sheet(item: presentation) { selected in
                NavigationStack {
                    destination(selected)
                        .toolbar { ToolbarItem(placement: .cancellationAction) {
                            Button("merchant.personalIncome.close") { if source?.id == selected.id { source = nil } }
                        } }
                }.presentationDetents([.medium, .large])
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { source = nil } }
            .onChange(of: reader.scope) { _, _ in source = nil }
            .onChange(of: reader.authorizationGeneration) { _, _ in source = nil }
        }
    }
}

@MainActor struct SessionMerchantPersonalIncomeView: View {
    @ObservedObject var session: AppSession
    let source: MerchantPersonalIncomeSource
    @StateObject private var gate = MerchantPersonalIncomeGate()
    @State private var showsFinance = false
    private var wallet: WalletCommerceReader { session.walletHistoryReader }
    private var sourceBelongsToSession: Bool { source.reader === session.merchantBusinessReader && source.current }
    var body: some View {
        Group {
            if !sourceBelongsToSession { Text("merchant.personalIncome.changed") }
            else if !wallet.isConfigured { Text("wallet.unavailable") }
            else if gate.permits(source: source, wallet: wallet) {
                VStack(spacing: 8) {
                    Text("merchant.personalIncome.boundary").font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                    WalletIncomeView(reader: wallet, onCooperationFinance: { showsFinance = true })
                        .id(wallet.scope)
                }
            } else if gate.busy { ProgressView("merchant.loading") }
            else {
                VStack(spacing: 12) {
                    Text("merchant.personalIncome.changed")
                    Button("merchant.personalIncome.retry") { Task { await open() } }
                }
            }
        }
        .appNavigationTitle("merchant.personalIncome.title")
        .task(id: session.walletHistoryViewIdentity) { await open() }
        .onDisappear { gate.cancel() }
        .navigationDestination(isPresented: $showsFinance) {
            if sourceBelongsToSession {
                CoopFlowReadView(reader: session.cooperationFlowReader, resource: .finance, title: "coopflow.finance")
            } else { Text("merchant.personalIncome.changed") }
        }
    }
    private func open() async {
        guard sourceBelongsToSession else { gate.cancel(); return }
        await gate.open(source: source, currentWallet: { session.walletHistoryReader })
    }
}

private struct MerchantPersonalIncomeDestinationKey: EnvironmentKey {
    static let defaultValue: ((MerchantPersonalIncomeSource) -> AnyView)? = nil
}
extension EnvironmentValues {
    var merchantPersonalIncomeDestination: ((MerchantPersonalIncomeSource) -> AnyView)? {
        get { self[MerchantPersonalIncomeDestinationKey.self] }
        set { self[MerchantPersonalIncomeDestinationKey.self] = newValue }
    }
}
