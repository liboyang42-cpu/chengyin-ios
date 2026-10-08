import SwiftUI
import UIKit
import XCTest
@testable import Questify

/// Exercise the production UI owners with synthetic writers. Apple execution required.
@MainActor final class IMConversationReplyPolicyAppTests: XCTestCase {
    private let identity = MessagingReadIdentity(accountID: 7, epoch: 1)
    private func policy(_ type: Int) throws -> IMConversationReplyPolicy {
        let row = try JSONDecoder().decode(MessagingConversation.self,
            from: Data("{\"conversationId\":9,\"type\":\(type)}".utf8))
        return .init(conversationID: 9, conversation: row)
    }
    private func textModel(_ writer: Writer) -> MessageComposerModel {
        let model = MessageComposerModel(.init(accountID: 7, conversationID: 9, writer: writer))
        model.observe(); return model
    }
    private func expandedModel(_ writer: Writer) throws -> IMExpandedViewModel {
        let model = IMExpandedViewModel(.init(scope: try IMScope(identity: identity, conversationID: 9), writer: writer))
        model.observe(); return model
    }
    private func route(_ model: IMExpandedViewModel) throws -> IMMutation {
        .send(try IMOutgoingIntent(scope: model.owner.scope, payload: .route(topicID: 11)))
    }
    func testSystemPolicyBlocksTextAndAllExpandedReplyReviewEntries() throws {
        let writer = Writer(), text = textModel(writer), expanded = try expandedModel(writer), system = try policy(2)
        XCTAssertNil(text.prepare(.send("hello"), identity: identity, canReply: system.permitsReply))
        XCTAssertFalse(expanded.review(try route(expanded), permits: system.permits))
        XCTAssertTrue(writer.texts.isEmpty); XCTAssertTrue(writer.mutations.isEmpty)
    }
    func testSystemReadMuteStillDispatchThroughExistingOwner() async throws {
        let writer = Writer(), model = try expandedModel(writer), system = try policy(2)
        for mutation in [IMMutation.read(conversationID: 9), .mute(conversationID: 9, muted: true)] {
            XCTAssertTrue(model.review(mutation, permits: system.permits))
            let token = try XCTUnwrap(model.prepare(.confirm, permits: system.permits))
            let accepted = await model.perform(token, permits: system.permits)
            XCTAssertTrue(accepted)
        }
        XCTAssertEqual(writer.mutations, [.read(conversationID: 9), .mute(conversationID: 9, muted: true)])
    }
    func testQueuedTextRevocationConsumesTokenWithoutRevival() async throws {
        let writer = Writer(), model = textModel(writer)
        let token = try XCTUnwrap(model.prepare(.send("hello"), identity: identity, canReply: true))
        let denied = await model.perform(token, canReply: { false })
        let restored = await model.perform(token, canReply: { true })
        XCTAssertFalse(denied); XCTAssertFalse(restored); XCTAssertTrue(writer.texts.isEmpty)
    }
    func testClosedOrReplacedTextAppearanceCannotDispatchOldToken() async throws {
        for reopen in [false, true] {
            let writer = Writer(), model = textModel(writer)
            let token = try XCTUnwrap(model.prepare(.send("hello"), identity: identity, canReply: true))
            model.retire(); if reopen { model.observe() }
            let accepted = await model.perform(token, canReply: { true })
            XCTAssertFalse(accepted); XCTAssertTrue(writer.texts.isEmpty)
        }
    }
    func testTextTokenCannotCrossSameAccountEpochChange() async throws {
        let writer = Writer(), model = textModel(writer)
        let token = try XCTUnwrap(model.prepare(.send("hello"), identity: identity, canReply: true))
        writer.identity = .init(accountID: 7, epoch: 2)
        let accepted = await model.perform(token, canReply: { true })
        XCTAssertFalse(accepted); XCTAssertTrue(writer.texts.isEmpty)
    }
    func testUnknownTextSurvivesCloseAndRetriesOnlyOriginalIDAfterNewTap() async throws {
        let writer = Writer(), model = textModel(writer)
        writer.fail = true
        let first = try XCTUnwrap(model.prepare(.send("original"), identity: identity, canReply: true))
        _ = await model.perform(first, canReply: { true })
        let clientID = try XCTUnwrap(model.coordinator.pendingClientMessageID)
        let retry = try XCTUnwrap(model.prepare(.retry(clientID), identity: identity, canReply: true))
        model.retire(); model.observe()
        _ = await model.perform(retry, canReply: { true })
        XCTAssertEqual(writer.texts.count, 1)
        XCTAssertEqual(model.coordinator.pendingText, "original")
        XCTAssertNil(model.prepare(.send("replacement"), identity: identity, canReply: true))
        XCTAssertNil(model.prepare(.retry(clientID), identity: identity, canReply: false))
        writer.fail = false
        let explicit = try XCTUnwrap(model.prepare(.retry(clientID), identity: identity, canReply: true))
        _ = await model.perform(explicit, canReply: { true })
        XCTAssertEqual(writer.texts.map(\.clientMessageID), [clientID, clientID])
        XCTAssertEqual(writer.texts.map(\.content), ["original", "original"])
    }
    func testDuplicateTextTokenCannotSendTwice() async throws {
        let writer = Writer(), model = textModel(writer)
        let token = try XCTUnwrap(model.prepare(.send("hello"), identity: identity, canReply: true))
        XCTAssertNil(model.prepare(.send("other"), identity: identity, canReply: true))
        _ = await model.perform(token, canReply: { true })
        _ = await model.perform(token, canReply: { true })
        XCTAssertEqual(writer.texts.count, 1)
    }
    func testLateTextCompletionDoesNotClearReopenedDraft() async throws {
        let writer = Writer(), model = textModel(writer)
        writer.suspend = true
        let started = expectation(description: "synthetic send starts")
        writer.onSuspend = { started.fulfill() }
        let token = try XCTUnwrap(model.prepare(.send("original"), identity: identity, canReply: true))
        let task = Task { await model.perform(token, canReply: { true }) }
        await fulfillment(of: [started], timeout: 2)
        model.retire(); model.observe(); model.draft = "new draft"
        writer.resume()
        let accepted = await task.value
        XCTAssertFalse(accepted); XCTAssertEqual(model.draft, "new draft")
        XCTAssertEqual(writer.texts.count, 1)
        if case .acknowledged = model.coordinator.visibleState {} else { XCTFail("The existing owner retains its definite receipt") }
    }
    func testQueuedExpandedReplyRevalidatesSystemPolicyAndCannotRevive() async throws {
        let writer = Writer(), model = try expandedModel(writer), normal = try policy(1), system = try policy(2)
        XCTAssertTrue(model.review(try route(model), permits: normal.permits))
        let token = try XCTUnwrap(model.prepare(.confirm, permits: normal.permits))
        _ = await model.perform(token, permits: system.permits)
        _ = await model.perform(token, permits: normal.permits)
        XCTAssertTrue(writer.mutations.isEmpty)
    }
    func testClosedAndReplacedExpandedAppearanceRejectOldConfirmation() async throws {
        let writer = Writer(), model = try expandedModel(writer), normal = try policy(1)
        XCTAssertTrue(model.review(try route(model), permits: normal.permits))
        let token = try XCTUnwrap(model.prepare(.confirm, permits: normal.permits))
        model.retire(); model.observe()
        XCTAssertTrue(model.review(try route(model), permits: normal.permits))
        _ = await model.perform(token, permits: normal.permits)
        XCTAssertTrue(writer.mutations.isEmpty)
    }
    func testExpandedUnknownIsNotReplacedBySystemReadAndRetryStaysExact() async throws {
        let writer = Writer(), model = try expandedModel(writer), normal = try policy(1), system = try policy(2)
        let original = try route(model); writer.fail = true
        XCTAssertTrue(model.review(original, permits: normal.permits))
        let first = try XCTUnwrap(model.prepare(.confirm, permits: normal.permits))
        _ = await model.perform(first, permits: normal.permits)
        model.retire(); model.observe()
        XCTAssertFalse(model.review(.read(conversationID: 9), permits: system.permits))
        XCTAssertNil(model.prepare(.retry, permits: system.permits))
        XCTAssertEqual(model.owner.visibleState, .outcomeUnknown(original))
        let retry = try XCTUnwrap(model.prepare(.retry, permits: normal.permits))
        writer.fail = false
        _ = await model.perform(retry, permits: normal.permits)
        XCTAssertEqual(writer.mutations, [original, original])
    }
    func testExpandedQueuedAccountChangeDoesNotDispatch() async throws {
        let writer = Writer(), model = try expandedModel(writer), normal = try policy(1)
        XCTAssertTrue(model.review(try route(model), permits: normal.permits))
        let token = try XCTUnwrap(model.prepare(.confirm, permits: normal.permits))
        writer.identity = .init(accountID: 7, epoch: 2)
        _ = await model.perform(token, permits: normal.permits)
        XCTAssertTrue(writer.mutations.isEmpty)
    }
    func testMediaQueuedSelectionRevokedOrClosedNeverOpensPicker() async throws {
        for close in [false, true] {
            let writer = Writer()
            let (model, picker) = try mediaModel(writer)
            let token = try XCTUnwrap(model.prepare(.select, canReply: true))
            if close { model.retire(); model.observe() }
            await model.perform(token, canReply: { close })
            await model.perform(token, canReply: { true })
            XCTAssertEqual(picker.selectionCount, 0); XCTAssertEqual(writer.uploads, 0)
        }
    }
    func testMediaQueuedUploadRevokedNeverWritesAndRequiresNewTap() async throws {
        let writer = Writer()
        let (model, _) = try mediaModel(writer)
        let select = try XCTUnwrap(model.prepare(.select, canReply: true))
        await model.perform(select, canReply: { true })
        let upload = try XCTUnwrap(model.prepare(.upload, canReply: true))
        await model.perform(upload, canReply: { false })
        await model.perform(upload, canReply: { true })
        XCTAssertEqual(writer.uploads, 0)
        let next = try XCTUnwrap(model.prepare(.upload, canReply: true))
        await model.perform(next, canReply: { true })
        XCTAssertEqual(writer.uploads, 1)
    }
    func testNormalMediaChildReturnsLocalReviewWithoutParentAppearanceOrAutomaticSend() async throws {
        let writer = Writer(), expanded = try expandedModel(writer), normal = try policy(1)
        expanded.retire() // Normal NavigationLink makes the controls parent disappear.
        let (media, _) = try mediaModel(writer)
        let select = try XCTUnwrap(media.prepare(.select, canReply: true)); await media.perform(select, canReply: { true })
        let upload = try XCTUnwrap(media.prepare(.upload, canReply: true)); await media.perform(upload, canReply: { true })
        let url = URL(string: "https://example.test/image.jpg")!
        XCTAssertFalse(media.apply(url, canReply: false, consume: { _ in XCTFail(); return true }))
        let applied = media.apply(url, canReply: normal.permitsReply) { url in
            guard let intent = try? IMOutgoingIntent(scope: expanded.owner.scope, payload: .image(url)) else { return false }
            return expanded.owner.review(.send(intent))
        }
        XCTAssertTrue(applied); XCTAssertTrue(writer.mutations.isEmpty)
        expanded.observe()
        if case .reviewing(.send(_)) = expanded.state {} else { XCTFail("Return must show the image review") }
        media.retire()
        XCTAssertFalse(media.apply(url, canReply: true, consume: { _ in XCTFail(); return true }))
    }
    func testRetainedTextClosureRechecksLatestPolicyLeaseWithoutLifecycleCleanup() async throws {
        let writer = Writer(), model = textModel(writer), reader = Reader(), gate = IMConversationReplyAuthority()
        let normal = try policy(1), system = try policy(2)
        let lease = gate.bind(reader: reader, policy: normal, ready: true)
        let retained = { gate.permitsReply(lease) }
        let token = try XCTUnwrap(model.prepare(.send("old snapshot"), identity: identity, canReply: retained()))
        _ = gate.bind(reader: reader, policy: system, ready: true)
        XCTAssertFalse(retained())
        _ = await model.perform(token, canReply: retained)
        _ = gate.bind(reader: reader, policy: normal, ready: true)
        XCTAssertFalse(retained())
        _ = await model.perform(token, canReply: retained)
        XCTAssertTrue(writer.texts.isEmpty)
    }
    func testRetainedExpandedClosureCannotAdoptReplacementReaderWithSameIdentity() async throws {
        let writer = Writer(), model = try expandedModel(writer), reader = Reader(), replacement = Reader()
        let gate = IMConversationReplyAuthority(), normal = try policy(1)
        let lease = gate.bind(reader: reader, policy: normal, ready: true)
        let retained: (IMMutation) -> Bool = { gate.isCurrent(lease) && normal.permits($0) }
        XCTAssertTrue(model.review(try route(model), permits: retained))
        let token = try XCTUnwrap(model.prepare(.confirm, permits: retained))
        _ = gate.bind(reader: replacement, policy: normal, ready: true)
        _ = await model.perform(token, permits: retained)
        XCTAssertTrue(writer.mutations.isEmpty)
    }
    func testRetainedMediaClosureAndReadLeaseRejectRevokedHistory() async throws {
        let writer = Writer(), reader = Reader(), gate = IMConversationReplyAuthority(), normal = try policy(1)
        let (model, picker) = try mediaModel(writer)
        let lease = gate.bind(reader: reader, policy: normal, ready: true)
        let retained = { gate.permitsReply(lease) }
        let token = try XCTUnwrap(model.prepare(.select, canReply: retained()))
        // Shipping reload/terminal failure invalidates synchronously before rerender.
        gate.invalidate()
        XCTAssertFalse(gate.isCurrent(lease))
        await model.perform(token, canReply: retained)
        XCTAssertEqual(picker.selectionCount, 0); XCTAssertEqual(writer.uploads, 0)
        let active = gate.bind(reader: reader, policy: normal, ready: true)
        XCTAssertTrue(gate.isCurrent(active))
        reader.isConfigured = false
        XCTAssertFalse(gate.isCurrent(active))
    }
    func testSystemAuthorityKeepsReadLeaseAndOnlyLatestRenderCanReply() throws {
        let reader = Reader(), gate = IMConversationReplyAuthority()
        let system = try policy(2), normal = try policy(1)
        let systemLease = gate.bind(reader: reader, policy: system, ready: true)
        XCTAssertTrue(gate.isCurrent(systemLease)); XCTAssertFalse(gate.permitsReply(systemLease))
        let normalLease = gate.bind(reader: reader, policy: normal, ready: true)
        XCTAssertFalse(gate.isCurrent(systemLease)); XCTAssertTrue(gate.permitsReply(normalLease))
        XCTAssertEqual(normalLease, gate.bind(reader: reader, policy: normal, ready: true))
        reader.identity = .init(accountID: 7, epoch: 2)
        XCTAssertFalse(gate.isCurrent(normalLease))
    }
    @MainActor private final class Reader: MessagingReading {
        var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
        var isConfigured = true
        func messagingConversations() async throws -> [MessagingConversation] { throw APIError.notConfigured }
        func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage { throw APIError.notConfigured }
    }
    private func mediaModel(_ writer: Writer) throws -> (IMUploadViewModel, IMFixtureImagePicker) {
        let scope = try IMScope(identity: identity, conversationID: 9)
        let selection = try IMMediaSelection(scope: scope, bytes: Data([255, 216, 255]), mimeType: "image/jpeg", fileExtension: "jpg")
        let picker = IMFixtureImagePicker(selection: selection)
        let storage = Storage()
        let journal = StoredImageUploadJournal(read: { storage.data[$0] }, write: { storage.data[$1] = $0 })
        let target = try ImageUploadTarget(accountID: 7, namespace: "synthetic", realm: "https://example.test", kind: "im", entityID: 9, field: "image")
        let owner = IMImageUploadCoordinator(scope: scope, writer: writer, picker: picker, journal: journal, target: target)
        let model = IMUploadViewModel(owner); model.observe(); return (model, picker)
    }
    @MainActor private final class Storage { var data: [String: Data] = [:] }
    @MainActor private final class Writer: MessageActionWriting, IMExpandedWriting {
        var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
        var isConfigured = true, fail = false, suspend = false
        var texts: [MessageTextIntent] = [], mutations: [IMMutation] = []
        var uploads = 0
        var onSuspend: (() -> Void)?
        private var continuation: CheckedContinuation<Void, Never>?
        func resume() { let pending = continuation; continuation = nil; pending?.resume() }
        func send(_ intent: MessageTextIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage {
            texts.append(intent)
            if suspend { await withCheckedContinuation { continuation = $0; onSuspend?() } }
            if fail { throw URLError(.timedOut) }
            return try message(intent.content)
        }
        func perform(_ mutation: IMMutation, expectedIdentity: MessagingReadIdentity) async throws -> IMMutationReceipt {
            mutations.append(mutation)
            if fail { throw URLError(.timedOut) }
            switch mutation {
            case .read: return .read
            case .mute(_, let muted): return .muted(muted)
            case .send: return .sent(try message("card"))
            case .start: return .started(conversationID: 9)
            }
        }
        func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, expectedIdentity: MessagingReadIdentity) async throws -> URL {
            uploads += 1; return URL(string: "https://example.test/image.jpg")!
        }
        private func message(_ text: String) throws -> MessagingMessage {
            try JSONDecoder().decode(MessagingMessage.self, from: JSONSerialization.data(withJSONObject:
                ["id": 10, "conversationId": 9, "senderId": 7, "status": 0, "msgType": 1, "content": text]))
        }
    }
}
