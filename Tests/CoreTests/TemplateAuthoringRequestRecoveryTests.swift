import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Offline fake-transport coverage. These tests do not authorize any deployment.
@MainActor final class TemplateAuthoringRequestRecoveryTests: XCTestCase {
    final class HTTP: HTTPTransport {
        var requests: [URLRequest] = []
        var reply: ((URLRequest) throws -> (Data, Int))?
        var beforeReply: (() -> Void)?
        var pause: (() async -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?(); await pause?()
            guard let reply else { throw TemplateAuthoringError.uncertain }
            return try reply(request)
        }
    }
    final class Storage: TemplateAuthoringStorage {
        var values: [String: Data] = [:]
        var dropWrites = false
        var rejectReceipts = false
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws {
            if rejectReceipts, let pending = try? JSONDecoder().decode(TemplateAuthoringPending.self, from: data), pending.serverReceipt != nil {
                throw TemplateAuthoringError.storageUnavailable
            }
            if !dropWrites { values[key] = data }
        }
        func remove(_ key: String) throws { values.removeValue(forKey: key) }
    }
    final class Credentials {
        var session: TemplateAuthoringSession
        var token = "fixture-template-request-token"
        var read: OperationEndpointApproval?
        var write: OperationEndpointApproval?
        init() throws {
            session = try .init(accountID: 7, namespace: "original-template-fixture", epoch: 1, authorizationRevision: "member")
        }
    }
    func setup(read: Bool = true, write: Bool = true) throws -> (HTTP, Credentials, TemplateAuthoringRequestHTTPService) {
        let http = HTTP(), c = try Credentials()
        let configuration = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test")))
        if read { c.read = try .init(baseURL: configuration.baseURL, namespace: c.session.namespace, accountID: 7, paths: [TemplateAuthoringRequestReceipt.readPath]) }
        if write { c.write = try .init(baseURL: configuration.baseURL, namespace: c.session.namespace, accountID: 7,
            paths: [TemplateAuthoringRequestReceipt.submitPath, "api/template/draft", "api/template/publish"]) }
        let service = TemplateAuthoringRequestHTTPService(configuration: configuration, transport: http,
            readApproval: c.read, submitApproval: c.write, currentReadApproval: { c.read }, currentSubmitApproval: { c.write },
            credentials: { (c.session, c.token) })
        return (http, c, service)
    }
    func draft() -> TemplateAuthoringDraft {
        var value = TemplateAuthoringDraft(title: "Original request fixture")
        value.description = "Read the original result"; value.players = "1-2"; value.duration = 10; value.categoryId = 4
        value.finishEnabled = true; value.validationMethod = .manual
        return value
    }
    func request(_ intent: TemplateAuthoringIntent = .saveDraft) throws -> TemplateAuthoringRequest {
        try TemplateAuthoringContract.request(draft(), intent: intent)
    }
    func submit(_ intent: TemplateAuthoringIntent = .saveDraft) throws -> TemplateAuthoringRequestReceipt.Submit {
        try .init(id: UUID(), command: .init(request: request(intent)))
    }
    func response(_ request: URLRequest, state: String, id: Int = 42, altered: [String: Any] = [:]) throws -> (Data, Int) {
        let body = try XCTUnwrap(request.httpBody)
        let query = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        var receipt: [String: Any] = ["protocolVersion": try XCTUnwrap(query["protocolVersion"]),
            "requestId": try XCTUnwrap(query["requestId"]), "payloadSHA256": try XCTUnwrap(query["payloadSHA256"]), "state": state]
        if state == "COMMITTED" { receipt["originalResult"] = ["memberTemplateId": id] }
        receipt.merge(altered) { _, new in new }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": receipt]), 200)
    }
    func coordinator(_ service: TemplateAuthoringRequestHTTPService, _ c: Credentials, _ store: TemplateAuthoringLocalStore) -> TemplateAuthoringCoordinator {
        .init(store: store, requestService: service, currentSession: { c.session })
    }
    func dispatch(_ value: TemplateAuthoringCoordinator, intent: TemplateAuthoringIntent = .saveDraft) async throws {
        value.open(seed: draft()); value.prepare(intent)
        await value.confirm(try XCTUnwrap(value.review))
    }
    func testDefaultApprovalsCannotSubmitOrRead() async throws {
        let (http, c, service) = try setup(read: false, write: false)
        XCTAssertFalse(service.canRead); XCTAssertFalse(service.canSubmit(path: "/api/template/draft"))
        do { _ = try await service.submit(submit(), session: c.session); XCTFail("Unapproved submit") } catch {}
        do { _ = try await service.read(submit(), session: c.session); XCTFail("Unapproved read") } catch {}
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testSubmitRequiresBothProducerAndOriginalWriterGrant() throws {
        let (http, c, _) = try setup()
        let config = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test")))
        for path in [TemplateAuthoringRequestReceipt.submitPath, "api/template/draft"] {
            let grant = try OperationEndpointApproval(baseURL: config.baseURL, namespace: c.session.namespace, accountID: 7, paths: [path])
            let service = TemplateAuthoringRequestHTTPService(configuration: config, transport: http, submitApproval: grant, credentials: { (c.session, c.token) })
            XCTAssertFalse(service.canSubmit(path: "/api/template/draft"))
        }
    }
    func testPersonalCommandMatchesDonorWireShapeAndRejectsOtherBranches() throws {
        let value = try submit(), command = try XCTUnwrap(value.command)
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as? [String: Any])
        XCTAssertEqual(Set(raw.keys), Set(["originalPath", "fields"]))
        for extra in ["merchant", "memberTemplateID", "baselineSHA256", "copySourceMemberTemplateID"] {
            var invalid = raw; invalid[extra] = 1
            XCTAssertThrowsError(try JSONDecoder().decode(TemplateAuthoringRequestReceipt.Command.self, from: JSONSerialization.data(withJSONObject: invalid)))
        }
    }
    func testCorruptedWireBytesAndWrongOperationCannotMatch() throws {
        let value = try submit()
        XCTAssertTrue(value.matches(operationID: try XCTUnwrap(UUID(uuidString: value.requestId)), request: request()))
        XCTAssertFalse(value.matches(operationID: UUID(), request: request()))
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        raw["payloadBase64Chunks"] = [Data("{}".utf8).base64EncodedString()]
        let bad = try JSONDecoder().decode(TemplateAuthoringRequestReceipt.Submit.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertNil(bad.command)
    }
    func testUnknownReopensAndReadsOriginalOnlyWithoutWriteApproval() async throws {
        let (http, c, service) = try setup(), storage = Storage(), store = TemplateAuthoringLocalStore(storage: storage)
        let first = coordinator(service, c, store); try await dispatch(first)
        let original = try XCTUnwrap(first.pending?.serverRequest)
        XCTAssertEqual(first.state, .uncertain); XCTAssertTrue(first.locked)
        c.write = nil
        http.reply = { try self.response($0, state: "COMMITTED") }
        let reopened = coordinator(service, c, store); reopened.open()
        XCTAssertFalse(reopened.canSubmit); XCTAssertTrue(reopened.canReadOriginalRequest)
        await reopened.readOriginalRequest()
        XCTAssertEqual(http.requests.map { $0.url!.path }, ["/api/template/author-requests/submit", "/api/template/author-requests/read"])
        XCTAssertEqual(reopened.pending?.serverRequest, original); XCTAssertEqual(reopened.savedDraft?.memberTemplateID.rawValue, 42)
        XCTAssertEqual(reopened.state, .acknowledged)
        let read = try JSONDecoder().decode(TemplateAuthoringRequestReceipt.Read.self, from: XCTUnwrap(http.requests.last?.httpBody))
        XCTAssertEqual(read.requestId, original.requestId); XCTAssertEqual(read.payloadSHA256, original.payloadSHA256)
        let readBody = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(http.requests.last?.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(readBody.keys), Set(["protocolVersion", "requestId", "payloadSHA256"]))
    }
    func testNotFoundAndRunningKeepIdentityAndLockWithoutResend() async throws {
        let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
        let value = coordinator(service, c, store); try await dispatch(value)
        let original = value.pending?.serverRequest
        for state in ["NOT_FOUND", "RUNNING"] {
            http.reply = { try self.response($0, state: state) }; await value.readOriginalRequest()
            XCTAssertEqual(value.state, .uncertain); XCTAssertTrue(value.locked); XCTAssertEqual(value.pending?.serverRequest, original)
            value.prepare(.publish); XCTAssertNil(value.review); value.discardLocal(); XCTAssertNotNil(value.pending)
        }
        XCTAssertEqual(http.requests.filter { $0.url!.path.hasSuffix("/submit") }.count, 1)
    }
    func testLegacyPendingDoesNotInventServerIdentity() async throws {
        let (_, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
        let identity = TemplateAuthoringIdentity()
        try store.save(.init(title: "Legacy"), session: c.session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: c.session.ownerKey, identity: identity, request: request(), createdAt: Date()), session: c.session)
        let value = coordinator(service, c, store); value.open(); await value.readOriginalRequest()
        XCTAssertFalse(value.canReadOriginalRequest); XCTAssertNil(value.pending?.serverRequest)
        XCTAssertEqual(value.state, .uncertain); XCTAssertTrue(value.locked)
    }
    func testMismatchedReceiptCannotAcknowledge() async throws {
        for changed in [["requestId": UUID().uuidString.lowercased()], ["payloadSHA256": String(repeating: "0", count: 64)], ["protocolVersion": "wrong"]] {
            let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
            http.reply = { try self.response($0, state: "COMMITTED", altered: changed) }
            let value = coordinator(service, c, store); try await dispatch(value)
            XCTAssertEqual(value.state, .uncertain); XCTAssertNil(value.savedDraft); XCTAssertNil(value.pending?.serverReceipt)
        }
    }
    func testCommittedWithoutIDAndMerchantReceiptAreNotAccepted() async throws {
        let invalid: [[String: Any]] = [["originalResult": [:]], ["merchant": ["actorId": 7]]]
        for changed in invalid {
            let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
            http.reply = { try self.response($0, state: "COMMITTED", altered: changed) }
            let value = coordinator(service, c, store); try await dispatch(value)
            XCTAssertEqual(value.state, .uncertain); XCTAssertNil(value.savedDraft)
        }
    }
    func testPublishUsesExistingPublishedReceiptNotSavedDraftHandoff() async throws {
        let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
        http.reply = { try self.response($0, state: "COMMITTED") }
        let value = coordinator(service, c, store); try await dispatch(value, intent: .publish)
        XCTAssertEqual(value.publishedReceipt?.memberTemplateID.rawValue, 42); XCTAssertNil(value.savedDraft)
        XCTAssertNotNil(TemplateAuthoringPublishResult(coordinator: value))
    }
    func testRejectedReceiptStaysRetainedAcrossReopen() async throws {
        let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
        http.reply = { try self.response($0, state: "REJECTED") }
        let value = coordinator(service, c, store); try await dispatch(value)
        let original = value.pending
        XCTAssertEqual(value.state, .blocked); XCTAssertTrue(value.locked)
        let reopened = coordinator(service, c, store); reopened.open()
        XCTAssertEqual(reopened.state, .blocked); XCTAssertEqual(reopened.pending, original)
        reopened.discardLocal(); XCTAssertEqual(reopened.pending, original)
    }
    func testStorageLossStopsDispatchBeforeNetwork() async throws {
        let (http, c, service) = try setup(), storage = Storage(), store = TemplateAuthoringLocalStore(storage: storage)
        storage.dropWrites = true
        let value = coordinator(service, c, store); try await dispatch(value)
        XCTAssertTrue(http.requests.isEmpty); XCTAssertNil(value.savedDraft)
    }
    func testReceiptPersistenceFailureCannotExposeAcknowledgement() async throws {
        let (http, c, service) = try setup(), storage = Storage(), store = TemplateAuthoringLocalStore(storage: storage)
        storage.rejectReceipts = true; http.reply = { try self.response($0, state: "COMMITTED") }
        let value = coordinator(service, c, store); try await dispatch(value)
        XCTAssertEqual(value.state, .uncertain); XCTAssertNil(value.savedDraft); XCTAssertNil(value.pending?.serverReceipt)
        XCTAssertNotNil(try store.pending(session: c.session, identity: value.identity)?.serverRequest)
    }
    func testRevokedReadApprovalRejectsLateResult() async throws {
        let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
        let value = coordinator(service, c, store); try await dispatch(value)
        http.beforeReply = { c.read = nil }; http.reply = { try self.response($0, state: "COMMITTED") }
        await value.readOriginalRequest(); XCTAssertEqual(value.state, .uncertain); XCTAssertNil(value.savedDraft)
    }
    func testSessionAndTokenChangesRejectLateResult() async throws {
        for changeSession in [true, false] {
            let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
            let value = coordinator(service, c, store); try await dispatch(value)
            http.beforeReply = {
                if changeSession { c.session = try! .init(accountID: 8, namespace: "original-template-fixture", epoch: 2, authorizationRevision: "member"); value.synchronizeSession() }
                else { c.token = "different-template-token" }
            }
            http.reply = { try self.response($0, state: "COMMITTED") }
            await value.readOriginalRequest(); XCTAssertNil(value.savedDraft)
            if changeSession { XCTAssertNil(value.pending); XCTAssertEqual(value.state, .idle) }
            else { XCTAssertEqual(value.state, .uncertain) }
        }
    }
    func testLeaveDuringReadDoesNotApplyLateResult() async throws {
        let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
        let value = coordinator(service, c, store); try await dispatch(value)
        http.beforeReply = { value.leaveScreen() }; http.reply = { try self.response($0, state: "COMMITTED") }
        await value.readOriginalRequest()
        XCTAssertNil(value.savedDraft); XCTAssertEqual(value.state, .uncertain); XCTAssertFalse(value.originalRequestBusy)
    }
    func testTerminalReceiptCannotRegressOrSwitchMemberID() async throws {
        let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
        http.reply = { try self.response($0, state: "COMMITTED") }
        let value = coordinator(service, c, store); try await dispatch(value)
        let receipt = value.pending?.serverReceipt
        for state in ["NOT_FOUND", "COMMITTED"] {
            http.reply = { try self.response($0, state: state, id: 99) }; await value.readOriginalRequest()
            XCTAssertEqual(value.savedDraft?.memberTemplateID.rawValue, 42); XCTAssertEqual(value.pending?.serverReceipt, receipt)
        }
    }
    func testPersistedRequestMustMatchOperationAndDescriptor() throws {
        let (_, c, _) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage()), identity = TemplateAuthoringIdentity()
        var value = TemplateAuthoringPending(operationID: UUID(), ownerKey: c.session.ownerKey, identity: identity, request: request(), createdAt: Date())
        value.serverRequest = try submit()
        XCTAssertThrowsError(try store.savePending(value, session: c.session))
        value.serverRequest = try .init(id: value.operationID, command: .init(request: request(.publish)))
        XCTAssertThrowsError(try store.savePending(value, session: c.session))
    }
    func testCancellationDuringReadRetainsLockAndRejectsResult() async throws {
        let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
        let value = coordinator(service, c, store); try await dispatch(value)
        var continuation: CheckedContinuation<Void, Never>?
        http.pause = { await withCheckedContinuation { continuation = $0 } }
        http.reply = { try self.response($0, state: "COMMITTED") }
        let task = Task { await value.readOriginalRequest() }
        while continuation == nil { await Task.yield() }
        task.cancel(); continuation?.resume(); await task.value
        XCTAssertNil(value.savedDraft); XCTAssertTrue(value.locked); XCTAssertFalse(value.originalRequestBusy)
    }
    func testRepeatedReadWhileInFlightMakesOneRead() async throws {
        let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
        let value = coordinator(service, c, store); try await dispatch(value)
        var continuation: CheckedContinuation<Void, Never>?
        http.pause = { await withCheckedContinuation { continuation = $0 } }
        http.reply = { try self.response($0, state: "RUNNING") }
        let first = Task { await value.readOriginalRequest() }
        while continuation == nil { await Task.yield() }
        await value.readOriginalRequest()
        XCTAssertEqual(http.requests.count, 2)
        continuation?.resume(); await first.value
        XCTAssertTrue(value.locked); XCTAssertFalse(value.originalRequestBusy)
    }
    func testHTTPNotFoundDoesNotClearOrResend() async throws {
        let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
        let value = coordinator(service, c, store); try await dispatch(value)
        let original = value.pending
        http.reply = { _ in (Data(#"{"code":404}"#.utf8), 404) }
        await value.readOriginalRequest()
        XCTAssertEqual(value.pending, original); XCTAssertEqual(value.state, .uncertain)
        XCTAssertEqual(http.requests.filter { $0.url!.path.hasSuffix("/submit") }.count, 1)
    }

    /// Raw wire fixtures deliberately bypass JSONSerialization for duplicate keys.
    private func committedRawResponse(_ request: URLRequest) throws -> String {
        let query = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let protocolVersion = try XCTUnwrap(query["protocolVersion"] as? String)
        let requestId = try XCTUnwrap(query["requestId"] as? String)
        let payloadSHA256 = try XCTUnwrap(query["payloadSHA256"] as? String)
        // These identity values come from the generated canonical request, not external fixture text.
        return "{\"code\":200,\"data\":{\"protocolVersion\":\"\(protocolVersion)\",\"requestId\":\"\(requestId)\",\"payloadSHA256\":\"\(payloadSHA256)\",\"state\":\"COMMITTED\",\"originalResult\":{\"memberTemplateId\":42}}}"
    }
    private func verifyMalformedOriginalResponse(_ transform: @escaping (String) -> String) async throws {
        let (http, c, service) = try setup(), storage = Storage(), store = TemplateAuthoringLocalStore(storage: storage)
        http.reply = { request in
            let valid = try self.committedRawResponse(request), invalid = transform(valid)
            XCTAssertNotEqual(invalid, valid)
            return (Data(invalid.utf8), 200)
        }
        let value = coordinator(service, c, store); try await dispatch(value)
        let original = try XCTUnwrap(value.pending)
        XCTAssertEqual(value.state, .uncertain); XCTAssertTrue(value.locked)
        XCTAssertNil(value.savedDraft); XCTAssertNil(value.publishedReceipt); XCTAssertNil(value.pending?.serverReceipt)
        XCTAssertNotNil(original.serverRequest)
        await value.readOriginalRequest()
        XCTAssertEqual(value.state, .uncertain); XCTAssertTrue(value.locked)
        XCTAssertEqual(value.pending, original)
        XCTAssertEqual(try store.pending(session: c.session, identity: value.identity), original)
        XCTAssertNil(value.savedDraft); XCTAssertNil(value.publishedReceipt); XCTAssertNil(value.pending?.serverReceipt)
        XCTAssertEqual(http.requests.map { $0.url!.path }, ["/api/template/author-requests/submit", "/api/template/author-requests/read"])
    }
    func testDuplicateProtocolRequestHashAndStateRejectSubmitAndRead() async throws {
        for (field, other) in [("protocolVersion", "\"wrong-protocol\""), ("requestId", "\"wrong-request\""),
                               ("payloadSHA256", "\"wrong-hash\""), ("state", "\"REJECTED\"")] {
            try await verifyMalformedOriginalResponse { wire in
                wire.replacingOccurrences(of: "\"\(field)\":", with: "\"\(field)\":\(other),\"\(field)\":")
            }
        }
    }
    func testDuplicateEnvelopeAndNestedMemberIDRejectSubmitAndRead() async throws {
        let transforms: [(String) -> String] = [
            { $0.replacingOccurrences(of: "\"code\":200", with: "\"code\":200,\"code\":200") },
            { $0.replacingOccurrences(of: "\"data\":", with: "\"data\":null,\"data\":") },
            { $0.replacingOccurrences(of: "\"memberTemplateId\":42", with: "\"memberTemplateId\":42,\"memberTemplateId\":99") },
            { $0.replacingOccurrences(of: "\"memberTemplateId\":42", with: "\"memberTemplateId\":99,\"memberTemplateId\":42") }
        ]
        for transform in transforms {
            try await verifyMalformedOriginalResponse(transform)
        }
    }
    func testEscapedDuplicateIdentityAndNestedMemberIDRejectSubmitAndRead() async throws {
        try await verifyMalformedOriginalResponse {
            $0.replacingOccurrences(of: #""requestId":"#, with: #""\u0072equestId":"wrong-request","requestId":"#)
        }
        try await verifyMalformedOriginalResponse {
            $0.replacingOccurrences(of: #""memberTemplateId":42"#, with: #""\u006demberTemplateId":99,"memberTemplateId":42"#)
        }
    }
    func testMalformedIdentityFieldTypesKeepSubmitAndReadUnknown() async throws {
        let invalid: [Any] = [NSNull(), 7, ["nested": true], [1, 2]]
        for field in ["protocolVersion", "requestId", "payloadSHA256"] {
            for bad in invalid {
                let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
                http.reply = { try self.response($0, state: "COMMITTED", altered: [field: bad]) }
                let value = coordinator(service, c, store); try await dispatch(value)
                let original = try XCTUnwrap(value.pending)
                await value.readOriginalRequest()
                XCTAssertEqual(value.state, .uncertain); XCTAssertTrue(value.locked)
                XCTAssertEqual(value.pending, original); XCTAssertNil(value.pending?.serverReceipt)
                XCTAssertNil(value.savedDraft); XCTAssertNil(value.publishedReceipt)
                XCTAssertEqual(http.requests.map { $0.url!.path }, ["/api/template/author-requests/submit", "/api/template/author-requests/read"])
            }
        }
    }
    func testMalformedCommittedResultCannotCreateAnyHandoff() async throws {
        for invalid in ["null", "false", "0", "-1", "42.5", "\"not-an-id\"", "[]", "{}"] {
            try await verifyMalformedOriginalResponse {
                $0.replacingOccurrences(of: "\"memberTemplateId\":42", with: "\"memberTemplateId\":\(invalid)")
            }
        }
        try await verifyMalformedOriginalResponse { $0.replacingOccurrences(of: "\"memberTemplateId\":42", with: "\"missingMemberId\":42") }
        try await verifyMalformedOriginalResponse { String($0.dropLast()) }
    }
    func testWrongAccountAfterReadKeepsOriginalOwnersDurableUnknownRecord() async throws {
        let (http, c, service) = try setup(), store = TemplateAuthoringLocalStore(storage: Storage())
        let value = coordinator(service, c, store); try await dispatch(value)
        let owner = c.session, identity = value.identity, original = try XCTUnwrap(value.pending)
        http.beforeReply = {
            c.session = try! .init(accountID: 8, namespace: owner.namespace, epoch: 2, authorizationRevision: owner.authorizationRevision)
            value.synchronizeSession()
        }
        http.reply = { request in (Data(try self.committedRawResponse(request).utf8), 200) }
        await value.readOriginalRequest()
        XCTAssertEqual(value.state, .idle); XCTAssertNil(value.pending); XCTAssertNil(value.savedDraft); XCTAssertNil(value.publishedReceipt)
        XCTAssertEqual(try store.pending(session: owner, identity: identity), original)
        XCTAssertEqual(http.requests.map { $0.url!.path }, ["/api/template/author-requests/submit", "/api/template/author-requests/read"])
    }

}
