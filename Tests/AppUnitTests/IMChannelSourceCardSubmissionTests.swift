import Foundation
import XCTest
@testable import Questify

/// Synthetic owner tests. Never opens MapKit, records, uploads, or accesses a server.
@MainActor final class IMChannelSourceCardSubmissionTests: XCTestCase {
    private func model(_ writer: SourceCardWriter, location: Bool) throws -> (IMExpandedViewModel, IMMutation) {
        let scope = try IMScope(identity: .init(accountID: 7, epoch: 1), conversationID: 9)
        let payload: IMOutgoingPayload = location
            ? .staticLocation(try .init(name: "Fixture", address: "", latitude: 31, longitude: 121, datum: "WGS84"))
            : .route(topicID: 11)
        let model = IMExpandedViewModel(try IMExpandedCoordinator(scope: scope, writer: writer))
        model.observe()
        return (model, .send(try IMOutgoingIntent(scope: scope, payload: payload)))
    }
    func testSourceCardConfirmationPublishesAcknowledgedOnlyThroughCurrentTicket() async throws {
        for location in [false, true] {
            let writer = SourceCardWriter(), (model, mutation) = try self.model(writer, location: location)
            XCTAssertTrue(model.review(mutation, permits: { _ in true }))
            let token = try XCTUnwrap(model.prepare(.confirm, permits: { _ in true }))
            let accepted = await model.perform(token, permits: { _ in true })
            XCTAssertTrue(accepted)
            guard case .acknowledged(.sent) = model.state else { return XCTFail("The visible owner lost its confirmed source-card result") }
            XCTAssertEqual(writer.mutations, [mutation])
        }
    }
    func testReceiptOnlySourceCardRecoveryKeepsOriginalAndDoesNotRequireSEND() async throws {
        for location in [false, true] {
            let writer = SourceCardWriter(), (model, mutation) = try self.model(writer, location: location)
            writer.fail = true
            XCTAssertTrue(model.review(mutation, permits: { _ in true }))
            let original = try XCTUnwrap(model.prepare(.confirm, permits: { _ in true }))
            _ = await model.perform(original, permits: { _ in true })
            guard case .outcomeUnknown(let pending) = model.state else { return XCTFail("Expected original unknown result") }
            XCTAssertEqual(pending, mutation)
            writer.fail = false; writer.isConfigured = false
            let receipt = try XCTUnwrap(model.prepare(location ? .recoverStaticLocation : .recoverRoute, permits: { _ in true }))
            let accepted = await model.perform(receipt, permits: { _ in true })
            XCTAssertTrue(accepted); XCTAssertEqual(writer.mutations, [mutation])
            guard case .send(let intent) = mutation else { return XCTFail("Expected source card") }
            XCTAssertEqual(writer.reads, [intent])
            guard case .acknowledged(.sent) = model.state else { return XCTFail("Receipt result was hidden from the current presentation") }
        }
    }
    func testQueuedSourceCardReceiptCannotRunAfterDisappearAndReappearance() async throws {
        for location in [false, true] {
            let writer = SourceCardWriter(), (model, mutation) = try self.model(writer, location: location)
            writer.fail = true; XCTAssertTrue(model.review(mutation, permits: { _ in true }))
            let send = try XCTUnwrap(model.prepare(.confirm, permits: { _ in true }))
            _ = await model.perform(send, permits: { _ in true })
            let receipt = try XCTUnwrap(model.prepare(location ? .recoverStaticLocation : .recoverRoute, permits: { _ in true }))
            model.retire(); model.observe(); writer.fail = false
            let accepted = await model.perform(receipt, permits: { _ in true })
            XCTAssertFalse(accepted); XCTAssertTrue(writer.reads.isEmpty); XCTAssertEqual(writer.mutations, [mutation])
        }
    }
    func testLateSourceCardReceiptCannotReviveReopenedPresentation() async throws {
        for location in [false, true] {
            let writer = SourceCardWriter(), (model, mutation) = try self.model(writer, location: location)
            writer.fail = true; XCTAssertTrue(model.review(mutation, permits: { _ in true }))
            let send = try XCTUnwrap(model.prepare(.confirm, permits: { _ in true }))
            _ = await model.perform(send, permits: { _ in true }); writer.fail = false; writer.suspendRead = true
            let receipt = try XCTUnwrap(model.prepare(location ? .recoverStaticLocation : .recoverRoute, permits: { _ in true }))
            let started = expectation(description: "synthetic receipt")
            writer.onSuspend = { started.fulfill() }
            let task = Task { await model.perform(receipt, permits: { _ in true }) }
            await fulfillment(of: [started], timeout: 2)
            model.retire(); model.observe(); let appearance = model.appearance, state = model.state
            writer.resume(); let accepted = await task.value
            XCTAssertFalse(accepted); XCTAssertEqual(model.appearance, appearance); XCTAssertEqual(model.state, state)
            XCTAssertEqual(writer.mutations, [mutation]); XCTAssertEqual(writer.reads.count, 1)
        }
    }
    func testCancelledRouteRetryCannotSendAfterSuspendedReadSentReturns() async throws {
        let writer = SourceCardWriter(), (model, mutation) = try self.model(writer, location: false)
        writer.fail = true; XCTAssertTrue(model.review(mutation, permits: { _ in true }))
        let first = try XCTUnwrap(model.prepare(.confirm, permits: { _ in true }))
        _ = await model.perform(first, permits: { _ in true }); writer.fail = false; writer.suspendRead = true
        let retry = try XCTUnwrap(model.prepare(.retry, permits: { _ in true }))
        let started = expectation(description: "readSent before same-intent retry")
        writer.onSuspend = { started.fulfill() }
        let task = Task { await model.perform(retry, permits: { _ in true }) }
        await fulfillment(of: [started], timeout: 2)
        task.cancel(); model.retire(); model.observe(); writer.resume()
        let accepted = await task.value
        XCTAssertFalse(accepted); XCTAssertEqual(writer.mutations, [mutation]); XCTAssertEqual(writer.readSentCount, 1)
    }
    func testCancelledReceiptKeepsOriginalUnknownInsteadOfReopenedOwnerSubmitting() async throws {
        for location in [false, true] {
            let writer = SourceCardWriter(), (model, mutation) = try self.model(writer, location: location)
            writer.fail = true; XCTAssertTrue(model.review(mutation, permits: { _ in true }))
            let first = try XCTUnwrap(model.prepare(.confirm, permits: { _ in true }))
            _ = await model.perform(first, permits: { _ in true }); writer.fail = false; writer.suspendRead = true
            let receipt = try XCTUnwrap(model.prepare(location ? .recoverStaticLocation : .recoverRoute, permits: { _ in true }))
            let started = expectation(description: "cancelled original receipt")
            writer.onSuspend = { started.fulfill() }
            let task = Task { await model.perform(receipt, permits: { _ in true }) }
            await fulfillment(of: [started], timeout: 2)
            task.cancel(); model.retire(); model.observe(); writer.resume()
            let accepted = await task.value
            XCTAssertFalse(accepted)
            guard case .outcomeUnknown(let original) = model.state else { return XCTFail("Cancelled receipt must restore the retained original, not success or permanent loading") }
            XCTAssertEqual(original, mutation); XCTAssertEqual(writer.mutations, [mutation])
        }
    }
    func testExistingReadCursorStillInvalidatesExactlyOnce() async throws {
        let writer = SourceCardWriter(), (model, _) = try self.model(writer, location: false)
        let mutation = IMMutation.readCursor(conversationID: 9, lastMessageID: 81, requestID: "ack-fixture")
        XCTAssertTrue(model.review(mutation, permits: { _ in true }))
        let token = try XCTUnwrap(model.prepare(.confirm, permits: { _ in true }))
        var accepted = 0
        _ = await model.perform(token, permits: { _ in true }, onConversationMutationAccepted: { _ in accepted += 1 })
        _ = await model.perform(token, permits: { _ in true }, onConversationMutationAccepted: { _ in accepted += 1 })
        XCTAssertEqual(writer.mutations, [mutation]); XCTAssertEqual(accepted, 1)
    }
}

