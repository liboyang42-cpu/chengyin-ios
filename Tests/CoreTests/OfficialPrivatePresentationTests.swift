import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class OPPAccess: OfficialActionAccess {
    let identity: OfficialActionIdentity? = .init(accountID: 77, epoch: UUID(), namespace: "synthetic")
    var enabled = false
    var invite: OfficialPartyInvite?
    var sends = 0
    func snapshot(for command: OfficialActionCommand) async throws -> OfficialActionSnapshot {
        OfficialActionSnapshot(identity: identity!, publisher: true, invite: invite)
    }
    func send(_ command: OfficialActionCommand) async throws -> OfficialActionReceipt { sends += 1; throw OfficialActionFailure.unknown }
}
@MainActor private final class OPPLocks: OfficialActionLockStore {
    var values: Set<String> = []
    func contains(_ key: String) throws -> Bool { values.contains(key) }
    func insert(_ key: String) throws { values.insert(key) }
    func remove(_ key: String) throws { values.remove(key) }
}

/// Source pages/activity/official-inbox and official-mine parity (synthetic records only).
@MainActor final class OfficialPrivatePresentationTests: XCTestCase {
    private func invite(_ json: String) throws -> OfficialPartyInvite {
        try JSONDecoder().decode(OfficialPartyInvite.self, from: Data(json.utf8))
    }
    private func body(_ command: OfficialActionCommand) throws -> [String: String] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(command.payload())) as? [String: String])
    }

    func testEveryInvitedRowOffersDeclineThenAcceptIncludingOfficial() throws {
        for type in ["OFFICIAL", "MERCHANT", "CLUB"] {
            let row = try invite(#"{"partyId":4,"partyType":""# + type + #"","role":"ORGANIZER","status":"INVITED"}"#)
            XCTAssertEqual(OfficialInboxPresentation.actions(for: row), [.decline, .accept])
        }
        XCTAssertEqual(OfficialInboxPresentation.actions(for: try invite(#"{"partyId":4,"partyType":"MERCHANT","status":"DECLINED"}"#)), [])
        XCTAssertEqual(OfficialInboxPresentation.actions(for: try invite(#"{"partyId":4,"partyType":"MERCHANT"}"#)), [])
    }
    func testAcceptedOrganizerShowsTransferNoticeInsteadOfWithdraw() throws {
        let organizer = try invite(#"{"partyId":4,"partyType":"OFFICIAL","role":"ORGANIZER","status":"ACTIVE"}"#)
        XCTAssertEqual(OfficialInboxPresentation.actions(for: organizer), [])
        XCTAssertTrue(OfficialInboxPresentation.showsOrganizerTransferNotice(organizer))
        XCTAssertTrue(OfficialInboxPresentation.requiresOrganizerTransfer(organizer, action: .withdraw))
        let merchant = try invite(#"{"partyId":5,"partyType":"MERCHANT","role":"FULFILLMENT_MERCHANT","status":"ACCEPTED"}"#)
        XCTAssertEqual(OfficialInboxPresentation.actions(for: merchant), [.withdraw])
        XCTAssertFalse(OfficialInboxPresentation.showsOrganizerTransferNotice(merchant))
        XCTAssertFalse(OfficialInboxPresentation.requiresOrganizerTransfer(merchant, action: .withdraw))
        let coOrganizer = try invite(#"{"partyId":6,"partyType":"OFFICIAL","role":"CO_ORGANIZER","status":"ACCEPTED"}"#)
        XCTAssertTrue(OfficialInboxPresentation.requiresOrganizerTransfer(coOrganizer, action: .withdraw))
    }
    func testFixedSourceReasonsReplaceFreeText() throws {
        XCTAssertEqual(OfficialResponseAction.decline.sourceReason, "主体拒绝本场邀约")
        XCTAssertEqual(OfficialResponseAction.withdraw.sourceReason, "主体退出本场职责")
        XCTAssertEqual(OfficialResponseAction.accept.sourceReason, "")
        let club = try invite(#"{"partyId":4,"partyType":"CLUB","status":"INVITED"}"#)
        let decline = OfficialActionCommand.sourceInboxResponse(to: club, action: .decline)
        XCTAssertEqual(decline, .respond(partyID: 4, type: "CLUB", action: .decline, reason: "主体拒绝本场邀约"))
        XCTAssertEqual(decline.path, "api/official/v2/parties/4/DECLINE")
        XCTAssertEqual(try body(decline), ["reason": "主体拒绝本场邀约"])
        let accepted = try invite(#"{"partyId":4,"partyType":"CLUB","status":"ACCEPTED"}"#)
        XCTAssertEqual(try body(.sourceInboxResponse(to: accepted, action: .withdraw)), ["reason": "主体退出本场职责"])
        XCTAssertEqual(try body(.sourceInboxResponse(to: club, action: .accept)), ["reason": ""])
    }
    func testOrganizerRoutesCarryFixedReasonAndWithdrawStaysInvalid() throws {
        let organizer = try invite(#"{"partyId":9,"partyType":"OFFICIAL","role":"ORGANIZER","status":"INVITED"}"#)
        let decline = OfficialActionCommand.sourceInboxResponse(to: organizer, action: .decline)
        XCTAssertEqual(decline.path, "api/official/v2/organizer-invites/9/decline")
        XCTAssertEqual(try body(decline), ["reason": "主体拒绝本场邀约"])
        XCTAssertEqual(OfficialActionCommand.sourceInboxResponse(to: organizer, action: .accept).path, "api/official/v2/organizer-invites/9/accept")
        XCTAssertThrowsError(try OfficialActionCommand.sourceInboxResponse(to: organizer, action: .withdraw).payload())
        // The legacy bodiless organizer request is unchanged when no reason is supplied.
        XCTAssertNil(try OfficialActionCommand.respond(partyID: 9, type: "OFFICIAL", action: .accept, reason: nil).payload())
    }
    func testFixedReasonReviewStillNeedsGateAndKeepsStableScope() async throws {
        let row = try invite(#"{"partyId":4,"partyType":"MERCHANT","status":"INVITED"}"#)
        let access = OPPAccess(); access.invite = row
        let locks = OPPLocks()
        let coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let command = OfficialActionCommand.sourceInboxResponse(to: row, action: .decline)
        XCTAssertEqual(command.scope, "party:4")
        let review = try await coordinator.prepare(command)
        XCTAssertEqual(review.body, try command.payload())
        do { _ = try await coordinator.confirm(review); XCTFail("disabled gate must refuse") }
        catch { XCTAssertEqual(error as? OfficialActionFailure, .disabled) }
        XCTAssertEqual(access.sends, 0); XCTAssertTrue(locks.values.isEmpty)
    }
    func testUncertainOutcomeStaysLockedWhenEnabledInTests() async throws {
        let row = try invite(#"{"partyId":4,"partyType":"MERCHANT","status":"ACCEPTED"}"#)
        let access = OPPAccess(); access.invite = row; access.enabled = true
        let locks = OPPLocks()
        let coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let review = try await coordinator.prepare(.sourceInboxResponse(to: row, action: .withdraw))
        do { _ = try await coordinator.confirm(review); XCTFail("unknown outcome must throw") } catch {}
        XCTAssertEqual(access.sends, 1); XCTAssertEqual(coordinator.state, .unknown); XCTAssertEqual(locks.values.count, 1)
        do { _ = try await coordinator.prepare(.sourceInboxResponse(to: row, action: .withdraw)); XCTFail("locked") }
        catch { XCTAssertEqual(error as? OfficialActionFailure, .locked) }
    }
    func testConfirmationCopyKeysFollowSourceModal() throws {
        let organizer = try invite(#"{"partyId":9,"partyType":"OFFICIAL","role":"ORGANIZER","status":"INVITED"}"#)
        let club = try invite(#"{"partyId":4,"partyType":"CLUB","status":"INVITED"}"#)
        XCTAssertEqual(OfficialInboxPresentation.confirmationTitleKey(organizer, action: .accept), "official.privateParity.inbox.confirm.acceptOrganizerTitle")
        XCTAssertEqual(OfficialInboxPresentation.confirmationBodyKey(organizer, action: .decline), "official.privateParity.inbox.confirm.organizerDeclineBody")
        XCTAssertEqual(OfficialInboxPresentation.confirmationTitleKey(club, action: .accept), "official.privateParity.inbox.confirm.acceptTitle")
        XCTAssertEqual(OfficialInboxPresentation.confirmationBodyKey(club, action: .withdraw), "official.privateParity.inbox.confirm.changeBody")
        XCTAssertEqual(OfficialInboxPresentation.buttonKey(.accept), "official.privateParity.inbox.accept")
    }
    func testServiceWindowFormatsNumericOnlyInShanghai() throws {
        func window(_ json: String) throws -> OfficialServiceWindow {
            try JSONDecoder().decode(OfficialInboxWindowFacts.self, from: Data(json.utf8)).window
        }
        // 2030-01-01T01:05:00Z == 09:05 in Asia/Shanghai.
        XCTAssertEqual(try window(#"{"windowStart":1893459900000,"windowEnd":"1893549600000"}"#).sourceText, "1月1日 09:05 — 1月2日 10:00")
        XCTAssertEqual(try window(#"{"windowStart":1893459900000}"#).sourceText, "1月1日 09:05 — 不限")
        XCTAssertEqual(try window(#"{"windowStart":"2026-09-22T09:00:00"}"#).sourceText, "2026-09-22T09:00:00 — 不限")
        XCTAssertEqual(try window("{}"), .unbounded)
        XCTAssertEqual(try window("{}").sourceText, "未限定服务时段")
    }
    func testPublisherStatusUsesOwnerLabels() {
        XCTAssertEqual(OfficialPublishedPresentation.ownerStatusKey(0), "official.privateParity.published.status.draft")
        XCTAssertEqual(OfficialPublishedPresentation.ownerStatusKey(1), "official.privateParity.published.status.pending")
        XCTAssertEqual(OfficialPublishedPresentation.ownerStatusKey(6), "official.privateParity.published.status.ended")
        XCTAssertEqual(OfficialPublishedPresentation.ownerStatusKey(9), "official.privateParity.published.status.offline")
        XCTAssertEqual(OfficialPublishedPresentation.ownerStatusKey(7), "official.privateParity.published.status.unknown")
        XCTAssertEqual(OfficialPublishedPresentation.ownerStatusKey(nil), "official.privateParity.published.status.unknown")
        XCTAssertNil(OfficialPublishedPresentation.nonBlank("  \n"))
        XCTAssertEqual(OfficialPublishedPresentation.nonBlank(" Example city "), "Example city")
    }
    func testBroadcastRowFollowsSourceAndKeepsUnknownsExplicit() throws {
        func facts(_ json: String) throws -> OfficialPublishedBroadcastFacts {
            try JSONDecoder().decode(OfficialPublishedBroadcastFacts.self, from: Data(json.utf8))
        }
        let known = try facts(#"{"id":91,"copyMode":2,"audience":"player, merchant","status":2,"city":" Example city "}"#)
        XCTAssertEqual(known.sourceLine, "分开发 · 发给 玩家 / 商家 · Example city")
        XCTAssertEqual(known.sourceStatusText, "已发")
        let unknown = try facts(#"{"id":92,"copyMode":5,"audience":"player,future","status":8,"city":" "}"#)
        XCTAssertNil(unknown.audience)
        XCTAssertEqual(unknown.sourceLine, "发送方式待确认 · 发给 对象待确认 · 范围待确认")
        XCTAssertEqual(unknown.sourceStatusText, "状态待确认")
        XCTAssertEqual(try facts(#"{"copyMode":1,"audience":"club","status":0}"#).sourceLine, "一起发 · 发给 俱乐部 · 范围待确认")
    }
}
