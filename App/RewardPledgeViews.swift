import SwiftUI

public struct RewardPledgePolicyKey: EnvironmentKey {
    public static let defaultValue = RewardPledgePolicy.unset
}

public extension EnvironmentValues {
    var rewardPledgePolicy: RewardPledgePolicy {
        get { self[RewardPledgePolicyKey.self] }
        set { self[RewardPledgePolicyKey.self] = newValue }
    }
}

/// Screen state for claim, pledge and staff redeem. Transport stays with the caller.
@MainActor public final class RewardPledgeModel: ObservableObject {
    @Published public private(set) var machine: RewardPledgeMachine
    @Published public private(set) var terms: RewardPledgeTerms?
    @Published public private(set) var intent: RewardPledgeIntent?
    @Published public private(set) var notice: String?
    private let journal: RewardPledgeFileJournal?
    private let journalBlocked: Bool

    public init(accountID: String, storeID: String, policy: RewardPledgePolicy, journalURL: URL?) {
        let stored = journalURL.map { RewardPledgeFileJournal(url: $0) }
        journal = stored
        let loaded: [RewardPledgeUnknown]
        var blocked = false
        if let stored {
            do { loaded = try stored.load() } catch { loaded = []; blocked = true }
        } else { loaded = [] }
        journalBlocked = blocked
        machine = .restored(accountID: accountID, storeID: storeID, policy: policy, journal: loaded)
        notice = blocked ? "journal" : nil
    }

    public func readClaim(serverRule: String, serverLimit: String, serverValidity: String, eligibility: String,
                          rewardScope: String, storeID: String, serverQuota: Int?, minorPrize: Bool, reviewRequired: Bool) {
        if journalBlocked { notice = "journal"; return }
        notice = nil
        if machine.scope.storeID.isEmpty {
            guard case .success = machine.bindStore(storeID, seen: machine.scope) else { notice = "store"; return }
        }
        var capabilities = SponsoredRewardCapabilities()
        capabilities.nonCash = machine.policy.nonCashEnabled == true
        switch machine.readTerms(serverRule: serverRule, serverLimit: serverLimit, serverValidity: serverValidity,
                                 eligibility: eligibility, rewardScope: rewardScope, beneficiary: machine.scope.accountID,
                                 storeID: machine.scope.storeID, serverQuota: serverQuota, minorPrize: minorPrize,
                                 reviewRequired: reviewRequired, clientComplete: false, capabilities: capabilities, seen: machine.scope) {
        case .success(let value): terms = value; notice = value.limitText
        case .failure(let error): fail(error)
        }
    }

    public func confirm() {
        guard let terms else { notice = "confirm"; return }
        switch machine.confirmClaim(terms, seen: machine.scope) {
        case .success(let value): intent = value; notice = value.requestID
        case .failure(let error): fail(error)
        }
    }

    public func loseResponse() {
        guard let intent else { notice = "intent"; return }
        switch machine.recordUnknown(intent, seen: machine.scope) {
        case .success: persist()
        case .failure(let error): fail(error)
        }
    }

    public func recover() {
        guard let row = machine.unknowns.last else { notice = "intent"; return }
        switch machine.recoveryIntent(row, proposedRequestID: row.requestID, seen: machine.scope) {
        case .success(let value):
            intent = value
            notice = RewardPledgeRoutes.plannedIntentQuery + "?requestId=" + value.requestID
        case .failure(let error): fail(error)
        }
    }

    public func accept(awardID: String, termsVersion: String, termsText: String) {
        guard let intent else { notice = "confirm"; return }
        switch machine.acceptGrant(awardID: awardID, termsVersion: termsVersion, termsText: termsText, requestID: intent.requestID,
                                   businessKey: intent.businessKey, seen: machine.scope) {
        case .success:
            persist()
            if notice != "journal" { notice = "GRANTED_UNREDEEMED" }
        case .failure(let error): fail(error)
        }
    }

    public func refresh() {
        switch machine.markRefreshed(seen: machine.scope) {
        case .success(let path): notice = path
        case .failure(let error): fail(error)
        }
    }

    public func saveDraft(pledgeID: String, quantityText: String, termsText: String, serverReserve: Int?) {
        switch machine.saveDraft(pledgeID: pledgeID, quantityText: quantityText, termsText: termsText, serverReserve: serverReserve, seen: machine.scope) {
        case .success(let row): notice = "DRAFT:" + String(row.version)
        case .failure(let error): fail(error)
        }
    }

