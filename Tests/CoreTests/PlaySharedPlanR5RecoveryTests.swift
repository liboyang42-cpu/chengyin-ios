import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class PlaySharedPlanR5RecoveryTests: XCTestCase {
    private var ticket: PlaySharedPlanOperationTicket {
        .init(id: UUID(), activityID: 41, sessionID: 501, teamID: 21, memberID: 7, nodeID: 9,
              sourceNodeID: 8, bindingVersion: 1, authorityEpoch: 3, round: 1, receiptID: 80, endingKey: "ending_a", proposalKey: "plan_a")
    }
    private func owner() throws -> PlayExperienceSession { try .init(accountID: 7, epoch: 1, namespace: "r5-synthetic", token: "synthetic", role: "player") }
    private func raw(version: Int = 4, frozen: Bool = true) throws -> PlayWireValue {
        var value = try JSONDecoder().decode(PlayWireValue.self, from: Data("""
        {"sessionId":901,"activityId":41,"topicId":2,"nodeId":9,"ownerType":2,"ownerId":21,"startedAt":1000,
        "status":"RUNNING","version":\(version),"config":{"outcomeRulesVersion":1,"check":{"enabled":true}},
        "r5Session":{"schemaVersion":1,"originalGameSessionId":501,"runtimeAuthorityEpoch":3,"playInstanceId":"original-instance","attemptOrdinal":2},
        "check":{"attemptId":"advanced:901:2","allowedActions":["ROLL_CHECK"],"dice":[],"submitted":false}}
        """.utf8)).object!
        if !frozen { value.removeValue(forKey: "r5Session") }; return .object(value)
    }
    private func command() -> PlayAdvancedPending { .init(sessionID: 901, version: 4, key: "FEA934DD-35F1-4F50-B0EB-CB43A67DD294", action: "ROLL_CHECK", payload: [:]) }
    private func receipt(member: Int = 7, key: String? = nil) throws -> PlayWireValue {
        var value = try raw(version: 5).object!
        var check = value["check"]!.object!; check["dice"] = .array([.int(6)]); value["check"] = .object(check)
        value["r5ActionRequest"] = .object(["schemaVersion": .int(1), "memberId": .int(member), "sessionId": .int(901),
            "idempotencyKey": .string(key ?? command().key), "action": .string("ROLL_CHECK"), "expectedVersion": .int(4), "payload": .object([:])])
        return .object(value)
    }
    private func model(_ wire: R5RecoveryWire, journal: any PlayAdvancedRecovery, approved: Bool = false,
                       current: @escaping () -> Bool = { true }) throws -> PlaySharedPlanR5Recovery {
        let s = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire, enabled: [.reads, .advanced])
        return .init(owner: try owner(), ticket: ticket, topicID: 2, service: s, outcomeService: s, journal: journal,
                     current: current, approvedWriteAndOriginalProof: { approved }, validateOperation: {})
    }
    func testC6MissingFrozenIdentityCannotAcquireWriteOrOutcomeBinding() throws {
        XCTAssertThrowsError(try PlaySharedPlanR5Projection(raw(frozen: false), ticket: ticket, topicID: 2))
    }
    func testHigherVersionAndPassAreNotOriginalActionProof() throws {
        let value = try raw(version: 99), p = try PlaySharedPlanR5Projection(value, ticket: ticket, topicID: 2)
        XCTAssertFalse(p.proves(value, pending: command(), memberID: 7))
    }
    func testExactActorRequestPayloadAndVersionAreRequired() throws {
        let exact = try receipt(), p = try PlaySharedPlanR5Projection(exact, ticket: ticket, topicID: 2)
        XCTAssertTrue(p.proves(exact, pending: command(), memberID: 7))
        XCTAssertFalse(p.proves(try receipt(member: 8), pending: command(), memberID: 7))
        XCTAssertFalse(p.proves(try receipt(key: UUID().uuidString), pending: command(), memberID: 7))
        var wrong = try XCTUnwrap(exact.object), proof = try XCTUnwrap(exact["r5ActionRequest"].object)
        proof["payload"] = .object(["clientPass": .bool(true)]); wrong["r5ActionRequest"] = .object(proof)
        XCTAssertFalse(p.proves(.object(wrong), pending: command(), memberID: 7))
    }
    func testDifferentRunOrAttemptCannotBind() throws {
        var value = try raw().object!, identity = value["r5Session"]!.object!
        identity["originalGameSessionId"] = .int(999); value["r5Session"] = .object(identity)
        XCTAssertThrowsError(try PlaySharedPlanR5Projection(.object(value), ticket: ticket, topicID: 2))
        value = try raw().object!; value["check"] = .object(["attemptId": .string("advanced:901:3"), "allowedActions": .array([])])
        XCTAssertThrowsError(try PlaySharedPlanR5Projection(.object(value), ticket: ticket, topicID: 2))
    }
    func testDefaultClosedAndC6LoadDoesNotPost() async throws {
        let w = R5RecoveryWire(); w.state = try raw(frozen: false); let j = PlayMemoryAdvancedRecovery(), m = try model(w, journal: j)
        await m.load(sessionID: 901); XCTAssertNil(m.projection); XCTAssertThrowsError(try m.review("ROLL_CHECK"))
        XCTAssertTrue(w.requests.allSatisfy { $0.httpMethod == "GET" }); let stored = try await j.read(); XCTAssertNil(stored)
    }
    func testEvenFutureIdentityNeedsSeparateProofAndWriteApproval() async throws {
        let w = R5RecoveryWire(); w.state = try raw(); let m = try model(w, journal: PlayMemoryAdvancedRecovery())
        await m.load(sessionID: 901); XCTAssertNotNil(m.projection); XCTAssertThrowsError(try m.review("ROLL_CHECK"))
    }
    func testUnknownPreservesExactEnvelopeAndLoadNeverReplays() async throws {
        let w = R5RecoveryWire(); w.state = try raw(); let j = PlayMemoryAdvancedRecovery(), m = try model(w, journal: j, approved: true)
        w.beforePost = { let value = try await j.read(); XCTAssertEqual(value?.value.phase, .dispatching) }
        await m.load(sessionID: 901); let r = try m.review("ROLL_CHECK"); await m.commit(r)
        let old = try await j.read(); XCTAssertEqual(old?.value.phase, .unknown)
        await m.load(sessionID: 901); let after = try await j.read(); XCTAssertEqual(old, after)
        XCTAssertEqual(w.requests.filter { $0.httpMethod == "POST" }.count, 1); XCTAssertFalse(m.acknowledged)
    }
    func testLegacyCoordinatorCannotConsumeAnR5BoundRecord() async throws {
        let w = R5RecoveryWire(), j = PlayMemoryAdvancedRecovery(), o = try owner()
        let binding = try PlaySharedPlanR5Identity(raw(), ticket: ticket, topicID: 2)
        let scope = try PlayAdvancedRecoveryScope(activityID: 41, topicID: 2, nodeID: 9)
        let saved = try await j.prepare(.init(session: o, scope: scope, pending: command(), requestedCard: false, sharedPlanR5: binding))
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: w, enabled: [.reads, .advanced])
        let legacy = PlayAdvancedCoordinator(activityID: 41, topicID: 2, nodeID: 9, service: service, recovery: j, currentSession: { o })
        await legacy.start(); XCTAssertTrue(w.requests.isEmpty); let after = try await j.read(); XCTAssertEqual(after, saved)
    }
    func testBoundJournalRoundTripAndLegacyAbsentBinding() throws {
        let binding = try PlaySharedPlanR5Identity(raw(), ticket: ticket, topicID: 2), scope = try PlayAdvancedRecoveryScope(activityID: 41, topicID: 2, nodeID: 9)
        for identity in [binding, nil] as [PlaySharedPlanR5Identity?] {
            let record = try PlayAdvancedRecoveryRecord(session: owner(), scope: scope, pending: command(), requestedCard: false, sharedPlanR5: identity)
            let copy = try PropertyListDecoder().decode(PlayAdvancedRecoveryRecord.self, from: PropertyListEncoder().encode(record))
            XCTAssertEqual(record, copy); XCTAssertEqual(copy.sharedPlanR5, identity)
        }
    }
    func testOutcomeNeedsExactAttemptAndDoesNotTurnBlockedCostIntoPass() throws {
        let identity = try PlaySharedPlanR5Identity(raw(), ticket: ticket, topicID: 2)
        let outcome: PlayWireValue = .object(["perspective": .string("PLAYER"), "activityId": .int(41), "sessionId": .int(501),
            "player": .object(["teamId": .int(21), "authorityEpoch": .int(3), "run": .object(["authorityEpoch": .int(3)]),
                "lastOutcome": .object(["attemptId": .string("advanced:901:2"), "status": .string("BLOCKED_COST"), "outcome": .string("PASS"), "settled": .bool(false)])])])
        let value = try PlaySharedPlanR5Outcome(outcome, identity: identity)
        XCTAssertEqual(value.status, "BLOCKED_COST"); XCTAssertNil(value.outcome)
    }
    func testExactProofAcknowledgesThenExplicitFreshReadbackRetiresOriginalLease() async throws {
        let w = R5RecoveryWire(); w.state = try raw(); let j = PlayMemoryAdvancedRecovery(), m = try model(w, journal: j, approved: true)
        w.postResult = { request in
            let body = try JSONDecoder().decode(PlayWireValue.self, from: XCTUnwrap(request.httpBody))
            let result = try self.receipt(key: XCTUnwrap(body["idempotencyKey"].text)); w.state = result; return result
        }
        await m.load(sessionID: 901); await m.commit(try m.review("ROLL_CHECK"))
        XCTAssertTrue(m.acknowledged); let acknowledged = try await j.read(); XCTAssertEqual(acknowledged?.value.phase, .acknowledged)
        await m.retireAcknowledged(); let after = try await j.read(); XCTAssertNil(after)
        XCTAssertEqual(w.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testProofWithoutActualDiceIsNotAcknowledgement() throws {
        var value = try receipt().object!, check = value["check"]!.object!
        check["dice"] = .array([]); value["check"] = .object(check)
        let raw = PlayWireValue.object(value), p = try PlaySharedPlanR5Projection(raw, ticket: ticket, topicID: 2)
        XCTAssertFalse(p.proves(raw, pending: command(), memberID: 7))
    }
    func testExplicitSameProcessInterruptedReplayKeepsOriginalKeyAndCASLease() async throws {
        let w = R5RecoveryWire(); w.state = try raw(); let j = PlayMemoryAdvancedRecovery(), o = try owner()
        let binding = try PlaySharedPlanR5Identity(raw(), ticket: ticket, topicID: 2)
        let prepared = try await j.prepare(.init(session: o, scope: .init(activityID: 41, topicID: 2, nodeID: 9),
            pending: command(), requestedCard: false, sharedPlanR5: binding))
        let old = try await j.transition(prepared, to: .dispatching, startedSessionID: nil)
        let m = try model(w, journal: j, approved: true); await m.retryOriginal()
        let body = try JSONDecoder().decode(PlayWireValue.self, from: XCTUnwrap(w.requests.first { $0.httpMethod == "POST" }?.httpBody))
        XCTAssertEqual(body["idempotencyKey"].text, command().key)
        do { _ = try await j.transition(old, to: .acknowledged, startedSessionID: nil); XCTFail("Old lease replaced the retry") } catch {}
        let after = try await j.read(); XCTAssertEqual(after?.value.pending, command()); XCTAssertEqual(after?.value.phase, .unknown)
    }
    func testRevokedOwnerCannotReadOrReplay() async throws {
        let w = R5RecoveryWire(), m = try model(w, journal: PlayMemoryAdvancedRecovery(), approved: true, current: { false })
        await m.load(sessionID: 901); await m.retryOriginal(); XCTAssertTrue(w.requests.isEmpty)
    }
}

@MainActor private final class R5RecoveryWire: HTTPTransport {
    var requests: [URLRequest] = []
    var state: PlayWireValue = .null
    var beforePost: (() async throws -> Void)?
    var postResult: ((URLRequest) throws -> PlayWireValue)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.httpMethod == "POST" {
            try await beforePost?()
            if let postResult { return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": postResult(request)])), 200) }
            throw PlayExperienceError.unknownResult
        }
        let data: PlayWireValue = request.url?.path.hasSuffix("/advanced/state") == true ? state : .null
        return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": data])), 200)
    }
}
