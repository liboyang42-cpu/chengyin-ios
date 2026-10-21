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

/// Screen state for claim, pledge and staff redeem. The entry client calls the controllers.
@MainActor public final class RewardPledgeModel: ObservableObject {
    @Published public private(set) var machine: RewardPledgeMachine
    @Published public private(set) var terms: RewardPledgeTerms?
    @Published public private(set) var intent: RewardPledgeIntent?
    @Published public private(set) var notice: String?
    @Published public private(set) var playerResult: RewardPledgeServerBody?
    @Published public private(set) var merchantResult: RewardPledgeServerBody?
    @Published public private(set) var busy = false
    @Published public private(set) var awards: [RewardPledgeAwardRow] = []
    @Published public private(set) var awardsLoaded = false
    @Published public private(set) var listFailed = false
    @Published public private(set) var selected: RewardPledgeAwardRow?
    private var offerVersionID = ""
    private var offerSubjectID = ""
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
        let store: String
        if let resolved = Self.restoredStore(requested: storeID, accountID: accountID, rows: loaded) {
            store = resolved
        } else {
            store = ""
            blocked = true
        }
        journalBlocked = blocked
        machine = .restored(accountID: accountID, storeID: store, policy: policy, journal: loaded)
        notice = blocked ? "journal" : (machine.unknowns.isEmpty ? nil : "unknown")
    }

    /// An empty requested store restores the one store recorded for this account. Two stores stay closed.
    private static func restoredStore(requested: String, accountID: String, rows: [RewardPledgeUnknown]) -> String? {
        if !requested.isEmpty { return requested }
        let stores = Set(rows.filter { $0.ownerID == accountID }.map(\.storeID))
        if stores.count <= 1 { return stores.first ?? "" }
        return nil
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

    public func showClosed() { notice = "not open" }

    public func loadStoreAwards(entry: RewardPledgeEntry) async {
        guard let caller = admitted(entry, { $0.preview }) else { awards = []; awardsLoaded = true; listFailed = true; return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            awards = try await entry.client.storeAwards(token: caller.token, open: caller.preview, still: { entry.current() == caller })
            awardsLoaded = true
            listFailed = false
        } catch { note(error); awards = []; awardsLoaded = true; listFailed = true }
    }

    public func previewAward(_ row: RewardPledgeAwardRow, entry: RewardPledgeEntry) async {
        selected = row
        guard let caller = admitted(entry, { $0.preview }) else { return }
        do {
            merchantResult = try await entry.client.preview(awardID: row.awardId, token: caller.token, open: caller.preview, still: { entry.current() == caller })
            notice = merchantResult?.fields["state"]
        } catch { note(error) }
    }

    public func resolveCode(_ code: String, entry: RewardPledgeEntry) async {
        guard let caller = admitted(entry, { $0.preview }) else { return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let body = try await entry.client.resolve(code: code, token: caller.token, open: caller.preview, still: { entry.current() == caller })
            merchantResult = body
            notice = body.fields["state"]
        } catch { note(error) }
    }

    public func loadAwards(entry: RewardPledgeEntry) async {
        guard let caller = admitted(entry, { $0.read }) else { awards = []; awardsLoaded = true; listFailed = true; return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let rows = try await entry.client.awards(token: caller.token, open: caller.read, still: { entry.current() == caller })
            awards = rows
            awardsLoaded = true
            listFailed = false
        } catch { note(error); awards = []; awardsLoaded = true; listFailed = true }
    }

    public func selectAward(_ row: RewardPledgeAwardRow, entry: RewardPledgeEntry) async {
        selected = row
        offerVersionID = ""
        offerSubjectID = ""
        terms = nil
        await loadDetail(awardID: row.awardId, entry: entry)
        guard selected?.awardId == row.awardId, entry.current()?.accountID == machine.scope.accountID else { return }
        if let subject = row.themeSubjectID {
            await readOffer(versionID: row.versionId, subjectID: subject, entry: entry)
        } else { notice = "noSubject" }
    }

    public func readOffer(versionID: String, subjectID: String, entry: RewardPledgeEntry) async {
        guard let caller = admitted(entry, { $0.read }) else { return }
        guard !busy else { return }
        terms = nil
        busy = true
        defer { busy = false }
        do {
            let body = try await entry.client.offer(versionID: versionID, subjectID: subjectID, token: caller.token, open: caller.read, still: { entry.current() == caller })
            guard body.fields["errorCode"] != "POLICY_CLOSED", !(body.fields["ruleVersion"] ?? "").isEmpty else { showClosed(); return }
            guard body.fields["guaranteed"] != "true" else { notice = "switches"; return }
            if let code = body.fields["errorCode"], !code.isEmpty { notice = code; return }
            if body.fields["available"] == "0" { notice = "STOCK_EXHAUSTED"; return }
            var policy = RewardPledgePolicy()
            policy.ruleVersion = body.fields["ruleVersion"]
            policy.validity = (body.fields["redeemStart"] ?? "") + "-" + (body.fields["redeemEnd"] ?? "")
            policy.quota = Int(body.fields["available"] ?? "")
            policy.nonCashEnabled = true
            policy.readSource = .plannedController
            if body.fields["minorRestricted"] == "1" { policy.minorEligible = true }
            machine.applyPolicy(policy)
            offerVersionID = versionID
            offerSubjectID = subjectID
            readClaim(serverRule: policy.ruleVersion ?? "", serverLimit: body.fields["terms"] ?? "",
                      serverValidity: policy.validity ?? "", eligibility: body.fields["factRef"] ?? "",
                      rewardScope: body.fields["rewardScope"] ?? "", storeID: body.fields["storeId"] ?? "",
                      serverQuota: policy.quota, minorPrize: body.fields["minorRestricted"] == "1", reviewRequired: false)
        } catch { note(error) }
    }

    public func claim(entry: RewardPledgeEntry) async {
        guard let caller = admitted(entry, { $0.claim }) else { return }
        guard !busy else { return }
        guard let terms, !offerVersionID.isEmpty, !offerSubjectID.isEmpty, selected?.themeSubjectID == offerSubjectID else { notice = "confirm"; return }
        switch machine.confirmClaim(terms, seen: machine.scope) {
        case .failure(let error): fail(error)
        case .success(let value):
            intent = value
            switch machine.recordUnknown(value, seen: machine.scope) {
            case .failure(let error): fail(error)
            case .success:
                guard persistOrStop() else { return }
                busy = true
                defer { busy = false }
                do {
                    let body = try await entry.client.claim(requestID: value.requestID, versionID: offerVersionID, subjectID: offerSubjectID, token: caller.token, open: caller.claim, still: { entry.current() == caller })
                    adopt(body, intent: value)
                } catch { note(error) }
            }
        }
    }

    public func recover(entry: RewardPledgeEntry) async {
        guard let caller = admitted(entry, { $0.claim }) else { return }
        guard !busy, let row = machine.unknowns.last else { notice = "intent"; return }
        switch machine.recoveryIntent(row, proposedRequestID: row.requestID, seen: machine.scope) {
        case .failure(let error): fail(error)
        case .success(let value):
            intent = value
            busy = true
            defer { busy = false }
            do {
                let body = try await entry.client.recover(requestID: value.requestID, token: caller.token, open: caller.claim, still: { entry.current() == caller })
                if body.fields["state"] == "UNKNOWN" { notice = "unknown"; return }
                adopt(body, intent: value)
            } catch { note(error) }
        }
    }

    public func loadDetail(entry: RewardPledgeEntry) async {
        let award = selected?.awardId ?? machine.grant?.awardID ?? ""
        await loadDetail(awardID: award, entry: entry)
    }

    private func loadDetail(awardID: String, entry: RewardPledgeEntry) async {
        guard let caller = admitted(entry, { $0.read }) else { return }
        guard !awardID.isEmpty else { notice = "award"; return }
        do {
            let body = try await entry.client.detail(awardID: awardID, token: caller.token, open: caller.read, still: { entry.current() == caller })
            playerResult = body
            notice = body.fields["state"]
            if machine.grant?.state == "GRANTED_UNREDEEMED", case .failure(let error) = machine.markRefreshed(seen: machine.scope) { fail(error) }
        } catch { note(error) }
    }

    public func redeemOriginal(awardID: String, requestID: String, entry: RewardPledgeEntry) async {
        guard let caller = admitted(entry, { $0.preview }) else { return }
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let preview = try await entry.client.preview(awardID: awardID, token: caller.token, open: caller.preview, still: { entry.current() == caller })
            switch RewardPledgeClient.acceptedVoucher(preview: preview, originalRequestID: requestID) {
            case .failure(.terminal("ALREADY_USED")):
                merchantResult = preview
                playerResult = preview
                notice = "ALREADY_USED"
            case .failure(let error): fail(error)
            case .success(let award):
                guard let now = entry.current(), now.redeem, now.accountID == caller.accountID, now.epoch == caller.epoch, now.region == caller.region, now.preview else {
                    merchantResult = preview
                    notice = entry.current()?.redeem == true ? "stale" : "not open"
                    return
                }
                let merchant = try await entry.client.redeem(awardID: award, token: now.token, open: now.redeem, still: { entry.current() == now })
                merchantResult = merchant
                let playerKeys: Set<String> = ["awardId", "requestId", "state", "historyId", "useStatus", "ruleVersion", "terms", "factRef"]
                var playerFields: [String: String] = [:]
                for (key, value) in merchant.fields where playerKeys.contains(key) { playerFields[key] = value }
                playerResult = RewardPledgeServerBody(code: merchant.code, message: merchant.message, fields: playerFields)
                notice = merchant.fields["redemption"] ?? "ALREADY_USED"
            }
        } catch { note(error) }
    }

    public func cancelPending() {
        guard let intent, machine.unknowns.contains(where: { $0.requestID == intent.requestID }) else {
            terms = nil
            self.intent = nil
            notice = "cancel"
            return
        }
        notice = "unknown"
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
        let existing: [RewardPledgeUnknown]
        if let journal {
            do { existing = try journal.load() } catch {
                machine.replaceAccount(accountID, store: "", journal: [])
                clearSelection(notice: "journal")
                return
            }
        } else { existing = [] }
        guard let store = Self.restoredStore(requested: storeID, accountID: accountID, rows: existing) else {
            machine.replaceAccount(accountID, store: "", journal: [])
            clearSelection(notice: "journal")
            return
        }
        machine.replaceAccount(accountID, store: store, journal: existing)
        clearSelection(notice: machine.unknowns.isEmpty ? "stale" : "unknown")
    }

    private func admitted(_ entry: RewardPledgeEntry, _ allows: (RewardPledgeCaller) -> Bool) -> RewardPledgeCaller? {
        guard let caller = entry.current(), !caller.region.isEmpty, AuthRequestBuilder.isValidToken(caller.token) else { showClosed(); return nil }
        guard caller.accountID == machine.scope.accountID else {
            replaceAccount(caller.accountID, store: "")
            return nil
        }
        guard allows(caller) else { showClosed(); return nil }
        return caller
    }

    private func clearSelection(notice: String) {
        terms = nil; intent = nil; awards = []; selected = nil
        playerResult = nil; merchantResult = nil; awardsLoaded = false
        self.notice = notice
    }

    private func persistOrStop() -> Bool {
        guard let journal else { notice = "journal"; return false }
        do {
            try journal.save(machine.persistedRows(existing: try journal.load()))
            return true
        } catch { notice = "journal"; return false }
    }

    private func adopt(_ body: RewardPledgeServerBody, intent: RewardPledgeIntent) {
        if body.fields["state"] == "REFUSED" {
            _ = machine.finishUnknown(requestID: intent.requestID, seen: machine.scope)
            persist()
            notice = body.fields["errorCode"] ?? "REFUSED"
            return
        }
        guard let award = body.fields["awardId"], !award.isEmpty, body.fields["requestId"] == intent.requestID else {
            notice = "unknown"
            return
        }
        playerResult = body
        accept(awardID: award, termsVersion: body.fields["ruleVersion"] ?? "", termsText: body.fields["terms"] ?? "")
    }

    private func note(_ error: Error) {
        if let failure = error as? RewardPledgeFailure {
            if case .closed("unknown") = failure { notice = "unknown" } else { fail(failure) }
            return
        }
        notice = (error as? APIError) == .unauthorized ? "permission" : "unknown"
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
        case .stale:
            playerResult = nil; merchantResult = nil; terms = nil; awards = []; selected = nil; listFailed = true; awardsLoaded = true
            notice = "stale"
        case .terminal(let name): notice = name
        }
    }
}

