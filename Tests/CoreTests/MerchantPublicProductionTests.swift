import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class MerchantPublicProductionTests: XCTestCase {
    final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var home = #"{"code":200,"data":{"id":31,"memberId":77,"name":"Synthetic store","npc":{"name":"Guide"}}}"#
        var outcome = "SUCCEEDED"
        var retryable = false
        var unknownChat = false
        var badReceipt = false
        var afterSend: ((URLRequest) -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); afterSend?(request)
            if request.url?.path.hasSuffix("public-home") == true { return (Data(home.utf8), 200) }
            if unknownChat { throw URLError(.timedOut) }
            let fields = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as! [String: Any]
            let reply: [String: Any] = ["code": 200, "data": ["requestId": badReceipt ? UUID().uuidString : fields["requestId"]!,
                "outcomeStatus": outcome, "retryable": retryable, "safeText": "Synthetic reply"]]
            return (try JSONSerialization.data(withJSONObject: reply), 200)
        }
        var chats: [URLRequest] { requests.filter { $0.url?.path.hasSuffix("merchant-chat") == true } }
    }
    final class Journal: OperationPendingJournal {
        var records: [String: OperationPendingRecord] = [:]
        var failWrite = false
        var failRead = false
        var afterWrite: (() -> Void)?
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            if failRead { throw APIError.malformedResponse }; return records[ownerKey + targetKey]
        }
        func write(_ record: OperationPendingRecord) throws {
            if failWrite { throw APIError.invalidRequest }
            if let old = records[record.ownerKey + record.targetKey], old != record { throw APIError.invalidRequest }
            records[record.ownerKey + record.targetKey] = record; afterWrite?()
        }
        func clear(_ record: OperationPendingRecord) throws {
            guard records[record.ownerKey + record.targetKey] == record else { throw APIError.invalidRequest }
            records.removeValue(forKey: record.ownerKey + record.targetKey)
        }
    }
    let url = URL(string: "https://example.com/prod-api/")!
    let row = PublicMerchantRowID(31)!
    func context(account: Int? = 9, epoch: UInt64 = 1, role: String? = "user", token: String? = "synthetic-token", market: RegionalMarket = .china) throws -> MerchantPublicHostContext {
        try .init(market: market, baseURL: url, namespace: "synthetic.merchant", accountID: account, epoch: epoch, role: role, token: token)
    }
    func approval(account: Int? = 9, read: Bool = true, chat: Bool = true) throws -> MerchantPublicProductionApproval {
        try .init(market: .china, baseURL: url, namespace: "synthetic.merchant", accountID: account, publicHomeRead: read, chatMerchantRows: chat ? [row] : [])
    }
    func scope() -> MerchantNPCScope { .init(accountID: 9, namespace: "synthetic.merchant", epoch: UUID(), merchantRowID: row, accessRevision: UUID()) }
    func grants() -> MerchantNPCGrants { var value = MerchantNPCGrants(); value.server = true; value.provider = true; value.legal = true; value.resourceOwnership = true; value.voiceCloning = true; value.mediaTransmission = true; return value }
    func factory(_ wire: Wire, journal: Journal? = nil, approval: MerchantPublicProductionApproval? = nil,
                 current: @escaping () -> MerchantPublicHostContext?, grants: (() -> MerchantNPCGrants)? = nil) throws -> MerchantPublicProductionFactory {
        try XCTUnwrap(MerchantPublicProductionFactory(api: APIConfiguration(baseURL: url), approval: approval ?? self.approval(),
            transport: wire, journal: journal, current: current, grants: grants ?? { self.grants() }))
    }
    func testDefaultApprovalAndGrantsMakeNoRequests() async throws {
        let wire = Wire(), c = try context()
        XCTAssertNil(MerchantPublicProductionFactory(api: try .init(baseURL: url), transport: wire, current: { c }))
        let f = try factory(wire, approval: approval(read: false, chat: false), current: { c })
        XCTAssertFalse(f.homeReader.isConfigured); XCTAssertFalse(f.chatGrants.chatAllowed)
        do { _ = try await f.homeReader.home(.legacyMerchantRowID(row)); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testGuestPublicReaderUsesOnlyOwnerIDAndNeverSendsCredentials() async throws {
        let wire = Wire(), c = try context(account: nil, role: nil, token: nil)
        let f = try factory(wire, approval: approval(account: nil, chat: false), current: { c })
        let home = try await f.homeReader.home(.ownerMemberID(PublicMerchantOwnerID(77)!))
        XCTAssertEqual(home.id, 31); XCTAssertFalse(f.chatGrants.chatAllowed)
        let r = try XCTUnwrap(wire.requests.first)
        XCTAssertEqual(r.url?.path, "/prod-api/api/merchant/public-home"); XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertNil(r.url?.query); XCTAssertNil(r.value(forHTTPHeaderField: "Authorization")); XCTAssertFalse(r.httpShouldHandleCookies)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(r.httpBody)) as? [String: Int], ["memberId": 77])
    }
    func testWrongAccountMarketRealmAndNamespaceRejectFactory() throws {
        let wire = Wire(), c = try context()
        for a in [try approval(account: 10), try .init(market: .unitedStates, baseURL: url, namespace: c.namespace, accountID: 9),
                  try .init(market: .china, baseURL: URL(string: "https://other.example.com/")!, namespace: c.namespace, accountID: 9),
                  try .init(market: .china, baseURL: url, namespace: "other", accountID: 9)] {
            XCTAssertNil(MerchantPublicProductionFactory(api: try .init(baseURL: url), approval: a, transport: wire, current: { c }))
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testChatApprovalRequiresAccountAndPublicRead() {
        XCTAssertThrowsError(try approval(account: nil)); XCTAssertThrowsError(try approval(read: false))
        XCTAssertThrowsError(try context(account: nil)); XCTAssertThrowsError(try context(token: nil))
    }
    func testHomeRejectsMissingOrDifferentRequestedIdentity() async throws {
        let wire = Wire(), c = try context(); let f = try factory(wire, current: { c })
        for body in [#"{"code":200,"data":null}"#, #"{"code":200,"data":{"id":77,"memberId":31}}"#] {
            wire.home = body
            do { _ = try await f.homeReader.home(.legacyMerchantRowID(row)); XCTFail() } catch { XCTAssertEqual(error as? PublicMerchantHomeFailure, .retryable) }
        }
    }
    func testRetainedReaderRejectsStaleBeforeAndAfterRead() async throws {
        let wire = Wire(); var c: MerchantPublicHostContext? = try context()
        let f = try factory(wire, current: { c })
        wire.afterSend = { _ in c = nil }
        do { _ = try await f.homeReader.home(.legacyMerchantRowID(row)); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        do { _ = try await f.homeReader.home(.legacyMerchantRowID(row)); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 1); XCTAssertFalse(f.homeReader.isConfigured)
    }
    func testEachEpochRoleTokenChangeFencesRetainedFactory() throws {
        let wire = Wire(), initial = try context()
        for replacement in [try context(epoch: 2), try context(role: "merchant"), try context(token: "replacement-token"), try context(account: 10)] {
            var c: MerchantPublicHostContext? = initial
            let f = try factory(wire, journal: Journal(), current: { c }); c = replacement
            XCTAssertFalse(f.isCurrent); XCTAssertFalse(f.chatGrants.chatAllowed); XCTAssertFalse(f.homeReader.isConfigured)
        }
    }
    func testExactChatFactoryReadsFreshPublicRowThenUsesRawToken() async throws {
        let wire = Wire(), j = Journal(), c = try context(), s = scope(), id = UUID()
        let f = try factory(wire, journal: j, current: { c }); let client = f.chatClient(currentScope: { _ in s })
        let reply = try await client.chat(message: "Hello", requestID: id, scope: s)
        XCTAssertTrue(reply.succeeded); XCTAssertEqual(wire.requests.count, 2)
        XCTAssertNil(wire.requests[0].value(forHTTPHeaderField: "Authorization"))
        let r = try XCTUnwrap(wire.chats.first)
        XCTAssertEqual(r.url?.path, "/prod-api/api/ai/npc/merchant-chat"); XCTAssertEqual(r.httpMethod, "POST")
        XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(r.httpBody)) as! [String: Any]
        XCTAssertEqual(Set(body.keys), ["requestId", "bizId", "message"]); XCTAssertEqual(body["bizId"] as? Int, 31)
        XCTAssertTrue(j.records.isEmpty)
        XCTAssertFalse(f.chatGrants.resourceAllowed); XCTAssertFalse(f.chatGrants.voiceCloning)
    }
    func testJournalAndAllChatGrantsRequired() async throws {
        let wire = Wire(), c = try context(), s = scope()
        for j in [nil, Journal()] {
            let f = try factory(wire, journal: j, current: { c }, grants: { .init() })
            do { _ = try await f.chatClient(currentScope: { _ in s }).chat(message: "Hi", requestID: UUID(), scope: s); XCTFail() } catch {}
        }
        let noJournal = try factory(wire, current: { c }); XCTAssertFalse(noJournal.chatGrants.chatAllowed)
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testUnsupportedResourceClientAndUnapprovedRowNeverSend() async throws {
        let wire = Wire(), c = try context(), s = scope(), f = try factory(wire, journal: Journal(), current: { c })
        XCTAssertFalse(MerchantPublicProductionFactory.supportsLegacyResources)
        do { _ = try await f.resourceClient().voiceScript(scope: s); XCTFail() } catch { XCTAssertEqual(error as? MerchantNPCFailure, .disabled) }
        let other = MerchantNPCScope(accountID: 9, namespace: c.namespace, epoch: s.epoch, merchantRowID: PublicMerchantRowID(77)!, accessRevision: s.accessRevision)
        do { _ = try await f.chatClient(currentScope: { _ in other }).chat(message: "Hi", requestID: UUID(), scope: other); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testHiddenOrMismatchedPublicRowPreventsChat() async throws {
        let wire = Wire(), c = try context(), s = scope(), j = Journal(), f = try factory(wire, journal: j, current: { c })
        for body in [#"{"code":500,"msg":"商家不存在或未开放"}"#, #"{"code":200,"data":{"id":31}}"#, #"{"code":200,"data":{"id":77,"npc":{"name":"Guide"}}}"#] {
            wire.home = body
            do { _ = try await f.chatClient(currentScope: { _ in s }).chat(message: "Hi", requestID: UUID(), scope: s); XCTFail() } catch {}
        }
        XCTAssertTrue(wire.chats.isEmpty); XCTAssertTrue(j.records.isEmpty)
    }
    func testGrantRevokedDuringReadbackMakesNoChatRequest() async throws {
        let wire = Wire(), c = try context(), s = scope(); var g = grants()
        let f = try factory(wire, journal: Journal(), current: { c }, grants: { g })
        let client = f.chatClient(currentScope: { _ in s }); wire.afterSend = { _ in g = .init() }
        do { _ = try await client.chat(message: "Hi", requestID: UUID(), scope: s); XCTFail() } catch {}
        XCTAssertTrue(wire.chats.isEmpty)
    }
    func testUnknownOutcomeRetriesExactIdentityAndBlocksNewIdentityAcrossRecreation() async throws {
        let wire = Wire(), c = try context(), s = scope(), j = Journal(), id = UUID()
        let f = try factory(wire, journal: j, current: { c }); let client = f.chatClient(currentScope: { _ in s }); wire.unknownChat = true
        do { _ = try await client.chat(message: "Hi", requestID: id, scope: s); XCTFail() } catch {}
        XCTAssertEqual(j.records.count, 1)
        let reopened = try factory(wire, journal: j, current: { c }).chatClient(currentScope: { _ in s })
        do { _ = try await reopened.chat(message: "Hi", requestID: UUID(), scope: s); XCTFail() } catch {}
        XCTAssertEqual(wire.chats.count, 1)
        wire.unknownChat = false
        _ = try await client.chat(message: "Hi", requestID: id, scope: s)
        XCTAssertEqual(wire.chats.count, 2); XCTAssertTrue(j.records.isEmpty)
        for r in wire.chats {
            let b = try JSONSerialization.jsonObject(with: XCTUnwrap(r.httpBody)) as! [String: Any]
            XCTAssertEqual(b["requestId"] as? String, id.uuidString)
        }
    }
    func testProcessingMismatchedReceiptAndLateAccountChangeKeepLock() async throws {
        for mode in 0..<3 {
            let wire = Wire(), j = Journal(), s = scope(); var c: MerchantPublicHostContext? = try context()
            let f = try factory(wire, journal: j, current: { c }); let client = f.chatClient(currentScope: { _ in s })
            if mode == 0 { wire.outcome = "PROCESSING"; wire.retryable = true }
            if mode == 1 { wire.badReceipt = true }
            if mode == 2 { wire.afterSend = { if $0.url?.path.hasSuffix("merchant-chat") == true { c = nil } } }
            do { _ = try await client.chat(message: "Hi", requestID: UUID(), scope: s); XCTAssertEqual(mode, 0) } catch { XCTAssertNotEqual(mode, 0) }
            XCTAssertEqual(j.records.count, 1)
        }
    }
    func testJournalFailureOrCancellationAfterReservationNeverDispatches() async throws {
        for mode in 0..<3 {
            let wire = Wire(), j = Journal(), s = scope(); var c: MerchantPublicHostContext? = try context()
            if mode == 0 { j.failRead = true }; if mode == 1 { j.failWrite = true }; if mode == 2 { j.afterWrite = { c = nil } }
            let f = try factory(wire, journal: j, current: { c })
            do { _ = try await f.chatClient(currentScope: { _ in s }).chat(message: "Hi", requestID: UUID(), scope: s); XCTFail() } catch {}
            XCTAssertTrue(wire.chats.isEmpty); if mode == 2 { XCTAssertEqual(j.records.count, 1) }
        }
    }
    func testCancelledTaskNeverReachesPublicReadOrChat() async throws {
        let wire = Wire(), c = try context(), s = scope(), f = try factory(wire, journal: Journal(), current: { c })
        let client = f.chatClient(currentScope: { _ in s })
        let task = Task { try await client.chat(message: "Hi", requestID: UUID(), scope: s) }
        task.cancel()
        do { _ = try await task.value; XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testCancelledAfterReservationKeepsUnknownLockWithoutSending() async throws {
        let wire = Wire(), c = try context(), s = scope(), j = Journal(), f = try factory(wire, journal: j, current: { c })
        j.afterWrite = { withUnsafeCurrentTask { $0?.cancel() } }
        let client = f.chatClient(currentScope: { _ in s })
        let task = Task { try await client.chat(message: "Hi", requestID: UUID(), scope: s) }
        do { _ = try await task.value; XCTFail() } catch {}
        XCTAssertTrue(wire.chats.isEmpty); XCTAssertEqual(j.records.count, 1)
    }
    func testSourceMessageLimitStopsBeforeReadback() async throws {
        let wire = Wire(), c = try context(), s = scope(), f = try factory(wire, journal: Journal(), current: { c })
        do { _ = try await f.chatClient(currentScope: { _ in s }).chat(message: String(repeating: "a", count: 301), requestID: UUID(), scope: s); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
}