    public func submitDraft() {
        switch machine.submitDraft(seen: machine.scope) {
        case .success(let row): notice = "SUBMITTED:" + String(row.version)
        case .failure(let error): fail(error)
        }
    }

    public func freeze(serverVersionText: String) {
        guard let version = Int(serverVersionText) else { notice = "ruleVersion"; return }
        freeze(serverVersion: version)
    }

    public func freeze(serverVersion: Int) {
        switch machine.freeze(serverVersion: serverVersion, seen: machine.scope) {
        case .success(let row): notice = "FROZEN:" + String(row.version)
        case .failure(let error): fail(error)
        }
    }

    public func withdraw() {
        switch machine.withdraw(seen: machine.scope) {
        case .success(let item): notice = item.readable
        case .failure(let error): fail(error)
        }
    }

    public func preview(permissionStore: String) {
        switch machine.preview(permissionStore: permissionStore, seen: machine.scope) {
        case .success: notice = permissionStore
        case .failure(let error): fail(error)
        }
    }

    public func redeem(historyID: String, serverCapacity: Int?) {
        switch machine.beginRedeem(explicit: true, historyID: historyID, serverCapacity: serverCapacity, seen: machine.scope) {
        case .success(let value):
            intent = value
            notice = machine.staffRoutes.joined(separator: " ")
        case .failure(let error): fail(error)
        }
    }

    public func redeemLost() {
        guard let intent, intent.kind == "redeem" else { notice = "intent"; return }
        switch machine.applyRedeem(requestID: intent.requestID, businessKey: intent.businessKey, serverRedeemed: false, seen: machine.scope) {
        case .success: break
        case .failure(let error):
            persist()
            if case .closed("unknown") = error { notice = "unknown" } else { fail(error) }
        }
    }

    public func redeemApplied() {
        guard let intent, intent.kind == "redeem" else { notice = "intent"; return }
        switch machine.applyRedeem(requestID: intent.requestID, businessKey: intent.businessKey, serverRedeemed: true, seen: machine.scope) {
        case .success:
            persist()
            if notice != "journal" { notice = "REDEEMED" }
        case .failure(let error): fail(error)
        }
    }

    public func expire(awardID: String) {
        switch machine.expire(awardID: awardID, seen: machine.scope) {
        case .success(let item): notice = item.readable
        case .failure(let error): fail(error)
        }
    }

    public func refuse(awardID: String) {
        switch machine.refuse(awardID: awardID, seen: machine.scope) {
        case .success(let item): notice = item.readable
        case .failure(let error): fail(error)
        }
    }

    public func replaceAccount(_ accountID: String, store storeID: String) {
        let existing = (try? journal?.load()) ?? []
        machine.replaceAccount(accountID, store: storeID, journal: existing)
        terms = nil; intent = nil; notice = nil
    }

    private func persist() {
        guard let journal else { notice = "journal"; return }
        do {
            try journal.save(machine.persistedRows(existing: try journal.load()))
            if machine.unknowns.isEmpty == false { notice = "unknown" }
        } catch { notice = "journal" }
    }

    private func fail(_ error: RewardPledgeFailure) {
        switch error {
        case .closed(let name): notice = name
        case .stale: notice = "stale"
        case .terminal(let name): notice = name
        }
    }
}

@MainActor public struct RewardPledgeClaimView: View {
    @ObservedObject var model: RewardPledgeModel
    @State private var rule = ""
    @State private var limit = ""
    @State private var validity = ""
    @State private var eligibility = ""
    @State private var rewardScope = ""
    @State private var store = ""
    @State private var quota = ""
    @State private var awardID = ""
    @State private var termsVersion = ""
    @State private var termsText = ""

    public init(model: RewardPledgeModel) { self.model = model }

