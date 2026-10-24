import XCTest
@testable import QuestifyCore

final class NativeChannelMessageActionEntryTests: XCTestCase {
    private let sendID = "c09-send-key-0001"
    private let editID = "c09-edit-key-0001"
    private let recallID = "c09-recall-key-001"
    private let pinID = "c09-pin-key-000001"

    func testFirstJourneyMessageActionSendEditRecallPinRecoverOriginal() throws {
        let entry = NativeChannelMessageActionEntry()
        let originalRequestID = sendID
        XCTAssertEqual(failure {
            try entry.send(requestID: originalRequestID, kind: .reply, actorID: 7, conversationID: 12, msgType: 1,
                           content: "hello", extraJSON: nil, replyToID: 88120, port: nil)
        }, .waitingSource(capability: ImmutableReceiptProducer.channelMessageSend))
        XCTAssertEqual(failure {
            try entry.edit(requestID: editID, kind: .edit, actorID: 7, conversationID: 12, messageID: 44,
                           content: "hello", expectedVersion: 2, port: nil)
        }, .waitingSource(capability: ImmutableReceiptProducer.channelMessageEdit))
        XCTAssertEqual(failure {
            try entry.recall(requestID: recallID, kind: .withdraw, actorID: 7, conversationID: 12, messageID: 44,
                             reason: nil, expectedVersion: 2, port: nil)
        }, .waitingSource(capability: ImmutableReceiptProducer.channelMessageRecall))
        XCTAssertEqual(failure {
            try entry.pin(requestID: pinID, kind: .pin, actorID: 7, conversationID: 12, messageID: 44,
                          pinned: true, port: nil)
        }, .waitingSource(capability: ImmutableReceiptProducer.channelMessagePin))

        var sends = 0
        var edits = 0
        var recalls = 0
        var pins = 0
        let sent = try entry.send(
            requestID: originalRequestID, kind: .reply, actorID: 7, conversationID: 12, msgType: 1,
            content: "hello", extraJSON: nil, replyToID: 88120,
            port: { actor, conversation, request, type, content, extra, replyTo, members, roles, everyone in
                sends += 1
                XCTAssertEqual(actor, 7)
                XCTAssertEqual(conversation, 12)
                XCTAssertEqual(request, originalRequestID)
                XCTAssertEqual(type, 1)
                XCTAssertEqual(content, "hello")
                XCTAssertNil(extra)
                XCTAssertEqual(replyTo, 88120)
                XCTAssertTrue(members.isEmpty)
                XCTAssertTrue(roles.isEmpty)
                XCTAssertFalse(everyone)
                return ["request_id": request, "message_id": 44]
            })
        let mentioned = try entry.send(
            requestID: "c09-mention-key-01", kind: .mention, actorID: 7, conversationID: 12, msgType: 1,
            content: "hello", extraJSON: nil, replyToID: nil, mentionEveryone: true,
            port: { _, _, request, _, _, _, _, _, _, everyone in
                sends += 1
                XCTAssertEqual(request, "c09-mention-key-01")
                XCTAssertTrue(everyone)
                return ["request_id": request, "message_id": 45]
            })
        let edited = try entry.edit(
            requestID: editID, kind: .edit, actorID: 7, conversationID: 12, messageID: 44,
            content: "hello", expectedVersion: 2,
            port: { _, _, message, request, content, version, _, _, _ in
                edits += 1
                XCTAssertEqual(message, 44)
                XCTAssertEqual(request, editID)
                XCTAssertEqual(content, "hello")
                XCTAssertEqual(version, 2)
                return ["request_id": request, "message_id": message]
            })
        let recalled = try entry.recall(
            requestID: recallID, kind: .withdraw, actorID: 7, conversationID: 12, messageID: 44,
            reason: " duplicate ", expectedVersion: 2,
            port: { _, _, message, request, reason, version in
                recalls += 1
                XCTAssertEqual(message, 44)
                XCTAssertEqual(request, recallID)
                XCTAssertEqual(reason, "duplicate")
                XCTAssertEqual(version, 2)
                return ["request_id": request, "message_id": message]
            })
        let pinned = try entry.pin(
            requestID: pinID, kind: .pin, actorID: 7, conversationID: 12, messageID: 44, pinned: false,
            port: { _, _, message, request, pinned in
                pins += 1
                XCTAssertEqual(message, 44)
                XCTAssertEqual(request, pinID)
                XCTAssertFalse(pinned)
                return ["request_id": request, "message_id": message, "pinned": false]
            })
        XCTAssertEqual(sends, 2)
        XCTAssertEqual(edits, 1)
        XCTAssertEqual(recalls, 1)
        XCTAssertEqual(pins, 1)
        for receipt in [sent, mentioned, edited, recalled, pinned] {
            XCTAssertEqual(receipt.outcome, ImmutableReceiptProducer.outcomeUnknown)
            XCTAssertNil(receipt.payloadHash)
            XCTAssertFalse(receipt.currentProjectionClaimsApplied)
            XCTAssertFalse(receipt.mintedNewRequest)
        }
        _ = try entry.send(
            requestID: originalRequestID, kind: .reply, actorID: 7, conversationID: 12, msgType: 1,
            content: "hello", extraJSON: nil, replyToID: 88120,
            port: { _, _, request, _, _, _, _, _, _, _ in
                sends += 1
                return ["request_id": request, "message_id": 44]
            })
        XCTAssertEqual(sends, 3)
        var idle = ImmutableReceiptProducer()
        let recovered = idle.recoverOriginal(originalRequestID: originalRequestID, projection: nil)
        XCTAssertEqual(recovered.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertNil(idle.originalByRequestID[originalRequestID])
    }

    func testMatchingRequestIDIsNotTrimmedIntoADifferentID() throws {
        let exact = sendID
        XCTAssertEqual(try ImmutableReceiptProducer.exactRequestID(exact), exact)
        let padded = " \(exact) "
        XCTAssertNotEqual(padded.trimmingCharacters(in: .whitespacesAndNewlines), padded)
        XCTAssertThrowsError(try ImmutableReceiptProducer.exactRequestID(padded)) { error in
            XCTAssertEqual(error as? NotifyFailure, .invalidRequestID)
        }
        let wide = String(repeating: "A", count: 32) + String(repeating: "b", count: 31) + "_"
        XCTAssertEqual(wide.count, 64)
        XCTAssertEqual(try ImmutableReceiptProducer.exactRequestID(wide), wide)
        XCTAssertThrowsError(try ImmutableReceiptProducer.exactRequestID(wide + "x")) { error in
            XCTAssertEqual(error as? NotifyFailure, .invalidRequestID)
        }
        XCTAssertThrowsError(try ImmutableReceiptProducer.exactRequestID(String(repeating: "a", count: 15))) { error in
            XCTAssertEqual(error as? NotifyFailure, .invalidRequestID)
        }

        let entry = NativeChannelMessageActionEntry()
        var seen: [String] = []
        XCTAssertThrowsError(try entry.send(
            requestID: padded, kind: .reply, actorID: 7, conversationID: 12, msgType: 1,
            content: "hello", extraJSON: nil, replyToID: 88120,
            port: { _, _, request, _, _, _, _, _, _, _ in
                seen.append(request)
                return ["request_id": request, "message_id": 44]
            })) { error in
            XCTAssertEqual(error as? NotifyFailure, .invalidRequestID)
        }
        XCTAssertTrue(seen.isEmpty)
        let sent = try entry.send(
            requestID: wide, kind: .reply, actorID: 7, conversationID: 12, msgType: 1,
            content: "hello", extraJSON: nil, replyToID: 88120,
            port: { _, _, request, _, _, _, _, _, _, _ in
                seen.append(request)
                return ["request_id": request, "message_id": 44]
            })
        XCTAssertEqual(seen, [wide])
        XCTAssertEqual(sent.requestId, wide)
        XCTAssertEqual(sent.outcome, ImmutableReceiptProducer.outcomeUnknown)
    }

    func testBlankContentIsInvalidAndDoesNotCallThePort() {
        let entry = NativeChannelMessageActionEntry()
        for content in [nil, "", " ", "\n", " \t "] {
            var calls = 0
            XCTAssertEqual(failure {
                try entry.send(requestID: sendID, kind: .reply, actorID: 7, conversationID: 12, msgType: 1,
                               content: content, extraJSON: nil, replyToID: 88120,
                               port: { _, _, _, _, _, _, _, _, _, _ in
                                   calls += 1
                                   return ["request_id": sendID, "message_id": 44]
                               })
            }, .invalidMessageContent)
            XCTAssertEqual(failure {
                try entry.edit(requestID: editID, kind: .edit, actorID: 7, conversationID: 12, messageID: 44,
                               content: content, expectedVersion: 2,
                               port: { _, _, _, _, _, _, _, _, _ in
                                   calls += 1
                                   return ["message_id": 44]
                               })
            }, .invalidMessageContent)
            XCTAssertEqual(calls, 0)
        }
    }

    func testReplayUnavailableWithoutMessageIDStaysUnknown() throws {
        let entry = NativeChannelMessageActionEntry()
        let unavailable = ["request_id": sendID, "message_unavailable": true] as [String: Any]
        let sent = try entry.send(
            requestID: sendID, kind: .reply, actorID: 7, conversationID: 12, msgType: 1,
            content: "hello", extraJSON: nil, replyToID: 88120,
            port: { _, _, request, _, _, _, _, _, _, _ in
                XCTAssertEqual(request, sendID)
                return unavailable
            })
        let edited = try entry.edit(
            requestID: editID, kind: .edit, actorID: 7, conversationID: 12, messageID: 44,
            content: "hello", expectedVersion: 2,
            port: { _, _, _, request, _, _, _, _, _ in
                ["request_id": request, "message_unavailable": true]
            })
        let recalled = try entry.recall(
            requestID: recallID, kind: .withdraw, actorID: 7, conversationID: 12, messageID: 44,
            reason: nil, expectedVersion: 2,
            port: { _, _, _, request, _, _ in
                ["request_id": request, "message_unavailable": true]
            })
        let pinned = try entry.pin(
            requestID: pinID, kind: .pin, actorID: 7, conversationID: 12, messageID: 44, pinned: true,
            port: { _, _, _, request, _ in
                ["request_id": request, "message_unavailable": true]
            })
        XCTAssertEqual(sent.requestId, sendID)
        XCTAssertNil(sent.payloadHash)
        for receipt in [sent, edited, recalled, pinned] {
            XCTAssertEqual(receipt.outcome, ImmutableReceiptProducer.outcomeUnknown)
            XCTAssertFalse(receipt.currentProjectionClaimsApplied)
        }
        var calls = 0
        XCTAssertThrowsError(try entry.send(
            requestID: sendID, kind: .reply, actorID: 7, conversationID: 12, msgType: 1,
            content: "hello", extraJSON: nil, replyToID: 88120,
            port: { _, _, _, _, _, _, _, _, _, _ in
                calls += 1
                throw NotifyFailure.invalidEnvironment
            }))
        XCTAssertEqual(calls, 1)
    }

    private func failure<T>(_ body: () throws -> T) -> NotifyFailure? {
        do { _ = try body(); return nil } catch let error as NotifyFailure { return error } catch { return nil }
    }
}
