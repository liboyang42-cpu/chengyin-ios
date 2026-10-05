import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class OfficialActionProductionTests: XCTestCase {
    private let url = URL(string: "https://example.com")!
    private let owner = OfficialActionIdentity(accountID: 71, epoch: UUID(), namespace: "official-cn")
    private func context(account: Int = 71, epoch: UInt64 = 1, token: String = "test-token", role: String = "player",
                         market: RegionalMarket = .china, base: URL? = nil, namespace: String = "official-cn") throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: base ?? url, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    private func approval(_ commands: [OfficialActionCommand]) throws -> OfficialActionProductionApproval {
        let paths = commands.reduce(into: Set<String>()) { result, command in
            result.insert(command.path); result.formUnion(OfficialActionProductionApproval.readPaths(for: command) ?? [])
        }
        return try .init(market: .china, endpoints: .init(baseURL: url, namespace: owner.namespace, accountID: owner.accountID, paths: paths),
                         commands: commands, reviewedPolicyVersion: "test-policy")
    }
    private func access(_ wire: Wire, _ commands: [OfficialActionCommand], current: @escaping () -> RuntimeDependencyContext?) throws -> OfficialActionProductionFactory {
        OfficialActionProductionFactory(api: try .init(baseURL: url), approval: try approval(commands), transport: wire,
                                        current: current, identity: { self.owner })
    }
    private func publish(_ title: String = "Reviewed event") -> OfficialActionCommand {
        var draft = OfficialEventDraft(); draft.title = title; return .publish(draft)
    }
    private func broadcast(_ title: String = "Reviewed notice") -> OfficialActionCommand {
        var draft = OfficialBroadcastDraft(); draft.unified.title = title; draft.audience = [.club]; draft.channels = [.inapp]
        return .broadcast(draft)
    }
    func testNoApprovalMakesZeroReadsAndWrites() async throws {
        let c = try context(), wire = Wire()
        let access = OfficialActionProductionFactory(api: try .init(baseURL: url), transport: wire, current: { c }, identity: { self.owner })
        XCTAssertFalse(access.enabled)
        do { _ = try await access.snapshot(for: .signup(8)); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .disabled) }
        do { _ = try await access.send(.signup(8)); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .forbidden) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testGrantNeedsExactReadbackPathsAndPolicy() throws {
        let endpoint = try OperationEndpointApproval(baseURL: url, namespace: owner.namespace, accountID: 71, paths: ["api/official/publish"])
        XCTAssertThrowsError(try OfficialActionProductionApproval(market: .china, endpoints: endpoint, commands: [publish()], reviewedPolicyVersion: "review"))
        XCTAssertThrowsError(try OfficialActionProductionApproval(market: .china, endpoints: endpoint, commands: [], reviewedPolicyVersion: ""))
    }
    func testUnsupportedArrivalAndIncompleteInvitesCannotReceiveGrant() throws {
        XCTAssertThrowsError(try approval([.inviteMerchants([42])]))
        let evidence = OfficialArrivalEvidence(identity: owner, eventID: 8, sessionID: 3, missionCode: "ARRIVE", requestID: "test",
            latitude: 0, longitude: 0, accuracyM: 1, expiresAt: .distantFuture)
        XCTAssertThrowsError(try approval([.arrival(evidence)]))
    }
    func testAccountNamespaceOriginAndMarketAreBound() throws {
        let command = publish(), approved = try approval([command])
        XCTAssertTrue(approved.permits(command, context: try context()))
        XCTAssertFalse(approved.permits(command, context: try context(account: 72)))
        XCTAssertFalse(approved.permits(command, context: try context(namespace: "other")))
        XCTAssertFalse(approved.permits(command, context: try context(base: URL(string: "https://other.example")!)))
        XCTAssertFalse(approved.permits(command, context: try context(market: .unitedStates)))
    }
    func testGrantBindsContentRecipientTypeAndTarget() throws {
        let approved = try approval([publish(), broadcast(), .signup(8), .respond(partyID: 4, type: "CLUB", action: .accept, reason: nil)])
        let c = try context()
        XCTAssertFalse(approved.permits(publish("Changed"), context: c))
        XCTAssertFalse(approved.permits(broadcast("Changed"), context: c))
        XCTAssertFalse(approved.permits(.signup(9), context: c))
        XCTAssertFalse(approved.permits(.respond(partyID: 4, type: "MERCHANT", action: .accept, reason: nil), context: c))
        XCTAssertFalse(approved.permits(.respond(partyID: 4, type: "CLUB", action: .decline, reason: nil), context: c))
    }
    func testNakedPreparedAccessCannotBypassDurableAuthorization() async throws {
        let wire = Wire(), c = try context(), command = publish()
        let access = try access(wire, [command], current: { c })
        let coordinator = OfficialActionCoordinator(access: access, locks: Locks())
        _ = try await coordinator.prepare(command)
        do { _ = try await access.send(command); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .forbidden) }
        XCTAssertEqual(wire.writes, 0)
    }
    func testPublishWritesExactReviewOnceThenReadsOwnedResult() async throws {
        let wire = Wire(), c = try context(), command = publish(), locks = Locks()
        let access = try access(wire, [command], current: { c })
        let coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let review = try await coordinator.prepare(command)
        let result = try await coordinator.confirm(review)
        XCTAssertEqual(result, .published(91)); XCTAssertEqual(wire.writes, 1)
        XCTAssertEqual(wire.requests.map(\.httpMethod), ["GET", "GET", "POST", "GET"])
        XCTAssertEqual(wire.requests[2].httpBody, review.body)
        XCTAssertEqual(wire.requests[2].url, url.appendingPathComponent(command.path))
        XCTAssertEqual(wire.requests[2].value(forHTTPHeaderField: "Authorization"), "test-token")
        XCTAssertEqual(wire.requests.last?.url?.path, "/api/official/my-published")
        XCTAssertTrue(locks.values.isEmpty); XCTAssertNotNil(coordinator.readback)
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        XCTAssertEqual(wire.writes, 1)
    }
    func testBroadcastReadbackNeverClaimsDelivery() async throws {
        let wire = Wire(), c = try context(), command = broadcast()
        let access = try access(wire, [command], current: { c })
        let coordinator = OfficialActionCoordinator(access: access, locks: Locks())
        let review = try await coordinator.prepare(command)
        let result = try await coordinator.confirm(review)
        XCTAssertEqual(result, .broadcastSubmitted(91))
        guard let readback = coordinator.readback, case .published(let facts) = readback else { return XCTFail() }
        XCTAssertEqual(facts.broadcasts.first?.id, 91); XCTAssertNil(facts.broadcasts.first?.reach)
    }
    func testSignupUnlocksOnlyAfterSignedReadback() async throws {
        let wire = Wire(), c = try context(), locks = Locks()
        let access = try access(wire, [.signup(8), .complete(8)], current: { c })
        let coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let review = try await coordinator.prepare(.signup(8))
        _ = try await coordinator.confirm(review)
        XCTAssertTrue(locks.values.isEmpty)
        _ = try await coordinator.prepare(.complete(8))
        XCTAssertEqual(wire.writes, 1)
    }
    func testUnchangedSignupReadbackRetainsReplayLock() async throws {
        let wire = Wire(); wire.changeSignup = false
        let c = try context(), locks = Locks(), access = try access(wire, [.signup(8)], current: { c })
        let coordinator = OfficialActionCoordinator(access: access, locks: locks)
        _ = try await coordinator.confirm(coordinator.prepare(.signup(8)))
        XCTAssertEqual(locks.values.count, 1)
        do { _ = try await coordinator.prepare(.signup(8)); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .locked) }
    }
    func testLegacyCompletionKeepsReplayLockDespiteAcknowledgment() async throws {
        let wire = Wire(); wire.signed = true
        let c = try context(), locks = Locks(), access = try access(wire, [.complete(8)], current: { c })
        let coordinator = OfficialActionCoordinator(access: access, locks: locks)
        _ = try await coordinator.confirm(coordinator.prepare(.complete(8)))
        XCTAssertEqual(locks.values.count, 1)
        guard let readback = coordinator.readback, case .event(let event) = readback else { return XCTFail() }
        XCTAssertEqual(event.myProgress, 1)
    }
    func testFilteredPartyDisappearanceIsInconclusiveAndLocked() async throws {
        let wire = Wire(), c = try context(), locks = Locks()
        let command = OfficialActionCommand.respond(partyID: 4, type: "CLUB", action: .decline, reason: "Reviewed reason")
        let access = try access(wire, [command], current: { c }), coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let review = try await coordinator.prepare(command)
        _ = try await coordinator.confirm(review)
        XCTAssertEqual(coordinator.readback, .party(nil)); XCTAssertEqual(locks.values.count, 1)
        XCTAssertEqual(wire.requests.first(where: { $0.httpMethod == "POST" })?.httpBody, review.body)
    }
    func testPermissionRevokedAfterReviewMakesZeroWrites() async throws {
        let wire = Wire(), c = try context(), command = publish()
        let access = try access(wire, [command], current: { c }), coordinator = OfficialActionCoordinator(access: access, locks: Locks())
        let review = try await coordinator.prepare(command); wire.permission = false
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .forbidden) }
        XCTAssertEqual(wire.writes, 0)
    }
    func testRoleAndTokenChangesInvalidateReviewedIdentity() async throws {
        let wire = Wire(); var c: RuntimeDependencyContext? = try context()
        let access = try access(wire, [.signup(8)], current: { c }), coordinator = OfficialActionCoordinator(access: access, locks: Locks())
        let review = try await coordinator.prepare(.signup(8))
        c = try context(token: "changed-token", role: "merchant")
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .stale) }
        XCTAssertEqual(wire.writes, 0)
    }
    func testSessionChangeDuringPostKeepsUnknownLockAndNoReadback() async throws {
        let wire = Wire(); var c: RuntimeDependencyContext? = try context()
        let locks = Locks(), access = try access(wire, [.signup(8)], current: { c })
        let coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let review = try await coordinator.prepare(.signup(8)); wire.onWrite = { c = nil }
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        XCTAssertEqual(coordinator.state, .unknown); XCTAssertEqual(locks.values.count, 1)
        XCTAssertNil(coordinator.readback); XCTAssertEqual(wire.requests.count, 3)
    }
    func testCancelDuringPostDoesNotPretendRejection() async throws {
        let wire = Wire(), c = try context(), locks = Locks()
        let access = try access(wire, [.signup(8)], current: { c }), coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let review = try await coordinator.prepare(.signup(8)); wire.onWrite = { coordinator.cancelReview() }
        do { _ = try await coordinator.confirm(review); XCTFail() } catch {}
        XCTAssertEqual(coordinator.state, .unknown); XCTAssertEqual(locks.values.count, 1); XCTAssertNil(coordinator.readback)
    }
    func testReadbackRejectionCannotUnlockSuccessfulPost() async throws {
        let wire = Wire(); wire.readbackFailure = true
        let c = try context(), locks = Locks(), access = try access(wire, [publish()], current: { c })
        let coordinator = OfficialActionCoordinator(access: access, locks: locks)
        do { _ = try await coordinator.confirm(coordinator.prepare(publish())); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .unknown) }
        XCTAssertEqual(wire.writes, 1); XCTAssertEqual(locks.values.count, 1); XCTAssertNil(coordinator.readback)
    }
    func testMissingOwnedPublishReadbackKeepsLock() async throws {
        let wire = Wire(); wire.hidePublished = true
        let c = try context(), locks = Locks(), access = try access(wire, [publish()], current: { c })
        let coordinator = OfficialActionCoordinator(access: access, locks: locks)
        do { _ = try await coordinator.confirm(coordinator.prepare(publish())); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .unknown) }
        XCTAssertEqual(locks.values.count, 1)
    }
    func testExplicitWriteRejectionAllowsFreshReviewWithoutRetry() async throws {
        let wire = Wire(); wire.rejectWrite = true
        let c = try context(), locks = Locks(), access = try access(wire, [.signup(8)], current: { c })
        let coordinator = OfficialActionCoordinator(access: access, locks: locks)
        do { _ = try await coordinator.confirm(coordinator.prepare(.signup(8))); XCTFail() } catch {}
        XCTAssertEqual(coordinator.state, .rejected); XCTAssertTrue(locks.values.isEmpty)
        _ = try await coordinator.prepare(.signup(8)); XCTAssertEqual(wire.writes, 1)
    }
    func testLockWriteFailureMakesZeroWrites() async throws {
        let wire = Wire(), c = try context(), locks = Locks(); locks.fail = true
        let access = try access(wire, [.signup(8)], current: { c }), coordinator = OfficialActionCoordinator(access: access, locks: locks)
        do { _ = try await coordinator.confirm(coordinator.prepare(.signup(8))); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .storage) }
        XCTAssertEqual(wire.writes, 0)
    }
    func testLockInsertedDuringFreshReadPreventsCompetingDispatch() async throws {
        let wire = Wire(), c = try context(), locks = Locks()
        let access = try access(wire, [.signup(8)], current: { c }), coordinator = OfficialActionCoordinator(access: access, locks: locks)
        let review = try await coordinator.prepare(.signup(8))
        let key = String(decoding: try JSONEncoder().encode([owner.namespace, String(owner.accountID), "event:8"]), as: UTF8.self)
        wire.onRead = { try? locks.insert(key) }
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .locked) }
        XCTAssertEqual(wire.writes, 0); XCTAssertEqual(locks.values.count, 1)
    }
    func testLogoutClearsReadbackAndNeverResurrectsOldReview() async throws {
        let wire = Wire(); var c: RuntimeDependencyContext? = try context()
        let original = c
        let access = try access(wire, [.signup(8)], current: { c }), coordinator = OfficialActionCoordinator(access: access, locks: Locks())
        let review = try await coordinator.prepare(.signup(8)); c = nil
        XCTAssertNil(access.identity); XCTAssertNil(access.readback)
        c = original
        do { _ = try await coordinator.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .stale) }
        XCTAssertEqual(wire.writes, 0)
    }
    func testUnknownPostSurvivesFactoryAndCoordinatorRecreation() async throws {
        let wire = Wire(); wire.failWrite = true
        let c = try context(), file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let first = OfficialActionCoordinator(access: try access(wire, [.signup(8)], current: { c }), locks: OfficialActionFileLocks(url: file))
        do { _ = try await first.confirm(first.prepare(.signup(8))); XCTFail() } catch {}
        let second = OfficialActionCoordinator(access: try access(wire, [.signup(8)], current: { c }), locks: OfficialActionFileLocks(url: file))
        do { _ = try await second.prepare(.signup(8)); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .locked) }
        XCTAssertEqual(wire.writes, 1)
        let persisted = try String(contentsOf: file)
        XCTAssertFalse(persisted.contains("test-token")); XCTAssertFalse(persisted.contains(owner.epoch.uuidString))
    }
    func testCorruptJournalFailsClosedBeforeReadOrWrite() async throws {
        let wire = Wire(), c = try context(), file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("corrupt".utf8).write(to: file)
        let coordinator = OfficialActionCoordinator(access: try access(wire, [.signup(8)], current: { c }), locks: OfficialActionFileLocks(url: file))
        do { _ = try await coordinator.prepare(.signup(8)); XCTFail() } catch { XCTAssertEqual(error as? OfficialActionFailure, .storage) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
}

@MainActor private final class Locks: OfficialActionLockStore {
    var values = Set<String>()
    var fail = false
    func contains(_ key: String) throws -> Bool { values.contains(key) }
    func insert(_ key: String) throws { if fail { throw OfficialActionFailure.storage }; values.insert(key) }
    func remove(_ key: String) throws { values.remove(key) }
}
@MainActor private final class Wire: HTTPTransport {
    var requests: [URLRequest] = []
    var writes: Int { requests.filter { $0.httpMethod == "POST" }.count }
    var signed = false, permission = true, changeSignup = true, readbackFailure = false, hidePublished = false, rejectWrite = false, failWrite = false
    var progress = 0
    var onWrite: (() -> Void)?
    var onRead: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        func reply(_ json: String) -> (Data, Int) { (Data(json.utf8), 200) }
        let path = request.url!.path
        if request.httpMethod == "POST" {
            onWrite?()
            if failWrite { throw URLError(.timedOut) }
            if rejectWrite { return reply(#"{"code":500,"msg":"Not allowed"}"#) }
            if path.hasSuffix("/signup"), changeSignup { signed = true }
            if path.hasSuffix("/complete") { progress += 1 }
            return reply(path.hasSuffix("/publish") || path.hasSuffix("/broadcast") ? #"{"code":200,"data":91}"# : #"{"code":200}"#)
        }
        onRead?()
        if writes > 0, readbackFailure { return reply(#"{"code":403,"msg":"Forbidden"}"#) }
        if path.hasSuffix("/can-publish") { return reply("{\"code\":200,\"data\":{\"canPublish\":\(permission)}}") }
        if path.hasSuffix("/my-published") {
            return reply(hidePublished ? #"{"code":200,"data":{"events":[],"broadcasts":[]}}"# : #"{"code":200,"data":{"events":[{"id":91,"title":"Reviewed event"}],"broadcasts":[{"id":91,"title":"Reviewed notice"}]}}"#)
        }
        if path.hasSuffix("/party-inbox") { return reply(writes > 0 ? #"{"code":200,"data":[]}"# : #"{"code":200,"data":[{"partyId":4,"partyType":"CLUB","status":"INVITED"}]}"#) }
        return reply("{\"code\":200,\"data\":{\"id\":8,\"title\":\"Test event\",\"status\":3,\"signed\":\(signed),\"myProgress\":\(progress)}}")
    }
}
