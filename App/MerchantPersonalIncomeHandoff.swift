import SwiftUI

@MainActor protocol MerchantPersonalIncomeOrigin: AnyObject {
    var accountID: Int { get }
    var current: Bool { get }
    func revalidate(isCurrent: () -> Bool) async throws
}

@MainActor final class MerchantPersonalIncomeSource: ObservableObject, Identifiable, MerchantPersonalIncomeOrigin {
    let id = UUID()
    @Published private(set) var active = true
    let reader: any MerchantBusinessReading
    let scope: MerchantBusinessScope
    let authorization: UUID?
    let baseline: MerchantBusinessSnapshot
    var accountID: Int { scope.accountID }
    let row: MerchantBusinessRecord
    private let currentSnapshot: () -> MerchantBusinessSnapshot?
    init?(row: MerchantBusinessRecord, reader: any MerchantBusinessReading, currentSnapshot: @escaping () -> MerchantBusinessSnapshot?) {
        guard reader.isConfigured, let scope = reader.scope, let baseline = currentSnapshot(),
              MerchantPersonalIncomeEligibility.matches(row: row, snapshot: baseline) else { return nil }
        self.reader = reader; self.scope = scope; authorization = reader.authorizationGeneration
        self.baseline = baseline; self.row = row; self.currentSnapshot = currentSnapshot
    }
    var current: Bool {
        active && reader.isConfigured && reader.scope == scope && reader.authorizationGeneration == authorization
            && currentSnapshot() == baseline
    }
    func retire() { active = false }
    func revalidate() async throws { try await revalidate(isCurrent: { true }) }
    func revalidate(isCurrent: () -> Bool) async throws {
        guard isCurrent(), current else { throw MerchantBusinessFailure.stale }
        // Existing snapshot includes fresh merchant access and the owned detail read.
        let latest = try await reader.snapshot(baseline.document.query, isCurrent: { isCurrent() && current })
        try Task.checkCancellation()
        guard isCurrent(), current, latest.access == baseline.access,
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
    private var approvedOrigin: ObjectIdentifier?
    func cancel() { generation = UUID(); busy = false; failed = false; approved = false; approvedScope = nil; approvedReader = nil; approvedOrigin = nil }
    func permits(source: any MerchantPersonalIncomeOrigin, wallet: WalletCommerceReader) -> Bool {
        approved && approvedOrigin == ObjectIdentifier(source) && source.current && wallet.isConfigured && wallet.scope == approvedScope
            && ObjectIdentifier(wallet) == approvedReader && wallet.scope?.accountID == source.accountID
    }
    func open(source: any MerchantPersonalIncomeOrigin, currentWallet: @escaping () -> WalletCommerceReader, isCurrent: @escaping () -> Bool = { true }) async {
        cancel(); let ticket = generation, wallet = currentWallet()
        guard isCurrent(), source.current, wallet.isConfigured, let scope = wallet.scope, scope.accountID == source.accountID else { failed = true; return }
        busy = true
        defer { if generation == ticket { busy = false } }
        do {
            try await source.revalidate(isCurrent: {
                self.generation == ticket && isCurrent() && source.current && currentWallet() === wallet
                    && wallet.isConfigured && wallet.scope == scope
            })
            guard !Task.isCancelled, generation == ticket, isCurrent(), source.current,
                  currentWallet() === wallet, wallet.isConfigured, wallet.scope == scope else { return }
            approvedScope = scope; approvedReader = ObjectIdentifier(wallet); approvedOrigin = ObjectIdentifier(source); approved = true
        } catch {
            guard !Task.isCancelled, generation == ticket, isCurrent() else { return }
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
        guard next == nil, let captured, let selected = source.wrappedValue, selected.id == captured else { return }
        selected.retire(); source.wrappedValue = nil
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
                            Button("merchant.personalIncome.close") { close(selected) }
                        } }
                }.presentationDetents([.medium, .large])
                    .onDisappear { close(selected) }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active, let source { close(source) } }
            .onChange(of: reader.scope) { _, _ in if let source { close(source) } }
            .onChange(of: source?.current) { _, valid in if valid == false, let source { close(source) } }
            .onChange(of: reader.authorizationGeneration) { _, _ in if let source { close(source) } }
        }
    }
    private func close(_ selected: MerchantPersonalIncomeSource) {
        selected.retire(); if source?.id == selected.id { source = nil }
    }

}