@MainActor private final class SourceCardWriter: IMExpandedWriting, IMSentReading {
    var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
    var isConfigured = true, fail = false, suspendRead = false
    var canSendStaticLocation: Bool { isConfigured }
    var canSendRoute: Bool { isConfigured }
    var canRecoverStaticLocation = true, canRecoverRoute = true
    var mutations: [IMMutation] = [], reads: [IMOutgoingIntent] = []
    var onSuspend: (() -> Void)?
    var readSentCount = 0
    private var continuation: CheckedContinuation<Void, Never>?
    func resume() { let pending = continuation; continuation = nil; pending?.resume() }
    func perform(_ mutation: IMMutation, expectedIdentity: MessagingReadIdentity) async throws -> IMMutationReceipt {
        mutations.append(mutation)
        if fail { throw URLError(.timedOut) }
        if case .readCursor = mutation { return .read }
        return .sent(try message())
    }
    func readSent(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage? {
        readSentCount += 1
        if suspendRead { await withCheckedContinuation { continuation = $0; onSuspend?() } }
        return nil
    }
    func recoverRoute(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage? {
        try await recover(intent)
    }
    func recoverStaticLocation(_ intent: IMOutgoingIntent, expectedIdentity: MessagingReadIdentity) async throws -> MessagingMessage? {
        try await recover(intent)
    }
    private func recover(_ intent: IMOutgoingIntent) async throws -> MessagingMessage? {
        reads.append(intent)
        if suspendRead { await withCheckedContinuation { continuation = $0; onSuspend?() } }
        return try message()
    }
    func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, expectedIdentity: MessagingReadIdentity) async throws -> URL {
        XCTFail("Source-card UI must not upload media"); throw APIError.notConfigured
    }
    private func message() throws -> MessagingMessage {
        try JSONDecoder().decode(MessagingMessage.self, from: Data("{\"id\":10,\"conversationId\":9,\"senderId\":7,\"status\":0,\"msgType\":1,\"content\":\"synthetic receipt\"}".utf8))
    }
}
