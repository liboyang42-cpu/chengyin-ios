import XCTest
@testable import Questify

/// Exercises the current public factory, not the retired authenticated resource bridge.
/// All HTTP and journal data are synthetic; no deployment capability is enabled.
@MainActor final class MerchantNPCPublicFactoryHTTPJourneyTests: XCTestCase {
    @MainActor private final class Journal: OperationPendingJournal {
        var record: OperationPendingRecord?
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            guard record?.ownerKey == ownerKey, record?.targetKey == targetKey else { return nil }
            return record
        }
        func write(_ value: OperationPendingRecord) throws {
            guard record == nil || record == value else { throw APIError.invalidRequest }
            record = value
        }
        func clear(_ value: OperationPendingRecord) throws {
            guard record == value else { throw APIError.invalidRequest }; record = nil
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var failChat = false
        var afterChat: (() -> Void)?
        var journal: Journal?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            switch request.url?.lastPathComponent {
            case "public-home":
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertEqual(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Int], ["id": 31])
                return (Data(#"{"code":200,"data":{"id":31,"memberId":77,"npc":{"name":"Synthetic guide"}}}"#.utf8), 200)
            case "merchant-chat":
                let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                let id = try XCTUnwrap(fields["requestId"] as? String)
                XCTAssertEqual(journal?.record?.operationID.uuidString, id)
                XCTAssertEqual(Set(fields.keys), ["requestId", "bizId", "message"])
                XCTAssertEqual(fields["bizId"] as? Int, 31)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-npc-token")
                afterChat?()
                if failChat { throw URLError(.timedOut) }
                return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["requestId": id,
                    "outcomeStatus": "SUCCEEDED", "retryable": false, "safetyDecision": "PASS", "safeText": "Synthetic reply"]]), 200)
            default: XCTFail("Unexpected HTTP route"); throw APIError.invalidRequest
            }
        }
        var chats: [URLRequest] { requests.filter { $0.url?.lastPathComponent == "merchant-chat" } }
    }
    @MainActor private final class Harness {
        let wire = Wire(), journal = Journal()
        let scope = MerchantNPCScope(accountID: 7, namespace: "npc-http-test", epoch: UUID(),
            merchantRowID: PublicMerchantRowID(31)!, accessRevision: UUID())
        var context: MerchantPublicHostContext?
        var grants = MerchantNPCGrants()
        let api: APIConfiguration
        init() throws {
            api = try APIConfiguration(baseURL: URL(string: "https://npc.example.test/native/")!)
            context = try .init(market: .china, baseURL: api.baseURL, namespace: scope.namespace,
                accountID: 7, epoch: 1, role: "player", token: "synthetic-npc-token")
            grants.server = true; grants.provider = true; grants.legal = true
            wire.journal = journal
        }
        func model() throws -> MerchantNPCChatModel {
            let approval = try MerchantPublicProductionApproval(market: .china, baseURL: api.baseURL,
                namespace: scope.namespace, accountID: 7, publicHomeRead: true, chatMerchantRows: [scope.merchantRowID])
            let factory = try XCTUnwrap(MerchantPublicProductionFactory(api: api, approval: approval,
                transport: wire, journal: journal, current: { self.context }, grants: { self.grants }))
            let client = factory.chatClient(currentScope: { row in self.context != nil && row == self.scope.merchantRowID ? self.scope : nil })
            return MerchantNPCChatModel(.init(scope: scope, client: client,
                currentScope: { self.context == factory.captured ? self.scope : nil }, grants: { factory.chatGrants }))
        }
    }
    func testFreshReadThenChatRecordsOnlyVerifiedReplyAndClearsOriginalJournal() async throws {
        let h = try Harness(), model = try h.model()
        let completion = await model.coordinator.send(" Original 🧭 ")
        XCTAssertNotNil(completion); XCTAssertNil(h.journal.record)
        XCTAssertEqual(h.wire.requests.map { $0.url?.lastPathComponent }, ["public-home", "merchant-chat"])
        XCTAssertEqual(model.coordinator.conversationHistory.turns.count, 1)
        XCTAssertEqual(model.coordinator.message, "Original 🧭")
        XCTAssertTrue(model.revision > 0)
        XCTAssertTrue(h.wire.requests.allSatisfy { $0.httpMethod == "POST" && !$0.httpShouldHandleCookies })
    }
    func testTimeoutRetainsOriginalLockAndExplicitRetryUsesSameBytesAfterFreshRead() async throws {
        let h = try Harness(), model = try h.model(); h.wire.failChat = true
        let first = await model.coordinator.send("Original question")
        XCTAssertNil(first); XCTAssertEqual(model.coordinator.failure, .unknownOutcome)
        let id = try XCTUnwrap(model.coordinator.requestID)
        XCTAssertEqual(h.journal.record?.operationID, id)
        let blocked = await model.coordinator.send("Replacement question")
        XCTAssertNil(blocked); XCTAssertEqual(h.wire.chats.count, 1)
        h.wire.failChat = false
        let recovered = await model.coordinator.retry(requestID: id)
        XCTAssertEqual(recovered?.requestID, id); XCTAssertNil(h.journal.record)
        XCTAssertEqual(h.wire.chats.count, 2)
        XCTAssertEqual(h.wire.chats.first?.httpBody, h.wire.chats.last?.httpBody)
        XCTAssertEqual(h.wire.requests.map { $0.url?.lastPathComponent }, ["public-home", "merchant-chat", "public-home", "merchant-chat"])
        XCTAssertEqual(model.coordinator.conversationHistory.turns.count, 1)
    }
    func testRecreatedConversationCannotReplaceUnresolvedOriginalRequest() async throws {
        let h = try Harness(), first = try h.model(); h.wire.failChat = true
        await first.coordinator.send("Original question")
        let original = try XCTUnwrap(h.journal.record)
        first.coordinator.invalidate()
        let reopened = try h.model(); h.wire.failChat = false
        let completion = await reopened.coordinator.send("New question")
        XCTAssertNil(completion); XCTAssertEqual(h.journal.record, original)
        XCTAssertEqual(reopened.coordinator.failure, .unknownOutcome)
        XCTAssertTrue(reopened.coordinator.conversationHistory.turns.isEmpty)
        XCTAssertEqual(h.wire.requests.count, 2)
    }
    func testMissingLegalGrantCannotReadHomeOrChatAndCompletedHistoryIsErasedOnLoss() async throws {
        let h = try Harness(); h.grants.legal = false
        let closed = try h.model()
        let refused = await closed.coordinator.send("No grant")
        XCTAssertNil(refused); XCTAssertTrue(h.wire.requests.isEmpty); XCTAssertNil(h.journal.record)
        h.grants.legal = true
        let active = try h.model()
        let completed = await active.coordinator.send("Permitted question")
        XCTAssertNotNil(completed); XCTAssertEqual(active.coordinator.conversationHistory.turns.count, 1)
        h.grants.legal = false
        XCTAssertTrue(active.coordinator.conversationHistory.turns.isEmpty)
        XCTAssertNil(active.coordinator.reply); XCTAssertNil(active.coordinator.message)
        XCTAssertFalse(active.coordinator.canSend); XCTAssertEqual(h.wire.chats.count, 1)
    }
    func testRevocationDuringReplyRetainsJournalAndNeverPublishesPrivateHistory() async throws {
        for revokeAccount in [false, true] {
            let h = try Harness(), model = try h.model()
            h.wire.afterChat = { if revokeAccount { h.context = nil } else { h.grants.legal = false } }
            let completion = await model.coordinator.send("Original question")
            XCTAssertNil(completion); XCTAssertNotNil(h.journal.record)
            XCTAssertTrue(model.coordinator.conversationHistory.turns.isEmpty)
            XCTAssertNil(model.coordinator.reply); XCTAssertNil(model.coordinator.message)
            XCTAssertFalse(model.coordinator.canSend); XCTAssertFalse(model.coordinator.canRetry)
            await model.coordinator.retry()
            XCTAssertEqual(h.wire.chats.count, 1)
        }
    }
}
