import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

private struct MessageOriginalHTTPFixture: HTTPTransport {
    let bytes: Data
    func send(_ request: URLRequest) async throws -> (Data, Int) { (bytes, 200) }
}
@MainActor final class NativeChannelMessageOriginalWireTests: XCTestCase {
    func testOriginalHistoryReceivesExactIntIDsAndSameResponseMutationWatermark() async throws {
        let binding = try NativeChannelMessageBinding(channelID: .init(rawValue: "9")!, conversationID: .init(rawValue: "9")!, mappingRevision: "source")
        let data = Data(#"{"code":200,"data":{"list":[{"id":"9007199254740993","conversationId":"9","senderId":"3","msgType":1,"status":0,"version":1,"content":"original body","mentions":[],"mention_everyone":false}],"nextCursor":"9007199254740993","hasMore":true,"mutation_cursor":"7","sync_contract":"VISIBLE_ORDER_PLUS_MUTATIONS_V1","legacy_cache_action":"RELOAD_ON_RESUME"}}"#.utf8)
        let config = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let bridge = NativeChannelMessageOriginalWireBridge(binding: binding, configuration: config,
            underlying: MessageOriginalHTTPFixture(bytes: data), current: { true })
        let request = try AuthRequestBuilder.makeFormRequest(url: config.baseURL.appendingPathComponent("api/im/messages"),
            fields: ["conversation_id":"9","cursor_id":"0","size":"30"], token: "test-only-token")
        let normalized = try await bridge.send(request)
        struct Envelope: Decodable { let data: MessagingPage }
        let page = try JSONDecoder().decode(Envelope.self, from: normalized.0).data
        var originalHistory = MessagingHistory(conversationID: 9)
        try originalHistory.replace(with: page)
        let supplement = try bridge.consumedFullReplacement(messages: originalHistory.messages)
        XCTAssertEqual(originalHistory.messages.first?.id, 9_007_199_254_740_993)
        XCTAssertEqual(supplement.mutation_cursor, "7")
        XCTAssertEqual(bridge.snapshot(for: originalHistory.messages[0])?.version, 1)
        XCTAssertThrowsError(try bridge.consumedFullReplacement(messages: originalHistory.messages))
    }
    func testMutationCursorCannotBeAcknowledgedBeforeMatchingOriginalReplacement() async throws {
        let binding = try NativeChannelMessageBinding(channelID: .init(rawValue: "9")!, conversationID: .init(rawValue: "9")!, mappingRevision: "source")
        let data = Data(#"{"code":200,"data":{"list":[{"id":"8","conversationId":"9","msgType":1,"status":0,"version":1,"content":"message"}],"nextCursor":null,"hasMore":false,"mutation_cursor":"7","sync_contract":"VISIBLE_ORDER_PLUS_MUTATIONS_V1","legacy_cache_action":"RELOAD_ON_RESUME"}}"#.utf8)
        let config = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let bridge = NativeChannelMessageOriginalWireBridge(binding: binding, configuration: config,
            underlying: MessageOriginalHTTPFixture(bytes: data), current: { true })
        let request = try AuthRequestBuilder.makeFormRequest(url: config.baseURL.appendingPathComponent("api/im/messages"), fields: ["conversation_id":"9","cursor_id":"0","size":"30"], token: "test-only-token")
        _ = try await bridge.send(request)
        XCTAssertThrowsError(try bridge.consumedFullReplacement(messages: []))
        bridge.retire()
        XCTAssertThrowsError(try bridge.consumedFullReplacement(messages: []))
    }

    func testOriginalSendAndReceiptRecognizeWholeConversationAndPreserveProof() async throws {
        for conversation in ["9", "19"] {
            for path in ["api/im/send", "api/im/send-receipt"] {
                let binding = try NativeChannelMessageBinding(channelID: .init(rawValue: conversation)!,
                    conversationID: .init(rawValue: conversation)!, mappingRevision: "source")
                let config = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
                let originalContent = "末尾🙂\r\nnext"
                let message: [String: Any] = ["id": "42", "conversationId": conversation,
                    "senderId": "3", "msgType": 1, "status": 0, "content": originalContent]
                // Opaque source proof is passed through, never constructed or certified by this bridge.
                let proof: [String: Any] = ["request_id": "original-request", "request_hash": "opaque-source-proof"]
                let body: [String: Any] = path.hasSuffix("send-receipt")
                    ? ["found": true, "state": "APPLIED", "original_send_proof": proof, "message": message]
                    : message
                let bytes = try JSONSerialization.data(withJSONObject: ["code": 200, "data": body])
                let bridge = NativeChannelMessageOriginalWireBridge(binding: binding, configuration: config,
                    underlying: MessageOriginalHTTPFixture(bytes: bytes), current: { true })
                var fields = ["conversation_id": conversation, "client_message_id": "original-request"]
                if path.hasSuffix("/send") { fields["msg_type"] = "1"; fields["content"] = originalContent }
                let request = try AuthRequestBuilder.makeFormRequest(url: config.baseURL.appendingPathComponent(path),
                    fields: fields, token: "test-only-token")
                let response = try await bridge.send(request)
                let root = try XCTUnwrap(JSONSerialization.jsonObject(with: response.0) as? [String: Any])
                let normalized = try XCTUnwrap(root["data"] as? [String: Any])
                let row: [String: Any]
                if path.hasSuffix("send-receipt") {
                    row = try XCTUnwrap(normalized["message"] as? [String: Any])
                    let retained = try XCTUnwrap(normalized["original_send_proof"] as? [String: String])
                    XCTAssertEqual(retained, ["request_id": "original-request", "request_hash": "opaque-source-proof"])
                    XCTAssertEqual(normalized["state"] as? String, "APPLIED")
                } else { row = normalized }
                XCTAssertEqual(row["id"] as? Int, 42)
                XCTAssertEqual(row["conversationId"] as? Int, Int(conversation))
                XCTAssertEqual(row["senderId"] as? Int, 3)
                XCTAssertEqual(row["content"] as? String, originalContent)
                XCTAssertThrowsError(try bridge.consumedFullReplacement(messages: []))
            }
        }
    }
    func testDifferentConversationAndTruncatedMultipartNeverGainHistoryAcknowledgement() async throws {
        let binding = try NativeChannelMessageBinding(channelID: .init(rawValue: "9")!,
            conversationID: .init(rawValue: "9")!, mappingRevision: "source")
        let config = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let bytes = Data(#"{"code":200,"data":{"list":[],"hasMore":false,"mutation_cursor":"7","sync_contract":"VISIBLE_ORDER_PLUS_MUTATIONS_V1","legacy_cache_action":"RELOAD_ON_RESUME"}}"#.utf8)
        for otherConversation in [false, true] {
            let bridge = NativeChannelMessageOriginalWireBridge(binding: binding, configuration: config,
                underlying: MessageOriginalHTTPFixture(bytes: bytes), current: { true })
            var request = try AuthRequestBuilder.makeFormRequest(url: config.baseURL.appendingPathComponent("api/im/messages"),
                fields: ["conversation_id": otherConversation ? "99" : "9", "cursor_id": "0", "size": "30"], token: "test-only-token")
            if !otherConversation { request.httpBody = request.httpBody.map { Data($0.dropLast(2)) } }
            let response = try await bridge.send(request)
            XCTAssertEqual(response.0, bytes)
            XCTAssertThrowsError(try bridge.consumedFullReplacement(messages: []))
        }
    }
}
