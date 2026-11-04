import XCTest
@testable import QuestifyCore

final class NativeChannelMessageProjectionIsolationTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }

    private func row(id: String = "41", version: Int = 1, kind: Int = 1, status: Int = 0) -> [String: Any] {
        ["id": id, "conversationId": "9", "version": version, "status": status,
         "msgType": kind, "senderId": "7", "senderType": 1, "senderName": "Member",
         "senderAvatar": "https://example.invalid/avatar.png", "content": "Current text",
         "extraJson": "{}", "pinned": false, "mention_everyone": false,
         "mentions": [["member_id": "8", "mention_type": "USER"]],
         "replyTo": ["id": "40", "state": "VISIBLE", "summary": "Earlier text", "senderId": "8"],
         "edited_at": "2026-11-04T00:00:00Z", "createTime": "2026-11-04T00:00:00Z"]
    }

    private func binding(_ revision: String = "mapping-1") throws -> NativeChannelMessageBinding {
        try .init(channelID: .init(rawValue: "9")!, conversationID: .init(rawValue: "9")!, mappingRevision: revision)
    }

    private func replace(_ projection: inout NativeChannelMessageProjection, cursor: String,
                         rows: [NativeChannelMessageSnapshot], binding: NativeChannelMessageBinding) throws {
        try projection.replacedHistory(mutationCursor: cursor, syncContract: "VISIBLE_ORDER_PLUS_MUTATIONS_V1",
                                       legacyCacheAction: "RELOAD_ON_RESUME", snapshots: rows, binding: binding)
    }

    private func recalledProjection() throws -> NativeChannelMessageProjection {
        var projection = NativeChannelMessageProjection()
        try replace(&projection, cursor: "10", rows: [decode(NativeChannelMessageSnapshot.self, row())], binding: binding())
        let page = try decode(NativeChannelMessageMutationPage.self,
            ["list": [["mutation_cursor": "11", "message_id": "41", "version": 2, "kind": "RECALL", "invalidate": true]],
             "has_more": false, "next_mutation_cursor": "11", "sync_contract": "VISIBLE_ORDER_PLUS_MUTATIONS_V1"])
        try projection.consume(page, binding: binding())
        return projection
    }

    func testUnknownKindsKeepOnlyPlaceholderIdentityAndNeverProjectActions() throws {
        for kind in [-1, 0, 16, Int.max] {
            let snapshot = try decode(NativeChannelMessageSnapshot.self, row(kind: kind))
            XCTAssertEqual(snapshot.kind, .unknown)
            XCTAssertEqual(snapshot.id.rawValue, "41")
            XCTAssertEqual(snapshot.conversationID.rawValue, "9")
            XCTAssertEqual(snapshot.version, 1)
            XCTAssertNil(snapshot.senderID); XCTAssertNil(snapshot.senderType)
            XCTAssertNil(snapshot.content); XCTAssertNil(snapshot.extraJSON); XCTAssertNil(snapshot.reply)
            XCTAssertNil(snapshot.editedAt); XCTAssertNil(snapshot.pinned)
            XCTAssertNil(snapshot.mentions); XCTAssertNil(snapshot.mentionEveryone)
            XCTAssertNil(snapshot.message.senderID); XCTAssertNil(snapshot.message.senderName)
            XCTAssertNil(snapshot.message.senderAvatar); XCTAssertNil(snapshot.message.content)
            XCTAssertNil(snapshot.message.extraJSON); XCTAssertNil(snapshot.message.card)
            XCTAssertTrue(IMCardAction.actions(for: snapshot.message).isEmpty)
            XCTAssertEqual(NativeChannelMessageAttachmentAvailability.project(snapshot), .sourceRequired(kind: .unknown))
        }
    }

    func testFuturePayloadAndMetadataShapesCannotPoisonHistoryPage() throws {
        var future = row(kind: 999)
        for key in ["senderId", "senderType", "senderName", "senderAvatar", "content", "extraJson",
                    "replyTo", "edited_at", "pinned", "mentions", "mention_everyone", "createTime"] {
            future[key] = ["future": ["payload": [1, 2, 3]]]
        }
        let history = try decode(NativeChannelMessageHistorySupplement.self,
            ["list": [row(id: "40"), future, row(id: "42")], "mutation_cursor": "12",
             "sync_contract": "VISIBLE_ORDER_PLUS_MUTATIONS_V1", "legacy_cache_action": "RELOAD_ON_RESUME"])
        XCTAssertEqual(history.list.map(\.id.rawValue), ["40", "41", "42"])
        XCTAssertEqual(history.list.map(\.kind), [.text, .unknown, .text])
        XCTAssertEqual(history.list[0].content, "Current text")
        XCTAssertEqual(history.list[2].message.senderName, "Member")
        XCTAssertNil(history.list[1].content); XCTAssertNil(history.list[1].message.createdAt)
    }

    func testUnknownKindStillRequiresValidEnvelopeIdentityVersionAndStatus() throws {
        for (key, value) in [("id", "01"), ("conversationId", "0"), ("version", "future"), ("status", "future")] {
            var invalid = row(kind: 999); invalid[key] = value
            XCTAssertThrowsError(try decode(NativeChannelMessageSnapshot.self, invalid))
        }
        var invalidVersion = row(kind: 999); invalidVersion["version"] = 0
        XCTAssertThrowsError(try decode(NativeChannelMessageSnapshot.self, invalidVersion))
    }

    func testKnownTextKeepsServerSenderQuoteAndMentionIdentity() throws {
        let snapshot = try decode(NativeChannelMessageSnapshot.self, row())
        XCTAssertEqual(snapshot.kind, .text)
        XCTAssertEqual(snapshot.senderID?.rawValue, "7")
        XCTAssertEqual(snapshot.senderType, 1)
        XCTAssertEqual(snapshot.message.senderName, "Member")
        XCTAssertEqual(snapshot.message.senderAvatar, "https://example.invalid/avatar.png")
        XCTAssertEqual(snapshot.reply?.senderId?.rawValue, "8")
        XCTAssertEqual(snapshot.mentions?.first?.member_id, "8")
        XCTAssertEqual(snapshot.pinned, false)
        XCTAssertEqual(snapshot.mentionEveryone, false)
    }

    func testKnownMessageMalformedMetadataStillFailsClosed() throws {
        for key in ["content", "senderId", "mentions", "pinned", "replyTo"] {
            var malformed = row(); malformed[key] = ["future": true]
            XCTAssertThrowsError(try decode(NativeChannelMessageSnapshot.self, malformed))
        }
    }

    func testRecalledAndUnknownStatusNeverDecodePayloadMetadata() throws {
        for status in [1, 999] {
            var hidden = row(status: status)
            for key in ["msgType", "senderId", "senderType", "content", "extraJson", "replyTo", "mentions", "pinned"] {
                hidden[key] = ["untrusted": true]
            }
            let snapshot = try decode(NativeChannelMessageSnapshot.self, hidden)
            XCTAssertNil(snapshot.content); XCTAssertNil(snapshot.reply); XCTAssertNil(snapshot.senderID)
            XCTAssertNil(snapshot.message.content)
            XCTAssertEqual(NativeChannelMessageAttachmentAvailability.project(snapshot), .withheld)
        }
    }

    func testHistoryStartedBeforeRecallCannotRollBackMutationFence() throws {
        var projection = try recalledProjection()
        let stale = try decode(NativeChannelMessageSnapshot.self, row())
        XCTAssertThrowsError(try replace(&projection, cursor: "10", rows: [stale], binding: binding()))
        XCTAssertEqual(projection.mutationCursor, "11")
        XCTAssertEqual(projection.versions[stale.id], 2)
        XCTAssertTrue(projection.withheld.contains(stale.id))
    }

    func testAdvancedHistoryCursorCannotSmuggleAnOlderMessageVersion() throws {
        var projection = try recalledProjection()
        let stale = try decode(NativeChannelMessageSnapshot.self, row())
        XCTAssertThrowsError(try replace(&projection, cursor: "12", rows: [stale], binding: binding()))
        XCTAssertEqual(projection.mutationCursor, "11")
        XCTAssertEqual(projection.versions[stale.id], 2)
        XCTAssertTrue(projection.withheld.contains(stale.id))
    }

    func testCurrentRecallReadAndRepeatedSnapshotAreAccepted() throws {
        var projection = try recalledProjection()
        let recalled = try decode(NativeChannelMessageSnapshot.self, row(version: 2, status: 1))
        try replace(&projection, cursor: "11", rows: [recalled], binding: binding())
        try replace(&projection, cursor: "11", rows: [recalled], binding: binding())
        XCTAssertEqual(projection.versions[recalled.id], 2)
        XCTAssertTrue(projection.withheld.contains(recalled.id))
    }

    func testRetirementAndNewBindingDoNotReuseAnotherProjectionFence() throws {
        let first = try decode(NativeChannelMessageSnapshot.self, row())
        var projection = try recalledProjection()
        projection.retire()
        try replace(&projection, cursor: "0", rows: [first], binding: binding())
        XCTAssertEqual(projection.mutationCursor, "0")
        XCTAssertTrue(projection.withheld.isEmpty)
        projection = try recalledProjection()
        try replace(&projection, cursor: "0", rows: [first], binding: binding("mapping-2"))
        XCTAssertEqual(projection.mutationCursor, "0")
        XCTAssertEqual(projection.versions[first.id], 1)
    }
}
