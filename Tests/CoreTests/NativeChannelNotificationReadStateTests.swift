import XCTest
@testable import QuestifyCore

final class NativeChannelNotificationReadStateTests: XCTestCase {
    private func row(_ id: String = "9", unread: Int64 = 7, mentions: Int64 = 2) -> [String: Any] {
        ["channel_id": id, "last_read_msg_id": "0", "unread": unread, "mention_count": mentions, "read_state_available": 1]
    }
    private func summary(_ rows: [[String: Any]]? = nil, scope: String? = nil) throws -> NativeChannelNotificationUnreadSummary {
        var value: [String: Any] = ["total": 0, "mention_count": 0, "has_mention": 0, "by_tab": ["dm": 0, "sys": 0, "channel": 0]]
        value["by_channel"] = rows; value["channel_scope"] = scope
        let result = try JSONDecoder().decode(NativeChannelNotificationUnreadSummary.self, from: JSONSerialization.data(withJSONObject: value))
        try result.validate(); return result
    }
    private func conversation(id: Int = 9, type: Int = 5, channel: Int? = 9) throws -> MessagingConversation {
        var value: [String: Any] = ["conversationId": id, "type": type, "unread": 11]
        if let channel { value["channel_id"] = channel; value["guild_id"] = 3; value["guild_kind"] = 1 }
        return try JSONDecoder().decode(MessagingConversation.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func testLegacySummaryDoesNotInventPerConversationZero() throws {
        let value = try summary()
        XCTAssertEqual(value.total, 0); XCTAssertNil(value.byChannel)
        XCTAssertNil(value.channelState(for: try conversation()))
    }
    func testExplicitOriginalSameKeyMappingUsesItsOwnCountsNotGlobalCounts() throws {
        let value = try summary([row()], scope: "CHANNEL_INDEX")
        let current = try XCTUnwrap(value.channelState(for: try conversation()))
        XCTAssertEqual(current.unread, 7); XCTAssertEqual(current.mentionCount, 2)
        XCTAssertEqual(value.total, 0); XCTAssertEqual(value.mentionCount, 0)
    }
    func testEqualIDsWithoutOriginalDirectoryMappingDoNotDisplay() throws {
        let value = try summary([row()], scope: "CHANNEL_INDEX")
        XCTAssertNil(value.channelState(for: try conversation(channel: nil)))
    }
    func testDifferentIDsWithDirectoryFieldsRemainUnsupportedByCanonicalSharedKeyContract() throws {
        let value = try summary([row()], scope: "CHANNEL_INDEX")
        // Current original ContextAdapter and backend use one shared primary key.
        // A future different-ID contract needs its real mapping adapter, not client inference.
        XCTAssertNil(value.channelState(for: try conversation(id: 99, channel: 9)))
    }
    func testDirectAndUnknownConversationKindsCannotBorrowChannelCounts() throws {
        let value = try summary([row()], scope: "CHANNEL_INDEX")
        for type in [1, 2, 3, 99] { XCTAssertNil(value.channelState(for: try conversation(type: type))) }
    }
    func testLegacyDefaultGroupMappingAndNewChannelMappingAreBothReadOnlySupported() throws {
        let value = try summary([row()], scope: "CHANNEL_INDEX")
        for type in [4, 5] { XCTAssertEqual(value.channelState(for: try conversation(type: type))?.channelID, "9") }
    }
    func testMutedRowsNeedNotSumToBadgeTotalsAndEmptyIndexIsNotMissingContract() throws {
        let value = try summary([row(unread: 100, mentions: 80)], scope: "CHANNEL_INDEX")
        XCTAssertEqual(value.byTab.channel, 0); XCTAssertEqual(value.byChannel?.first?.unread, 100)
        let empty = try summary([], scope: "CHANNEL_INDEX")
        XCTAssertEqual(empty.byChannel, []); XCTAssertNil(empty.channelState(channelID: "9"))
    }
    func testUnavailableStateRetainsNilCountsInsteadOfZero() throws {
        let value = try summary([["channel_id": "9", "read_state_available": 0]], scope: "CHANNEL_INDEX")
        XCTAssertEqual(value.byChannel?.first?.readStateAvailable, 0)
        XCTAssertNil(value.byChannel?.first?.unread); XCTAssertNil(value.byChannel?.first?.mentionCount)
        XCTAssertThrowsError(try summary([["channel_id": "9", "read_state_available": 0, "unread": 0]], scope: "CHANNEL_INDEX"))
    }
    func testMalformedRowsAndDuplicateIdentitiesAreRejectedNotCollapsed() throws {
        XCTAssertThrowsError(try summary([row(), row()], scope: "CHANNEL_INDEX"))
        XCTAssertThrowsError(try summary([row(unread: -1)], scope: "CHANNEL_INDEX"))
        XCTAssertThrowsError(try summary([row(mentions: -1)], scope: "CHANNEL_INDEX"))
        var missing = row(); missing.removeValue(forKey: "last_read_msg_id")
        XCTAssertThrowsError(try summary([missing], scope: "CHANNEL_INDEX"))
        XCTAssertThrowsError(try summary([row()], scope: "OTHER_INDEX"))
        XCTAssertThrowsError(try summary(nil, scope: "CHANNEL_INDEX"))
    }
    func testLargeIDsAndReadCursorsKeepExactDecimalStrings() throws {
        var large = row("9007199254740993"); large["last_read_msg_id"] = "9007199254740995"
        let value = try summary([large], scope: "CHANNEL_INDEX")
        XCTAssertEqual(value.byChannel?.first?.channelID, "9007199254740993")
        XCTAssertEqual(value.byChannel?.first?.lastReadMessageID, "9007199254740995")
        large["last_read_msg_id"] = "00"
        XCTAssertThrowsError(try summary([large], scope: "CHANNEL_INDEX"))
    }
}