@MainActor struct SessionMerchantPersonalIncomeView: View {
    @ObservedObject var session: AppSession
    @ObservedObject var source: MerchantPersonalIncomeSource
    @StateObject private var owner = MerchantLedgerAssetsReadOwner()
    @State private var showsFinance = false
    private var wallet: WalletCommerceReader { session.walletHistoryReader }
    private var sourceBelongsToSession: Bool { source.reader === session.merchantBusinessReader && source.current }
    var body: some View {
        Group {
            if !sourceBelongsToSession { Text("merchant.personalIncome.changed") }
            else if !wallet.isConfigured { Text("wallet.unavailable") }
            else if let restricted = owner.wallet, restricted.scope != nil {
                VStack(spacing: 8) {
                    Text("merchant.personalIncome.boundary").font(.footnote).foregroundStyle(.secondary).padding(.horizontal)
                    WalletIncomeView(reader: restricted, onCooperationFinance: { showsFinance = true })
                        .id(ObjectIdentifier(restricted))
                }
            } else if owner.busy { ProgressView("merchant.loading") }
            else {
                VStack(spacing: 12) {
                    Text("merchant.personalIncome.changed")
                    Button("merchant.personalIncome.retry") { Task { await open() } }
                }
            }
        }
        .appNavigationTitle("merchant.personalIncome.title")
        .task(id: session.walletHistoryViewIdentity) { await open() }
        .onChange(of: source.active) { _, active in if !active { owner.retire() } }
        .onChange(of: sourceBelongsToSession) { _, current in if !current { source.retire(); owner.retire() } }
        // The enclosing sheet owns retirement; income detail and finance pushes retain this lease.
        .navigationDestination(isPresented: $showsFinance) {
            if sourceBelongsToSession {
                CoopFlowReadView(reader: session.cooperationFlowReader, resource: .finance, title: "coopflow.finance")
            } else { Text("merchant.personalIncome.changed") }
        }
    }
    private func open() async {
        guard sourceBelongsToSession else { source.retire(); owner.retire(); return }
        await owner.open(source: source, currentWallet: { session.walletHistoryReader }, isCurrent: { sourceBelongsToSession })
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


/// The merchant aggregate may belong to an owner; personal assets always belong to this session's principal.
@MainActor final class MerchantLedgerAssetsSource: ObservableObject, Identifiable, MerchantPersonalIncomeOrigin {
    let id = UUID()
    let reader: any MerchantBusinessReading
    let scope: MerchantBusinessScope
    let authorization: UUID?
    let baseline: MerchantBusinessSnapshot
    @Published private(set) var active = true
    private let snapshot: () -> MerchantBusinessSnapshot?
    var accountID: Int { scope.accountID }
    init?(reader: any MerchantBusinessReading, currentSnapshot: @escaping () -> MerchantBusinessSnapshot?) {
        guard reader.isConfigured, let scope = reader.scope, let baseline = currentSnapshot(),
              MerchantPersonalIncomeEligibility.matchesLedgerOverview(baseline) else { return nil }
        self.reader = reader; self.scope = scope; authorization = reader.authorizationGeneration
        self.baseline = baseline; snapshot = currentSnapshot
    }
    var current: Bool {
        active && reader.isConfigured && reader.scope == scope && reader.authorizationGeneration == authorization && snapshot() == baseline
    }
    func retire() { active = false }
    func revalidate(isCurrent: () -> Bool) async throws {
        guard current, isCurrent() else { throw MerchantBusinessFailure.stale }
        let latest = try await reader.snapshot(.overview, isCurrent: { current && isCurrent() })
        guard !Task.isCancelled, current, isCurrent(), latest.access == baseline.access,
              MerchantPersonalIncomeEligibility.matchesLedgerOverview(latest) else { throw MerchantBusinessFailure.stale }
    }
}
@MainActor final class MerchantLedgerAssetsReadOwner: ObservableObject {
    @Published private(set) var wallet: WalletCommerceReader?
    @Published private(set) var busy = false
    @Published private(set) var failed = false
    private let gate = MerchantPersonalIncomeGate()
    private var generation = UUID()
    func retire() { generation = UUID(); gate.cancel(); wallet = nil; busy = false; failed = false }
    func open(source: any MerchantPersonalIncomeOrigin, currentWallet: @escaping () -> WalletCommerceReader,
              isCurrent: @escaping () -> Bool) async {
        retire(); let ticket = generation, original = currentWallet(), scope = original.scope
        guard source.current, isCurrent() else { return }
        busy = true
        await gate.open(source: source, currentWallet: currentWallet, isCurrent: { self.generation == ticket && isCurrent() })
        guard !Task.isCancelled, generation == ticket, isCurrent(), source.current else { if generation == ticket { retire() }; return }
        busy = false
        guard gate.permits(source: source, wallet: original), currentWallet() === original, original.scope == scope else { failed = true; return }
        let valid = { [weak self] in
            guard let self else { return false }
            return self.generation == ticket && source.current && isCurrent() && currentWallet() === original
                && original.scope == scope && self.gate.permits(source: source, wallet: original)
        }
        wallet = original.restrictedToPresentation(valid)
    }
}

@MainActor func merchantLedgerAssetsPresentation(_ binding: Binding<MerchantLedgerAssetsSource?>) -> Binding<MerchantLedgerAssetsSource?> {
    var captured = binding.wrappedValue?.id
    return Binding(get: {
        guard let source = binding.wrappedValue else { return nil }
        if captured == nil { captured = source.id }
        return source.id == captured ? source : nil
    }, set: { next in
        guard next == nil, let captured, let source = binding.wrappedValue, source.id == captured else { return }
        source.retire(); binding.wrappedValue = nil
    })
}
@MainActor struct MerchantLedgerAssetsEntry: View {
    let reader: any MerchantBusinessReading
    let currentSnapshot: () -> MerchantBusinessSnapshot?
    @Environment(\.merchantLedgerAssetsDestination) private var destination
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var source: MerchantLedgerAssetsSource?
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    var body: some View {
        if let snapshot = currentSnapshot(), MerchantPersonalIncomeEligibility.matchesLedgerOverview(snapshot), let destination {
            Button(zh ? "去我的资产" : "My personal earnings") {
                guard source == nil else { return }
                source = .init(reader: reader, currentSnapshot: currentSnapshot)
            }.accessibilityIdentifier("merchant.ledger.personalAssets")
            .sheet(item: merchantLedgerAssetsPresentation($source)) { selected in
                NavigationStack {
                    destination(selected)
                        .toolbar { ToolbarItem(placement: .cancellationAction) {
                            Button(zh ? "关闭" : "Close") { close(selected) }
                        } }
                }
                // This owner remains mounted during income/detail/history navigation.
                .onDisappear { close(selected) }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active, let source { close(source) } }
            .onChange(of: source?.current) { _, valid in if valid == false, let source { close(source) } }
            .onChange(of: reader.scope) { _, _ in if let source { close(source) } }
            .onChange(of: reader.authorizationGeneration) { _, _ in if let source { close(source) } }
        }
    }
    private func close(_ selected: MerchantLedgerAssetsSource) {
        selected.retire(); if source?.id == selected.id { source = nil }
    }
}
@MainActor struct SessionMerchantLedgerAssetsView: View {
    @ObservedObject var session: AppSession
    @ObservedObject var source: MerchantLedgerAssetsSource
    @StateObject private var owner = MerchantLedgerAssetsReadOwner()
    @Environment(\.locale) private var locale
    private var zh: Bool { locale.language.languageCode?.identifier == "zh" }
    private var current: Bool { source.current && source.reader === session.merchantBusinessReader }
    private var visibility: WalletCommerceVisibility {
        var value = WalletCommerceVisibility(); value.income = true; value.withdrawalRecords = true; return value
    }
    var body: some View {
        Group {
            if !current { Text("merchant.personalIncome.changed") }
            else if let wallet = owner.wallet, wallet.scope != nil {
                WalletCommerceHomeView(reader: wallet, visibility: visibility, onCooperationFinance: {},
                    showsWithdrawalSupport: false, showsCooperationFinance: false)
                    .id(ObjectIdentifier(wallet))
                    .environment(\.bankWithdrawalDestination, nil)
                    .environment(\.withdrawalSupportReader, nil)
            } else if owner.busy { ProgressView("merchant.loading") }
            else {
                VStack(spacing: 12) {
                    Text(zh ? "个人资产需独立读取授权，商家汇总不代表个人可用余额。" : "Personal earnings need their own read approval. Merchant totals are not your personal balance.")
                    Button("action.retry") { Task { await open() } }
                }
            }
        }
        .appNavigationTitle("merchant.personalIncome.title")
        .task(id: session.walletHistoryViewIdentity) { await open() }
        .onChange(of: source.active) { _, active in if !active { owner.retire() } }
        // Do not retire on a child push: the enclosing sheet owns final dismissal.
    }
    private func open() async {
        guard current else { owner.retire(); return }
        await owner.open(source: source, currentWallet: { session.walletHistoryReader }, isCurrent: { current })
    }
}
private struct MerchantLedgerAssetsDestinationKey: EnvironmentKey {
    static let defaultValue: ((MerchantLedgerAssetsSource) -> AnyView)? = nil
}
extension EnvironmentValues {
    var merchantLedgerAssetsDestination: ((MerchantLedgerAssetsSource) -> AnyView)? {
        get { self[MerchantLedgerAssetsDestinationKey.self] }
        set { self[MerchantLedgerAssetsDestinationKey.self] = newValue }
    }
}
