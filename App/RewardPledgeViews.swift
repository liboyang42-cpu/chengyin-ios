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
    @Published public private(set) var pledgeID = ""
    @Published public private(set) var versionID = ""
    @Published public private(set) var coupons: [CouponDefinition] = []
    @Published public private(set) var couponsLoaded = false
    @Published public private(set) var statsBody: RewardPledgeServerBody?
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
        if let memory = Self.loadSupply(journalURL, accountID: accountID) {
            if RewardPledgeRoutes.id(memory.pledgeID) {
                pledgeID = memory.pledgeID
                versionID = memory.versionID
            }
            if !blocked, memory.pendingDraft != nil || !(memory.locks ?? []).isEmpty { notice = "unknown" }
        }
    }

    private struct SupplyLock: Codable, Equatable { var op, key: String }
    private struct PendingDraft: Codable, Equatable {
        var key: String
        var couponID: Int
        var supplyRef, terms: String
        var quantity: Int
        var windowStart, windowEnd: Int64
        func matches(_ supply: RewardPledgeRequests.Supply) -> Bool {
            couponID == supply.couponID && supplyRef == supply.supplyRef && terms == supply.terms
                && quantity == supply.quantity && windowStart == supply.windowStart && windowEnd == supply.windowEnd
        }
    }
    private struct SupplyMemory: Codable {
        var accountID, pledgeID, versionID: String
        var pendingDraft: PendingDraft?
        var locks: [SupplyLock]?
    }
    private static func supplyURL(_ journalURL: URL?, accountID: String) -> URL? {
        guard let journalURL, RewardPledgeRoutes.id(accountID) else { return nil }
        return journalURL.deletingLastPathComponent().appendingPathComponent("reward-pledge-supply-" + accountID + ".json")
    }
    private static func loadSupply(_ journalURL: URL?, accountID: String) -> SupplyMemory? {
        let urls = [supplyURL(journalURL, accountID: accountID), journalURL?.deletingLastPathComponent().appendingPathComponent("reward-pledge-supply.json")]
        for url in urls {
            guard let url, let data = try? Data(contentsOf: url),
                  let memory = try? JSONDecoder().decode(SupplyMemory.self, from: data), memory.accountID == accountID else { continue }
            return memory
        }
        return nil
    }
    private func loadMemory() -> SupplyMemory? { Self.loadSupply(journal?.url, accountID: machine.scope.accountID) }
    private func blankMemory() -> SupplyMemory {
        SupplyMemory(accountID: machine.scope.accountID, pledgeID: pledgeID, versionID: versionID, pendingDraft: nil, locks: [])
    }
    /// Disk failure throws. Callers must not send until this returns.
    private func store(_ memory: SupplyMemory) throws {
        guard memory.accountID == machine.scope.accountID, let url = Self.supplyURL(journal?.url, accountID: memory.accountID) else {
            throw RewardPledgeFailure.closed("journal")
        }
        let data = try JSONEncoder().encode(memory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try data.write(to: url, options: .atomic) } catch { throw RewardPledgeFailure.closed("journal") }
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
                adoptSupply(for: accountID)
                return
            }
        } else { existing = [] }
        guard let store = Self.restoredStore(requested: storeID, accountID: accountID, rows: existing) else {
            machine.replaceAccount(accountID, store: "", journal: [])
            clearSelection(notice: "journal")
            adoptSupply(for: accountID)
            return
        }
        machine.replaceAccount(accountID, store: store, journal: existing)
        clearSelection(notice: machine.unknowns.isEmpty ? "stale" : "unknown")
        adoptSupply(for: accountID)
    }

    private func adoptSupply(for accountID: String) {
        coupons = []; couponsLoaded = false; statsBody = nil
        guard let memory = Self.loadSupply(journal?.url, accountID: accountID) else {
            pledgeID = ""; versionID = ""
            return
        }
        pledgeID = RewardPledgeRoutes.id(memory.pledgeID) ? memory.pledgeID : ""
        versionID = RewardPledgeRoutes.id(memory.versionID) ? memory.versionID : ""
        if memory.pendingDraft != nil || !(memory.locks ?? []).isEmpty { notice = "unknown" }
    }

    public func loadCoupons(entry: RewardPledgeEntry) async {
        guard let caller = admitted(entry, { $0.draft }) else { coupons = []; return }
        switch await entry.coupons() {
        case .success(let rows):
            guard entry.current() == caller else { coupons = []; couponsLoaded = false; notice = "stale"; return }
            coupons = rows
            couponsLoaded = true
        case .failure(let error):
            coupons = []
            couponsLoaded = false
            fail(error)
        }
    }

    public func draftSupply(coupon: CouponDefinition, supplyRef: String, terms: String, quantity: String, entry: RewardPledgeEntry) async {
        guard let caller = admitted(entry, { $0.draft }), !busy else { return }
        busy = true
        defer { busy = false }
        let probed: RewardPledgeRequests.Supply
        do { probed = try RewardPledgeRequests.Supply(coupon: coupon, supplyRef: supplyRef, terms: terms, quantity: Int(quantity) ?? 0, requestID: "pending") }
        catch { note(error); return }
        let key: String
        do { key = try beginDraft(probed) } catch { note(error); return }
        do {
            let supply = try RewardPledgeRequests.Supply(coupon: coupon, supplyRef: supplyRef, terms: terms, quantity: Int(quantity) ?? 0, requestID: key)
            let body = try await entry.client.draft(supply, token: caller.token, open: caller.draft, still: { entry.current() == caller })
            guard body.fields["pledge.pledgeId"] == key else { notice = "unknown"; return }
            try finish("draft", key, body)
        } catch {
            await reconcileDraft(key, error, entry, caller)
        }
    }

    public func submitSupply(entry: RewardPledgeEntry) async {
        await pledged(entry, "submit", Self.submitted) { caller, key in
            try await entry.client.submit(pledgeID: key, token: caller.token, open: caller.draft, still: { entry.current() == caller })
        }
    }

    public func confirmSupply(entry: RewardPledgeEntry) async {
        await pledged(entry, "confirm", Self.confirmed) { caller, key in
            try await entry.client.confirm(pledgeID: key, token: caller.token, open: caller.draft, still: { entry.current() == caller })
        }
    }

    public func readSupply(entry: RewardPledgeEntry) async {
        await pledgeCall(entry, { $0.draft }) { caller in
            try await entry.client.readPledge(pledgeID: pledgeID, token: caller.token, open: caller.draft, still: { entry.current() == caller })
        }
    }

    public func freezeSupply(ruleVersion: String, entry: RewardPledgeEntry) async {
        await pledgeCall(entry, { $0.freeze }) { caller in
            try await entry.client.freeze(pledgeID: pledgeID, ruleVersion: ruleVersion, token: caller.token, open: caller.freeze, still: { entry.current() == caller })
        }
    }

    public func holdSupply(entry: RewardPledgeEntry) async {
        guard let caller = admitted(entry, { $0.hold }), !busy, RewardPledgeRoutes.id(versionID), RewardPledgeRoutes.id(pledgeID) else { return }
        busy = true
        defer { busy = false }
        let version = versionID, pledge = pledgeID
        await guarded(op: "hold", key: version, applied: Self.held, send: {
            try await entry.client.hold(versionID: version, token: caller.token, open: caller.hold, still: { entry.current() == caller })
        }, read: {
            try await entry.client.readPledge(pledgeID: pledge, token: caller.token, open: caller.draft, still: { entry.current() == caller })
        })
    }

    public func withdrawSupply(entry: RewardPledgeEntry) async {
        guard let caller = admitted(entry, { $0.withdrawVersion }), !busy, RewardPledgeRoutes.id(versionID), RewardPledgeRoutes.id(pledgeID) else { return }
        busy = true
        defer { busy = false }
        let version = versionID, pledge = pledgeID
        await guarded(op: "withdraw", key: version, applied: Self.withdrawn, send: {
            try await entry.client.withdraw(versionID: version, token: caller.token, open: caller.withdrawVersion, still: { entry.current() == caller })
        }, read: {
            try await entry.client.readPledge(pledgeID: pledge, token: caller.token, open: caller.draft, still: { entry.current() == caller })
        })
    }

    public func loadStats(entry: RewardPledgeEntry) async {
        guard let caller = admitted(entry, { $0.stats }), !busy, RewardPledgeRoutes.id(pledgeID) else { return }
        busy = true
        defer { busy = false }
        do {
            let body = try await entry.client.stats(pledgeID: pledgeID, token: caller.token, open: caller.stats, still: { entry.current() == caller })
            guard body.fields["asOf"] != nil, body.fields["awardCount"] != nil else { throw APIError.malformedResponse }
            statsBody = body
            notice = body.fields["asOf"]
        } catch { statsBody = nil; note(error) }
    }

    public func expireAward(entry: RewardPledgeEntry) async {
        guard let award = selected?.awardId, RewardPledgeRoutes.id(award), let caller = admitted(entry, { $0.expire }), !busy else { return }
        busy = true
        defer { busy = false }
        await guarded(op: "expire", key: award, applied: { $0.fields["useStatus"] == "2" }, send: {
            try await entry.client.expire(awardID: award, token: caller.token, open: caller.expire, still: { entry.current() == caller })
        }, read: {
            try await entry.client.preview(awardID: award, token: caller.token, open: caller.preview, still: { entry.current() == caller })
        })
    }

    public func returnAward(entry: RewardPledgeEntry) async {
        guard let award = selected?.awardId, RewardPledgeRoutes.id(award), let caller = admitted(entry, { $0.returnPool }), !busy else { return }
        busy = true
        defer { busy = false }
        await guarded(op: "return", key: award, applied: { $0.fields["state"] == "RETURNED" }, send: {
            try await entry.client.returnToPool(awardID: award, token: caller.token, open: caller.returnPool, still: { entry.current() == caller })
        }, read: {
            try await entry.client.preview(awardID: award, token: caller.token, open: caller.preview, still: { entry.current() == caller })
        })
    }

    public func openSupport(reason: String, entry: RewardPledgeEntry) async {
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text != "CASH_REFUND" else { notice = "CASH_CLOSED"; return }
        guard !text.isEmpty, text.count <= 128, !text.contains("\n") else { notice = "validity"; return }
        guard let row = selected, RewardPledgeRoutes.id(row.awardId), let caller = admitted(entry, { $0.support }), !busy else { return }
        busy = true
        defer { busy = false }
        let award = row.awardId
        do { try lock("case", award) } catch { note(error); return }
        do {
            let opened = try await entry.client.openCase(awardID: award, versionID: row.versionId, reason: text, token: caller.token, open: caller.support, still: { entry.current() == caller })
            guard let caseID = opened.fields["caseId"], RewardPledgeRoutes.id(caseID) else { notice = "unknown"; return }
            let read = try await entry.client.readCase(caseID: caseID, token: caller.token, open: caller.support, still: { entry.current() == caller })
            guard read.fields["awardId"] == award, let state = read.fields["state"], !state.isEmpty, let why = read.fields["reason"], !why.isEmpty else {
                notice = "unknown"; return
            }
            try unlock("case", award)
            playerResult = read
            notice = state + " " + why
        } catch {
            if businessRejection(error) == nil { note(error) } else { notice = "unknown" }
        }
    }

    private func pledgeCall(_ entry: RewardPledgeEntry, _ allows: (RewardPledgeCaller) -> Bool, _ send: (RewardPledgeCaller) async throws -> RewardPledgeServerBody) async {
        guard let caller = admitted(entry, allows), !busy, RewardPledgeRoutes.id(pledgeID) else { return }
        busy = true
        defer { busy = false }
        do { try keepPledge(try await send(caller)) } catch { note(error) }
    }

    private func pledged(_ entry: RewardPledgeEntry, _ op: String, _ applied: @escaping (RewardPledgeServerBody) -> Bool, _ send: @escaping (RewardPledgeCaller, String) async throws -> RewardPledgeServerBody) async {
        guard let caller = admitted(entry, { $0.draft }), !busy, RewardPledgeRoutes.id(pledgeID) else { return }
        busy = true
        defer { busy = false }
        let key = pledgeID
        await guarded(op: op, key: key, applied: applied, send: { try await send(caller, key) }, read: {
            try await entry.client.readPledge(pledgeID: key, token: caller.token, open: caller.draft, still: { entry.current() == caller })
        })
    }

    private func beginDraft(_ supply: RewardPledgeRequests.Supply) throws -> String {
        var memory = loadMemory() ?? blankMemory()
        guard memory.accountID == machine.scope.accountID else { throw RewardPledgeFailure.stale }
        if let pending = memory.pendingDraft {
            guard pending.matches(supply) else { throw RewardPledgeFailure.closed("unknown") }
            return pending.key
        }
        let key = UUID().uuidString
        guard RewardPledgeRoutes.id(key) else { throw RewardPledgeFailure.closed("journal") }
        memory.pendingDraft = PendingDraft(key: key, couponID: supply.couponID, supplyRef: supply.supplyRef, terms: supply.terms,
                                            quantity: supply.quantity, windowStart: supply.windowStart, windowEnd: supply.windowEnd)
        try store(memory)
        return key
    }

    private func lock(_ op: String, _ key: String) throws {
        guard RewardPledgeRoutes.id(key) else { throw RewardPledgeFailure.closed("route") }
        var memory = loadMemory() ?? blankMemory()
        guard memory.accountID == machine.scope.accountID else { throw RewardPledgeFailure.stale }
        if memory.locks?.contains(where: { $0.op == op && $0.key == key }) == true { return }
        memory.locks = (memory.locks ?? []) + [SupplyLock(op: op, key: key)]
        try store(memory)
    }

    private func unlock(_ op: String, _ key: String) throws {
        var memory = loadMemory() ?? blankMemory()
        guard memory.accountID == machine.scope.accountID else { throw RewardPledgeFailure.stale }
        memory.locks = (memory.locks ?? []).filter { !($0.op == op && $0.key == key) }
        try store(memory)
    }

    private func finish(_ op: String, _ key: String, _ body: RewardPledgeServerBody) throws {
        var memory = loadMemory() ?? blankMemory()
        guard memory.accountID == machine.scope.accountID else { throw RewardPledgeFailure.stale }
        if op == "draft" { memory.pendingDraft = nil }
        memory.locks = (memory.locks ?? []).filter { !($0.op == op && $0.key == key) }
        if let id = body.fields["pledge.pledgeId"], RewardPledgeRoutes.id(id) {
            pledgeID = id
            memory.pledgeID = id
        }
        if let version = body.fields["version.versionId"], RewardPledgeRoutes.id(version) {
            versionID = version
            memory.versionID = version
        }
        try store(memory)
        merchantResult = body
        notice = body.fields["version.state"] ?? body.fields["state"] ?? body.fields["useStatus"] ?? body.message
    }

    private func guarded(op: String, key: String, applied: @escaping (RewardPledgeServerBody) -> Bool,
                         send: () async throws -> RewardPledgeServerBody, read: () async throws -> RewardPledgeServerBody) async {
        do { try lock(op, key) } catch { note(error); return }
        do {
            let body = try await send()
            if applied(body) { try finish(op, key, body); return }
            try unlock(op, key)
            merchantResult = body
            notice = body.fields["useStatus"] ?? body.fields["version.state"] ?? body.fields["state"] ?? body.message
        } catch {
            await reconcile(op, key, error, applied: applied, read: read)
        }
    }

    private func reconcile(_ op: String, _ key: String, _ error: Error, applied: (RewardPledgeServerBody) -> Bool, read: () async throws -> RewardPledgeServerBody) async {
        guard businessRejection(error) != nil else { note(error); return }
        do {
            let body = try await read()
            if applied(body) { try finish(op, key, body); return }
            try unlock(op, key)
            note(error)
        } catch { notice = "unknown" }
    }

    private func reconcileDraft(_ key: String, _ error: Error, _ entry: RewardPledgeEntry, _ caller: RewardPledgeCaller) async {
        guard businessRejection(error) != nil else { note(error); return }
        do {
            let body = try await entry.client.readPledge(pledgeID: key, token: caller.token, open: caller.draft, still: { entry.current() == caller })
            guard body.fields["pledge.pledgeId"] == key else { notice = "unknown"; return }
            try finish("draft", key, body)
        } catch let read {
            guard let failure = read as? RewardPledgeFailure, case .closed("NOT_FOUND") = failure else { notice = "unknown"; return }
            do {
                var memory = loadMemory() ?? blankMemory()
                guard memory.pendingDraft?.key == key else { note(error); return }
                memory.pendingDraft = nil
                try store(memory)
                note(error)
            } catch { notice = "unknown" }
        }
    }

    private func businessRejection(_ error: Error) -> String? {
        guard let failure = error as? RewardPledgeFailure, case .closed(let name) = failure else { return nil }
        switch name {
        case "unknown", "not open", "permission", "FORBIDDEN", "journal": return nil
        default: return name
        }
    }

    private static func submitted(_ body: RewardPledgeServerBody) -> Bool {
        ["SUBMITTED", "CONFIRMED", "FROZEN", "WITHDRAWN"].contains(body.fields["version.state"] ?? "")
    }
    private static func confirmed(_ body: RewardPledgeServerBody) -> Bool {
        ["CONFIRMED", "FROZEN", "WITHDRAWN"].contains(body.fields["version.state"] ?? "")
    }
    private static func held(_ body: RewardPledgeServerBody) -> Bool {
        guard let frozen = body.fields["stock.frozenUnits"] else { return false }
        return frozen != "0"
    }
    private static func withdrawn(_ body: RewardPledgeServerBody) -> Bool { body.fields["version.state"] == "WITHDRAWN" }

    /// True only when the pledge's own service window is longer than the coupon. This client never invents that window.
    var serviceOutlivesCoupon: Bool {
        guard let service = Int64(merchantResult?.fields["serviceEnd"] ?? ""),
              let redeem = Int64(merchantResult?.fields["redeemEnd"] ?? "") else { return false }
        return service > redeem
    }

    private func keepPledge(_ body: RewardPledgeServerBody) throws {
        guard let id = body.fields["pledge.pledgeId"], RewardPledgeRoutes.id(id) else { throw APIError.malformedResponse }
        pledgeID = id
        if let version = body.fields["version.versionId"], RewardPledgeRoutes.id(version) { versionID = version }
        merchantResult = body
        var memory = loadMemory() ?? blankMemory()
        memory.pledgeID = pledgeID
        memory.versionID = versionID
        try store(memory)
        notice = body.fields["version.state"] ?? body.message
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
    @State private var caseReason = ""

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
                if entry.current()?.support == true, model.selected != nil {
                    TextField("rewards.pledge.caseReason", text: $caseReason)
                    Button("rewards.pledge.case") { Task { await model.openSupport(reason: caseReason, entry: entry) } }
                        .disabled(model.busy).accessibilityIdentifier("rewards.pledge.case")
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
                Text(player.fields["reason"] ?? "").accessibilityIdentifier("rewards.pledge.caseReasonText")
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
    var entry: RewardPledgeEntry?
    @State private var supplyRef = ""
    @State private var terms = ""
    @State private var quantity = ""
    @State private var picked: CouponDefinition?

    public init(model: RewardPledgeModel, entry: RewardPledgeEntry? = nil) {
        self.model = model
        self.entry = entry
    }

    public var body: some View {
        Form {
            if entry?.current()?.draft != true && entry?.current()?.hold != true
                && entry?.current()?.withdrawVersion != true && entry?.current()?.stats != true {
                Text("rewards.unavailable").accessibilityIdentifier("rewards.pledge.draftClosed")
            }
            if let entry, entry.current()?.draft == true {
                Button("rewards.pledge.coupons") { Task { await model.loadCoupons(entry: entry) } }
                    .disabled(model.busy).accessibilityIdentifier("rewards.pledge.coupons")
                if model.couponsLoaded, model.coupons.isEmpty { Text("rewards.empty").accessibilityIdentifier("rewards.pledge.couponEmpty") }
                ForEach(model.coupons) { coupon in
                    Button {
                        picked = coupon
                    } label: {
                        VStack(alignment: .leading) {
                            Text(verbatim: coupon.name ?? "")
                            Text(verbatim: (coupon.startTime ?? "") + " – " + (coupon.endTime ?? ""))
                        }
                    }
                    .accessibilityIdentifier("rewards.pledge.coupon." + String(coupon.id.value))
                }
                TextField("rewards.pledge.supply", text: $supplyRef)
                TextField("rewards.pledge.terms", text: $terms)
                TextField("rewards.pledge.quantity", text: $quantity)
                Button("rewards.pledge.draft") {
                    guard let picked else { return }
                    Task { await model.draftSupply(coupon: picked, supplyRef: supplyRef, terms: terms, quantity: quantity, entry: entry) }
                }
                .disabled(model.busy || picked == nil).accessibilityIdentifier("rewards.pledge.draft")
                Button("rewards.pledge.submit") { Task { await model.submitSupply(entry: entry) } }
                    .disabled(model.busy || !RewardPledgeRoutes.id(model.pledgeID)).accessibilityIdentifier("rewards.pledge.submit")
                Button("rewards.pledge.ownerConfirm") { Task { await model.confirmSupply(entry: entry) } }
                    .disabled(model.busy || !RewardPledgeRoutes.id(model.pledgeID)).accessibilityIdentifier("rewards.pledge.ownerConfirm")
                Button("rewards.pledge.readback") { Task { await model.readSupply(entry: entry) } }
                    .disabled(model.busy || !RewardPledgeRoutes.id(model.pledgeID)).accessibilityIdentifier("rewards.pledge.readback")
            }
            if let entry, entry.current()?.hold == true {
                Button("rewards.pledge.hold") { Task { await model.holdSupply(entry: entry) } }
                    .disabled(model.busy || !RewardPledgeRoutes.id(model.versionID)).accessibilityIdentifier("rewards.pledge.hold")
            }
            if let entry, entry.current()?.withdrawVersion == true {
                Button("rewards.pledge.withdraw") { Task { await model.withdrawSupply(entry: entry) } }
                    .disabled(model.busy || !RewardPledgeRoutes.id(model.versionID)).accessibilityIdentifier("rewards.pledge.withdraw")
            }
            if let entry, entry.current()?.stats == true {
                Button("rewards.pledge.stats") { Task { await model.loadStats(entry: entry) } }
                    .disabled(model.busy || !RewardPledgeRoutes.id(model.pledgeID)).accessibilityIdentifier("rewards.pledge.stats")
                if let stats = model.statsBody {
                    LabeledContent("rewards.pledge.asOf") { Text(verbatim: stats.fields["asOf"] ?? "") }
                    LabeledContent("rewards.pledge.awardCount") { Text(verbatim: stats.fields["awardCount"] ?? "") }
                    LabeledContent("rewards.pledge.stock") { Text(verbatim: stats.fields["stock.available"] ?? "") }
                    Text(verbatim: stats.fields["pledgeId"] ?? "").accessibilityIdentifier("rewards.pledge.original")
                    Text(verbatim: stats.fields["versionId"] ?? "").accessibilityIdentifier("rewards.pledge.originalVersion")
                }
            }
            if !model.pledgeID.isEmpty { Text(verbatim: model.pledgeID).accessibilityIdentifier("rewards.pledge.pledge") }
            if let state = model.merchantResult?.fields["version.state"] { Text(verbatim: state).accessibilityIdentifier("rewards.pledge.version") }
            if let notice = model.notice { Text(notice).accessibilityIdentifier("rewards.pledge.notice") }
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
                if entry.current()?.expire == true {
                    Button("rewards.pledge.expire") { Task { await model.expireAward(entry: entry) } }
                        .disabled(model.busy || model.selected == nil).accessibilityIdentifier("rewards.pledge.expire")
                }
                if entry.current()?.returnPool == true, model.serviceOutlivesCoupon {
                    Button("rewards.pledge.return") { Task { await model.returnAward(entry: entry) } }
                        .disabled(model.busy || model.selected == nil).accessibilityIdentifier("rewards.pledge.return")
                } else if entry.current()?.returnPool == true {
                    Text("rewards.unavailable").accessibilityIdentifier("rewards.pledge.returnClosed")
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

/// Review stays off this merchant's own draft. There is no list of pledges waiting for a reviewer.
@MainActor struct RewardPledgeReviewHost: View {
    let entry: RewardPledgeEntry
    var body: some View {
        Form {
            if entry.current()?.freeze == true {
                Text("rewards.unavailable").accessibilityIdentifier("rewards.pledge.reviewQueue")
            }
        }
        .navigationTitle("rewards.pledge.freeze")
    }
}

@MainActor struct RewardPledgeMerchantHost: View {
    let entry: RewardPledgeEntry
    @StateObject private var model: RewardPledgeModel
    init(entry: RewardPledgeEntry) {
        self.entry = entry
        _model = StateObject(wrappedValue: RewardPledgeModel(accountID: entry.accountID, storeID: "", policy: .unset, journalURL: entry.journalURL))
    }
    var body: some View {
        RewardPledgeMerchantView(model: model, entry: entry)
            .onChange(of: entry.accountID) { _, accountID in model.replaceAccount(accountID, store: "") }
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
