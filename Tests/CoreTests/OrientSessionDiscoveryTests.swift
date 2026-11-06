import XCTest
import Foundation
@testable import QuestifyCore

// c6 contract examples only. Contract selection does not prove a live deployment.
@MainActor private func orientCurrentService(_ transport: any HTTPTransport) throws -> OrientSessionService {
    try .init(configuration: APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: transport, contract: .currentC6)
}
private func orientCurrentView(id: Int = 9, activity: Int = 0, phase: String = "RUNNING", status: Int = 0) -> String {
    orientTestView(id: id, activity: activity, phase: phase, status: status)
        .replacingOccurrences(of: "\"sessionId\":\(id)", with: "\"sessionId\":\"\(id)\"")
        .replacingOccurrences(of: "\"topicId\":3", with: "\"topicId\":\"3\"")
        .replacingOccurrences(of: "\"activityId\":\(activity)", with: "\"activityId\":\"\(activity)\"")
}
private func orientCurrentList(_ rows: [String]) -> String { "{\"sessions\":[" + rows.joined(separator: ",") + "]}" }

@MainActor final class OrientSessionDiscoveryTests: XCTestCase {
    private func make(_ t: OrientTestTransport, _ store: any OrientSessionRecovery, _ box: OrientTestIdentityBox) throws -> OrientSessionCoordinator {
        try .init(scope: orientTestScope(), service: orientCurrentService(t), recovery: store, currentIdentity: { box.value })
    }
    func testCurrentNilActivityOmitsFilterAndKeepsStringIDsExact() async throws {
        let t = OrientTestTransport(); let id = 9_007_199_254_740_993
        t.append(orientCurrentList([orientCurrentView(id: id), orientCurrentView(id: 10, activity: 21)]))
        let result = try await orientCurrentService(t).current(topicID: 3, token: "synthetic-token")
        XCTAssertEqual(result.sessions.map(\.sessionID), [id, 10])
        XCTAssertEqual(result.sessions.map { $0.scope.activityID }, [0, 21])
        XCTAssertEqual(t.requests.first?.url?.query, "topicId=3")
        XCTAssertEqual(t.requests.first?.httpMethod, "GET")
    }
    func testCurrentExplicitZeroIsNotOmittedAndEmptyIsAuthoritative() async throws {
        let t = OrientTestTransport(); t.append(orientCurrentList([]))
        let result = try await orientCurrentService(t).current(topicID: 3, activityID: 0, token: "synthetic-token")
        XCTAssertTrue(result.sessions.isEmpty)
        XCTAssertEqual(t.requests.first?.url?.query, "activityId=0&topicId=3")
    }
    func testFrozenContractNeverProbesCurrent() async throws {
        let t = OrientTestTransport()
        do { _ = try await orientTestService(t).current(topicID: 3, token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? OrientSessionFlowError, .discoveryUnavailable) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testDuplicateOrWrongScopeListsFailClosed() async throws {
        let t = OrientTestTransport(); let service = try orientCurrentService(t)
        let bad = [orientCurrentList([orientCurrentView(), orientCurrentView()]),
                   orientCurrentList([orientCurrentView(activity: 21)]),
                   orientCurrentList([orientCurrentView().replacingOccurrences(of: "\"topicId\":\"3\"", with: "\"topicId\":\"4\"")])]
        for value in bad {
            t.append(value)
            do { _ = try await service.current(topicID: 3, activityID: 0, token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testDiscoveryNeverSelectsNewestAndExplicitSelectionRereads() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientCurrentList([orientCurrentView(id: 10), orientCurrentView()]))
        try await c.discoverSessions()
        XCTAssertNil(c.view); XCTAssertTrue(c.requiresSessionSelection)
        do { try await c.selectSession(sessionID: 99); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .sessionSelectionRequired) }
        XCTAssertEqual(t.requests.count, 1)
        t.append(orientCurrentView()); try await c.selectSession(sessionID: 9)
        XCTAssertEqual(c.view?.sessionID, 9); XCTAssertFalse(c.requiresSessionSelection)
        XCTAssertTrue(t.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testEvenSingleSessionRequiresExplicitSelection() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientCurrentList([orientCurrentView(phase: "ABANDONED", status: 2)]))
        try await c.discoverSessions()
        XCTAssertNil(c.view); XCTAssertTrue(c.requiresSessionSelection)
        do { try await c.prepare(key: "new-prepare-key"); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .sessionSelectionRequired) }
        XCTAssertEqual(t.requests.count, 1); XCTAssertNil(store.value)
    }
    func testPrepareRequiresDiscoveryAndAddsReturnedRealSessionToEmptyList() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        do { try await c.prepare(key: "prepare-key-01"); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .sessionDiscoveryRequired) }
        XCTAssertTrue(t.requests.isEmpty)
        t.append(orientCurrentList([])); try await c.discoverSessions()
        t.append(orientTestSafety); t.append(orientCurrentView(phase: "PREPARED")); t.append(orientCurrentView(phase: "PREPARED"))
        try await c.prepare(key: "prepare-key-01")
        XCTAssertEqual(c.sessions.map(\.sessionID), [9]); XCTAssertEqual(c.view?.phase, .prepared); XCTAssertNil(store.value)
    }
    func testAbsentCurrentDeploymentDoesNotFallbackToPrepare() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append("null", code: 404, status: 404)
        do { try await c.discoverSessions(); XCTFail() } catch {}
        XCTAssertFalse(c.hasDiscoveredSessions); XCTAssertNil(c.view); XCTAssertNil(store.value)
        XCTAssertEqual(t.requests.count, 1); XCTAssertEqual(t.requests[0].httpMethod, "GET")
    }
    func testLostPrepareRecoversByUniqueOriginalKeyWithoutExternalSessionID() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox()
        store.value = try orientTestPending(.prepare, key: "original-prepare-key")
        let c = try make(t, store, box)
        t.append(orientCurrentList([orientCurrentView(), orientCurrentView(id: 10, phase: "FINISHED", status: 1)]))
        t.append(orientCurrentView()); t.append("null", code: 404, err: "ORIENT_RECEIPT_NOT_FOUND")
        t.append(orientCurrentView(id: 10, phase: "FINISHED", status: 1)); t.append(orientCurrentView(id: 10, phase: "PREPARED"))
        t.append(orientCurrentView(id: 10, phase: "FINISHED", status: 1))
        try await c.recoverPending()
        XCTAssertEqual(c.view?.sessionID, 10); XCTAssertEqual(c.view?.phase, .finished); XCTAssertNil(store.value)
        let receipts = t.requests.filter { $0.url!.path.hasSuffix("/receipt") }
        XCTAssertEqual(receipts.count, 2)
        XCTAssertTrue(receipts.allSatisfy { $0.url!.query!.contains("idempotencyKey=original-prepare-key") })
        XCTAssertTrue(t.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testMissingOrAmbiguousPrepareReceiptsPreserveOriginalRecord() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox()
        let original = try orientTestPending(.prepare); store.value = original; let c = try make(t, store, box)
        t.append(orientCurrentList([]))
        do { try await c.recoverPending(); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .receiptUnresolved) }
        XCTAssertEqual(store.value, original)
        t.append(orientCurrentList([orientCurrentView(), orientCurrentView(id: 10)]))
        t.append(orientCurrentView()); t.append(orientCurrentView(phase: "PREPARED"))
        t.append(orientCurrentView(id: 10)); t.append(orientCurrentView(id: 10, phase: "PREPARED"))
        do { try await c.recoverPending(); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .sessionSelectionRequired) }
        XCTAssertEqual(store.value, original); XCTAssertNil(c.view)
        XCTAssertTrue(t.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testUnknownSecondCandidateCannotMakeFirstReceiptUnique() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox()
        let original = try orientTestPending(.prepare); store.value = original; let c = try make(t, store, box)
        t.append(orientCurrentList([orientCurrentView(), orientCurrentView(id: 10)]))
        t.append(orientCurrentView()); t.append(orientCurrentView(phase: "PREPARED"))
        t.append(orientCurrentView(id: 10)); t.append("null", code: 503, status: 503)
        do { try await c.recoverPending(); XCTFail() } catch {}
        XCTAssertEqual(store.value, original); XCTAssertNil(c.view)
    }
    func testLateDiscoveryReplyCannotPopulateDifferentIdentity() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientCurrentList([orientCurrentView()])); t.beforeReply = { _ in box.value = nil }
        do { try await c.discoverSessions(); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .staleIdentity) }
        XCTAssertTrue(c.sessions.isEmpty); XCTAssertFalse(c.hasDiscoveredSessions)
    }
    func testCurrentAlternativeRecoveryReadsOriginalReceiptWithoutPost() async throws {
        let t = OrientTestTransport(); let service = try orientCurrentService(t)
        let pending = try orientTestPending(.alternative(sessionID: 9, taskID: 12, playInstanceID: "route:real", evidence: .photo(picURL: "owned-photo")))
        t.append(orientCurrentView()); t.append(orientTestAlternative())
        guard case .alternative(let value) = try await service.receipt(pending, token: "synthetic-token") else { return XCTFail() }
        XCTAssertEqual(value.outcome, "PENDING_REVIEW"); XCTAssertFalse(value.completed)
        XCTAssertEqual(t.requests.last?.url?.path, "/api/orient/task/alternative/receipt")
        XCTAssertEqual(t.requests.last?.url?.query, "activityId=0&idempotencyKey=test-key-01&playInstanceId=route:real&taskId=12&topicId=3")
        XCTAssertTrue(t.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testCurrentScoreDimensionsAcceptExactSignedIntegerStrings() async throws {
        let t = OrientTestTransport()
        let score = orientTestScore().replacingOccurrences(of: "\"totalCenti\":1700", with: "\"totalCenti\":\"1700\"")
            .replacingOccurrences(of: "\"TASK\":2000", with: "\"TASK\":\"2000\"")
            .replacingOccurrences(of: "\"PENALTY\":-300", with: "\"PENALTY\":\"-300\"")
        t.append(score)
        let value = try await orientCurrentService(t).score(sessionID: 9, scope: orientTestScope(), token: "synthetic-token")
        XCTAssertEqual(value.byDimension["PENALTY"], -300); XCTAssertEqual(value.totalCenti, 1700)
        t.append(score.replacingOccurrences(of: "\"TASK\":\"2000\"", with: "\"TASK\":\"2000.0\""))
        do { _ = try await orientCurrentService(t).score(sessionID: 9, scope: orientTestScope(), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testC6CannotSendLegacyUnkeyedScoreSync() async throws {
        let t = OrientTestTransport()
        do { _ = try await orientCurrentService(t).syncScore(sessionID: 9, token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testLegacyEndedStatusWithDisqualifiedPhaseRemainsTerminal() async throws {
        let t = OrientTestTransport(); t.append(orientCurrentList([orientCurrentView(phase: "DISQUALIFIED", status: 2)]))
        let value = try await orientCurrentService(t).current(topicID: 3, activityID: 0, token: "synthetic-token")
        XCTAssertEqual(value.sessions.first?.phase, .disqualified)
        XCTAssertTrue(value.sessions.first?.phase.isTerminal == true)
    }
}
