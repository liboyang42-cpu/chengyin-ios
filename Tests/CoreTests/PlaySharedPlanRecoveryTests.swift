import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class PlaySharedPlanRecoveryTests: XCTestCase {
    typealias Anchors = PlayDurableRecoveryTests.Anchors
    typealias Blobs = PlayDurableRecoveryTests.Blobs
    private func owner(account: Int = 7, role: String = "player") throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: 1, namespace: "synthetic-plan", token: "synthetic", role: role)
    }
    private func command() -> PlaySharedPlanCommand {
        .init(activityID: 41, sessionID: 501, memberID: 7, revision: 4, authorityEpoch: 3,
              identity: .init(teamID: 21, ownerRevision: 2, round: 0, endingKey: "ending_a", proposalKey: nil,
                              proposalVersion: nil, operationNodeID: nil, sourceNodeID: nil, bindingVersion: nil, operationReceiptID: nil),
              requestID: "original-plan-001", action: .propose,
              payload: .object(["proposalKey": .string("plan_original"), "endingKey": .string("ending_a")]))
    }
    private func projection(captain: Bool = true, sessionID: Int = 501) throws -> PlayWireValue {
        let json = """
        {"perspective":"PLAYER","activityId":41,"sessionId":\(sessionID),"revision":4,"status":"RUNNING",
        "availableActions":["PLAN_PROPOSE"],"player":{"scope":"TEAM","playMode":"ROUTE","worldMode":"WORLD_SHARED",
        "teamId":21,"ownerRevision":2,"authorityEpoch":3,"isCaptain":\(captain),"naturallyCompleted":false,
        "run":{"authorityEpoch":3,"operationStatus":"RUNNING","authorityMode":"ONLINE","exitedTeams":{}},
        "world":{"itemCatalog":[],"ownMaterials":[],"locked":{},"round":0,"votePhase":"FUNDING","votePolicy":"MAJORITY_ACCEPTANCE",
        "proposals":[],"plans":[{"endingKey":"ending_a","title":"Original plan","materialCost":[],"conditionsMet":true,
        "actions":{"canFund":true,"canVote":false,"canAccept":false,"canExecute":false}}]}}}
        """
        return try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8))
    }
    private func model(_ wire: PlanRecoveryWire, journal: any PlayGameCommandJournal, session: PlayExperienceSession? = nil,
                       enabled: Set<PlayExperienceCapability> = [.reads], current: @escaping () -> Bool = { true },
                       canWrite: @escaping () -> Bool = { false }) throws -> PlaySharedPlanLifecycle {
        .init(activityID: 41, session: try session ?? owner(), service: .init(configuration: try .init(baseURL: URL(string: "https://example.test")!),
            transport: wire, enabled: enabled), journal: journal, current: current, canWrite: canWrite, onUnauthorized: {})
    }
    private func seed(_ journal: any PlayGameCommandJournal) async throws -> PlayGameCommandJournalSnapshot {
        try await journal.recordGameCommand(.init(plan: command(), session: owner()), key: PlayRunStorageKey.make(session: owner(), scope: .activity(41)))
    }
    private func stored(_ journal: any PlayGameCommandJournal) async throws -> PlayGameCommandJournalSnapshot? {
        try await journal.readGameCommand(PlayRunStorageKey.make(session: owner(), scope: .activity(41)))
    }
    private func unpublishedInventory(materials: PlayWireValue) throws -> PlayWireValue {
        var raw = try XCTUnwrap(projection().object)
        var player = try XCTUnwrap(raw["player"]?.object)
        var world = try XCTUnwrap(player["world"]?.object)
        world.removeValue(forKey: "locked")
        world["itemCatalog"] = .array([.object(["id": .string("wood"), "name": .string("Wood"), "slotCost": .int(1)])])
        world["ownMaterials"] = materials
        player["world"] = .object(world); raw["player"] = .object(player)
        return .object(raw)
    }
    func testUnpublishedInventoryRejectsNonemptyOwnMaterials() throws {
        let raw = try unpublishedInventory(materials: .array([
            .object(["itemId": .string("wood"), "available": .int(2), "locked": .int(0)])
        ]))
        XCTAssertThrowsError(try PlaySharedPlanTeamProjection(raw, activityID: 41)) { error in
            XCTAssertEqual(error as? PlayExperienceError, .malformed)
        }
    }
    func testUnpublishedInventoryKeepsCatalogUnknownAndCaptainReadOnly() throws {
        let raw = try unpublishedInventory(materials: .array([]))
        let projection = try PlaySharedPlanProjection(raw, activityID: 41)
        XCTAssertEqual(projection.team.activityID, 41)
        XCTAssertEqual(projection.team.sessionID, 501)
        XCTAssertEqual(projection.team.teamID, 21)
        XCTAssertTrue(projection.team.captain)
        XCTAssertFalse(projection.team.writable)
        XCTAssertEqual(projection.team.items.count, 1)
        let item = try XCTUnwrap(projection.team.items.first)
        XCTAssertEqual(item.id, "wood"); XCTAssertEqual(item.name, "Wood")
        XCTAssertNil(item.available); XCTAssertNil(item.locked)
        let row = try XCTUnwrap(projection.rows.first)
        XCTAssertFalse(projection.allows(.propose, row: row))
    }
    func testDefaultCapabilityMakesNoNetworkRequest() async throws {
        let w = PlanRecoveryWire(), m = try model(w, journal: PlayMemoryGameCommandJournal(), enabled: [])
        await m.load(); XCTAssertTrue(w.requests.isEmpty); XCTAssertFalse(m.ready); XCTAssertFalse(m.writesEnabled)
    }
    func testReadApprovalDoesNotEnableWritingEvenWithCaptainProjection() async throws {
        let w = PlanRecoveryWire(); w.view = try projection(); let m = try model(w, journal: PlayMemoryGameCommandJournal(), enabled: [.reads, .playerCommands])
        await m.load(); XCTAssertNotNil(m.projection); XCTAssertFalse(m.writesEnabled)
        await m.prepare(.propose, endingKey: "ending_a"); XCTAssertNil(m.review); XCTAssertEqual(w.requests.count, 1)
    }
    func testNonCaptainCannotPrepareWithExplicitWriteGate() async throws {
        let w = PlanRecoveryWire(); w.view = try projection(captain: false)
        let m = try model(w, journal: PlayMemoryGameCommandJournal(), enabled: [.reads, .playerCommands], canWrite: { true })
        await m.load(); await m.prepare(.propose, endingKey: "ending_a"); XCTAssertNil(m.review); XCTAssertTrue(w.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testPendingRestoresExactRequestAndNeverPostsOrClears() async throws {
        let w = PlanRecoveryWire(); w.view = try projection(); let j = PlayMemoryGameCommandJournal(), original = try await seed(j)
        let m = try model(w, journal: j); await m.load(); await m.load()
        XCTAssertEqual(m.pending, command()); XCTAssertFalse(m.ready); let after = try await stored(j); XCTAssertEqual(after, original)
        XCTAssertEqual(w.requests.filter { $0.url?.path.hasSuffix("/receipt") == true }.count, 2)
        XCTAssertTrue(w.requests.allSatisfy { $0.httpMethod == "GET" })
        for r in w.requests where r.url?.path.hasSuffix("/receipt") == true {
            let q = URLComponents(url: try XCTUnwrap(r.url), resolvingAgainstBaseURL: false)?.queryItems
            XCTAssertTrue(q?.contains(.init(name: "requestId", value: "original-plan-001")) == true)
            XCTAssertTrue(q?.contains(.init(name: "perspective", value: "PLAYER")) == true)
        }
    }
    func testExplicitFailureIsDisplayedButReadOnlyRecoveryRetainsJournal() async throws {
        let w = PlanRecoveryWire(); w.view = try projection(); w.receipt = .object(["activityId": .int(41), "requestId": .string("original-plan-001"),
            "action": .string("PLAN_PROPOSE"), "outcome": .string("FAILED"), "receiptId": .int(80), "revision": .int(4)])
        let j = PlayMemoryGameCommandJournal(), original = try await seed(j); let m = try model(w, journal: j); await m.load()
        XCTAssertEqual(m.receipt?.outcome, "FAILED"); XCTAssertEqual(m.pending, command()); let after = try await stored(j); XCTAssertEqual(after, original)
    }
    func testDifferentSessionCannotConsumeOriginalReceipt() async throws {
        let w = PlanRecoveryWire(); w.view = try projection(sessionID: 999); let j = PlayMemoryGameCommandJournal(), original = try await seed(j)
        let m = try model(w, journal: j); await m.load(); XCTAssertFalse(w.requests.contains { $0.url?.path.hasSuffix("/receipt") == true })
        let after = try await stored(j); XCTAssertEqual(after, original)
    }
    func testRoleMismatchAndRevokedContextMakeNoRequest() async throws {
        for role in ["merchant", "club"] {
            let w = PlanRecoveryWire(), m = try model(w, journal: PlayMemoryGameCommandJournal(), session: owner(role: role))
            await m.load(); XCTAssertTrue(w.requests.isEmpty)
        }
        let w = PlanRecoveryWire(), m = try model(w, journal: PlayMemoryGameCommandJournal(), current: { false })
        await m.load(); XCTAssertTrue(w.requests.isEmpty)
    }
    func testSuspendPreservesOriginalJournal() async throws {
        let w = PlanRecoveryWire(); w.view = try projection(); let j = PlayMemoryGameCommandJournal(), original = try await seed(j)
        let m = try model(w, journal: j); await m.load(); m.suspend(); XCTAssertNil(m.projection); XCTAssertNil(m.pending)
        let after = try await stored(j); XCTAssertEqual(after, original)
    }
    func testJournalReadFailureStopsBeforeNetworkAndNeverClears() async throws {
        let w = PlanRecoveryWire(), j = PlanRecoveryJournal(); j.failRead = true
        let m = try model(w, journal: j); await m.load()
        XCTAssertTrue(w.requests.isEmpty); XCTAssertEqual(j.clearCalls, 0); XCTAssertFalse(m.ready)
    }
    func testForeignAccountJournalCannotBeAdopted() async throws {
        let w = PlanRecoveryWire(), j = PlanRecoveryJournal()
        let original = try PlayPendingGameCommand(plan: command(), session: owner())
        j.value = .init(value: original, generation: Data([1]))
        let m = try model(w, journal: j, session: owner(account: 8)); await m.load()
        XCTAssertTrue(w.requests.isEmpty); XCTAssertEqual(j.value?.value, original); XCTAssertEqual(j.clearCalls, 0)
    }
    func testLateResponseAfterRevocationIsNotPublished() async throws {
        let w = PlanRecoveryWire(); w.view = try projection(); var live = true
        w.beforeReply = { live = false }
        let m = try model(w, journal: PlayMemoryGameCommandJournal(), current: { live })
        await m.load(); XCTAssertNil(m.projection); XCTAssertNil(m.receipt); XCTAssertFalse(m.ready)
    }
    func testAppliedProposalDoesNotProveExecutionAndRetainsJournalByDefault() async throws {
        let w = PlanRecoveryWire(); w.view = try projection()
        w.receipt = .object(["activityId": .int(41), "requestId": .string("original-plan-001"), "action": .string("PLAN_PROPOSE"),
            "outcome": .string("APPLIED"), "receiptId": .int(80), "revision": .int(5),
            "result": .object(["receiptOwnerTeamId": .int(21), "result": .object(["proposalKey": .string("plan_original"),
                "endingKey": .string("ending_a"), "version": .int(1), "status": .string("OPEN"), "teamId": .int(21)])])])
        var raw = try XCTUnwrap(w.view.object); raw["revision"] = .int(5); w.view = .object(raw)
        let j = PlayMemoryGameCommandJournal(), original = try await seed(j), m = try model(w, journal: j)
        await m.load(); XCTAssertEqual(m.receipt?.action, .propose); XCTAssertEqual(m.projection?.phase, "FUNDING")
        XCTAssertFalse(m.ready); let after = try await stored(j); XCTAssertEqual(after, original)
    }
    func testEncryptedJournalRebuildRestoresPlanAndOldLeaseCannotClearReplacement() async throws {
        let a = Anchors(), b = Blobs(), session = try owner()
        let key = PlayRunStorageKey.make(session: session, scope: .activity(41))
        let first = try PlayDurableRecovery(owner: .init(session: session), key: key, anchors: a, ciphertexts: b, processID: UUID())
        let original = try await seed(first)
        let reopened = try PlayDurableRecovery(owner: .init(session: session), key: key, anchors: a, ciphertexts: b, processID: UUID())
        let restored = try await reopened.readGameCommand(key)
        XCTAssertEqual(try restored?.value.planCommand(), command())
        try await reopened.clearGameCommand(try XCTUnwrap(restored), key: key)
        let next = try PlayPlayerCommand(activityID: 41, nodeID: 7, requestID: "replacement-original", expectedRevision: 5,
                                        action: .choice, payload: ["choiceId": .string("LEFT")])
        let replacement = try await reopened.recordGameCommand(.init(command: next, session: session, sessionID: 501), key: key)
        do { try await first.clearGameCommand(original, key: key); XCTFail("Stale lease cleared a replacement") } catch {}
        let after = try await reopened.readGameCommand(key); XCTAssertEqual(after, replacement)
    }
    func testAdvancedAdapterCannotUseAnUnissuedTicketOrBorrowWritePermission() async throws {
        let w = PlanRecoveryWire(), m = try model(w, journal: PlayMemoryGameCommandJournal())
        let ticket = PlaySharedPlanOperationTicket(id: UUID(), activityID: 41, sessionID: 501, teamID: 21, memberID: 7,
            nodeID: 9, sourceNodeID: 8, bindingVersion: 1, authorityEpoch: 3, round: 1, receiptID: 80,
            endingKey: "ending_a", proposalKey: "plan_original")
        let adapter = PlaySharedPlanAdvancedTransport(underlying: w, flow: m, ticket: ticket, topicID: 2)
        var request = URLRequest(url: URL(string: "https://example.test/api/play/advanced/start")!); request.httpMethod = "POST"
        do { _ = try await adapter.send(request); XCTFail("Unissued ticket reached advanced transport") } catch {}
        XCTAssertTrue(w.requests.isEmpty)
    }
    func testPlanJournalRoundTripPreservesExactEnvelopeAndLegacyCannotReplayIt() throws {
        let p = try PlayPendingGameCommand(plan: command(), session: owner()); let data = try PropertyListEncoder().encode(p)
        let decoded = try PropertyListDecoder().decode(PlayPendingGameCommand.self, from: data)
        XCTAssertEqual(try decoded.planCommand(), command()); XCTAssertThrowsError(try decoded.command()); try decoded.validateOriginalCommand()
    }
    func testLegacyJournalDecodesWithoutNewFields() throws {
        let c = try PlayPlayerCommand(activityID: 41, nodeID: 7, requestID: "legacy-original", expectedRevision: 4, action: .choice, payload: ["choiceId": .string("LEFT")])
        let p = try PlayPendingGameCommand(command: c, session: owner(), sessionID: 501)
        let data = try PropertyListEncoder().encode(p), decoded = try PropertyListDecoder().decode(PlayPendingGameCommand.self, from: data)
        XCTAssertNil(decoded.sharedPlanIdentity); XCTAssertNil(decoded.authorityEpoch); XCTAssertEqual(try decoded.command(), c)
    }
    func testExplicitWritePersistsBeforeSinglePostThenOnlyReadsReceipt() async throws {
        let w = PlanRecoveryWire(); w.view = try projection(); let j = PlayMemoryGameCommandJournal()
        w.beforePost = { let value = try await self.stored(j); XCTAssertNotNil(value) }
        let m = try model(w, journal: j, enabled: [.reads, .playerCommands], canWrite: { true })
        await m.load(); await m.prepare(.propose, endingKey: "ending_a"); let review = try XCTUnwrap(m.review)
        await m.commit(review)
        let pending = try XCTUnwrap(m.pending)
        let saved = try await stored(j)
        let original = try XCTUnwrap(saved)
        XCTAssertEqual(try original.value.planCommand(), pending)
        // The generated UUID must be the one returned by the receipt fixture, too.
        // A hard-coded different key would exercise malformed rather than PENDING.
        w.receipt = .object(["activityId": .int(pending.activityID),
            "requestId": .string(pending.requestID), "outcome": .string("PENDING")])
        XCTAssertThrowsError(try PlaySharedPlanReceipt(w.receipt, command: pending)) { error in
            XCTAssertEqual(error as? PlayExperienceError, .unknownResult)
        }
        let dispatchedCount = w.requests.count
        await m.commit(review); await m.load()
        XCTAssertEqual(w.requests.filter { $0.httpMethod == "POST" }.count, 1)
        let subsequent = Array(w.requests.dropFirst(dispatchedCount))
        XCTAssertTrue(subsequent.allSatisfy { $0.httpMethod == "GET" })
        let receipts = subsequent.filter { $0.url?.path.hasSuffix("/receipt") == true }
        XCTAssertEqual(receipts.count, 1)
        let receiptRequest = try XCTUnwrap(receipts.first)
        let receiptURL = try XCTUnwrap(receiptRequest.url)
        let query = try XCTUnwrap(URLComponents(url: receiptURL, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(query.count, 3)
        XCTAssertTrue(query.contains(.init(name: "activityId", value: String(pending.activityID))))
        XCTAssertTrue(query.contains(.init(name: "perspective", value: "PLAYER")))
        XCTAssertTrue(query.contains(.init(name: "requestId", value: pending.requestID)))
        XCTAssertEqual(m.pending, pending); XCTAssertNil(m.receipt); XCTAssertFalse(m.ready)
        let after = try await stored(j); XCTAssertEqual(after, original)
    }
}

@MainActor private final class PlanRecoveryWire: HTTPTransport {
    var requests: [URLRequest] = []
    var view: PlayWireValue = .null
    var receipt: PlayWireValue = .object(["activityId": .int(41), "requestId": .string("original-plan-001"), "outcome": .string("PENDING")])
    var beforeReply: (() -> Void)?
    var beforePost: (() async throws -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.httpMethod == "POST" { try await beforePost?(); throw PlayExperienceError.unknownResult }
        beforeReply?()
        let value = request.url?.path.hasSuffix("/receipt") == true ? receipt : view
        return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": value])), 200)
    }
}

@MainActor private final class PlanRecoveryJournal: PlayGameCommandJournal {
    var value: PlayGameCommandJournalSnapshot?
    var failRead = false
    var clearCalls = 0
    func readGameCommand(_ key: String) async throws -> PlayGameCommandJournalSnapshot? {
        if failRead { throw PlayExperienceError.persistenceUnavailable }; return value
    }
    func recordGameCommand(_ value: PlayPendingGameCommand, key: String) async throws -> PlayGameCommandJournalSnapshot {
        throw PlayExperienceError.persistenceUnavailable
    }
    func clearGameCommand(_ snapshot: PlayGameCommandJournalSnapshot, key: String) async throws { clearCalls += 1 }
}
