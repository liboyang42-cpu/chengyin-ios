import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class WorkspaceRecoveryBarrierHTTP: HTTPTransport {
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var requests = 0
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests += 1
        return try await withCheckedThrowingContinuation {
            continuation = $0; let waiter = started; started = nil; waiter?.resume()
        }
    }
    func waitForRequest() async {
        if requests > 0 { return }
        await withCheckedContinuation { started = $0 }
    }
    func release(error: Error? = nil) {
        let value = continuation; continuation = nil
        if let error { value?.resume(throwing: error) }
        else {
            let body = String(data: SquareWorkspaceFixtures.legacyPost, encoding: .utf8)!
            value?.resume(returning: (Data("{\"code\":200,\"data\":\(body)}".utf8), 200))
        }
    }
}
@MainActor final class SquareWorkspaceRecoverySerializationTests: XCTestCase {
    private func session() throws -> SquareWorkspaceSession { try .init(accountID: 81, namespace: "recovery-serialization", epoch: 1) }
    private func entry(_ id: String, body: String, postID: Int? = 701) -> SquareWorkspaceLocalEntry {
        .init(draft: .init(workflowID: id, postID: postID, body: body), lane: .legacy, pending: false, receipt: nil, updatedAt: Date(timeIntervalSince1970: 1))
    }
    private func coordinator(_ http: WorkspaceRecoveryBarrierHTTP, store: SquareWorkspaceStore) throws -> SquareWorkspaceCoordinator {
        let identity = try session(); var grants = SquareWorkspaceGrants(); grants.live = true
        let api = SquareWorkspaceService(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: http)
        return .init(session: identity, store: store, service: api, grants: grants, currentSession: { identity }, token: { "fixture-token" })
    }
    func testSuspendedRecoverySerializesCompetingResumeIncludingNewLocalDraft() async throws {
        let http = WorkspaceRecoveryBarrierHTTP(), store = SquareWorkspaceStore(storage: SquareWorkspaceMemoryStorage())
        let first = entry("first-workflow", body: "Saved first edits"), second = entry("second-workflow", body: "Saved second edits")
        let new = entry("new-local-workflow", body: "New unsent draft", postID: nil)
        for value in [first, second, new] { try store.save(value, session: session()) }
        let model = try coordinator(http, store: store)
        let recovery = Task { try await model.resume(first) }; await http.waitForRequest()
        XCTAssertTrue(model.busy)
        for competing in [second, new] {
            do { _ = try await model.resume(competing); XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .pending) }
        }
        XCTAssertEqual(http.requests, 1); XCTAssertTrue(model.busy)
        http.release(); let result = try await recovery.value
        XCTAssertFalse(model.busy); XCTAssertEqual(result.body, first.draft.body)
        let untouched = try store.entries(session: session()).filter { $0.id != first.id }
        XCTAssertEqual(untouched, [second, new])
        let resumedNew = try await model.resume(new)
        XCTAssertEqual(resumedNew.body, "New unsent draft"); XCTAssertEqual(http.requests, 1)
    }
    func testSavedEditsDuringSuspendedReadSurviveAndRejectLateRecovery() async throws {
        let http = WorkspaceRecoveryBarrierHTTP(), store = SquareWorkspaceStore(storage: SquareWorkspaceMemoryStorage())
        let original = entry("edited-workflow", body: "Before edit")
        try store.save(original, session: session()); let model = try coordinator(http, store: store)
        let recovery = Task { try await model.resume(original) }; await http.waitForRequest()
        var edited = original; edited.draft.body = "Newer edits from another editor"
        try store.save(edited, session: session()); http.release()
        do { _ = try await recovery.value; XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .staleReview) }
        XCTAssertFalse(model.busy); XCTAssertEqual(try store.entries(session: session()).first, edited)
    }
    func testFailedRecoveryReleasesBusyAndKeepsOriginalDraftAndUnknownLock() async throws {
        let http = WorkspaceRecoveryBarrierHTTP(), store = SquareWorkspaceStore(storage: SquareWorkspaceMemoryStorage())
        let original = entry("failed-workflow", body: "Saved unsent facts")
        var locked = entry("unknown-workflow", body: "Unknown prior attempt"); locked.pending = true
        for value in [original, locked] { try store.save(value, session: session()) }
        let model = try coordinator(http, store: store)
        let recovery = Task { try await model.resume(original) }; await http.waitForRequest()
        XCTAssertTrue(model.busy); http.release(error: URLError(.timedOut))
        do { _ = try await recovery.value; XCTFail() } catch {}
        XCTAssertFalse(model.busy); XCTAssertEqual(try store.entries(session: session()), [original, locked])
        do { _ = try await model.resume(locked); XCTFail() } catch { XCTAssertEqual(error as? SquareWorkspaceFailure, .pending) }
        XCTAssertFalse(model.busy); XCTAssertEqual(http.requests, 1)
    }
}
