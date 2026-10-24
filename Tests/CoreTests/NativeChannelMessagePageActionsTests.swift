import XCTest
@testable import QuestifyCore

final class NativeChannelMessagePageActionsTests: XCTestCase {
    private let sendID = "c09-send-key-0001"
    private let editID = "c09-edit-key-0001"
    private let recallID = "c09-recall-key-001"
    private let pinID = "c09-pin-key-000001"

    func testFirstJourneyChannelMessagePageSendEditRecallPinRecoverOriginal() throws {
        let page = NativeChannelMessagePageActions()
        let originalRequestID = sendID
        XCTAssertEqual(failure {
            try page.send(requestID: originalRequestID, kind: .reply, actorID: 7, conversationID: 12, msgType: 1,
                          content: "hello", extraJSON: nil, replyToID: 88120, port: nil)
        }, .waitingSource(capability: ImmutableReceiptProducer.channelMessageSend))
        XCTAssertEqual(failure {
            try page.edit(requestID: editID, kind: .edit, actorID: 7, conversationID: 12, messageID: 44,
                          content: "hello", expectedVersion: 2, port: nil)
        }, .waitingSource(capability: ImmutableReceiptProducer.channelMessageEdit))
        XCTAssertEqual(failure {
            try page.recall(requestID: recallID, kind: .withdraw, actorID: 7, conversationID: 12, messageID: 44,
                            reason: nil, expectedVersion: 2, port: nil)
        }, .waitingSource(capability: ImmutableReceiptProducer.channelMessageRecall))
        XCTAssertEqual(failure {
            try page.pin(requestID: pinID, kind: .pin, actorID: 7, conversationID: 12, messageID: 44,
                         pinned: true, port: nil)
        }, .waitingSource(capability: ImmutableReceiptProducer.channelMessagePin))

        var sends = 0
        var edits = 0
        var recalls = 0
        var pins = 0
        let sent = try page.send(
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
        let edited = try page.edit(
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
        let recalled = try page.recall(
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
        let pinned = try page.pin(
            requestID: pinID, kind: .pin, actorID: 7, conversationID: 12, messageID: 44, pinned: false,
            port: { _, _, message, request, pinned in
                pins += 1
                XCTAssertEqual(message, 44)
                XCTAssertEqual(request, pinID)
                XCTAssertFalse(pinned)
                return ["request_id": request, "message_id": message, "pinned": false]
            })
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(edits, 1)
        XCTAssertEqual(recalls, 1)
        XCTAssertEqual(pins, 1)
        for receipt in [sent, edited, recalled, pinned] {
            XCTAssertEqual(receipt.outcome, ImmutableReceiptProducer.outcomeUnknown)
            XCTAssertNil(receipt.payloadHash)
            XCTAssertFalse(receipt.currentProjectionClaimsApplied)
            XCTAssertFalse(receipt.mintedNewRequest)
        }
        XCTAssertEqual(sent.requestId, originalRequestID)
        XCTAssertEqual(edited.requestId, editID)
        XCTAssertEqual(recalled.requestId, recallID)
        XCTAssertEqual(pinned.requestId, pinID)
        _ = try page.send(
            requestID: originalRequestID, kind: .reply, actorID: 7, conversationID: 12, msgType: 1,
            content: "hello", extraJSON: nil, replyToID: 88120,
            port: { _, _, request, _, _, _, _, _, _, _ in
                sends += 1
                return ["request_id": request, "message_id": 44]
            })
        XCTAssertEqual(sends, 2)
        var idle = ImmutableReceiptProducer()
        let recovered = idle.recoverOriginal(originalRequestID: originalRequestID, projection: nil)
        XCTAssertEqual(recovered.outcome, ImmutableReceiptProducer.outcomeUnknown)
        XCTAssertNil(idle.originalByRequestID[originalRequestID])
        let labels = Mirror(reflecting: page).children.compactMap(\.label)
        XCTAssertFalse(labels.contains { $0.localizedCaseInsensitiveContains("receipt") || $0.localizedCaseInsensitiveContains("ledger") })
    }

    func testAppearanceDoesNotSend() {
        let page = NativeChannelMessagePageActions()
        var sends = 0
        page.appear()
        XCTAssertEqual(sends, 0)
        XCTAssertNil(failure {
            try page.send(requestID: sendID, kind: .reply, actorID: 7, conversationID: 12, msgType: 1,
                          content: "hello", extraJSON: nil, replyToID: 88120,
                          port: { _, _, _, _, _, _, _, _, _, _ in
                              sends += 1
                              return ["request_id": sendID, "message_id": 44]
                          })
        })
        XCTAssertEqual(sends, 1)
    }

    func testBlankContentIsInvalidAndDoesNotCallThePort() {
        let page = NativeChannelMessagePageActions()
        for content in [nil, "", " ", "\n", " \t "] {
            var calls = 0
            XCTAssertEqual(failure {
                try page.send(requestID: sendID, kind: .reply, actorID: 7, conversationID: 12, msgType: 1,
                              content: content, extraJSON: nil, replyToID: 88120,
                              port: { _, _, _, _, _, _, _, _, _, _ in
                                  calls += 1
                                  return ["request_id": sendID, "message_id": 44]
                              })
            }, .invalidMessageContent)
            XCTAssertEqual(failure {
                try page.edit(requestID: editID, kind: .edit, actorID: 7, conversationID: 12, messageID: 44,
                              content: content, expectedVersion: 2,
                              port: { _, _, _, _, _, _, _, _, _ in
                                  calls += 1
                                  return ["message_id": 44]
                              })
            }, .invalidMessageContent)
            XCTAssertEqual(calls, 0)
        }
    }

    func testRequestIDIsNotRewritten() throws {
        let page = NativeChannelMessagePageActions()
        let exact = sendID
        let padded = " \(exact) "
        var seen: [String] = []
        XCTAssertEqual(failure {
            try page.send(requestID: padded, kind: .reply, actorID: 7, conversationID: 12, msgType: 1,
                          content: "hello", extraJSON: nil, replyToID: 88120,
                          port: { _, _, request, _, _, _, _, _, _, _ in
                              seen.append(request)
                              return ["request_id": request, "message_id": 44]
                          })
        }, .invalidRequestID)
        XCTAssertTrue(seen.isEmpty)
        let wide = String(repeating: "A", count: 32) + String(repeating: "b", count: 31) + "_"
        let sent = try page.send(
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

    private func failure<T>(_ body: () throws -> T) -> NotifyFailure? {
        do { _ = try body(); return nil } catch let error as NotifyFailure { return error } catch { return nil }
    }
}
