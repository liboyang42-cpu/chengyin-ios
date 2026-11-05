import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic wires only. These tests do not approve or dispatch a production endpoint.
@MainActor final class MerchantGameNPCBridgeTests: XCTestCase {
    final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var response: (URLRequest) throws -> (Data, Int) = { _ in (Data(), 200) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); return try response(request)
        }
    }
    final class Journal: OperationPendingJournal {
        var record: OperationPendingRecord?
        var clears = 0
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            guard let record, record.ownerKey == ownerKey, record.targetKey == targetKey else { return nil }
            return record
        }
        func write(_ value: OperationPendingRecord) throws {
            guard record == nil || record == value else { throw APIError.invalidRequest }; record = value
        }
        func clear(_ value: OperationPendingRecord) throws {
            guard record == value else { throw APIError.invalidRequest }; record = nil; clears += 1
        }
    }
    @MainActor final class Fixture {
        let base = URL(string: "https://bridge.example.test/native/")!
        let row = PublicMerchantRowID(31)!
        let read = Wire(), write = Wire(), journal = Journal()
        let scope: MerchantNPCScope
        let captured: MerchantPublicHostContext
        let approval: MerchantPublicProductionApproval
        var current: MerchantPublicHostContext?
        var grants: MerchantNPCGrants
        init() throws {
            scope = .init(accountID: 9, namespace: "game.fixture", epoch: UUID(), merchantRowID: PublicMerchantRowID(31)!, accessRevision: UUID())
            captured = try .init(market: .china, baseURL: base, namespace: "game.fixture", accountID: 9,
                                 epoch: 1, role: "user", token: "synthetic-token")
            current = captured
            approval = try .init(market: .china, baseURL: base, namespace: "game.fixture", accountID: 9,
                                 publicHomeRead: true, chatMerchantRows: [row])
            var g = MerchantNPCGrants(); g.server = true; g.provider = true; g.legal = true; grants = g
            read.response = { request in
                guard request.url?.path.hasSuffix("public-home") == true else { throw URLError(.unsupportedURL) }
                return (Data(#"{"code":200,"data":{"id":31,"memberId":77,"npc":{"name":"Synthetic guide"}}}"#.utf8), 200)
            }
        }
        func bridge(_ selected: MerchantPublicProductionApproval? = nil) -> MerchantGameNPCProductionTransport {
            .init(approval: selected ?? approval, context: captured, transport: write,
                  current: { [unowned self] in self.current }, grants: { [unowned self] in self.grants })
        }
        func request(_ fields: [String: Any]? = nil) throws -> URLRequest {
            var r = URLRequest(url: base.appendingPathComponent("api/ai/npc/merchant-chat"))
            r.httpMethod = "POST"; r.httpShouldHandleCookies = false
            r.setValue("synthetic-token", forHTTPHeaderField: "Authorization")
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: fields ?? ["requestId": UUID().uuidString, "bizId": 31, "message": "Original"], options: [.sortedKeys])
            return r
        }
        func factory() throws -> MerchantPublicProductionFactory {
            try XCTUnwrap(MerchantPublicProductionFactory(api: .init(baseURL: base), approval: approval,
                transport: read, chatTransport: bridge(), journal: journal,
                current: { [unowned self] in self.current }, grants: { [unowned self] in self.grants }))
        }
        static func terminal(_ request: URLRequest) throws -> (Data, Int) {
            let data = try XCTUnwrap(request.httpBody)
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let reply: [String: Any] = ["requestId": fields["requestId"]!, "outcomeStatus": "SUCCEEDED",
                "safetyDecision": "PASS", "safeText": "Verified response", "retryable": false]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": reply]), 200)
        }
    }
    private func rejected(_ request: URLRequest, by bridge: MerchantGameNPCProductionTransport) async {
        do { _ = try await bridge.send(request); XCTFail("Unapproved request dispatched") } catch {}
    }
    func testIndependentFactoryUsesHomeWireOnlyForFreshHomeAndGameWireOnlyForPost() async throws {
        let f = try Fixture(); f.write.response = Fixture.terminal
        let factory = try f.factory()
        let reply = try await factory.chatClient(currentScope: { _ in f.scope }).chat(message: "Original", requestID: UUID(), scope: f.scope)
        XCTAssertTrue(reply.succeeded)
        XCTAssertEqual(f.read.requests.count, 1); XCTAssertEqual(f.write.requests.count, 1)
        XCTAssertNil(f.read.requests.first?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(f.read.requests.first?.url?.path.hasSuffix("public-home") == true)
        XCTAssertTrue(f.write.requests.first?.url?.path.hasSuffix("merchant-chat") == true)
        XCTAssertNil(f.journal.record); XCTAssertEqual(f.journal.clears, 1)
    }
    func testBridgeRejectsOtherRoutesMethodsOriginsBodiesAndAmbientCredentials() async throws {
        let f = try Fixture(), bridge = f.bridge(), valid = try f.request()
        for mode in 0..<12 {
            var request = valid
            switch mode {
            case 0: request.httpMethod = "GET"; request.httpBody = nil
            case 1: request.url = f.base.appendingPathComponent("api/ai/npc/merchant-public-chat")
            case 2: request.url = f.base.appendingPathComponent("api/merchant/npc/voice/enroll")
            case 3: request.url = f.base.appendingPathComponent("api/merchant/authoring/player/31/game")
            case 4: request.url = URL(string: "https://other.example.test/native/api/ai/npc/merchant-chat")!
            case 5: request.url = URL(string: valid.url!.absoluteString + "?extra=true")!
            case 6: request.url = URL(string: valid.url!.absoluteString + "#extra")!
            case 7: request.httpShouldHandleCookies = true
            case 8: request.setValue("sid=synthetic", forHTTPHeaderField: "Cookie")
            case 9: request.setValue("synthetic", forHTTPHeaderField: "Proxy-Authorization")
            case 10: request.setValue("replacement-token", forHTTPHeaderField: "Authorization")
            default: request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            }
            await rejected(request, by: bridge)
        }
        XCTAssertTrue(f.write.requests.isEmpty)
    }
    func testBridgeRejectsUnlistedRowExtraFieldsInvalidUuidMessageAndNonCanonicalBody() async throws {
        let f = try Fixture(), bridge = f.bridge()
        for mode in 0..<7 {
            var fields: [String: Any] = ["requestId": UUID().uuidString, "bizId": 31, "message": "Original"]
            switch mode {
            case 0: fields["bizId"] = 32
            case 1: fields["conversationRoute"] = "TASK"
            case 2: fields["requestId"] = "not-a-uuid"
            case 3: fields["message"] = "  "
            case 4: fields["message"] = String(repeating: "a", count: 301)
            default: break
            }
            var request = try f.request(fields)
            if mode == 5 { request.httpBody = Data(repeating: 0x20, count: 4097) }
            if mode == 6 { request.httpBody!.append(0x20) }
            await rejected(request, by: bridge)
        }
        XCTAssertTrue(f.write.requests.isEmpty)
    }
    func testMissingServerProviderOrLegalGrantNeverDispatches() async throws {
        for mode in 0..<3 {
            let f = try Fixture()
            if mode == 0 { f.grants.server = false }
            if mode == 1 { f.grants.provider = false }
            if mode == 2 { f.grants.legal = false }
            await rejected(try f.request(), by: f.bridge())
            XCTAssertTrue(f.write.requests.isEmpty)
        }
    }
    func testHomeReadApprovalDoesNotCreateGamePostAuthority() async throws {
        let f = try Fixture()
        let onlyHome = try MerchantPublicProductionApproval(market: .china, baseURL: f.base, namespace: "game.fixture",
                                                           accountID: 9, publicHomeRead: true)
        await rejected(try f.request(), by: f.bridge(onlyHome))
        XCTAssertTrue(f.write.requests.isEmpty)
    }
    func testChangedContextBeforeDispatchNeverUsesCapturedToken() async throws {
        let f = try Fixture(), request = try f.request(), bridge = f.bridge()
        f.current = try .init(market: .china, baseURL: f.base, namespace: "game.fixture", accountID: 10,
                             epoch: 2, role: "user", token: "replacement-token")
        await rejected(request, by: bridge); XCTAssertTrue(f.write.requests.isEmpty)
    }
    func testLateOwnerOrGrantChangeRejectsResponseBeforeDenialClassification() async throws {
        for mode in 0..<2 {
            let f = try Fixture(), request = try f.request(), bridge = f.bridge()
            f.write.response = { _ in
                if mode == 0 { f.current = nil } else { f.grants = .init() }
                return (Data(repeating: 0xFF, count: 1_048_577), 403)
            }
            do { _ = try await bridge.send(request); XCTFail("Stale response accepted") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(f.write.requests.count, 1)
        }
    }
    func testOversizedHttpDenialPreservesOnlyStatusAndNeverChangesJournal() async throws {
        for status in [401, 403] {
            let f = try Fixture()
            let record = OperationPendingRecord(ownerKey: "unrelated", targetKey: "unrelated"); f.journal.record = record
            f.write.response = { _ in (Data(repeating: 0xFF, count: 1_048_577), status) }
            let reply = try await f.bridge().send(f.request())
            XCTAssertEqual(reply.1, status); XCTAssertTrue(reply.0.isEmpty)
            XCTAssertEqual(f.journal.record, record); XCTAssertEqual(f.journal.clears, 0)
        }
    }
    func testOversizedOrdinaryResponseFailsClosed() async throws {
        let f = try Fixture(); f.write.response = { _ in (Data(repeating: 0, count: 1_048_577), 200) }
        do { _ = try await f.bridge().send(f.request()); XCTFail("Oversized ordinary response accepted") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testBusinessDenialReachesExistingCoordinatorWithoutClearingOriginalMarker() async throws {
        let f = try Fixture(); f.write.response = { _ in (Data(#"{"code":403}"#.utf8), 200) }
        let factory = try f.factory()
        let flow = MerchantNPCChatCoordinator(scope: f.scope, client: factory.chatClient(currentScope: { _ in f.scope }),
                                             currentScope: { f.scope }, grants: { factory.chatGrants })
        _ = await flow.send("Original")
        XCTAssertEqual(flow.gameDispatchDenial, .forbidden); XCTAssertFalse(flow.canRetry)
        XCTAssertEqual(f.journal.record?.operationID, flow.requestID); XCTAssertEqual(f.journal.clears, 0)
    }
    func testTimeoutRetryKeepsUuidAndPayloadAcrossIndependentBridge() async throws {
        let f = try Fixture(); f.write.response = { _ in throw URLError(.timedOut) }
        let factory = try f.factory()
        let flow = MerchantNPCChatCoordinator(scope: f.scope, client: factory.chatClient(currentScope: { _ in f.scope }),
                                             currentScope: { f.scope }, grants: { factory.chatGrants })
        _ = await flow.send("Original"); let record = try XCTUnwrap(f.journal.record)
        _ = await flow.retry(); _ = await flow.retry(); _ = await flow.retry()
        XCTAssertEqual(f.write.requests.count, 3); XCTAssertEqual(f.journal.record, record)
        XCTAssertTrue(f.write.requests.allSatisfy { $0.httpBody == f.write.requests.first?.httpBody })
        XCTAssertFalse(flow.canRetry); XCTAssertEqual(f.journal.clears, 0)
    }
    func testCancellationBeforeDispatchLeavesUnderlyingWireUntouched() async throws {
        let f = try Fixture(), bridge = f.bridge(), request = try f.request()
        let task = Task { try await bridge.send(request) }; task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled request dispatched") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(f.write.requests.isEmpty)
    }
    func testStreamBodyNeverUsesGameBridge() async throws {
        let f = try Fixture(); var request = try f.request()
        request.httpBodyStream = InputStream(data: Data("unreviewed stream".utf8))
        await rejected(request, by: f.bridge()); XCTAssertTrue(f.write.requests.isEmpty)
    }
    func testWrongDeploymentNamespaceOrAccountApprovalNeverDispatches() async throws {
        for mode in 0..<3 {
            let f = try Fixture()
            let wrong = try MerchantPublicProductionApproval(market: .china,
                baseURL: mode == 0 ? URL(string: "https://other.example.test/native/")! : f.base,
                namespace: mode == 1 ? "other" : "game.fixture", accountID: mode == 2 ? 10 : 9,
                publicHomeRead: true, chatMerchantRows: [f.row])
            await rejected(try f.request(), by: f.bridge(wrong))
            XCTAssertTrue(f.write.requests.isEmpty)
        }
    }
    func testRestartGetAndExplicitAckUseIndependentReaderNotGamePostBridge() async throws {
        let f = try Fixture(); f.write.response = { _ in throw URLError(.timedOut) }
        let factory = try f.factory()
        let flow = MerchantNPCChatCoordinator(scope: f.scope, client: factory.chatClient(currentScope: { _ in f.scope }),
                                             currentScope: { f.scope }, grants: { factory.chatGrants })
        _ = await flow.send("Original"); let record = try XCTUnwrap(f.journal.record); flow.invalidate()
        let readback = Wire(), api = try APIConfiguration(baseURL: f.base)
        let session = try MerchantGamePlayerSession(namespace: "game.fixture", accountID: 9, epoch: 2, credential: "fresh-synthetic-token")
        let grant = MerchantGamePlayerReadGrant(market: .china, endpoints: try .init(baseURL: f.base,
            namespace: "game.fixture", accountID: 9, paths: MerchantGamePlayerReadGrant.playerPaths))
        readback.response = { request in
            XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody)
            if request.url!.path.hasSuffix("/game") { return (Data(#"{"code":500}"#.utf8), 503) }
            XCTAssertTrue(request.url!.path.hasSuffix(record.operationID.uuidString))
            let original: [String: Any] = ["merchantId": 31, "requestId": record.operationID.uuidString,
                "outcomeStatus": "REJECTED", "safetyDecision": "NOT_RUN", "safeText": "Original fixed exit",
                "errorCode": "MERCHANT_ENVIRONMENT_EXIT", "retryable": false, "ai": false]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": original]), 200)
        }
        let service = try MerchantGamePlayerService(configuration: api, merchantID: 31, session: session,
            grant: grant, transport: readback, journal: f.journal, current: { session })
        let player = MerchantGamePlayerCoordinator(service: service)
        XCTAssertFalse(player.canOpenChat); await player.load(); await player.readOriginal()
        XCTAssertTrue(player.canAcknowledge); XCTAssertEqual(f.journal.record, record)
        player.acknowledgeOriginal(); XCTAssertNil(f.journal.record); XCTAssertTrue(player.canOpenChat)
        XCTAssertEqual(f.write.requests.count, 1); XCTAssertEqual(readback.requests.count, 2)
    }
}
