import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class PlaySharedPlanR5HostTests: XCTestCase {
    private var ticket: PlaySharedPlanOperationTicket {
        .init(id: UUID(), activityID: 41, sessionID: 501, teamID: 21, memberID: 7, nodeID: 9, sourceNodeID: 8,
              bindingVersion: 1, authorityEpoch: 3, round: 1, receiptID: 80, endingKey: "ending_a", proposalKey: "plan_a")
    }
    private func owner(_ id: Int = 7) throws -> PlayExperienceSession { try .init(accountID: id, epoch: 1, namespace: "host-synthetic", token: "synthetic", role: "player") }
    private func scope() throws -> PlayAdvancedRecoveryScope { try .init(activityID: 41, topicID: 2, nodeID: 9) }
    private func host(_ wire: PlanStartWire, _ journal: any PlayAdvancedRecovery, approved: Bool = false,
                      current: @escaping () -> Bool = { true }) throws -> PlaySharedPlanR5Host {
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire, enabled: [.reads, .advanced])
        return .init(owner: try owner(), ticket: ticket, topicID: 2, service: service, outcomeService: service, journal: journal,
            current: current, approvedWriteAndOriginalProof: { approved }, validateOperation: {})
    }
    private func marker(_ journal: any PlayAdvancedRecovery) throws -> PlayAdvancedRecoveryRecord {
        try .init(session: owner(), scope: scope(), process: journal.processID, sharedPlanStart: .init(ticket: ticket, topicID: 2))
    }
    func testOpeningAndDefaultApprovalNeverStart() async throws {
        let w = PlanStartWire(), j = PlayMemoryAdvancedRecovery(), m = try host(w, j)
        await m.load(); XCTAssertEqual(m.phase, "readyToStart"); XCTAssertFalse(m.canStart)
        await m.startConfirmed(); XCTAssertTrue(w.requests.isEmpty); let value = try await j.read(); XCTAssertNil(value)
    }
    func testExplicitStartPersistsBeforePostAndKeepsRealSessionCursor() async throws {
        let w = PlanStartWire(), j = PlayMemoryAdvancedRecovery(), m = try host(w, j, approved: true)
        w.beforeStart = { let value = try await j.read(); XCTAssertEqual(value?.value.phase, .starting); XCTAssertNotNil(value?.value.sharedPlanStart) }
        await m.load(); await m.startConfirmed()
        let stored = try await j.read(); XCTAssertEqual(stored?.value.phase, .started); XCTAssertEqual(stored?.value.sessionID, 901)
        XCTAssertEqual(m.phase, "awaitingOriginalContract") // c6-like response lacks r5Session.
        XCTAssertEqual(w.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testRestartReadsRetainedIDWithoutStartingAgain() async throws {
        let w = PlanStartWire(), j = PlayMemoryAdvancedRecovery(), m = try host(w, j, approved: true)
        await m.load(); await m.startConfirmed(); m.suspend()
        let after = try host(w, j, approved: true); await after.load()
        XCTAssertEqual(after.sessionID, 901); XCTAssertEqual(w.requests.filter { $0.httpMethod == "POST" }.count, 1)
        let reads = w.requests.filter { $0.url?.path.hasSuffix("/state") == true }
        XCTAssertTrue(reads.allSatisfy { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(.init(name: "sessionId", value: "901")) == true })
    }
    func testLostStartNeverResubmitsAcrossNewHost() async throws {
        let w = PlanStartWire(); w.loseStart = true; let j = PlayMemoryAdvancedRecovery(), m = try host(w, j, approved: true)
        await m.load(); await m.startConfirmed(); let saved = try await j.read(); XCTAssertEqual(saved?.value.phase, .starting)
        let after = try host(w, j, approved: true); await after.load(); await after.startConfirmed()
        XCTAssertEqual(after.phase, "unknownStart"); XCTAssertEqual(w.requests.filter { $0.httpMethod == "POST" }.count, 1)
        let unchanged = try await j.read(); XCTAssertEqual(saved, unchanged)
    }
    func testFirstR5ActionAtomicallyPromotesOriginalStartedCursor() async throws {
        let j = PlayMemoryAdvancedRecovery(); let start = try await j.prepare(marker(j))
        let cursor = try await j.transition(start, to: .started, startedSessionID: 901)
        let raw = try JSONDecoder().decode(PlayWireValue.self, from: Data("""
        {"sessionId":901,"activityId":41,"topicId":2,"nodeId":9,"ownerType":2,"ownerId":21,"startedAt":1000,
        "config":{"outcomeRulesVersion":1},"r5Session":{"schemaVersion":1,"originalGameSessionId":501,"runtimeAuthorityEpoch":3,
        "playInstanceId":"original","attemptOrdinal":1},"check":{"attemptId":"advanced:901:1"}}
        """.utf8))
        let identity = try PlaySharedPlanR5Identity(raw, ticket: ticket, topicID: 2)
        let pending = PlayAdvancedPending(sessionID: 901, version: 4, key: UUID().uuidString, action: "ROLL_CHECK", payload: [:])
        let prepared = try await j.prepare(.init(session: owner(), scope: scope(), pending: pending, requestedCard: false, sharedPlanR5: identity))
        XCTAssertEqual(prepared.value.sharedPlanR5, identity)
        do { try await j.clear(cursor); XCTFail("Old start lease cleared new original") } catch {}
        let after = try await j.read(); XCTAssertEqual(after, prepared)
    }
    func testEncryptedStartedCursorSurvivesRebuildAndCannotBeClearedByOldLeaseAfterPromotion() async throws {
        let anchors = PlayDurableRecoveryTests.Anchors(), blobs = PlayDurableRecoveryTests.Blobs(), owner = try self.owner()
        let first = try PlayAdvancedDurableRecovery(owner: .init(session: owner), scope: scope(), anchors: anchors, ciphertexts: blobs, processID: UUID())
        let start = try await first.prepare(marker(first)), cursor = try await first.transition(start, to: .started, startedSessionID: 901)
        let reopened = try PlayAdvancedDurableRecovery(owner: .init(session: owner), scope: scope(), anchors: anchors, ciphertexts: blobs, processID: UUID())
        let restored = try await reopened.read(); XCTAssertEqual(restored?.value, cursor.value)
        let raw = try JSONDecoder().decode(PlayWireValue.self, from: Data("""
        {"sessionId":901,"activityId":41,"topicId":2,"nodeId":9,"ownerType":2,"ownerId":21,"startedAt":1000,
        "config":{"outcomeRulesVersion":1},"r5Session":{"schemaVersion":1,"originalGameSessionId":501,"runtimeAuthorityEpoch":3,
        "playInstanceId":"original","attemptOrdinal":1},"check":{"attemptId":"advanced:901:1"}}
        """.utf8))
        let identity = try PlaySharedPlanR5Identity(raw, ticket: ticket, topicID: 2)
        let pending = PlayAdvancedPending(sessionID: 901, version: 4, key: UUID().uuidString, action: "ROLL_CHECK", payload: [:])
        let next = try await reopened.prepare(.init(session: owner, scope: scope(), pending: pending, requestedCard: false, sharedPlanR5: identity))
        do { try await first.clear(cursor); XCTFail("Old encrypted cursor cleared new request") } catch {}
        let after = try await reopened.read(); XCTAssertEqual(after, next)
    }
    func testUnknownStartCannotBeReplacedByAnotherStart() async throws {
        let j = PlayMemoryAdvancedRecovery(), first = try marker(j); let saved = try await j.prepare(first)
        do { _ = try await j.prepare(marker(j)); XCTFail("Unknown start replaced") } catch {}
        let after = try await j.read(); XCTAssertEqual(after, saved)
    }
    func testOrdinaryAdvancedJournalRemainsBlocking() async throws {
        let w = PlanStartWire(), j = PlayMemoryAdvancedRecovery()
        let saved = try await j.prepare(.init(session: owner(), scope: scope(), process: j.processID))
        let m = try host(w, j, approved: true); await m.load(); await m.startConfirmed()
        XCTAssertEqual(m.phase, "otherOriginalPending"); XCTAssertTrue(w.requests.isEmpty)
        let after = try await j.read(); XCTAssertEqual(after, saved)
    }
    func testRevokedPresentationCannotStart() async throws {
        let w = PlanStartWire(), j = PlayMemoryAdvancedRecovery(); var current = true
        let m = try host(w, j, approved: true, current: { current }); await m.load(); current = false
        await m.startConfirmed(); XCTAssertTrue(w.requests.isEmpty)
    }
}

@MainActor private final class PlanStartWire: HTTPTransport {
    var requests: [URLRequest] = []
    var loseStart = false
    var beforeStart: (() async throws -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.httpMethod == "POST" { try await beforeStart?(); if loseStart { throw PlayExperienceError.unknownResult } }
        let value: PlayWireValue = .object(["sessionId": .int(901), "activityId": .int(41), "topicId": .int(2),
            "nodeId": .int(9), "ownerType": .int(2), "ownerId": .int(21), "startedAt": .int(1000), "version": .int(0)])
        return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": value])), 200)
    }
}
