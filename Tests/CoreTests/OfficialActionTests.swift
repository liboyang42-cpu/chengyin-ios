import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class OAStub: HTTPTransport {
    var requests: [URLRequest] = []
    var json = #"{"code":200,"data":91}"#
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(json.utf8), 200) }
}
@MainActor private final class OAMemoryLocks: OfficialActionLockStore {
    var values: Set<String> = []
    var fail = false
    func contains(_ key: String) throws -> Bool { values.contains(key) }
    func insert(_ key: String) throws { if fail { throw OfficialActionFailure.storage }; values.insert(key) }
    func remove(_ key: String) throws { values.remove(key) }
}
@MainActor final class OfficialActionTests: XCTestCase {
    private let identity = OfficialActionIdentity(accountID: 77, epoch: UUID(), namespace: "synthetic")
    private func event(_ additions: String = "") throws -> OfficialEvent {
        try JSONDecoder().decode(OfficialEvent.self, from: Data((#"{"id":8,"title":"Synthetic event","status":3,"signed":false"# + additions + "}").utf8))
    }
    private func snapshot(_ e: OfficialEvent? = nil, publisher: Bool = true) -> OfficialActionSnapshot {
        .init(identity: identity, publisher: publisher, event: e)
    }
    func testPublishWireContract() throws {
        var draft = OfficialEventDraft(); draft.title = " Example "; draft.end = Date(timeIntervalSince1970: 100)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: draft.payload()) as? [String: Any])
        XCTAssertEqual(Set(body.keys), Set(["title", "subtitle", "city", "category", "activityStart", "activityEnd", "settleTime", "collectiveEnabled", "collectiveMetric", "collectiveThreshold", "rewardJson"]))
        XCTAssertEqual(body["title"] as? String, "Example"); XCTAssertEqual(body["settleTime"] as? Double, 100000)
    }
    func testBroadcastRequiresExplicitAudienceAndChannels() throws {
        var draft = OfficialBroadcastDraft(); draft.unified.title = "Synthetic"
        XCTAssertThrowsError(try draft.payload()); draft.audience = [.merchant, .player]
        XCTAssertThrowsError(try draft.payload()); draft.channels = [.subscribe, .inapp]
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: draft.payload()) as? [String: Any])
        XCTAssertEqual(object["audience"] as? String, "player,merchant"); XCTAssertEqual(object["channels"] as? String, "inapp,subscribe")
    }
    func testSplitCopyExcludesUnselectedRoles() throws {
        var draft = OfficialBroadcastDraft(); draft.split = true; draft.audience = [.club]; draft.channels = [.inapp]
        draft.copies = [.club: .init(title: "Club"), .merchant: .init(title: "Hidden")]
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: draft.payload()) as? [String: Any])
        let content = try XCTUnwrap(object["contentJson"] as? String)
        XCTAssertTrue(content.contains("club")); XCTAssertFalse(content.contains("Hidden"))
    }
    func testSignupOnlyExplicitUnsignedOpenEvent() throws {
        try snapshot(event()).validate(.signup(8), now: Date())
        let paused = try event(#", "paused":true"#)
        XCTAssertThrowsError(try snapshot(paused).validate(.signup(8), now: Date()))
        XCTAssertThrowsError(try snapshot(event()).validate(.signup(9), now: Date()))
    }
    func testCompleteCannotFabricateV2Progress() throws {
        let e = try JSONDecoder().decode(OfficialEvent.self, from: Data(#"{"id":8,"title":"Synthetic","status":3,"signed":true,"contractVersion":2}"#.utf8))
        XCTAssertThrowsError(try snapshot(e).validate(.complete(8), now: Date()))
    }
    func testPartyRoutesAndReasonContract() throws {
        let c = OfficialActionCommand.respond(partyID: 4, type: "CLUB", action: .decline, reason: "Synthetic reason")
        XCTAssertEqual(c.path, "api/official/v2/parties/4/DECLINE")
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(c.payload())) as? [String: String])
        XCTAssertEqual(value, ["reason": "Synthetic reason"])
        let official = OfficialActionCommand.respond(partyID: 4, type: "OFFICIAL", action: .accept, reason: nil)
        XCTAssertEqual(official.path, "api/official/v2/organizer-invites/4/accept"); XCTAssertNil(try official.payload())
    }
    func testUnknownPartyAndOfficialWithdrawRejected() throws {
        XCTAssertThrowsError(try OfficialActionCommand.respond(partyID: 4, type: "UNKNOWN", action: .accept, reason: nil).payload())
        XCTAssertThrowsError(try OfficialActionCommand.respond(partyID: 4, type: "OFFICIAL", action: .withdraw, reason: nil).payload())
    }
    func testArrivalRejectsStaleEvidenceAndWrongIdentity() throws {
        let evidence = OfficialArrivalEvidence(identity: identity, eventID: 8, sessionID: 3, missionCode: "ARRIVE", requestID: "synthetic-request", latitude: 0, longitude: 0, accuracyM: 5, expiresAt: .distantPast)
        XCTAssertThrowsError(try snapshot(event()).validate(.arrival(evidence), now: Date()))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(OfficialActionCommand.arrival(evidence).payload())) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["missionCode", "latitude", "longitude", "accuracyM", "sessionId", "requestId"]))
    }
    func testDefaultServiceIsOffWithZeroRequests() async throws {
        let t = OAStub(); let config = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let api = OfficialActionService(configuration: config, transport: t)
        do { _ = try await api.send(.signup(8), token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .disabled) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testFakeTransportRouteAndStrictID() async throws {
        let t = OAStub(); let config = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let api = OfficialActionService(configuration: config, transport: t, enabled: true)
        var draft = OfficialEventDraft(); draft.title = "Synthetic"
        let result = try await api.send(.publish(draft), token: "synthetic-token")
        XCTAssertEqual(result, .published(91)); XCTAssertEqual(t.requests.first?.url?.path, "/api/official/publish")
        XCTAssertEqual(t.requests.first?.httpMethod, "POST")
        t.json = #"{"code":200,"data":true}"#
        do { _ = try await api.send(.publish(draft), token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .unknown) }
    }
    func testPersistentLockSurvivesRecreation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try OfficialActionFileLocks(url: url).insert("synthetic-key")
        XCTAssertTrue(try OfficialActionFileLocks(url: url).contains("synthetic-key"))
    }
    func testCorruptLockStoreFailsClosed() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("corrupt".utf8).write(to: url)
        XCTAssertThrowsError(try OfficialActionFileLocks(url: url).contains("key"))
    }
    func testAcknowledgmentIsLockedAndNotAttendance() async throws {
        let access = OAFakeAccess(snapshot: snapshot(try event()))
        let locks = OAMemoryLocks(); let coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let review = try await coordinator.prepare(.signup(8)); let receipt = try await coordinator.confirm(review)
        XCTAssertEqual(receipt, .acknowledged); XCTAssertEqual(access.value.event?.signed, false)
        do { _ = try await coordinator.prepare(.signup(8)); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .locked) }
        XCTAssertEqual(access.sends, 1)
    }
    func testEpochChangeInvalidatesReviewWithoutSend() async throws {
        let access = OAFakeAccess(snapshot: snapshot(try event())); let coordinator = OfficialActionCoordinator(access: access, locks: OAMemoryLocks())
        let review = try await coordinator.prepare(.signup(8)); access.identity = .init(accountID: 77, epoch: UUID(), namespace: "synthetic")
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .stale) }
        XCTAssertEqual(access.sends, 0)
    }
    func testUnknownWriteRemainsLockedAcrossCoordinator() async throws {
        let access = OAFakeAccess(snapshot: snapshot(try event())); access.failure = .unknown
        let locks = OAMemoryLocks(); let first = OfficialActionCoordinator(access: access, locks: locks)
        let review = try await first.prepare(.signup(8))
        do { _ = try await first.confirm(review); XCTFail() } catch {}
        let second = OfficialActionCoordinator(access: access, locks: locks)
        do { _ = try await second.prepare(.signup(8)); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .locked) }
    }
    func testLockWriteFailurePreventsDispatch() async throws {
        let access = OAFakeAccess(snapshot: snapshot(try event())); let locks = OAMemoryLocks(); locks.fail = true
        let coordinator = OfficialActionCoordinator(access: access, locks: locks); let review = try await coordinator.prepare(.signup(8))
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        XCTAssertEqual(access.sends, 0)
    }
    func testCancelMakesReviewUnusable() async throws {
        let access = OAFakeAccess(snapshot: snapshot(try event())); let coordinator = OfficialActionCoordinator(access: access, locks: OAMemoryLocks())
        let review = try await coordinator.prepare(.signup(8)); coordinator.cancelReview()
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .stale) }
        XCTAssertEqual(access.sends, 0)
    }
    func testBusinessRejectionAllowsFreshReview() async throws {
        let access = OAFakeAccess(snapshot: snapshot(try event())); access.failure = .rejected(500, "Synthetic rejection")
        let coordinator = OfficialActionCoordinator(access: access, locks: OAMemoryLocks())
        let review = try await coordinator.prepare(.signup(8))
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        _ = try await coordinator.prepare(.signup(8))
        XCTAssertEqual(access.sends, 1)
    }
    func testPublisherAndMerchantSelectionFailClosed() throws {
        var draft = OfficialEventDraft(); draft.title = "Synthetic"
        XCTAssertThrowsError(try snapshot(publisher: false).validate(.publish(draft), now: Date()))
        XCTAssertThrowsError(try snapshot().validate(.inviteMerchants([1]), now: Date()))
        XCTAssertThrowsError(try OfficialActionCommand.inviteMerchants([1, 1]).payload())
    }
    func testPartyStateControlsWithdraw() throws {
        let invite = try JSONDecoder().decode(OfficialPartyInvite.self, from: Data(#"{"partyId":4,"partyType":"MERCHANT","status":"ACCEPTED"}"#.utf8))
        let value = OfficialActionSnapshot(identity: identity, invite: invite)
        try value.validate(.respond(partyID: 4, type: "MERCHANT", action: .withdraw, reason: nil), now: Date())
        XCTAssertThrowsError(try value.validate(.respond(partyID: 4, type: "MERCHANT", action: .accept, reason: nil), now: Date()))
    }
    func testArrivalFactsAreStrictAndDoNotImplyRewards() async throws {
        let t = OAStub(); t.json = #"{"code":200,"data":{"accepted":false,"completed":false}}"#
        let api = OfficialActionService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: t, enabled: true)
        let evidence = OfficialArrivalEvidence(identity: identity, eventID: 8, sessionID: 3, missionCode: "ARRIVE", requestID: "synthetic", latitude: 0, longitude: 0, accuracyM: 5, expiresAt: .distantFuture)
        let result = try await api.send(.arrival(evidence), token: "synthetic-token")
        XCTAssertEqual(result, .arrival(accepted: false, completed: false, reason: nil))
        t.json = #"{"code":200,"data":{"accepted":1,"completed":true}}"#
        do { _ = try await api.send(.arrival(evidence), token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .unknown) }
    }
    func testIdentityChangeAfterDispatchKeepsUnknownLock() async throws {
        let access = OAFakeAccess(snapshot: snapshot(try event()))
        access.afterSend = { access.identity = nil }
        let locks = OAMemoryLocks(); let coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let review = try await coordinator.prepare(.signup(8))
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .unknown) }
        XCTAssertEqual(coordinator.state, .unknown); XCTAssertEqual(locks.values.count, 1)
    }
    func testReviewCannotBeConfirmedTwice() async throws {
        let access = OAFakeAccess(snapshot: snapshot(try event())); let coordinator = OfficialActionCoordinator(access: access, locks: OAMemoryLocks())
        let review = try await coordinator.prepare(.signup(8)); _ = try await coordinator.confirm(review)
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        XCTAssertEqual(access.sends, 1)
    }
    func testChangedServerFactsRequireNewReview() async throws {
        let access = OAFakeAccess(snapshot: snapshot(try event())); let coordinator = OfficialActionCoordinator(access: access, locks: OAMemoryLocks())
        let review = try await coordinator.prepare(.signup(8)); access.value = snapshot(try event(#", "paused":true"#))
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        XCTAssertEqual(access.sends, 0)
    }
}
@MainActor private final class OAFakeAccess: OfficialActionAccess {
    var identity: OfficialActionIdentity?
    var enabled = true
    var value: OfficialActionSnapshot
    var sends = 0
    var failure: OfficialActionFailure?
    var afterSend: (() -> Void)?
    init(snapshot: OfficialActionSnapshot) { value = snapshot; identity = snapshot.identity }
    func snapshot(for command: OfficialActionCommand) async throws -> OfficialActionSnapshot { value }
    func send(_ command: OfficialActionCommand) async throws -> OfficialActionReceipt {
        sends += 1; afterSend?(); if let failure { throw failure }; return .acknowledged
    }
}
