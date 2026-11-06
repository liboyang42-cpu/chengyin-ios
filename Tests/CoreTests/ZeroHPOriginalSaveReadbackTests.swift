import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ZeroHPOriginalSaveReadbackTests: XCTestCase {
    private static let before = #"{"schemaVersion":1,"gameplayRuntime":{"survival":{"zeroHpPolicy":"BLOCK_HP_COST","zeroMessage":"before"},"futureRuntime":"keep"}}"#
    private static let after = #"{"schemaVersion":1,"gameplayRuntime":{"survival":{"zeroHpPolicy":"BLOCK_HP_COST","zeroMessage":"after"},"futureRuntime":"keep"}}"#
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "zero-readback") }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], failWrite = false, failRead = false
        var theme = ZeroHPOriginalSaveReadbackTests.before, revision = "r1"
        func detail() throws -> Data {
            var root = try JSONDecoder().decode([String: ProjectEditJSON].self, from: ProjectEditRemoteFixtures.detail(product: .freeExplore, revision: revision))
            var data = try XCTUnwrap(root["data"]?.object), topic = try XCTUnwrap(data["topic"]?.object)
            topic["themeRuntimeConfig"] = .string(theme); data["topic"] = .object(topic); root["data"] = .object(data)
            return try JSONEncoder().encode(root)
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url!.path.hasSuffix("/edit-detail") {
                if failRead { throw URLError(.timedOut) }; return (try detail(), 200)
            }
            guard request.url!.path.hasSuffix("/topic/edit-requests/submit") else { throw APIError.invalidRequest }
            let payload = try projectOriginalTestPayload(request)
            theme = try XCTUnwrap(payload["themeRuntimeConfig"]?.text); revision = "r2"
            if failWrite { throw URLError(.timedOut) }
            return (try projectOriginalTestReceipt(request, legacy: Data(#"{"code":200,"data":71}"#.utf8)), 200)
        }
        var writes: [URLRequest] { requests.filter { $0.url!.path.hasSuffix("/topic/edit-requests/submit") } }
    }
    private func setup() async throws -> (ProjectEditCoordinator, Owner, Wire, ProjectEditLocalStore) {
        let owner = Owner(), wire = Wire(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
        let configuration = try APIConfiguration(baseURL: URL(string: "https://zero-readback.test/")!)
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: "zero-readback", accountID: 7, paths: ["api/topic/update", ProjectEditRequestContract.submitPath])
        let service = ProjectEditHTTPService(configuration: configuration, transport: wire, owner: .personal, approval: approval, store: store,
            currentCredentials: { owner.session.flatMap { try? .init(session: $0, token: "synthetic-zero-readback") } })
        let co = ProjectEditCoordinator(initial: .init(topicID: 71, draft: .init(product: .freeExplore)), service: service, store: store, currentSession: { owner.session })
        await co.load(); XCTAssertEqual(co.state, .idle); return (co, owner, wire, store)
    }
    private func submit(_ co: ProjectEditCoordinator) async throws -> ProjectEditPending {
        var draft = try XCTUnwrap(co.snapshot?.draft); draft.preserved["themeRuntimeConfig"] = .string(Self.after)
        co.prepare(draft); let confirmation = try XCTUnwrap(co.confirmation)
        XCTAssertEqual(confirmation.payload["themeRuntimeConfig"], .string(Self.after))
        await co.confirm(confirmation); return try XCTUnwrap(co.pending)
    }
    func testExactOriginalPayloadAcknowledgmentThenIndependentCurrentReadback() async throws {
        let (co, owner, wire, store) = try await setup(), pending = try await submit(co)
        XCTAssertEqual(co.state, .acknowledged); XCTAssertEqual(wire.writes.count, 1)
        XCTAssertEqual(pending.payload["themeRuntimeConfig"], .string(Self.after))
        XCTAssertEqual(co.snapshot?.draft.preserved["themeRuntimeConfig"], .string(Self.before), "acknowledgment is not server detail")
        let continued = await co.continueAcknowledged(try XCTUnwrap(co.acknowledgedContinuation)); XCTAssertTrue(continued)
        XCTAssertEqual(co.snapshot?.draft.preserved["themeRuntimeConfig"], .string(Self.after))
        XCTAssertEqual(try NativeZeroHPAuthorDraft(draft: XCTUnwrap(co.snapshot?.draft)).zeroMessage, "after")
        XCTAssertNil(co.pending); XCTAssertNil(try store.pending(session: XCTUnwrap(owner.session), identity: pending.identity))
        XCTAssertEqual(wire.writes.count, 1)
    }
    func testFailedFreshReadKeepsAcknowledgedOriginalUntilExplicitRetry() async throws {
        let (co, _, wire, _) = try await setup(), pending = try await submit(co)
        wire.failRead = true
        let continued = await co.continueAcknowledged(try XCTUnwrap(co.acknowledgedContinuation)); XCTAssertFalse(continued)
        XCTAssertEqual(co.pending?.operationID, pending.operationID); XCTAssertEqual(co.pending?.payload, pending.payload)
        XCTAssertEqual(co.pending?.serverAcknowledged, true); XCTAssertEqual(wire.writes.count, 1)
        wire.failRead = false
        let retried = await co.continueAcknowledged(try XCTUnwrap(co.acknowledgedContinuation)); XCTAssertTrue(retried)
        XCTAssertEqual(co.snapshot?.draft.preserved["themeRuntimeConfig"], .string(Self.after)); XCTAssertEqual(wire.writes.count, 1)
    }
    func testUnknownWriteCannotBeResolvedByMatchingCurrentDetailOrReentry() async throws {
        let (co, owner, wire, store) = try await setup(); wire.failWrite = true
        let pending = try await submit(co); XCTAssertEqual(co.state, .unknown)
        // Server fixture contains the new value, but the original command outcome remains unknown.
        co.leaveScreen(); await co.load(); await co.checkOutcome()
        XCTAssertEqual(co.snapshot?.draft.preserved["themeRuntimeConfig"], .string(Self.after))
        XCTAssertTrue(co.isLocked); XCTAssertNil(co.acknowledgedContinuation)
        XCTAssertEqual(co.pending?.operationID, pending.operationID); XCTAssertNotEqual(co.pending?.serverAcknowledged, true)
        XCTAssertEqual(try store.pending(session: XCTUnwrap(owner.session), identity: pending.identity)?.payload, pending.payload)
        co.prepare(try XCTUnwrap(co.snapshot?.draft)); XCTAssertNil(co.confirmation); XCTAssertEqual(wire.writes.count, 1)
    }
    func testChangedAccountCannotConsumeAcknowledgedOriginalContinuation() async throws {
        let (co, owner, wire, store) = try await setup(), pending = try await submit(co)
        let capture = try XCTUnwrap(co.acknowledgedContinuation), originalOwner = try XCTUnwrap(owner.session), reads = wire.requests.count
        owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: "zero-readback")
        let continued = await co.continueAcknowledged(capture); XCTAssertFalse(continued)
        XCTAssertEqual(wire.requests.count, reads)
        XCTAssertEqual(try store.pending(session: originalOwner, identity: pending.identity)?.operationID, pending.operationID)
        XCTAssertEqual(wire.writes.count, 1)
    }
}