    public var body: some View {
        Form {
            TextField("rewards.pledge.rule", text: $rule)
            TextField("rewards.pledge.limit", text: $limit)
            TextField("rewards.pledge.validity", text: $validity)
            TextField("rewards.pledge.eligibility", text: $eligibility)
            TextField("rewards.pledge.scope", text: $rewardScope)
            TextField("rewards.pledge.store", text: $store)
            TextField("rewards.pledge.quota", text: $quota)
            Button("rewards.pledge.read") {
                model.readClaim(serverRule: rule, serverLimit: limit, serverValidity: validity, eligibility: eligibility,
                                rewardScope: rewardScope, storeID: store, serverQuota: Int(quota), minorPrize: false, reviewRequired: false)
            }.accessibilityIdentifier("rewards.pledge.read")
            Button("rewards.pledge.confirm") { model.confirm() }.accessibilityIdentifier("rewards.pledge.confirm")
            Button("rewards.pledge.lose") { model.loseResponse() }.accessibilityIdentifier("rewards.pledge.unknown")
            Button("rewards.pledge.recover") { model.recover() }.accessibilityIdentifier("rewards.pledge.recover")
            TextField("rewards.pledge.award", text: $awardID)
            TextField("rewards.pledge.termsVersion", text: $termsVersion)
            TextField("rewards.pledge.terms", text: $termsText)
            Button("rewards.pledge.accept") { model.accept(awardID: awardID, termsVersion: termsVersion, termsText: termsText) }
                .accessibilityIdentifier("rewards.pledge.granted")
            Button("rewards.pledge.refresh") { model.refresh() }.accessibilityIdentifier("rewards.pledge.refresh")
            if let grant = model.machine.grant, grant.state == "GRANTED_UNREDEEMED" {
                Text(grant.termsText).accessibilityIdentifier("rewards.pledge.frozenTerms")
                Text(grant.state).accessibilityIdentifier("rewards.pledge.grantedState")
            }
            if let notice = model.notice { Text(notice).accessibilityIdentifier("rewards.pledge.notice") }
            if let item = model.machine.serviceCase { Text(item.readable).accessibilityIdentifier("rewards.pledge.case") }
        }
    }
}

@MainActor public struct RewardPledgeMerchantView: View {
    @ObservedObject var model: RewardPledgeModel
    @State private var pledgeID = ""
    @State private var quantity = ""
    @State private var terms = ""
    @State private var reserve = ""
    @State private var serverVersion = ""

    public init(model: RewardPledgeModel) { self.model = model }

    public var body: some View {
        Form {
            TextField("rewards.pledge.pledgeID", text: $pledgeID)
            TextField("rewards.pledge.quantity", text: $quantity)
            TextField("rewards.pledge.reserve", text: $reserve)
            TextField("rewards.pledge.terms", text: $terms)
            Button("rewards.pledge.draft") { model.saveDraft(pledgeID: pledgeID, quantityText: quantity, termsText: terms, serverReserve: Int(reserve)) }
                .accessibilityIdentifier("rewards.pledge.draft")
            Button("rewards.pledge.submit") { model.submitDraft() }.accessibilityIdentifier("rewards.pledge.submit")
            TextField("rewards.pledge.serverVersion", text: $serverVersion)
            Button("rewards.pledge.freeze") { model.freeze(serverVersionText: serverVersion) }
                .accessibilityIdentifier("rewards.pledge.frozen")
            Button("rewards.pledge.withdraw") { model.withdraw() }.accessibilityIdentifier("rewards.pledge.withdraw")
            if let frozen = model.machine.frozen { Text(frozen.status + " " + String(frozen.version)).accessibilityIdentifier("rewards.pledge.version") }
            if let notice = model.notice { Text(notice).accessibilityIdentifier("rewards.pledge.notice") }
            if let item = model.machine.serviceCase { Text(item.readable).accessibilityIdentifier("rewards.pledge.case") }
        }
    }
}

@MainActor public struct RewardPledgeStaffView: View {
    @ObservedObject var model: RewardPledgeModel
    @State private var store = ""
    @State private var historyID = ""
    @State private var capacity = ""

    public init(model: RewardPledgeModel) { self.model = model }

    public var body: some View {
        Form {
            TextField("rewards.pledge.permissionStore", text: $store)
            Button("rewards.pledge.preview") { model.preview(permissionStore: store) }.accessibilityIdentifier("rewards.pledge.preview")
            TextField("rewards.pledge.history", text: $historyID)
            TextField("rewards.pledge.capacity", text: $capacity)
            Button("rewards.pledge.redeem") { model.redeem(historyID: historyID, serverCapacity: Int(capacity)) }
                .accessibilityIdentifier("rewards.pledge.redeem")
            Button("rewards.pledge.redeemLost") { model.redeemLost() }.accessibilityIdentifier("rewards.pledge.redeemLost")
            Button("rewards.pledge.redeemApplied") { model.redeemApplied() }.accessibilityIdentifier("rewards.pledge.redeemApplied")
            if let notice = model.notice { Text(notice).accessibilityIdentifier("rewards.pledge.notice") }
            ForEach(model.machine.staffRoutes, id: \.self) { route in Text(route) }
            if let item = model.machine.serviceCase { Text(item.readable).accessibilityIdentifier("rewards.pledge.case") }
        }
    }
}
