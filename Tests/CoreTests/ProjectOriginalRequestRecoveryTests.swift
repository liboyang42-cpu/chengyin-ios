import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ProjectOriginalRequestRecoveryTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "original-request-test")
    }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var reply: (URLRequest) throws -> Data = { _ in throw URLError(.timedOut) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path == "/api/publish/home" {
                return (Data(#"{"code":200,"data":{"permission":{"canProPublish":true},"quota":{"themesRemaining":2}}}"#.utf8), 200)
            }
            return (try reply(request), 200)
        }
    }
    private func service(_ owner: Owner, _ store: ProjectEditLocalStore, _ wire: Wire,
                         paths: Set<String> = ["api/topic/create", "api/topic/update", ProjectEditRequestContract.submitPath, ProjectEditRequestContract.readPath]) throws -> ProjectEditHTTPService {
        let configuration = try APIConfiguration(baseURL: URL(string: "https://original.test")!)
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: "original-request-test", accountID: 7, paths: paths)
        return .init(configuration: configuration, transport: wire, owner: .personal, approval: approval, store: store,
                     currentCredentials: { owner.session.flatMap { try? .init(session: $0, token: "fixture-only") } })
    }
    private func pending(_ owner: Owner, _ store: ProjectEditLocalStore, existing: Bool = false, paired: Bool = true) throws -> ProjectEditPending {
        let session = try XCTUnwrap(owner.session), draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        let identity = try (existing ? ProjectEditDraftIdentity(topicID: 71) : ProjectEditDraftIdentity())
        var value = ProjectEditPending(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            payload: try ProjectEditContract.payload(draft, topicID: existing ? 71 : nil, scope: .full))
        value.dispatchStarted = true
        if paired { value.serverRequest = try .init(operationID: value.operationID, originalPath: existing ? "api/topic/update" : "api/topic/create", payload: value.payload) }
        try store.save(draft, session: session, identity: identity); try store.savePending(value, session: session)
        return value
    }
    func testExactEnvelopeIsDurableBeforeOneOriginalSubmit() async throws {
        let owner = Owner(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), wire = Wire()
        let session = try XCTUnwrap(owner.session), draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        wire.reply = { request in
            XCTAssertEqual(request.url?.path, "/api/topic/edit-requests/submit")
            let sent = try JSONDecoder().decode(ProjectEditRequestContract.Submit.self, from: XCTUnwrap(request.httpBody))
            let identity = try XCTUnwrap(store.activeIdentity(session: session, product: draft.product, owner: draft.owner))
            let durable = try XCTUnwrap(store.pending(session: session, identity: identity))
            XCTAssertEqual(durable.serverRequest, sent); XCTAssertEqual(durable.dispatchStarted, true)
            XCTAssertTrue(sent.matches(operationID: durable.operationID, originalPath: "api/topic/create", payload: durable.payload))
            return try projectOriginalTestReceipt(sent)
        }
        let coordinator = ProjectEditCoordinator(initial: .init(draft: draft), service: try service(owner, store, wire), store: store, currentSession: { owner.session })
        await coordinator.load(); coordinator.prepare(draft); await coordinator.confirm(try XCTUnwrap(coordinator.confirmation))
        XCTAssertEqual(coordinator.state, .acknowledged); XCTAssertEqual(coordinator.pending?.serverRequestCommitted, true)
        XCTAssertEqual(wire.requests.filter { $0.url?.path == "/api/topic/edit-requests/submit" }.count, 1)
        XCTAssertFalse(wire.requests.contains { $0.url?.path == "/api/topic/create" })
    }
    func testRestartRestoresPendingBeforeFailedDetailAndReadOnlyGrantRecovers() async throws {
        let owner = Owner(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), wire = Wire()
        let original = try pending(owner, store, existing: true), sent = try XCTUnwrap(original.serverRequest)
        owner.session = try .init(accountID: 7, epoch: 2, storageNamespace: "original-request-test")
        let api = try service(owner, store, wire, paths: [ProjectEditRequestContract.readPath])
        wire.reply = { request in
            if request.url?.path == "/api/topic/edit-detail" { throw URLError(.notConnectedToInternet) }
            XCTAssertEqual(request.url?.path, "/api/topic/edit-requests/read")
            return try projectOriginalTestReceipt(sent)
        }
        let coordinator = ProjectEditCoordinator(initial: .init(topicID: 71, draft: .init(product: .freeExplore)), service: api, store: store, currentSession: { owner.session })
        await coordinator.load()
        XCTAssertEqual(coordinator.state, .unknown); XCTAssertEqual(coordinator.pending?.operationID, original.operationID)
        XCTAssertTrue(coordinator.canCheckOutcome); XCTAssertEqual(api.authority, .readOnly)
        await coordinator.checkOutcome()
        XCTAssertEqual(coordinator.state, .acknowledged); XCTAssertEqual(coordinator.pending?.completedTopicID, 71)
        XCTAssertFalse(wire.requests.contains { $0.url?.path.contains("submit") == true })
    }
    func testLegacyLocalUUIDRemainsLockedAndMakesZeroRecoveryRequests() async throws {
        let owner = Owner(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), wire = Wire()
        let original = try pending(owner, store, paired: false), api = try service(owner, store, wire)
        let coordinator = ProjectEditCoordinator(initial: .init(draft: ProjectEditSyntheticFixtures.draft(product: .freeExplore)), service: api, store: store, currentSession: { owner.session })
        await coordinator.load(); XCTAssertTrue(coordinator.isLocked); XCTAssertFalse(coordinator.canCheckOutcome)
        await coordinator.checkOutcome(); let retry = try await api.retrySameRequest(original, session: XCTUnwrap(owner.session))
        XCTAssertEqual(retry, .unknown); XCTAssertTrue(wire.requests.isEmpty)
        XCTAssertNil(try store.pending(session: XCTUnwrap(owner.session), identity: original.identity)?.serverRequest)
    }
    func testRunningAndNotFoundOnlyReadOriginalAndNeverResend() async throws {
        for state in ["RUNNING", "NOT_FOUND"] {
            let owner = Owner(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), wire = Wire()
            let original = try pending(owner, store), api = try service(owner, store, wire)
            wire.reply = { _ in try projectOriginalTestReceipt(XCTUnwrap(original.serverRequest), state: state) }
            let result = try await api.retrySameRequest(original, session: XCTUnwrap(owner.session))
            XCTAssertEqual(result, .unknown); XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/api/topic/edit-requests/read"])
            XCTAssertTrue(ProjectEditLocalStore.exactPending(try XCTUnwrap(store.pending(session: XCTUnwrap(owner.session), identity: original.identity)), original))
        }
    }
    func testReceiptIdentityMismatchRemainsUnknown() throws {
        let owner = Owner(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), original = try pending(owner, store)
        let valid = try projectOriginalTestReceipt(XCTUnwrap(original.serverRequest))
        for field in ["protocolVersion", "requestId", "originalPath", "payloadSHA256"] {
            var root = try JSONDecoder().decode([String: ProjectEditJSON].self, from: valid), body = try XCTUnwrap(root["data"]?.object)
            body[field] = .string("different"); root["data"] = .object(body)
            XCTAssertEqual(ProjectEditHTTPService.decodeRequestReceipt(try JSONEncoder().encode(root), status: 200, operation: original), .unknown)
        }
    }
    func testAccountChangeDuringReadCannotAcknowledgeOldOperation() async throws {
        let owner = Owner(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), wire = Wire()
        let session = try XCTUnwrap(owner.session), original = try pending(owner, store), api = try service(owner, store, wire)
        wire.reply = { _ in owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: "original-request-test"); return try projectOriginalTestReceipt(XCTUnwrap(original.serverRequest)) }
        do { _ = try await api.terminalReceipt(operation: original, session: session); XCTFail("Old owner read accepted") } catch {}
        XCTAssertTrue(ProjectEditLocalStore.exactPending(try XCTUnwrap(store.pending(session: session, identity: original.identity)), original))
    }
    func testReplacedDurableRecordDuringReadCannotConsumeReceipt() async throws {
        let owner = Owner(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), wire = Wire()
        let session = try XCTUnwrap(owner.session), original = try pending(owner, store), api = try service(owner, store, wire)
        wire.reply = { _ in
            var replacement = original; replacement.dispatchStarted = false; try store.savePending(replacement, session: session)
            return try projectOriginalTestReceipt(XCTUnwrap(original.serverRequest))
        }
        do { _ = try await api.terminalReceipt(operation: original, session: session); XCTFail("Replaced record accepted") } catch {}
        XCTAssertEqual(try store.pending(session: session, identity: original.identity)?.dispatchStarted, false)
    }
    func testMissingReadGrantNeverSubstitutesSubmitGrant() async throws {
        let owner = Owner(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), wire = Wire()
        let original = try pending(owner, store), api = try service(owner, store, wire, paths: [ProjectEditRequestContract.submitPath])
        let result = try await api.retrySameRequest(original, session: XCTUnwrap(owner.session))
        XCTAssertEqual(result, .unknown); XCTAssertTrue(wire.requests.isEmpty)
    }
    func testAuthorInputDecoratorForwardsOriginalRecoveryWithoutNewOwner() async throws {
        let owner = Owner(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), wire = Wire()
        let original = try pending(owner, store), api = try service(owner, store, wire, paths: [ProjectEditRequestContract.readPath])
        wire.reply = { _ in try projectOriginalTestReceipt(XCTUnwrap(original.serverRequest)) }
        let decorated = ProjectAuthorInputService(original: api, reader: nil)
        XCTAssertTrue(decorated.supportsRequestReadback); XCTAssertFalse(decorated.supportsRequestRetry)
        let result = try await decorated.terminalReceipt(operation: original, session: XCTUnwrap(owner.session))
        XCTAssertEqual(result, .committedReceipt(operationID: original.operationID, topicID: 71, bundle: nil))
    }
    func testDuplicateOriginalReceiptIdentityAndEscapedAliasesStayUnknown() throws {
        let owner = Owner(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), original = try pending(owner, store)
        let text = String(decoding: try projectOriginalTestReceipt(XCTUnwrap(original.serverRequest)), as: UTF8.self)
        for key in ["protocolVersion", "requestId", "originalPath", "payloadSHA256", "state"] {
            let duplicate = text.replacingOccurrences(of: "\"\(key)\":", with: "\"\(key)\":\"different\",\"\(key)\":")
            XCTAssertNotEqual(duplicate, text)
            XCTAssertEqual(ProjectEditHTTPService.decodeRequestReceipt(Data(duplicate.utf8), status: 200, operation: original), .unknown)
        }
        let escaped = text.replacingOccurrences(of: "\"requestId\":", with: "\"request\\u0049d\":\"different\",\"requestId\":")
        XCTAssertNotEqual(escaped, text)
        XCTAssertEqual(ProjectEditHTTPService.decodeRequestReceipt(Data(escaped.utf8), status: 200, operation: original), .unknown)
    }
    func testOversizedOrDeepOriginalReceiptCannotUnlock() throws {
        let owner = Owner(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), original = try pending(owner, store)
        let text = String(decoding: try projectOriginalTestReceipt(XCTUnwrap(original.serverRequest)), as: UTF8.self)
        let nested = String(repeating: "[", count: 33) + "0" + String(repeating: "]", count: 33)
        let large = "\"" + String(repeating: "x", count: 4 * 1024 * 1024) + "\""
        for value in [nested, large] {
            let body = "{\"unexpected\":" + value + "," + String(text.dropFirst())
            XCTAssertEqual(ProjectEditHTTPService.decodeRequestReceipt(Data(body.utf8), status: 200, operation: original), .unknown)
        }
    }
    func testTransportFailureAndMalformedCommitCannotStandInForTerminalReceipt() throws {
        let owner = Owner(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage()), original = try pending(owner, store)
        let sent = try XCTUnwrap(original.serverRequest), valid = try projectOriginalTestReceipt(sent)
        for status in [400, 401, 403, 500] {
            XCTAssertEqual(ProjectEditHTTPService.decodeRequestReceipt(valid, status: status, operation: original), .unknown)
        }
        for result in [ProjectEditJSON.null, .number(0), .string("not-a-topic"), .object(["id": .number(71)])] {
            let malformed = try projectOriginalTestReceipt(sent, original: result)
            XCTAssertEqual(ProjectEditHTTPService.decodeRequestReceipt(malformed, status: 200, operation: original), .unknown)
        }
    }

}
