import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class MessagingHistoryReadApprovalTests: XCTestCase {
    private func context(account: Int = 7, epoch: UInt64 = 1, role: String = "player", namespace: String = "synthetic-realm-A", base: String = "https://example.test/native", token: String = "synthetic-7", market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: URL(string: base)!, role: role,
            session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    func testFullContextExpiryAndIrreversibleRevocation() throws {
        let original = try context(), deadline = Date().addingTimeInterval(600)
        let lease = try MessagingHistoryReadApproval(context: original, expiresAt: deadline)
        XCTAssertTrue(lease.matches(original))
        for changed in [try context(account: 8), try context(epoch: 2), try context(role: "merchant"),
                        try context(namespace: "synthetic-realm-B"), try context(base: "https://other.test/native"),
                        try context(base: "https://example.test/other"), try context(token: "rotated"), try context(market: .unitedStates)] {
            XCTAssertFalse(lease.matches(changed))
        }
        XCTAssertFalse(lease.matches(original, now: deadline)); lease.expireIfNeeded(now: deadline)
        XCTAssertTrue(lease.isRevoked); XCTAssertFalse(lease.matches(original, now: deadline.addingTimeInterval(-1)))
        XCTAssertThrowsError(try MessagingHistoryReadApproval(context: context(base: "http://example.test"), expiresAt: deadline))
        XCTAssertThrowsError(try MessagingHistoryReadApproval(context: context(role: "admin"), expiresAt: deadline))
        XCTAssertThrowsError(try MessagingHistoryReadApproval(context: context(market: .unitedStates), expiresAt: deadline))
    }
    func testCanonicalFormsAndMalformedBodiesAreRejectedWithoutTraps() throws {
        let base = try context().baseURL
        func form(_ path: String, _ fields: [String: String]) throws -> URLRequest {
            try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/im/" + path), fields: fields, token: "synthetic-7", boundary: "BOUNDARY")
        }
        let list = try form("conversations", [:])
        let messages = try form("messages", ["conversation_id": "901", "cursor_id": "0", "size": "30"])
        XCTAssertEqual(MessagingHistoryReadRoute(request: list, baseURL: base), .conversations)
        XCTAssertEqual(MessagingHistoryReadRoute(request: messages, baseURL: base), .messages(conversationID: 901, cursor: 0, size: 30))
        for field in ["conversation_id", "cursor_id", "size"] {
            for value in ["", "-1", "01", "+1", "1.0", "true", " 1", "999999999999999999999999"] {
                var fields = ["conversation_id": "901", "cursor_id": "0", "size": "30"]; fields[field] = value
                XCTAssertNil(MessagingHistoryReadRoute(request: try form("messages", fields), baseURL: base))
            }
        }
        for fields in [["member_id": "7"], ["conversation_id": "901"], ["conversation_id": "901", "cursor_id": "0", "size": "51"], ["conversation_id": "901", "cursor_id": "0", "size": "30", "member_id": "7"]] {
            XCTAssertNil(MessagingHistoryReadRoute(request: try form("messages", fields), baseURL: base))
        }
        for path in ["read", "send", "start", "mute", "delete", "block", "unblock", "report", "unread-total"] {
            XCTAssertNil(MessagingHistoryReadRoute(request: try form(path, [:]), baseURL: base))
        }
        var invalid = [URLRequest]()
        let body = try XCTUnwrap(messages.httpBody)
        // Every truncation, reversed/missing delimiter, duplicate field and trailing byte.
        for count in 0..<body.count { var request = messages; request.httpBody = Data(body.prefix(count)); invalid.append(request) }
        for text in ["\r\nContent-Disposition: form-data; name=\"size\"", String(decoding: body, as: UTF8.self) + "x", String(decoding: body, as: UTF8.self).replacingOccurrences(of: "--BOUNDARY--", with: "--BOUNDARY\r\nContent-Disposition: form-data; name=\"size\"\r\n\r\n30\r\n--BOUNDARY--")] {
            var request = messages; request.httpBody = Data(text.utf8); invalid.append(request)
        }
        for request in invalid { XCTAssertNil(MessagingHistoryReadRoute(request: request, baseURL: base)) }
    }
}
