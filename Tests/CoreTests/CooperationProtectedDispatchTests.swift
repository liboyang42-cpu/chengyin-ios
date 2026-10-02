import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class ProtectedWire: CoopFlowOfflineHTTPTransport {
    var requests: [URLRequest] = []
    var data = Data(#"{"code":200,"data":{"conversationId":17}}"#.utf8)
    var status = 200
    var error: Error?
    var hook: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); hook?()
        if let error { throw error }; return (data, status)
    }
}
private final class UnmarkedProtectedWire: HTTPTransport {
    var calls = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls += 1; return (Data(), 200)
    }
}
@MainActor private final class ProtectedEvidence: CoopFlowEvidenceReading {
    var calls = 0
    var allowed = true
    var revision = 1
    var hook: (() -> Void)?
    func freshEvidence(for operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowEvidence {
        calls += 1; hook?()
        return CoopFlowEvidence(baseline: .object([
            "id": .id(8), "status": .id(0), "fromId": .id(9), "inviteType": .id(0),
            "revision": .id(revision), "termsMode": .string("TRAFFIC")
        ]), permitted: allowed)
    }
}
@MainActor final class CooperationProtectedDispatchTests: XCTestCase {
    private let endpoint = URL(string: "https://example.com/source")!
    private func session(_ account: Int = 1, _ epoch: UInt64 = 1) throws -> CoopFlowSession {
        try CoopFlowSession(accountID: account, epoch: epoch, token: "synthetic-token")
    }
    private func operations() throws -> [CoopFlowMutation] {
        [.invite(try CoopFlowInvitation(kind: .merchant, recipient: CoopFlowIdentity(.member, 2), topicID: 3, message: "Synthetic invitation")),
         .handle(inviteID: 8, action: .accept, reason: "Synthetic reply"),
         .contact(inviteID: 8), .complaint(topicID: 3, reason: "Synthetic reason"),
         .enrollOffer(fields: ["chapterId": .id(4), "termsMode": .string("TRAFFIC")])]
    }
    private func service(_ wire: any HTTPTransport, enabled: Bool = true,
                         grants: Set<CoopFlowProtectedOperation> = Set(CoopFlowProtectedOperation.allCases),
                         approved: URL? = nil) throws -> CoopFlowService {
        CoopFlowService(configuration: try APIConfiguration(baseURL: endpoint), transport: wire,
                        dormantWritesEnabled: enabled,
                        protectedDispatch: CoopFlowProtectedDispatch(operations: grants, endpoint: approved ?? endpoint))
    }
    private func lockURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("locks.json") }
    private func assertFailure(_ expected: CoopFlowFailure, _ body: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await body(); XCTFail("Expected rejection", file: file, line: line) }
        catch { XCTAssertEqual(error as? CoopFlowFailure, expected, file: file, line: line) }
    }
    func testAllFiveExactWireRequestsThroughReviewAndFakeHTTP() async throws {
        let ops = try operations()
        let expected: [CoopFlowJSON] = [
            .object(["inviteType": .id(0), "toType": .string("merchant"), "toId": .id(2), "topicId": .id(3), "shareMode": .id(0), "message": .string("Synthetic invitation")]),
            .object(["id": .id(8), "status": .id(1), "handleReason": .string("Synthetic reply")]),
            .object(["id": .id(8)]), .object(["topicId": .id(3), "reason": .string("Synthetic reason")]),
            .object(["chapterId": .id(4), "termsMode": .string("TRAFFIC")])]
        let paths = ["invite", "handle", "contact", "complaint/report", "offer/enroll"]
        for (index, op) in ops.enumerated() {
            let wire = ProtectedWire(), evidence = ProtectedEvidence(), captured = try session()
            let c = CoopFlowCoordinator(current: { captured }, evidence: evidence,
                executor: CoopFlowDormantExecutor(service: try service(wire)), locks: CoopFlowFileLocks(url: lockURL()), enabled: true)
            let review = try await c.prepare(op)
            _ = try await c.confirm(review)
            XCTAssertEqual(evidence.calls, 2); XCTAssertEqual(wire.requests.count, 1)
            let request = try XCTUnwrap(wire.requests.first)
            XCTAssertEqual(request.url?.absoluteString, endpoint.absoluteString + "/api/coop/" + paths[index])
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(try JSONDecoder().decode(CoopFlowJSON.self, from: XCTUnwrap(request.httpBody)), expected[index])
            await assertFailure(.stale) { _ = try await c.confirm(review) }
            XCTAssertEqual(wire.requests.count, 1)
        }
    }
    func testDefaultOffGlobalOffIndependentGrantsEndpointAndMarker() async throws {
        let wire = ProtectedWire(), captured = try session()
        let defaultService = CoopFlowService(configuration: try APIConfiguration(baseURL: endpoint), transport: wire)
        for op in try operations() {
            let kind = try XCTUnwrap(CoopFlowProtectedOperation(op))
            let configs = [defaultService, try service(wire, enabled: false), try service(wire, grants: []),
                           try service(wire, grants: Set(CoopFlowProtectedOperation.allCases).subtracting([kind])),
                           try service(wire, approved: URL(string: "https://example.com/other")!)]
            for config in configs {
                XCTAssertFalse(config.permitsDispatch(op))
                await assertFailure(.disabled) { _ = try await config.perform(op, session: captured) }
            }
            XCTAssertTrue(try service(wire, grants: [kind]).permitsDispatch(op))
        }
        let unmarked = UnmarkedProtectedWire()
        for op in try operations() { await assertFailure(.disabled) { _ = try await self.service(unmarked).perform(op, session: captured) } }
        XCTAssertEqual(unmarked.calls, 0); XCTAssertTrue(wire.requests.isEmpty)
    }
    func testEveryOperationServerUnauthorizedAndMalformedErrors() async throws {
        for op in try operations() {
            let wire = ProtectedWire(), config = try service(wire), captured = try session()
            wire.data = Data(#"{"code":409,"msg":"Synthetic source rejection"}"#.utf8)
            await assertFailure(.server(409, "Synthetic source rejection")) { _ = try await config.perform(op, session: captured) }
            wire.data = Data("not JSON".utf8)
            await assertFailure(.malformed) { _ = try await config.perform(op, session: captured) }
            wire.status = 401
            do { _ = try await config.perform(op, session: captured); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
            wire.status = 200; wire.data = Data(#"{"code":401}"#.utf8)
            do { _ = try await config.perform(op, session: captured); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        }
    }
    func testContactRequiresNumericPositiveConversationAndVoidAcknowledgementsWork() async throws {
        let wire = ProtectedWire(), config = try service(wire), captured = try session()
        for data in [#"{}"#, #"{"conversationId":0}"#, #"{"conversationId":"17"}"#, #"{"conversationId":1.5}"#] {
            wire.data = Data(("{\"code\":200,\"data\":" + data + "}").utf8)
            await assertFailure(.ambiguous) { _ = try await config.perform(.contact(inviteID: 8), session: captured) }
        }
        wire.data = Data(#"{"code":200}"#.utf8)
        _ = try await config.perform(operations()[0], session: captured)
        _ = try await config.perform(operations()[1], session: captured)
        for op in try operations().suffix(2) { await assertFailure(.ambiguous) { _ = try await config.perform(op, session: captured) } }
    }
    func testEveryUnknownOutcomePersistsAcrossRelaunchAndEpoch() async throws {
        for op in try operations() {
            let wire = ProtectedWire(), evidence = ProtectedEvidence(), url = lockURL()
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            var current = try session()
            let executor = CoopFlowDormantExecutor(service: try service(wire))
            let c = CoopFlowCoordinator(current: { current }, evidence: evidence, executor: executor, locks: CoopFlowFileLocks(url: url), enabled: true)
            wire.error = URLError(.timedOut)
            let review = try await c.prepare(op)
            do { _ = try await c.confirm(review); XCTFail() } catch {}
            current = try session(1, 2); wire.error = nil
            let relaunched = CoopFlowCoordinator(current: { current }, evidence: evidence, executor: executor, locks: CoopFlowFileLocks(url: url), enabled: true)
            await assertFailure(.ambiguous) { _ = try await relaunched.prepare(op) }
            XCTAssertEqual(wire.requests.count, 1)
            current = try session(3, 3)
            _ = try await relaunched.prepare(op) // Account isolation, without dispatch.
            let persisted = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(persisted.contains("endpoint:")); XCTAssertFalse(persisted.contains("synthetic-token"))
            XCTAssertFalse(persisted.contains("Synthetic reason"))
        }
    }
    func testFreshEvidenceChangePermissionLossAndSessionChangeNeverSend() async throws {
        for op in try operations() {
            for mode in 0..<4 {
                let wire = ProtectedWire(), evidence = ProtectedEvidence()
                var current = try session()
                let c = CoopFlowCoordinator(current: { current }, evidence: evidence,
                    executor: CoopFlowDormantExecutor(service: try service(wire)), locks: CoopFlowFileLocks(url: lockURL()), enabled: true)
                let review = try await c.prepare(op)
                if mode == 0 { evidence.revision += 1 }
                if mode == 1 { evidence.allowed = false }
                if mode == 2 { current = try session(1, 2) }
                if mode == 3 { evidence.hook = { current = try! self.session(2, 3) } }
                await assertFailure(mode == 0 ? .conflict : mode == 1 ? .permission : .stale) { _ = try await c.confirm(review) }
                XCTAssertTrue(wire.requests.isEmpty)
            }
        }
    }
    func testSessionChangeAfterSendRetainsDurableLock() async throws {
        let wire = ProtectedWire(), evidence = ProtectedEvidence(), url = lockURL()
        var current = try session()
        let original = current
        wire.hook = { current = try! self.session(2, 2) }
        let c = CoopFlowCoordinator(current: { current }, evidence: evidence,
            executor: CoopFlowDormantExecutor(service: try service(wire)), locks: CoopFlowFileLocks(url: url), enabled: true)
        let op = CoopFlowMutation.contact(inviteID: 8), review = try await c.prepare(.contact(inviteID: 8))
        await assertFailure(.stale) { _ = try await c.confirm(review) }
        current = original
        await assertFailure(.ambiguous) { _ = try await c.prepare(op) }
        XCTAssertEqual(wire.requests.count, 1)
    }
}

@MainActor private final class ScopedProtectedExecutor: CoopFlowExecuting {
    var dispatchScope: String? = "https://example.com/source"
    var calls = 0
    func permitsDispatch(_ operation: CoopFlowMutation) -> Bool { true }
    func execute(_ operation: CoopFlowMutation, session: CoopFlowSession) async throws -> CoopFlowJSON {
        calls += 1; return .object([:])
    }
}
@MainActor final class CooperationProtectedScopeTests: XCTestCase {
    func testEndpointSwapInvalidatesPreparedReview() async throws {
        let session = try CoopFlowSession(accountID: 1, epoch: 1, token: "synthetic")
        let executor = ScopedProtectedExecutor(), evidence = ProtectedEvidence()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let c = CoopFlowCoordinator(current: { session }, evidence: evidence, executor: executor, locks: CoopFlowFileLocks(url: url), enabled: true)
        let review = try await c.prepare(.contact(inviteID: 8))
        executor.dispatchScope = "https://example.com/other"
        do { _ = try await c.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .stale) }
        XCTAssertEqual(executor.calls, 0)
    }
    func testUnscopedProtectedExecutorAndDefaultCoordinatorStayDisabled() async throws {
        let session = try CoopFlowSession(accountID: 1, epoch: 1, token: "synthetic")
        for enabled in [false, true] {
            let executor = ScopedProtectedExecutor(); if enabled { executor.dispatchScope = nil }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let c = CoopFlowCoordinator(current: { session }, evidence: ProtectedEvidence(), executor: executor, locks: CoopFlowFileLocks(url: url), enabled: enabled)
            let review = try await c.prepare(.contact(inviteID: 8))
            do { _ = try await c.confirm(review); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .disabled) }
            XCTAssertEqual(executor.calls, 0)
        }
    }
    func testOldUnknownLocksSurviveUpgradeToEndpointKeys() async throws {
        let session = try CoopFlowSession(accountID: 1, epoch: 99, token: "synthetic")
        let executor = ScopedProtectedExecutor()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try CoopFlowFileLocks(url: url).acquire("1:invite-8")
        let c = CoopFlowCoordinator(current: { session }, evidence: ProtectedEvidence(), executor: executor, locks: CoopFlowFileLocks(url: url), enabled: true)
        do { _ = try await c.prepare(.contact(inviteID: 8)); XCTFail() } catch { XCTAssertEqual(error as? CoopFlowFailure, .ambiguous) }
        XCTAssertEqual(executor.calls, 0)
    }
}
