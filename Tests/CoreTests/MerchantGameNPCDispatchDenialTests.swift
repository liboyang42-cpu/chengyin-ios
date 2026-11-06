import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic transport only: no service, credentials, publication or capability is enabled.
@MainActor final class MerchantGameNPCDispatchDenialTests: XCTestCase {
    final class Journal: OperationPendingJournal {
        var records: [String: OperationPendingRecord] = [:]
        var cleared: [OperationPendingRecord] = []
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records[ownerKey + targetKey] }
        func write(_ record: OperationPendingRecord) throws {
            let key = record.ownerKey + record.targetKey
            if let prior = records[key], prior != record { throw APIError.invalidRequest }
            records[key] = record
        }
        func clear(_ record: OperationPendingRecord) throws {
            let key = record.ownerKey + record.targetKey
            guard records[key] == record else { throw APIError.invalidRequest }
            records[key] = nil; cleared.append(record)
        }
    }
    final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var chat: (URLRequest) throws -> (Data, Int) = { _ in throw URLError(.timedOut) }
        var read: (URLRequest) throws -> (Data, Int) = { _ in throw URLError(.timedOut) }
        var beforeChatReply: (() -> Void)?
        var hold = false
        var continuation: CheckedContinuation<Void, Never>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path.hasSuffix("public-home") == true {
                return (Data(#"{"code":200,"data":{"id":31,"memberId":77,"npc":{"name":"Synthetic guide"}}}"#.utf8), 200)
            }
            if request.httpMethod == "GET" { return try read(request) }
            if hold { await withCheckedContinuation { continuation = $0 } }
            beforeChatReply?()
            return try chat(request)
        }
        func release() { let held = continuation; continuation = nil; held?.resume() }
        var chats: [URLRequest] { requests.filter { $0.url?.path.hasSuffix("merchant-chat") == true } }
        static func reply(_ request: URLRequest, processing: Bool = false, mismatch: Bool = false) throws -> (Data, Int) {
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let data: [String: Any] = ["requestId": mismatch ? UUID().uuidString : fields["requestId"]!,
                "outcomeStatus": processing ? "PROCESSING" : "SUCCEEDED", "safetyDecision": processing ? "UNKNOWN" : "PASS",
                "safeText": processing ? "Original still unknown" : "Verified earlier answer", "retryable": false,
                "errorCode": processing ? "REQUEST_OUTCOME_UNKNOWN" : ""]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
        }
    }
    @MainActor final class Harness {
        let url = URL(string: "https://synthetic.example.test/prod-api/")!
        let row = PublicMerchantRowID(31)!
        let wire = Wire(), journal = Journal()
        var context: MerchantPublicHostContext?
        var currentScope: MerchantNPCScope?
        var grants: MerchantNPCGrants
        let scope: MerchantNPCScope
        var factory: MerchantPublicProductionFactory!
        var flow: MerchantNPCChatCoordinator!
        init() throws {
            let binding = MerchantNPCScope(accountID: 9, namespace: "synthetic.game", epoch: UUID(),
                merchantRowID: PublicMerchantRowID(31)!, accessRevision: UUID())
            scope = binding; currentScope = binding
            var g = MerchantNPCGrants(); g.server = true; g.provider = true; g.legal = true; grants = g
            context = try .init(market: .china, baseURL: url, namespace: binding.namespace, accountID: 9,
                                epoch: 1, role: "user", token: "synthetic-token")
            let approval = try MerchantPublicProductionApproval(market: .china, baseURL: url, namespace: scope.namespace,
                accountID: 9, publicHomeRead: true, chatMerchantRows: [row])
            factory = try XCTUnwrap(MerchantPublicProductionFactory(api: .init(baseURL: url), approval: approval,
                transport: wire, journal: journal,
                current: { [unowned self] in self.context }, grants: { [unowned self] in self.grants }))
            flow = newFlow()
        }
        func newFlow() -> MerchantNPCChatCoordinator {
            .init(scope: scope, client: factory.chatClient(currentScope: { [unowned self] _ in self.currentScope }),
                  currentScope: { [unowned self] in self.currentScope }, grants: { [unowned self] in self.factory.chatGrants })
        }
        func deny(http: Int, code: Int? = nil) {
            wire.chat = { _ in
                let body = try code.map { try JSONSerialization.data(withJSONObject: ["code": $0, "msg": "Synthetic denial", "data": ["malformed": true]]) } ?? Data("not JSON".utf8)
                return (body, http)
            }
        }
        func player(approved: Bool = true) throws -> MerchantGamePlayerService {
            let session = try MerchantGamePlayerSession(namespace: scope.namespace, accountID: 9, epoch: 1, credential: "synthetic-token")
            let api = try APIConfiguration(baseURL: url)
            let grant = approved ? MerchantGamePlayerReadGrant(market: .china, endpoints: try OperationEndpointApproval(
                baseURL: url, namespace: scope.namespace, accountID: 9, paths: MerchantGamePlayerReadGrant.playerPaths)) : nil
            return try .init(configuration: api, merchantID: row.rawValue, session: session, grant: grant,
                             transport: wire, journal: journal, current: { session })
        }
    }
    func testCurrentHTTPAndBusinessDenialsDisableDispatchButKeepOriginalIdentity() async throws {
        for (http, code) in [(401, nil), (403, nil), (200, 401), (200, 403)] as [(Int, Int?)] {
            let h = try Harness(); h.deny(http: http, code: code)
            let completion = await h.flow.send("Private original 🧭")
            let id = try XCTUnwrap(h.flow.requestID), record = try XCTUnwrap(h.journal.records.values.first)
            XCTAssertEqual(h.flow.gameDispatchDenial?.rawValue, code ?? http)
            XCTAssertEqual(h.flow.failure, .unknownOutcome); XCTAssertEqual(record.operationID, id)
            XCTAssertTrue(h.grants.chatAllowed); XCTAssertTrue(h.flow.isCurrent)
            XCTAssertFalse(h.flow.canSend); XCTAssertFalse(h.flow.canRetry); XCTAssertFalse(h.flow.canAbandon)
            XCTAssertNil(h.flow.message); XCTAssertNil(h.flow.reply); XCTAssertNil(completion)
            XCTAssertNil(h.flow.retryRecovery()); XCTAssertTrue(h.flow.conversationHistory.turns.isEmpty)
            h.flow.abandon(); _ = await h.flow.retry(); _ = await h.flow.send("Must not send")
            XCTAssertEqual(h.flow.requestID, id); XCTAssertEqual(h.journal.records.values.first, record)
            XCTAssertEqual(h.wire.chats.count, 1); XCTAssertTrue(h.journal.cleared.isEmpty)
        }
    }
    func testExplicitHTTPDenialIsNotHiddenByOversizedOrMalformedBody() async throws {
        let h = try Harness()
        h.wire.chat = { _ in (Data(repeating: 0xFF, count: 1_048_577), 401) }
        _ = await h.flow.send("Original")
        XCTAssertEqual(h.flow.gameDispatchDenial, .unauthorized); XCTAssertFalse(h.flow.canRetry)
        XCTAssertEqual(h.journal.records.count, 1); XCTAssertTrue(h.journal.cleared.isEmpty)
    }
    func testRetryDenialRetainsSameOriginalUUIDAndEarlierReceiptNotPrivateProjection() async throws {
        let h = try Harness(); h.wire.chat = { try Wire.reply($0) }
        _ = await h.flow.send("Earlier question")
        let earlierReceipt = try XCTUnwrap(h.journal.cleared.first)
        XCTAssertEqual(h.flow.conversationHistory.turns.count, 1)
        h.wire.chat = { _ in throw URLError(.timedOut) }
        _ = await h.flow.send("Pending original")
        let id = try XCTUnwrap(h.flow.requestID), record = try XCTUnwrap(h.journal.records.values.first)
        h.deny(http: 200, code: 403); _ = await h.flow.retry(requestID: id)
        XCTAssertEqual(h.flow.requestID, id); XCTAssertEqual(h.journal.records.values.first, record)
        XCTAssertEqual(h.journal.cleared, [earlierReceipt]); XCTAssertTrue(h.flow.conversationHistory.turns.isEmpty)
        XCTAssertEqual(h.wire.chats[1].httpBody, h.wire.chats[2].httpBody)
        XCTAssertFalse(h.flow.canRetry)
    }
    func testTimeoutServerFailureAndMalformedStaySameRequestRetryable() async throws {
        for mode in 0..<4 {
            let h = try Harness()
            h.wire.chat = { _ in
                if mode == 0 { throw URLError(.timedOut) }
                if mode == 1 { return (Data(#"{"code":403}"#.utf8), 503) }
                if mode == 2 { return (Data("malformed".utf8), 200) }
                return (Data(#"{"code":500}"#.utf8), 200)
            }
            _ = await h.flow.send("Same original"); let id = h.flow.requestID
            XCTAssertNil(h.flow.gameDispatchDenial); XCTAssertTrue(h.flow.canRetry)
            _ = await h.flow.retry(); _ = await h.flow.retry(); _ = await h.flow.retry()
            XCTAssertEqual(h.flow.requestID, id); XCTAssertEqual(h.wire.chats.count, 3)
            XCTAssertTrue(h.wire.chats.allSatisfy { $0.httpBody == h.wire.chats[0].httpBody })
            XCTAssertFalse(h.flow.canRetry); XCTAssertEqual(h.flow.retryRecovery()?.state, .attemptLimitReached)
        }
    }
    func testStructuredProcessingUnknownIsNotDenialOrRetryAuthority() async throws {
        let h = try Harness(); h.wire.chat = { try Wire.reply($0, processing: true) }
        _ = await h.flow.send("Original")
        XCTAssertNil(h.flow.gameDispatchDenial); XCTAssertNotNil(h.flow.requestID)
        XCTAssertFalse(h.flow.canSend); XCTAssertFalse(h.flow.canRetry)
        XCTAssertEqual(h.flow.retryRecovery()?.state, .unavailable)
        XCTAssertTrue(h.flow.retryRecovery()?.outcomeUnknown == true)
        XCTAssertEqual(h.journal.records.count, 1); XCTAssertTrue(h.journal.cleared.isEmpty)
    }
    func testOnlyFullyValidatedOriginalTerminalClearsGameMarker() async throws {
        let h = try Harness(); h.wire.chat = { try Wire.reply($0, mismatch: true) }
        _ = await h.flow.send("Original"); let id = h.flow.requestID
        XCTAssertNotNil(id); XCTAssertEqual(h.journal.records.count, 1)
        h.wire.chat = { try Wire.reply($0) }; let completion = await h.flow.retry()
        XCTAssertNotNil(completion); XCTAssertNil(h.flow.requestID); XCTAssertTrue(h.journal.records.isEmpty)
        XCTAssertEqual(h.flow.conversationHistory.turns.count, 1); XCTAssertEqual(h.journal.cleared.first?.operationID, id)
    }
    func testLateDenialAfterOwnerRealmTokenRoleOrScopeReplacementNeverBecomesCurrentDenial() async throws {
        for mode in 0..<6 {
            let h = try Harness(); h.deny(http: 403)
            h.wire.beforeChatReply = {
                if mode < 4 {
                    h.context = try! .init(market: .china, baseURL: mode == 3 ? URL(string: "https://replacement.example.test/")! : h.url,
                        namespace: h.scope.namespace, accountID: mode == 0 ? 10 : 9, epoch: 1,
                        role: mode == 2 ? "merchant" : "user", token: mode == 1 ? "replacement-token" : "synthetic-token")
                } else {
                    h.currentScope = .init(accountID: 9, namespace: h.scope.namespace, epoch: h.scope.epoch,
                        merchantRowID: mode == 4 ? PublicMerchantRowID(32)! : h.row, accessRevision: UUID())
                }
            }
            _ = await h.flow.send("Original")
            XCTAssertNil(h.flow.gameDispatchDenial); XCTAssertEqual(h.journal.records.count, 1)
            XCTAssertTrue(h.journal.cleared.isEmpty)
        }
    }
    func testLateDenialAfterGrantRevocationRetainsMarkerWithoutRegrant() async throws {
        let h = try Harness(); h.deny(http: 401); h.wire.beforeChatReply = { h.grants = .init() }
        _ = await h.flow.send("Original")
        XCTAssertFalse(h.flow.canSend); XCTAssertFalse(h.flow.canRetry); XCTAssertNil(h.flow.gameDispatchDenial)
        XCTAssertTrue(h.flow.conversationHistory.turns.isEmpty); XCTAssertEqual(h.journal.records.count, 1)
    }
    func testLateDenialCannotMutateReplacementConversation() async throws {
        let h = try Harness(); h.deny(http: 403); h.wire.hold = true
        let original = h.flow!, task = Task { await original.send("Original") }
        for _ in 0..<100 where h.wire.continuation == nil { await Task.yield() }
        guard h.wire.continuation != nil else { task.cancel(); return XCTFail("Transport did not start") }
        original.invalidate(); let replacement = h.newFlow()
        h.wire.release(); _ = await task.value
        XCTAssertNil(replacement.gameDispatchDenial); XCTAssertNil(replacement.message)
        XCTAssertEqual(h.journal.records.count, 1); XCTAssertTrue(h.journal.cleared.isEmpty)
    }
    func testDenialCannotBeResetByLocalStopBackgroundOrForeground() async throws {
        let h = try Harness(); h.deny(http: 403); _ = await h.flow.send("Original")
        let record = try XCTUnwrap(h.journal.records.values.first)
        h.flow.stopWaiting(); h.flow.abandon(); h.flow.interrupt(); h.flow.revalidateInterruption(); h.flow.resumeAfterInterruption()
        XCTAssertFalse(h.flow.canSend); XCTAssertFalse(h.flow.canRetry); XCTAssertFalse(h.flow.canResumeAfterInterruption)
        XCTAssertEqual(h.flow.gameDispatchDenial, .forbidden)
        XCTAssertEqual(h.journal.records.values.first, record); XCTAssertEqual(h.wire.chats.count, 1)
    }
    func testColdPlayerRecoveryRetainsPendingThroughCurrentFailureThenRequiresExactTerminalACK() async throws {
        let h = try Harness(); h.deny(http: 403); _ = await h.flow.send("Original")
        let record = try XCTUnwrap(h.journal.records.values.first)
        h.flow.invalidate(); h.grants = .init()
        let service = try h.player(), player = MerchantGamePlayerCoordinator(service: service)
        h.wire.read = { request in
            if request.url!.path.hasSuffix("/game") { return (Data(#"{"code":500}"#.utf8), 500) }
            let row: [String: Any] = ["merchantId": 31, "requestId": record.operationID.uuidString,
                "outcomeStatus": "REJECTED", "safetyDecision": "NOT_RUN", "safeText": "Original fixed exit",
                "errorCode": "MERCHANT_ENVIRONMENT_EXIT", "retryable": false, "ai": false]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": row]), 200)
        }
        await player.load(); XCTAssertEqual(player.pending, record); XCTAssertFalse(player.canOpenChat)
        await player.readOriginal(); XCTAssertTrue(player.canAcknowledge); XCTAssertEqual(try service.pending(), record)
        XCTAssertEqual(h.wire.chats.count, 1); XCTAssertTrue(h.journal.cleared.isEmpty)
        player.acknowledgeOriginal(); XCTAssertNil(try service.pending()); XCTAssertTrue(player.acknowledged)
        XCTAssertEqual(h.journal.cleared, [record]); XCTAssertEqual(h.wire.chats.count, 1)
    }
    func testMissingIndependentOriginalGrantNeverDispatchesOrClearsDenialMarker() async throws {
        let h = try Harness(); h.deny(http: 401); _ = await h.flow.send("Original")
        let record = try XCTUnwrap(h.journal.records.values.first), service = try h.player(approved: false)
        let prior = h.wire.requests.count
        do { _ = try await service.original(record); XCTFail("Missing read grant dispatched") }
        catch { XCTAssertEqual(error as? MerchantGamePlayerFailure, .configuration) }
        XCTAssertEqual(h.wire.requests.count, prior); XCTAssertEqual(try service.pending(), record)
    }
    func testDeniedOriginalGETRevokesProjectionNotMarker() async throws {
        let h = try Harness(); h.deny(http: 403); _ = await h.flow.send("Original")
        let record = try XCTUnwrap(h.journal.records.values.first), service = try h.player()
        h.wire.read = { _ in (Data(#"{"code":403}"#.utf8), 200) }
        let player = MerchantGamePlayerCoordinator(service: service)
        await player.load()
        XCTAssertFalse(player.active); XCTAssertNil(player.original); XCTAssertNil(player.publication)
        XCTAssertEqual(try service.pending(), record); XCTAssertTrue(h.journal.cleared.isEmpty)
    }
    final class Raw: MerchantNPCHTTPTransport {
        let status: Int, body: Data
        init(_ status: Int, _ body: String) { self.status = status; self.body = Data(body.utf8) }
        func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse { .init(status: status, body: body) }
    }
    func testClientClassificationIsExactGameRouteNotResources() async throws {
        let h = try Harness(), raw = Raw(200, #"{"code":403}"#)
        do { _ = try await MerchantNPCHTTPClient(transport: raw).chat(message: "Original", requestID: UUID(), scope: h.scope); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantNPCGameDispatchDenial, .forbidden) }
        do { _ = try await MerchantNPCHTTPClient(transport: raw).voiceScript(scope: h.scope); XCTFail() }
        catch { XCTAssertEqual(error as? MerchantNPCFailure, .rejected(code: 403, message: nil)) }
    }
}
