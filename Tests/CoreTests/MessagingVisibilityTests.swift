import XCTest
@testable import QuestifyCore

final class MessagingVisibilityTests: XCTestCase {
    // Exact synthetic output from pinned server ImServiceImpl + actual Jackson.
    // Contains no real user messages. See docs/messaging-history-composition.md.
    private let actualServiceResponse = #"""
{
  "msg" : "操作成功",
  "code" : 200,
  "data" : {
    "nextCursor" : 101,
    "blocked" : false,
    "blockedByMe" : false,
    "hasMore" : true,
    "list" : [ {
      "createBy" : null,
      "createTime" : "2026-10-04 20:00:00",
      "updateBy" : null,
      "updateTime" : null,
      "remark" : null,
      "id" : 101,
      "conversationId" : 9,
      "senderId" : 0,
      "receiverId" : null,
      "msgType" : 1,
      "content" : "Synthetic recalled content",
      "extraJson" : null,
      "status" : 1,
      "checkStatus" : null,
      "clientMessageId" : null,
      "senderName" : null,
      "senderAvatar" : null
    } ]
  }
}
"""#
    private func row(status: Any?, type: Int = 3) throws -> MessagingMessage {
        var fields: [String: Any] = ["id": 101, "conversationId": 9, "senderId": 7,
            "senderName": "PRIVATE-SENDER", "senderAvatar": "https://private.example/avatar",
            "msgType": type, "content": "https://private.example/PRIVATE-PAYLOAD",
            "extraJson": #"{"cardType":"route","topicId":42,"pollId":31,"title":"PRIVATE-TITLE","buttons":[{"text":"PRIVATE-ACTION","action":"/topic/42"}],"result":{"outcome":"PRIVATE-RESULT"}}"#]
        if let status { fields["status"] = status }
        return try JSONDecoder().decode(MessagingMessage.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func assertWithheld(_ message: MessagingMessage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(message.isPayloadVisible, file: file, line: line)
        XCTAssertNil(message.content, file: file, line: line); XCTAssertNil(message.extraJSON, file: file, line: line)
        XCTAssertNil(message.type, file: file, line: line); XCTAssertNil(message.senderID, file: file, line: line)
        XCTAssertNil(message.senderName, file: file, line: line); XCTAssertNil(message.senderAvatar, file: file, line: line)
        XCTAssertNil(message.card, file: file, line: line); XCTAssertNil(message.pollReference, file: file, line: line)
        XCTAssertTrue(IMCardAction.actions(for: message).isEmpty, file: file, line: line)
        XCTAssertThrowsError(try SocialMessageMedia(message: message), file: file, line: line)
        XCTAssertFalse(String(reflecting: message).contains("PRIVATE-"), file: file, line: line)
    }
    func testActualServiceRecalledEnvelopeDiscardsContentBeforeProjection() throws {
        struct Envelope: Decodable { let data: MessagingPage }
        let page = try JSONDecoder().decode(Envelope.self, from: Data(actualServiceResponse.utf8)).data
        let recalled = try XCTUnwrap(page.messages.first)
        XCTAssertEqual(recalled.status, .recalled); XCTAssertEqual(recalled.id, 101); XCTAssertEqual(recalled.conversationID, 9)
        assertWithheld(recalled); XCTAssertFalse(String(reflecting: recalled).contains("Synthetic recalled content"))
        XCTAssertEqual(page.nextCursor, 101); XCTAssertTrue(page.hasMore)
    }
    func testRecalledBlockedUnknownMissingAndMalformedStatusNeverExposeAnyPayloadKind() throws {
        let statuses: [Any?] = [1, 2, -1, 99, nil, NSNull(), "0", true, 0.5]
        for status in statuses {
            for type in [1, 2, 3, 4, 99] { try assertWithheld(row(status: status, type: type)) }
        }
        XCTAssertEqual(try row(status: 1).status, .recalled)
        XCTAssertEqual(try row(status: 2).status, .blocked)
        XCTAssertEqual(try row(status: nil).status, .unknown)
    }
    func testExplicitNormalStatusPreservesTextImageCardAndPollProjections() throws {
        let text = try row(status: 0, type: 1)
        XCTAssertTrue(text.isPayloadVisible); XCTAssertEqual(text.status, .normal)
        XCTAssertEqual(text.senderID, 7); XCTAssertEqual(text.senderName, "PRIVATE-SENDER")
        XCTAssertEqual(text.content, "https://private.example/PRIVATE-PAYLOAD")
        XCTAssertNoThrow(try SocialMessageMedia(message: row(status: 0, type: 2)))
        XCTAssertEqual(try row(status: 0, type: 3).card?.topicID, 42)
        XCTAssertEqual(IMCardAction.actions(for: try row(status: 0, type: 3)).first?.destination, .topic(42))
        XCTAssertEqual(try row(status: 0, type: 4).pollReference?.pollID, 31)
    }
    func testConversationSummaryWithoutStatusProvenanceDiscardsPreviewEvenIfClaimedNormal() throws {
        for status in [0, 1, 99] {
            let object: [String: Any] = ["conversationId": 9, "type": 1, "unread": 2,
                "lastMsgText": "PRIVATE-PREVIEW", "lastMsgType": 1, "status": status,
                "counterparty": ["id": 7, "nickname": "Conversation name"]]
            let row = try JSONDecoder().decode(MessagingConversation.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNil(row.lastMessageText); XCTAssertNil(row.lastMessageType)
            XCTAssertFalse(String(reflecting: row).contains("PRIVATE-PREVIEW"))
            XCTAssertEqual(row.counterparty?.nickname, "Conversation name"); XCTAssertEqual(row.unread, 2)
        }
    }
    func testRefreshedRecalledRowAndHistoryResetCannotRetainOldVisiblePayload() throws {
        func page(_ status: Int, more: Bool = false) throws -> MessagingPage {
            let object: [String: Any] = ["list": [["id": 101, "conversationId": 9, "status": status,
                "msgType": 1, "content": "PRIVATE-PAYLOAD"]], "nextCursor": 42, "hasMore": more]
            return try JSONDecoder().decode(MessagingPage.self, from: JSONSerialization.data(withJSONObject: object))
        }
        var history = MessagingHistory(conversationID: 9)
        try history.replace(with: page(0, more: true)); XCTAssertNotNil(history.messages.first?.content)
        try history.prepend(page(1), requestedCursor: 42)
        assertWithheld(try XCTUnwrap(history.messages.first))
        XCTAssertFalse(String(reflecting: history).contains("PRIVATE-PAYLOAD"))
        try history.replace(with: page(1)); assertWithheld(try XCTUnwrap(history.messages.first))
        history = MessagingHistory(conversationID: 9); XCTAssertTrue(history.messages.isEmpty)
    }
}
