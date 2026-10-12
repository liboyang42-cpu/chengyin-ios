import SwiftUI

struct ClubOwnerFundsContext {
    var reader: (any ClubOwnerFundsReading)? = nil
    var isCurrent: () -> Bool = { false }
    var support: (() -> AnyView)? = nil
}
private struct ClubOwnerFundsKey: EnvironmentKey {
    static let defaultValue = ClubOwnerFundsContext()
}
extension EnvironmentValues {
    var clubOwnerFunds: ClubOwnerFundsContext {
        get { self[ClubOwnerFundsKey.self] }
        set { self[ClubOwnerFundsKey.self] = newValue }
    }
}
@MainActor extension AppSession {
    func clubOwnerFundsContext() -> ClubOwnerFundsContext {
        let reader = walletHistoryReader, supportReader = withdrawalSupportReader
        let identity = clubIdentity, revision = walletHistoryViewIdentity
        return .init(reader: reader, isCurrent: { [weak self, weak reader] in
            guard let self, let reader else { return false }
            return self.clubIdentity == identity && self.walletHistoryViewIdentity == revision &&
                self.walletHistoryReader === reader
        }, support: {
            AnyView(WithdrawalSupportContactView().environment(\.withdrawalSupportReader, supportReader))
        })
    }
}

@MainActor final class ClubOwnerFundsWorkflow: ObservableObject {
    @Published private(set) var funds: WalletFundsStages?
    @Published private(set) var loadedScope: WalletCommerceScope?
    @Published private(set) var loading = false
    @Published private(set) var failure: String?
    @Published private(set) var contactPresented = false
    private var generation: UInt64 = 0
    private var liveCheck: (() -> Bool)?
    var revision: UInt64 { generation }
    var availability: ClubOwnerFundsAvailability { .init(funds) }
    var contactIsCurrent: Bool { contactPresented && liveCheck?() == true }

    func load(target: ClubOwnerFundsTarget, access: any ClubGovernanceAccess,
              context: ClubOwnerFundsContext, sourceIsCurrent: @escaping () -> Bool, expectedGeneration: UInt64? = nil) async {
        guard expectedGeneration == nil || expectedGeneration == generation, !loading else { return }
        generation &+= 1; let ticket = generation
        funds = nil; loadedScope = nil; failure = nil; liveCheck = nil; contactPresented = false; loading = true
        do {
            guard let reader = context.reader, reader.isConfigured, let scope = reader.scope,
                  scope.accountID == target.context.identity?.accountID,
                  !scope.namespace.isEmpty, scope.namespace == access.storageNamespace else { throw WalletCommerceSafetyError.unavailable }
            let check: () throws -> Void = { [weak self] in
                guard let self, self.generation == ticket, !Task.isCancelled, sourceIsCurrent(), context.isCurrent(),
                      access.isConfigured, access.identity == target.context.identity,
                      access.authorizationGeneration == target.context.authorizationGeneration,
                      target.context.accessIdentity == ObjectIdentifier(access),
                      access.storageNamespace == scope.namespace, reader.isConfigured, reader.scope == scope else {
                    throw ClubGovernanceFailure.targetChanged
                }
            }
            try check()
            let before = try await access.read(.settlement, scope: target.context.scope, options: [:], check: check)
            try check(); guard target.accepts(before) else { throw ClubGovernanceFailure.forbidden }
            let value = try await reader.readClubOwnerFunds()
            try check()
            // Ownership/finance access can change while the wallet request is in flight.
            let after = try await access.read(.settlement, scope: target.context.scope, options: [:], check: check)
            try check(); guard target.accepts(after) else { throw ClubGovernanceFailure.forbidden }
            funds = value; loadedScope = scope; loading = false
            liveCheck = { (try? check()) != nil }
        } catch {
            guard generation == ticket else { return }
            funds = nil; loadedScope = nil; contactPresented = false; loading = false; liveCheck = nil
            if let error = error as? ClubGovernanceFailure { failure = error.localizationKey }
            else if (error as? WalletCommerceSafetyError) == .unavailable { failure = "wallet.unavailable" }
            else { failure = "wallet.failed" }
        }
    }
    func openContact(target: ClubOwnerFundsTarget, access: any ClubGovernanceAccess,
                     context: ClubOwnerFundsContext, sourceIsCurrent: @escaping () -> Bool, expectedGeneration: UInt64? = nil) async {
        guard expectedGeneration == nil || expectedGeneration == generation,
              !loading, target.hasSettlementRows, availability == .positive, context.support != nil else { return }
        // The displayed amount cannot authorize even a contact route: read it again.
        await load(target: target, access: access, context: context, sourceIsCurrent: sourceIsCurrent)
        guard availability == .positive, liveCheck?() == true else { return }
        contactPresented = true
    }
    func closeContact() { contactPresented = false }
    func invalidate() {
        generation &+= 1; funds = nil; loadedScope = nil; failure = nil
        contactPresented = false; loading = false; liveCheck = nil
    }
}

