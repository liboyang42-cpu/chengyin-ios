import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor private final class MessageReferenceProtectedStorageFixture: ProjectEditDataStorage {
    var rows: [String: Data] = [:]
    var writes = 0
    var removes = 0
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { writes += 1; rows[key] = data }
    func remove(_ key: String) throws { removes += 1; rows[key] = nil }
}
private final class MessageReferenceHTTPFixture: HTTPTransport {
    var requests: [URLRequest] = []
    var response = "{}"
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(response.utf8), 200) }
}

/// Requires original-writer-shared.patch applied to its exact e2d86c4c preimages.
/// These tests never enable an endpoint/grant or send a real request.
@MainActor final class NativeChannelMessageOriginalWriterJournalTests: XCTestCase {
    private let key = String(repeating: "a", count: 32)
    private func context(account: Int = 7, epoch: UInt64 = 1, namespace: String = "reference-journal-only") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://example.com/prod-api")!, role: "player",
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: "fixture-token"))
    }
    private func id(_ raw: String) -> NativeChannelMessageID { .init(rawValue: raw)! }
    private func reference(reply: String = "8", members: [String] = ["10","11"], roles: [String] = ["20"],
                           everyone: Bool = false, channel: String = "9", revision: String = "captured-mapping") throws -> NativeChannelMessageTextReference {
        try .init(binding: .init(channelID: id(channel), conversationID: id("9"), mappingRevision: revision),
                  replyToID: id(reply), memberIDs: members.map(id), roleIDs: roles.map(id), mentionEveryone: everyone)
    }
    private func intent(_ reference: NativeChannelMessageTextReference? = nil, text: String = "same text") throws -> MessageTextIntent {
        try .init(conversationID: 9, content: text, clientMessageID: key, channelReference: reference)
    }
    func testV1RestoresWithoutMigrationOrAnyByteRewriteAcrossNewLoginEpoch() throws {
        let storage = MessageReferenceProtectedStorageFixture(), scope = try NativeChannelTextScope(context: context(), conversationID: 9)
        let journal = NativeChannelTextJournal(storage: storage, scope: scope)
        try journal.saveBeforeDispatch(intent())
        let storageKey = try XCTUnwrap(storage.rows.keys.first)
        struct LegacyRecord: Encodable { let version: Int; let scope: NativeChannelTextScope; let content: String; let clientMessageID: String }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let originalBytes = try encoder.encode(LegacyRecord(version: 1, scope: scope, content: "same text", clientMessageID: key))
        storage.rows[storageKey] = originalBytes
        let cold = NativeChannelTextJournal(storage: storage, scope: try .init(context: context(epoch: 9), conversationID: 9))
        XCTAssertTrue(NativeChannelTextJournal.same(try cold.restore(), try intent()))
        try cold.saveBeforeDispatch(intent())
        XCTAssertEqual(storage.writes, 1); XCTAssertEqual(storage.removes, 0)
        XCTAssertEqual(storage.rows[storageKey], originalBytes)
    }
    func testV2UsesSameSingleSlotOriginalKeyAndCompleteReferenceIdentity() throws {
        let storage = MessageReferenceProtectedStorageFixture(), scope = try NativeChannelTextScope(context: context(), conversationID: 9)
        let journal = NativeChannelTextJournal(storage: storage, scope: scope), value = try intent(reference())
        try journal.saveBeforeDispatch(value)
        let original = storage.rows
        let restored = try XCTUnwrap(NativeChannelTextJournal(storage: storage, scope: scope).restore())
        XCTAssertTrue(NativeChannelTextJournal.same(restored, value)); XCTAssertEqual(restored.clientMessageID, key)
        XCTAssertEqual(storage.rows.count, 1)
        let row = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.rows.values.first)) as? [String: Any])
        XCTAssertEqual(row["version"] as? Int, 2)
        let alternatives = [try reference(reply: "7"), try reference(members: ["11","10"]), try reference(members: ["10"]),
            try reference(roles: ["21"]), try reference(everyone: true), try reference(channel: "99"), try reference(revision: "different-mapping")]
        for metadata in alternatives {
            let different = try intent(metadata)
            XCTAssertFalse(NativeChannelTextJournal.same(restored, different))
            XCTAssertThrowsError(try journal.saveBeforeDispatch(different))
            XCTAssertThrowsError(try journal.settle(different))
            XCTAssertEqual(storage.rows, original)
        }
    }
    func testPlainIntentCannotOverwriteOrSettleProtectedReferenceAndViceVersa() throws {
        for hasReference in [false, true] {
            let storage = MessageReferenceProtectedStorageFixture(), journal = NativeChannelTextJournal(storage: storage, scope: try .init(context: context(), conversationID: 9))
            let first = try intent(hasReference ? reference() : nil), replacement = try intent(hasReference ? nil : reference())
            try journal.saveBeforeDispatch(first); let original = storage.rows
            XCTAssertThrowsError(try journal.saveBeforeDispatch(replacement)); XCTAssertThrowsError(try journal.settle(replacement))
            XCTAssertEqual(storage.rows, original); XCTAssertEqual(storage.writes, 1); XCTAssertEqual(storage.removes, 0)
        }
    }
    func testUnknownFutureRecordFieldsArePreservedWithoutLossySettlement() throws {
        for location in ["root", "scope", "reference", "binding", "schema"] {
            let storage = MessageReferenceProtectedStorageFixture(), journal = NativeChannelTextJournal(storage: storage, scope: try .init(context: context(), conversationID: 9))
            let value = try intent(reference()); try journal.saveBeforeDispatch(value)
            let storageKey = try XCTUnwrap(storage.rows.keys.first)
            var row = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.rows[storageKey])) as? [String: Any])
            switch location {
            case "root": row["futureRequestIdentity"] = "do not discard"
            case "scope": var scope = row["scope"] as! [String: Any]; scope["futureOwner"] = "preserve"; row["scope"] = scope
            case "reference": var ref = row["channelReference"] as! [String: Any]; ref["futureMentions"] = ["999"]; row["channelReference"] = ref
            case "binding":
                var ref = row["channelReference"] as! [String: Any], binding = ref["binding"] as! [String: Any]
                binding["futureAuthorityVersion"] = "must not infer"; ref["binding"] = binding; row["channelReference"] = ref
            default: row["version"] = 3
            }
            let bytes = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]); storage.rows[storageKey] = bytes
            XCTAssertThrowsError(try journal.restore()); XCTAssertThrowsError(try journal.settle(value))
            XCTAssertThrowsError(try journal.saveBeforeDispatch(intent()))
            XCTAssertEqual(storage.rows[storageKey], bytes); XCTAssertEqual(storage.removes, 0)
        }
    }
    func testReferenceCannotBeAttachedToAnotherConversationOrContainDuplicateIDs() throws {
        XCTAssertThrowsError(try MessageTextIntent(conversationID: 10, content: "same text", clientMessageID: key, channelReference: reference()))
        XCTAssertThrowsError(try reference(members: ["10","10"]))
        XCTAssertThrowsError(try reference(roles: ["20","20"]))
    }
    func testUnknownPublicReferenceWireCannotSilentlySendOnlyText() async throws {
        let transport = MessageReferenceHTTPFixture(), config = try APIConfiguration(baseURL: URL(string: "https://example.com/prod-api")!)
        let value = try intent(reference())
        do { _ = try await NativeChannelTextService(configuration: config, transport: transport).send(value, accountID: 7, token: "fixture-token"); XCTFail("Unproved reference multipart was sent") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await MessageActionService(configuration: config, transport: transport).send(value, token: "fixture-token"); XCTFail("Original generic writer discarded reference") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testPlainReceiptCannotSettleReferenceButOriginalLookupKeyRemainsExact() async throws {
        let transport = MessageReferenceHTTPFixture(), config = try APIConfiguration(baseURL: URL(string: "https://example.com/prod-api")!)
        transport.response = #"{"code":200,"data":{"found":true,"message":{"id":42,"conversationId":9,"senderId":7,"clientMessageId":"KEY","msgType":1,"status":0,"content":"same text"}}}"#.replacingOccurrences(of: "KEY", with: key)
        do { _ = try await NativeChannelTextService(configuration: config, transport: transport).receipt(intent(reference()), accountID: 7, token: "fixture-token"); XCTFail("Plain text receipt accepted missing original metadata") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(transport.requests.count, 1)
        let body = String(data: try XCTUnwrap(transport.requests.first?.httpBody), encoding: .utf8)!
        XCTAssertTrue(body.contains("name=\"client_message_id\"\r\n\r\n\(key)\r\n"))
        XCTAssertTrue(body.contains("name=\"conversation_id\"\r\n\r\n9\r\n"))
        XCTAssertFalse(body.contains("reply_to_id"))
    }
    func testLegacyMultipartAllowlistDoesNotGainUnprovedReferenceFields() throws {
        let base = URL(string: "https://example.com/prod-api")!
        var fields = ["conversation_id":"9","client_message_id":key,"msg_type":"1","content":"same text"]
        fields["reply_to_id"] = "8"
        var request = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/im/send"), fields: fields, token: "fixture-token")
        request.httpShouldHandleCookies = false
        XCTAssertNil(NativeChannelTextRoute(request: request, baseURL: base))
    }
    func testOrdinaryV1SendAndReceiptStillUseOriginalFourFieldWriterAndKey() async throws {
        let transport = MessageReferenceHTTPFixture(), config = try APIConfiguration(baseURL: URL(string: "https://example.com/prod-api")!)
        let value = try intent(), service = NativeChannelTextService(configuration: config, transport: transport)
        let message = #"{"id":42,"conversationId":9,"senderId":7,"clientMessageId":"KEY","msgType":1,"status":0,"content":"same text"}"#.replacingOccurrences(of: "KEY", with: key)
        transport.response = "{\"code\":200,\"data\":" + message + "}"
        let sent = try await service.send(value, accountID: 7, token: "fixture-token")
        XCTAssertEqual(sent.id, 42)
        let request = try XCTUnwrap(transport.requests.first)
        guard case .send(let parsed)? = NativeChannelTextRoute(request: request, baseURL: config.baseURL) else { return XCTFail("Original route rejected ordinary v1 text") }
        XCTAssertTrue(NativeChannelTextJournal.same(parsed, value)); XCTAssertNil(parsed.channelReference)
        transport.response = "{\"code\":200,\"data\":{\"found\":true,\"message\":" + message + "}}"
        let recovered = try await service.receipt(value, accountID: 7, token: "fixture-token")
        XCTAssertEqual(recovered?.id, 42)
        XCTAssertEqual(transport.requests.count, 2)
        guard case .receipt(let conversation, let originalKey)? = NativeChannelTextRoute(request: transport.requests[1], baseURL: config.baseURL) else { return XCTFail("Original receipt route changed") }
        XCTAssertEqual(conversation, 9); XCTAssertEqual(originalKey, key)
    }
    func testOriginalMultipartRoutePreservesLastCharacterAndUnicodePayload() throws {
        let base = URL(string: "https://example.com/prod-api")!
        for text in ["x", "same text", "结尾", "emoji🙂", "line\r\nnext"] {
            let value = try intent(text: text)
            var request = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/im/send"),
                fields: ["conversation_id": "9", "client_message_id": key, "msg_type": "1", "content": text],
                token: "fixture-token", boundary: "original-boundary")
            request.httpShouldHandleCookies = false
            guard case .send(let parsed)? = NativeChannelTextRoute(request: request, baseURL: base) else {
                XCTFail("Original canonical payload lost its final character"); continue
            }
            XCTAssertTrue(NativeChannelTextJournal.same(parsed, value))
            // Missing final CRLF is not repaired or accepted by the parser.
            request.httpBody = request.httpBody.map { Data($0.dropLast(2)) }
            XCTAssertNil(NativeChannelTextRoute(request: request, baseURL: base))
        }
    }
    func testMutationJournalAlsoPreservesUnknownFutureRequestIdentityFields() throws {
        let storage = MessageReferenceProtectedStorageFixture(), binding = try reference().binding
        let credentials = try NativeChannelMessageCredentials(identity: .init(accountID: 7, epoch: 1), namespace: "reference-journal-only",
            baseURL: URL(string: "https://example.com/prod-api")!, binding: binding, authorityRevision: "fixture", token: "fixture-token")
        let journal = NativeChannelMessageMutationJournal(scope: .init(credentials: credentials), storage: storage)
        let original = try NativeChannelMessageCommand(operation: .edit, requestID: "original_mutation_0001", binding: binding,
            messageID: id("8"), expectedVersion: 1, content: "same text")
        try journal.saveBeforeDispatch(original)
        let storageKey = try XCTUnwrap(storage.rows.keys.first)
        var row = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(storage.rows[storageKey])) as? [String: Any])
        var command = row["command"] as! [String: Any]; command["futureOriginalIdentity"] = "preserve"; row["command"] = command
        let bytes = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]); storage.rows[storageKey] = bytes
        XCTAssertThrowsError(try journal.restore()); XCTAssertThrowsError(try journal.settle(original))
        XCTAssertEqual(storage.rows[storageKey], bytes); XCTAssertEqual(storage.removes, 0)
    }
}
