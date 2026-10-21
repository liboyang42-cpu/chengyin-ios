import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class RewardPledgeTests: XCTestCase {
    private let digest = "4519c0b051d2fda04db36e4e9e7042d27ab76f0746807aed50f34c1308eb0494"

    private func approved() -> RewardPledgePolicy {
        var policy = RewardPledgePolicy.unset
        policy.ruleVersion = "rule-a"
        policy.validity = "server-window"
        policy.quota = 2
        policy.reserveShare = 1
        policy.serviceCapacity = 4
        policy.merchantEvidence = "evidence-1"
        policy.nonCashEnabled = true
        policy.readSource = .plannedController
        policy.refusalPolicy = "manual"
        return policy
    }

    private func capabilities() -> SponsoredRewardCapabilities {
        var value = SponsoredRewardCapabilities()
        value.nonCash = true
        return value
    }

    private func terms(_ machine: RewardPledgeMachine) throws -> RewardPledgeTerms {
        let read = machine.readTerms(serverRule: "rule-a", serverLimit: "two left", serverValidity: "server-window",
                                     eligibility: "fact-9", rewardScope: "scope-theme", beneficiary: "42", storeID: "7",
                                     serverQuota: 2, minorPrize: false, reviewRequired: false, clientComplete: false,
                                     capabilities: capabilities(), seen: machine.scope)
        guard case .success(let value) = read else { throw RewardPledgeFailure.closed("read") }
        return value
    }

    func testStableIntentAndUnknownRecovery() throws {
        var machine = RewardPledgeMachine(accountID: "42", storeID: "7", policy: approved())
        let terms = try terms(machine)
        XCTAssertEqual(RewardPledgeIdentity.requestID(for: terms.businessKey), digest)
        guard case .success(let first) = machine.confirmClaim(terms, seen: machine.scope) else { return XCTFail("confirm") }
        guard case .success(let second) = machine.confirmClaim(terms, seen: machine.scope) else { return XCTFail("reconfirm") }
        XCTAssertEqual(first.requestID, digest)
        XCTAssertEqual(second.requestID, first.requestID)
        guard case .success(let row) = machine.recordUnknown(first, seen: machine.scope) else { return XCTFail("unknown") }
        XCTAssertEqual(row.requestID, digest)
        let stale = machine.recoveryIntent(row, proposedRequestID: String(repeating: "a", count: 64), seen: machine.scope)
        guard case .failure(.closed("requestID")) = stale else { return XCTFail("new id") }
        guard case .success(let recovered) = machine.recoveryIntent(row, proposedRequestID: row.requestID, seen: machine.scope) else { return XCTFail("recover") }
        XCTAssertEqual(recovered.requestID, digest)
        guard case .success = machine.acceptGrant(awardID: "award-1", termsVersion: "t1", termsText: "frozen terms", requestID: recovered.requestID, businessKey: recovered.businessKey, seen: machine.scope) else { return XCTFail("grant") }
        XCTAssertEqual(machine.grant?.state, "GRANTED_UNREDEEMED")
        XCTAssertTrue(machine.unknowns.isEmpty)
        guard case .success(let path) = machine.markRefreshed(seen: machine.scope) else { return XCTFail("refresh") }
        XCTAssertEqual(path, "api/rewards/noncash")
        XCTAssertTrue(machine.listRefreshed)
        XCTAssertTrue(machine.detailRefreshed)
        XCTAssertEqual(RewardPledgeRoutes.detailPath(.plannedController, awardID: "award-1"), "api/rewards/noncash/award-1")
    }

    func testUnsetPolicyCashSwitchAndClientCompleteFailClosed() {
        let open = RewardPledgeMachine(accountID: "42", storeID: "7", policy: .unset)
        let denied = open.readTerms(serverRule: "rule-a", serverLimit: "two left", serverValidity: "server-window",
                                   eligibility: "fact-9", rewardScope: "scope-theme", beneficiary: "42", storeID: "7",
                                   serverQuota: 2, minorPrize: false, reviewRequired: false, clientComplete: false,
                                   capabilities: capabilities(), seen: open.scope)
        guard case .failure(.closed("nonCashEnabled")) = denied else { return XCTFail("unset") }
        var caps = capabilities()
        caps.cash = true
        let machine = RewardPledgeMachine(accountID: "42", storeID: "7", policy: approved())
        let cash = machine.readTerms(serverRule: "rule-a", serverLimit: "two left", serverValidity: "server-window",
                                    eligibility: "fact-9", rewardScope: "scope-theme", beneficiary: "42", storeID: "7",
                                    serverQuota: 2, minorPrize: false, reviewRequired: false, clientComplete: false,
                                    capabilities: caps, seen: machine.scope)
        guard case .failure(.closed("switches")) = cash else { return XCTFail("cash") }
        let complete = machine.readTerms(serverRule: "rule-a", serverLimit: "two left", serverValidity: "server-window",
                                        eligibility: "fact-9", rewardScope: "scope-theme", beneficiary: "42", storeID: "7",
                                        serverQuota: 2, minorPrize: false, reviewRequired: false, clientComplete: true,
                                        capabilities: capabilities(), seen: machine.scope)
        guard case .failure(.closed("clientComplete")) = complete else { return XCTFail("complete") }
        XCTAssertEqual(machine.replenish(), .closed("topUp"))
        var topped = approved()
        topped.topUp = "approved"
        XCTAssertEqual(RewardPledgeMachine(accountID: "42", storeID: "7", policy: topped).replenish(), .closed("W06"))
    }

    func testJournalRestartIsolationAndTerminalCases() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pledge-\(UUID().uuidString).json")
        let journal = RewardPledgeFileJournal(url: url)
        var machine = RewardPledgeMachine(accountID: "42", storeID: "7", policy: approved())
        let terms = try terms(machine)
        guard case .success(let intent) = machine.confirmClaim(terms, seen: machine.scope) else { return XCTFail("confirm") }
        guard case .success = machine.recordUnknown(intent, seen: machine.scope) else { return XCTFail("unknown") }
        let other = RewardPledgeUnknown(ownerID: "99", storeID: "7", businessKey: "other", requestID: RewardPledgeIdentity.requestID(for: "other"), kind: "claim")
        try journal.save(machine.persistedRows(existing: [other]))
        let restarted = RewardPledgeMachine.restored(accountID: "42", storeID: "7", policy: approved(), journal: try journal.load())
        XCTAssertEqual(restarted.unknowns.map(\.requestID), [digest])
        var switched = restarted
        switched.replaceAccount("99", store: "7", journal: try journal.load())
        XCTAssertEqual(switched.unknowns, [other])
        XCTAssertNotEqual(switched.scope.generation, restarted.scope.generation)
        let old = restarted.recoveryIntent(restarted.unknowns[0], proposedRequestID: digest, seen: restarted.scope)
        guard case .failure(.stale) = switched.recoveryIntent(restarted.unknowns[0], proposedRequestID: digest, seen: oldScope(restarted)) else { return XCTFail("stale query") }
        _ = old
        guard case .success = machine.acceptGrant(awardID: "award-1", termsVersion: "t1", termsText: "frozen terms", requestID: intent.requestID, businessKey: intent.businessKey, seen: machine.scope) else { return XCTFail("grant") }
        guard case .success = machine.preview(permissionStore: "7", seen: machine.scope) else { return XCTFail("preview") }
        guard case .success(let expired) = machine.expire(awardID: "award-1", seen: machine.scope) else { return XCTFail("expire") }
        XCTAssertEqual(expired.reason, "EXPIRED")
        XCTAssertFalse(expired.readable.isEmpty)
        let blocked = machine.beginRedeem(explicit: true, historyID: "award-1", serverCapacity: 4, seen: machine.scope)
        guard case .failure(.terminal(let reason)) = blocked, reason == "EXPIRED" else { return XCTFail("redeem after expire") }
    }

    func testPledgeFreezeStaffRoutesAndSingleReadSource() throws {
        var machine = RewardPledgeMachine(accountID: "42", storeID: "7", policy: approved())
        guard case .success(let draft) = machine.saveDraft(pledgeID: "p1", quantityText: "2", termsText: "bring the card", serverReserve: 1, seen: machine.scope) else { return XCTFail("draft") }
        XCTAssertEqual(draft.status, "DRAFT")
        guard case .success(let submitted) = machine.submitDraft(seen: machine.scope) else { return XCTFail("submit") }
        guard case .success(let frozen) = machine.freeze(serverVersion: submitted.version, seen: machine.scope) else { return XCTFail("freeze") }
        XCTAssertEqual(frozen.status, "FROZEN")
        XCTAssertNil(machine.draft)
        let terms = try terms(machine)
        guard case .success(let intent) = machine.confirmClaim(terms, seen: machine.scope) else { return XCTFail("confirm") }
        guard case .success = machine.acceptGrant(awardID: "15", termsVersion: "t1", termsText: "frozen terms", requestID: intent.requestID, businessKey: intent.businessKey, seen: machine.scope) else { return XCTFail("grant") }
        guard case .success = machine.withdraw(seen: machine.scope) else { return XCTFail("withdraw") }
        XCTAssertEqual(machine.grant?.awardID, "15")
        XCTAssertEqual(machine.frozen?.status, "WITHDRAWN")
        XCTAssertEqual(machine.serviceCase?.reason, "WITHDRAWN")
        var staff = RewardPledgeMachine(accountID: "42", storeID: "7", policy: approved())
        guard case .success(let staffIntent) = staff.confirmClaim(try terms(staff), seen: staff.scope) else { return XCTFail("staff confirm") }
        _ = staff.acceptGrant(awardID: "15", termsVersion: "t1", termsText: "frozen terms", requestID: staffIntent.requestID, businessKey: staffIntent.businessKey, seen: staff.scope)
        XCTAssertNil(try? staffPreviewWrongStore(&staff))
        guard case .success = staff.preview(permissionStore: "7", seen: staff.scope) else { return XCTFail("preview") }
        guard case .failure(.stale) = staff.preview(permissionStore: "8", seen: staff.scope) else { return XCTFail("cross store") }
        guard case .success(let redeem) = staff.beginRedeem(explicit: true, historyID: "15", serverCapacity: 4, seen: staff.scope) else { return XCTFail("redeem") }
        XCTAssertEqual(staff.staffRoutes, ["api/coupon/qr-token", "api/coupon/status", "api/coupon/verification", "api/coupon/myrecvlist"])
        let base = try APIConfiguration(baseURL: URL(string: "https://example.com")!).baseURL
        let requests = try RewardPledgeRequests.staff(historyID: 15, verificationCode: "code-1", baseURL: base, token: "fixture-token")
        XCTAssertEqual(requests.compactMap { $0.url?.path }, staff.staffRoutes.map { "/" + $0 })
        XCTAssertFalse(requests.contains { $0.url?.path.contains("citynode") == true })
        XCTAssertThrowsError(try RewardPledgeRequests.query(original: redeem.asUnknown, proposedRequestID: "other", baseURL: base, token: "fixture-token"))
        let query = try RewardPledgeRequests.query(original: redeem.asUnknown, proposedRequestID: redeem.requestID, baseURL: base, token: "fixture-token")
        XCTAssertEqual(query.httpMethod, "GET")
        XCTAssertTrue(query.url?.query?.contains(redeem.requestID) == true)
        var closed = approved(); closed.readSource = nil
        staff.applyPolicy(closed)
        guard case .failure(.closed("readSource")) = staff.refreshSource() else { return XCTFail("unset source") }
        var coupon = approved(); coupon.readSource = .couponHistory
        staff.applyPolicy(coupon)
        XCTAssertEqual(try staff.refreshSource().get(), "api/coupon/myrecvlist")
        XCTAssertEqual(RewardPledgeRoutes.detailPath(.couponHistory, awardID: "15"), "api/coupon/myrecvlist")
        XCTAssertFalse(CityNodeRedemptionCode.acceptsPledgeRedeem("api/coupon/verification"))
        let item = SponsoredPoolItem(itemID: "i", pledgeID: "p", pledgeVersion: "1", merchantID: "1", storeID: "7", kind: .coupon,
                                     allocation: .fixedMilestone, title: "hat", termsVersion: "t", termsText: "bring the card",
                                     validFrom: Date(timeIntervalSince1970: 1), validUntil: Date(timeIntervalSince1970: 2),
                                     remaining: 1, guaranteeReserved: false, asOf: Date(timeIntervalSince1970: 1))
        XCTAssertTrue(item.pledgePresentable(capabilities()))
        var guaranteed = capabilities(); guaranteed.guaranteed = true
        XCTAssertFalse(item.pledgePresentable(guaranteed))
    }

    private func staffPreviewWrongStore(_ machine: inout RewardPledgeMachine) throws -> RewardPledgeGrant {
        let preview = machine.preview(permissionStore: "8", seen: machine.scope)
        guard case .success(let value) = preview else { throw RewardPledgeFailure.stale }
        return value
    }

    private func oldScope(_ machine: RewardPledgeMachine) -> RewardPledgeScope { machine.scope }
}

private extension RewardPledgeIntent {
    var asUnknown: RewardPledgeUnknown {
        RewardPledgeUnknown(ownerID: ownerID, storeID: storeID, businessKey: businessKey, requestID: requestID, kind: kind)
    }
}