@MainActor public struct RewardPledgeClaimView: View {
    @ObservedObject var model: RewardPledgeModel
    var entry: RewardPledgeEntry?

    public init(model: RewardPledgeModel, entry: RewardPledgeEntry? = nil) {
        self.model = model
        self.entry = entry
    }

    public var body: some View {
        Form {
            if entry?.current()?.read != true {
                Text("rewards.unavailable").accessibilityIdentifier("rewards.pledge.closed")
            } else if let entry {
                if !model.awardsLoaded { ProgressView("accountCollection.loading") }
                else if model.listFailed {
                    Button("accountCollection.refresh") { Task { await model.loadAwards(entry: entry) } }
                        .accessibilityIdentifier("rewards.pledge.retry")
                } else if model.awards.isEmpty {
                    ContentUnavailableView("rewards.empty", systemImage: "gift")
                }
                ForEach(model.awards) { row in
                    Button { Task { await model.selectAward(row, entry: entry) } } label: {
                        VStack(alignment: .leading) {
                            Text(LocalizedStringKey("rewards.state." + row.state))
                            Text(verbatim: row.ruleVersion)
                        }
                    }
                    .accessibilityIdentifier("rewards.pledge.row." + row.awardId)
                }
                Button("rewards.pledge.read") { Task { await model.loadAwards(entry: entry) } }
                    .disabled(model.busy).accessibilityIdentifier("rewards.pledge.read")
                if model.selected != nil, model.selected?.themeSubjectID == nil {
                    Text("rewards.pledge.noSubject").accessibilityIdentifier("rewards.pledge.noSubject")
                }
                if entry.current()?.claim == true, model.selected?.themeSubjectID != nil {
                    Button("rewards.pledge.confirm") { Task { await model.claim(entry: entry) } }
                        .disabled(model.busy).accessibilityIdentifier("rewards.pledge.confirm")
                } else {
                    Text("rewards.unavailable").accessibilityIdentifier("rewards.pledge.claimClosed")
                }
                Button("rewards.pledge.cancel") { model.cancelPending() }.accessibilityIdentifier("rewards.pledge.cancel")
                Button("rewards.pledge.lose") { model.loseResponse() }.accessibilityIdentifier("rewards.pledge.unknown")
                if entry.current()?.claim == true {
                    Button("rewards.pledge.recover") { Task { await model.recover(entry: entry) } }
                        .disabled(model.busy).accessibilityIdentifier("rewards.pledge.recover")
                }
                Button("rewards.pledge.refresh") { Task { await model.loadDetail(entry: entry) } }
                    .disabled(model.busy).accessibilityIdentifier("rewards.pledge.refresh")
            }
            if let terms = model.terms {
                Text(terms.ruleVersion).accessibilityIdentifier("rewards.pledge.rule")
                Text(terms.eligibilityFact).accessibilityIdentifier("rewards.pledge.eligibility")
                Text(terms.limitText).accessibilityIdentifier("rewards.pledge.inventory")
                Text(terms.validity).accessibilityIdentifier("rewards.pledge.window")
            }
            if let grant = model.machine.grant, grant.state == "GRANTED_UNREDEEMED" {
                Text(grant.termsText).accessibilityIdentifier("rewards.pledge.frozenTerms")
                Text(grant.state).accessibilityIdentifier("rewards.pledge.grantedState")
            }
            if let player = model.playerResult {
                Text(player.fields["state"] ?? "").accessibilityIdentifier("rewards.pledge.playerResult")
                Text(player.fields["historyId"] ?? "").accessibilityIdentifier("rewards.pledge.voucher")
                Text(player.fields["useStatus"] ?? "").accessibilityIdentifier("rewards.pledge.playerUse")
            }
            if let notice = model.notice { Text(notice).accessibilityIdentifier("rewards.pledge.notice") }
            if let item = model.machine.serviceCase { Text(item.readable).accessibilityIdentifier("rewards.pledge.case") }
        }
        .task {
            guard let entry, entry.current()?.read == true, !model.awardsLoaded else { return }
            await model.loadAwards(entry: entry)
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
    var entry: RewardPledgeEntry?
    @State private var scanning = false

    public init(model: RewardPledgeModel, entry: RewardPledgeEntry? = nil) {
        self.model = model
        self.entry = entry
    }

    public var body: some View {
        Form {
            if entry?.current()?.preview != true {
                Text("rewards.unavailable").accessibilityIdentifier("rewards.pledge.merchantClosed")
            } else if let entry {
                if !model.awardsLoaded { ProgressView("accountCollection.loading") }
                else if model.listFailed {
                    Button("accountCollection.refresh") { Task { await model.loadStoreAwards(entry: entry) } }
                        .accessibilityIdentifier("rewards.pledge.retry")
                } else if model.awards.isEmpty {
                    ContentUnavailableView("rewards.empty", systemImage: "gift")
                }
                ForEach(model.awards) { row in
                    Button { Task { await model.previewAward(row, entry: entry) } } label: {
                        VStack(alignment: .leading) {
                            Text(LocalizedStringKey("rewards.state." + row.state))
                            Text(verbatim: row.ruleVersion)
                        }
                    }
                    .accessibilityIdentifier("rewards.pledge.store." + row.awardId)
                }
                Button("verification.scan") { scanning = true }.accessibilityIdentifier("rewards.pledge.scan")
                if entry.current()?.redeem == true {
                    Button("rewards.pledge.redeem") {
                        let award = model.merchantResult?.fields["awardId"] ?? model.selected?.awardId ?? ""
                        let request = model.merchantResult?.fields["requestId"] ?? model.selected?.requestId ?? ""
                        Task { await model.redeemOriginal(awardID: award, requestID: request, entry: entry) }
                    }
                    .disabled(model.busy).accessibilityIdentifier("rewards.pledge.redeem")
                } else {
                    Text("rewards.unavailable").accessibilityIdentifier("rewards.pledge.redeemClosed")
                }
                Button("rewards.pledge.cancel") { model.cancelPending() }.accessibilityIdentifier("rewards.pledge.merchantCancel")
            }
            if let merchant = model.merchantResult {
                Text(merchant.fields["redemption"] ?? merchant.message).accessibilityIdentifier("rewards.pledge.merchantResult")
                Text(merchant.fields["stock.available"] ?? merchant.fields["available"] ?? "").accessibilityIdentifier("rewards.pledge.merchantStock")
            }
            if let player = model.playerResult {
                Text(player.fields["state"] ?? "").accessibilityIdentifier("rewards.pledge.playerResult")
                Text(player.fields["requestId"] ?? "").accessibilityIdentifier("rewards.pledge.playerRequest")
                Text(player.fields["useStatus"] ?? "").accessibilityIdentifier("rewards.pledge.playerUse")
            }
            if let notice = model.notice { Text(notice).accessibilityIdentifier("rewards.pledge.notice") }
            if let item = model.machine.serviceCase { Text(item.readable).accessibilityIdentifier("rewards.pledge.case") }
        }
        .task {
            guard let entry, entry.current()?.preview == true, !model.awardsLoaded else { return }
            await model.loadStoreAwards(entry: entry)
        }
        .sheet(isPresented: $scanning) {
            NativeQRScanner { value in
                scanning = false
                guard let entry else { return }
                Task { await model.resolveCode(value, entry: entry) }
            }
        }
    }
}

@MainActor struct RewardPledgeClaimHost: View {
    let entry: RewardPledgeEntry
    @StateObject private var model: RewardPledgeModel
    init(entry: RewardPledgeEntry) {
        self.entry = entry
        _model = StateObject(wrappedValue: RewardPledgeModel(accountID: entry.accountID, storeID: "", policy: .unset, journalURL: entry.journalURL))
    }
    var body: some View {
        RewardPledgeClaimView(model: model, entry: entry)
            .onChange(of: entry.accountID) { _, accountID in
                model.replaceAccount(accountID, store: "")
                Task { await model.loadAwards(entry: entry) }
            }
    }
}

@MainActor struct RewardPledgeStaffHost: View {
    let entry: RewardPledgeEntry
    @StateObject private var model: RewardPledgeModel
    init(entry: RewardPledgeEntry) {
        self.entry = entry
        _model = StateObject(wrappedValue: RewardPledgeModel(accountID: entry.accountID, storeID: "", policy: .unset, journalURL: entry.journalURL))
    }
    var body: some View {
        RewardPledgeStaffView(model: model, entry: entry)
            .onChange(of: entry.accountID) { _, accountID in
                model.replaceAccount(accountID, store: "")
                Task { await model.loadStoreAwards(entry: entry) }
            }
    }
}
