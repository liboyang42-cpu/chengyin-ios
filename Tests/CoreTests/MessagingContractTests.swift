import XCTest
@testable import QuestifyCore

final class MessagingContractTests: XCTestCase {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    func testConversationKindsMatchSourceSystemTwoMerchantThree() throws {
        XCTAssertEqual(MessagingConversationKind(rawValue: 1), .direct)
        XCTAssertEqual(MessagingConversationKind(rawValue: 2), .system)
        XCTAssertEqual(MessagingConversationKind(rawValue: 3), .merchant)
        XCTAssertEqual(MessagingConversationKind(rawValue: 4), .group)
        XCTAssertEqual(MessagingConversationKind(rawValue: nil), .unknown)
        XCTAssertEqual(MessagingConversationKind(rawValue: 99), .unknown)
    }
    func testConversationWireNamesAndNullableFacts() throws {
        let row = try decode(MessagingConversation.self, #"{"conversationId":12,"type":4,"counterparty":{"id":8,"nickname":"Fixture group","avatar":"synthetic image","bizKey":"club_7"},"lastMsgType":2,"lastMsgText":"literal preview","lastMsgAt":"2026-10-01 10:00:00","unread":4,"muted":"1"}"#)
        XCTAssertEqual(row.id, 12)
        XCTAssertEqual(row.kind, .group)
        XCTAssertEqual(row.counterparty?.bizKey, "club_7")
        XCTAssertNil(row.lastMessageType)
        XCTAssertNil(row.lastMessageText)
        XCTAssertEqual(row.lastMessageAt, "2026-10-01 10:00:00")
        XCTAssertEqual(row.unread, 4)
        XCTAssertEqual(row.muted, true)
        let missing = try decode(MessagingConversation.self, #"{"conversationId":12}"#)
        XCTAssertNil(missing.counterparty)
        XCTAssertNil(missing.unread)
        XCTAssertNil(missing.muted)
        XCTAssertEqual(missing.kind, .unknown)
    }
    func testMutedDoesNotGuessBooleanOrUnknownValue() throws {
        for (value, expected) in [("0", false), ("1", true), (#""0""#, false), (#""1""#, true)] {
            let row = try decode(MessagingConversation.self, "{\"conversationId\":1,\"muted\":\(value)}")
            XCTAssertEqual(row.muted, expected)
        }
        for value in ["true", "false", "2", "null", #""yes""#, "{}"] {
            XCTAssertNil(try decode(MessagingConversation.self, "{\"conversationId\":1,\"muted\":\(value)}").muted)
        }
    }
    func testInvalidConversationIDAndNegativeUnreadFailClosed() {
        for json in [#"{"conversationId":0}"#, #"{"conversationId":-1}"#, #"{"conversationId":"1"}"#, #"{}"#, #"{"conversationId":1,"unread":-1}"#] {
            XCTAssertThrowsError(try decode(MessagingConversation.self, json))
        }
    }
    func testSourceScopesKeepMerchantDirectAndSystemOnlyAll() throws {
        let rows = try decode([MessagingConversation].self, #"[{"conversationId":1,"type":1},{"conversationId":2,"type":2},{"conversationId":3,"type":3},{"conversationId":4,"type":4},{"conversationId":9,"type":99}]"#)
        XCTAssertEqual(rows.filter(MessagingConversationScope.all.includes).map(\.id), [1, 2, 3, 4, 9])
        XCTAssertEqual(rows.filter(MessagingConversationScope.direct.includes).map(\.id), [1, 3])
        XCTAssertEqual(rows.filter(MessagingConversationScope.channels.includes).map(\.id), [4])
    }
    func testMessageRetainsGroupSenderAndUnknownTypeWithoutInferringOwnership() throws {
        let row = try decode(MessagingMessage.self, #"{"id":8,"conversationId":2,"senderId":17,"senderName":"Fixture sender","senderAvatar":"synthetic image","status":0,"msgType":99,"content":"<script>literal</script>","createTime":"2026-10-01 10:00:00"}"#)
        XCTAssertEqual(row.senderID, 17)
        XCTAssertEqual(row.senderName, "Fixture sender")
        XCTAssertEqual(row.type, 99)
        XCTAssertEqual(row.content, "<script>literal</script>")
        XCTAssertNil(row.card)
        let missing = try decode(MessagingMessage.self, #"{"id":8,"conversationId":2}"#)
        XCTAssertNil(missing.senderID)
        XCTAssertNil(missing.type)
        let system = try decode(MessagingMessage.self, #"{"id":8,"conversationId":2,"status":0,"senderId":0}"#)
        XCTAssertEqual(system.senderID, 0)
    }
    func testMessageRejectsMissingOrInvalidRecordScope() {
        for json in [#"{"id":0,"conversationId":2}"#, #"{"id":8,"conversationId":0}"#, #"{"id":8}"#, #"{"id":8,"conversationId":2,"status":0,"senderId":-1}"#] {
            XCTAssertThrowsError(try decode(MessagingMessage.self, json))
        }
    }
    func testHistoryEnvelopeRequiresValidCollectionAndCursorContract() throws {
        let empty = try decode(MessagingPage.self, #"{"list":[],"hasMore":false,"nextCursor":0}"#)
        XCTAssertTrue(empty.messages.isEmpty)
        XCTAssertFalse(empty.hasMore)
        let partial = try decode(MessagingPage.self, #"{"list":[],"hasMore":true,"nextCursor":42}"#)
        XCTAssertEqual(partial.nextCursor, 42)
        for json in [#"{}"#, #"{"list":null,"hasMore":false}"#, #"{"list":[],"hasMore":1}"#, #"{"list":[],"hasMore":true}"#, #"{"list":[],"hasMore":true,"nextCursor":0}"#, #"{"list":[],"hasMore":false,"nextCursor":-1}"#, #"{"list":[],"hasMore":true,"nextCursor":"42"}"#] {
            XCTAssertThrowsError(try decode(MessagingPage.self, json))
        }
    }
    func testCardsUseOnlySourceDisplayProjection() throws {
        let location = try XCTUnwrap(MessagingCard.parse(#"{"cardType":"location","name":"Fixture point","address":"Synthetic address","lat":"0","lng":0}"#, fallbackTitle: nil))
        XCTAssertEqual(location.kind, .location)
        XCTAssertEqual(location.latitude, 0)
        XCTAssertEqual(location.longitude, 0)
        XCTAssertEqual(location.address, "Synthetic address")
        let route = try XCTUnwrap(MessagingCard.parse(#"{"cardType":"route","topicId":"17"}"#, fallbackTitle: nil))
        XCTAssertEqual(route.kind, .route)
        XCTAssertEqual(route.topicID, 17)
        let signup = try XCTUnwrap(MessagingCard.parse(#"{"cardType":"signup","topicId":19}"#, fallbackTitle: nil))
        XCTAssertEqual(signup.kind, .signup)
        let actionOnly = try XCTUnwrap(MessagingCard.parse(#"{"cardType":"route","action":"/untrusted/source/path"}"#, fallbackTitle: nil))
        XCTAssertEqual(actionOnly.kind, .route)
        XCTAssertNil(actionOnly.topicID)
    }
    func testGenericCardFallbackLabelsAndResultAreLiteralData() throws {
        let card = try XCTUnwrap(MessagingCard.parse(#"{"sub":"<b>Literal</b>","buttons":[{"text":"Review","action":"/untrusted","key":"write"},{"text":""}],"result":{"taskId":12,"bizId":"SYNTHETIC","outcome":"Fixture outcome","reason":"Fixture reason","followUp":"Fixture next step"}}"#, fallbackTitle: "Fallback content"))
        XCTAssertEqual(card.kind, .generic)
        XCTAssertEqual(card.title, "Fallback content")
        XCTAssertEqual(card.subtitle, "<b>Literal</b>")
        XCTAssertEqual(card.buttonLabels, ["Review"])
        XCTAssertEqual(card.result?.taskID, "12")
        XCTAssertEqual(card.result?.businessID, "SYNTHETIC")
        XCTAssertEqual(card.result?.followUp, "Fixture next step")
        XCTAssertNil(MessagingCard.parse(#"{"result":{}}"#, fallbackTitle: nil))
        XCTAssertEqual(MessagingCard.parse(#"{"cardType":"future","title":"Literal"}"#, fallbackTitle: nil)?.kind, .generic)
    }
    func testMalformedCardNeverDestroysTranscriptAndCoordinatesFailSafely() throws {
        for json in ["", "[]", "null", "broken", "{}", #"{"cardType":"route","topicId":0}"#, #"{"cardType":"location","lat":91,"lng":0}"#, #"{"cardType":"location","lat":true,"lng":0}"#] {
            XCTAssertNil(MessagingCard.parse(json, fallbackTitle: nil), json)
        }
        let named = try XCTUnwrap(MessagingCard.parse(#"{"cardType":"location","name":"Fixture name","lat":999,"lng":0}"#, fallbackTitle: nil))
        XCTAssertEqual(named.title, "Fixture name")
        XCTAssertNil(named.latitude)
        XCTAssertNil(named.longitude)
        let message = try decode(MessagingMessage.self, #"{"id":1,"conversationId":2,"status":0,"msgType":3,"extraJson":"broken"}"#)
        XCTAssertNil(message.card)
    }
}