struct ClubOwnerFundsReadKey: Hashable {
    let context: ClubGovernanceReadContext
    let reader: ObjectIdentifier?
    let scope: WalletCommerceScope?
    let sourceGeneration: UInt64
    let current: Bool
}
struct ClubOwnerFundsSection: View {
    let target: ClubOwnerFundsTarget
    let access: any ClubGovernanceAccess
    let context: ClubOwnerFundsContext
    let sourceGeneration: UInt64
    let sourceIsCurrent: () -> Bool
    @StateObject private var workflow = ClubOwnerFundsWorkflow()
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    private var current: Bool {
        scenePhase == .active && sourceIsCurrent() && context.isCurrent() && access.identity == target.context.identity &&
        access.authorizationGeneration == target.context.authorizationGeneration &&
        target.context.accessIdentity == ObjectIdentifier(access)
    }
    private var key: ClubOwnerFundsReadKey {
        .init(context: target.context, reader: context.reader.map { ObjectIdentifier($0) },
              scope: context.reader?.scope, sourceGeneration: sourceGeneration, current: current)
    }
    var body: some View {
        Section("club.ownerFunds.title") {
            Text("club.ownerFunds.accountScope").font(.footnote).foregroundStyle(.secondary)
            if workflow.loading { ProgressView("wallet.loading") }
            if current, let value = workflow.funds, workflow.loadedScope == context.reader?.scope {
                if !value.amountsKnown { Text("wallet.amountsUnknown") }
                if value.pendingSettlement.value > 0 { LabeledContent("wallet.pendingSettlement", value: amount(value.pendingSettlement, currency: value.currency)) }
                ForEach(Array(value.complaintPeriod.enumerated()), id: \.offset) { _, item in
                    LabeledContent { Text(verbatim: amount(item.amount, currency: value.currency)) } label: {
                        Text("wallet.complaintPeriod"); Text(verbatim: item.availableDate)
                    }
                }
                if value.disputed.value > 0 { LabeledContent("wallet.disputed", value: amount(value.disputed, currency: value.currency)) }
                if value.amountsKnown { LabeledContent("wallet.available", value: amount(value.withdrawable, currency: value.currency)) }
                else { LabeledContent("wallet.available") { Text("wallet.unknown") } }
            }
            if let key = workflow.failure { Text(LocalizedStringKey(key)).accessibilityIdentifier("club.ownerFunds.error") }
            if target.hasSettlementRows {
            Text(LocalizedStringKey(workflow.availability == .zero ? "club.ownerFunds.zero" : workflow.availability == .unknown ? "club.ownerFunds.unknown" : "club.ownerFunds.manual"))
                .font(.footnote)
            Button("club.ownerFunds.contact") {
                let revision = workflow.revision
                Task { await workflow.openContact(target: target, access: access, context: context, sourceIsCurrent: sourceIsCurrent, expectedGeneration: revision) }
            }.disabled(!current || workflow.loading || workflow.availability != .positive || context.support == nil)
                .accessibilityIdentifier("club.ownerFunds.contact")
            }
            Button("wallet.retry") {
                let revision = workflow.revision
                Task { await load(expectedGeneration: revision) }
            }.disabled(workflow.loading || !current)
                .accessibilityIdentifier("club.ownerFunds.retry")
        }
        .task(id: key) { workflow.invalidate(); if current { await load() } }
        .sheet(isPresented: Binding(get: { workflow.contactPresented }, set: { if !$0 { workflow.closeContact() } }), onDismiss: {
            workflow.invalidate()
            if current { let revision = workflow.revision; Task { await load(expectedGeneration: revision) } }
        }) {
            Group {
                if current, workflow.contactIsCurrent, let support = context.support { support() }
                else { Text("club.gov.changed") }
            }
            .onChange(of: key, initial: true) { _, _ in if !current || !workflow.contactIsCurrent { workflow.invalidate() } }
        }
        .onChange(of: current) { _, valid in if !valid { workflow.invalidate() } }
        .onChange(of: scenePhase) { _, phase in
            workflow.invalidate()
            if phase == .active, current { let revision = workflow.revision; Task { await load(expectedGeneration: revision) } }
        }
        .onDisappear { workflow.invalidate() }
    }
    private func load(expectedGeneration: UInt64? = nil) async {
        guard current else { return }
        await workflow.load(target: target, access: access, context: context, sourceIsCurrent: sourceIsCurrent, expectedGeneration: expectedGeneration)
    }
    private func amount(_ value: WalletAmount, currency: String?) -> String {
        value.text + " " + (currency ?? appLocalized("wallet.currencyUnknown", locale: locale))
    }
}
