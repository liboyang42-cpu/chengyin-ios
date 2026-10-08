import SwiftUI
import UIKit
import XCTest
@testable import Questify

/// Shipping review/list owners, synthetic I/O only. Requires an Apple test host.
@MainActor final class IMConversationReadAllAppTests: XCTestCase {
    private var window: UIWindow?
    private func closeHost() { window?.isHidden = true; window = nil }

    func testFinalReadbackUsesRealListOwnerAndServerBadgesWithoutLocalZero() async throws {
        let reader = Reader(), writer = Writer(), driver = Driver()
        let initial = expectation(description: "initial list")
        driver.didDisplay = { _ in initial.fulfill() }
        host(driver, reader); defer { closeHost() }; await fulfillment(of: [initial], timeout: 3)
        let (batch, _) = try make(reader, writer)
        let model = makeModel(batch, reader, driver.list)
        model.observe()
        let reread = expectation(description: "authoritative replacement")
        driver.didDisplay = { rows in if rows.first?.unread == 2 { reread.fulfill() } }
        // A newly arrived message can leave a nonzero count even after acceptance.
        reader.rows = try [Reader.row(1, unread: 2), Reader.row(2, unread: 0)]
        let token = try XCTUnwrap(model.prepare(appearance: model.appearance))
        await model.perform(token)
        await fulfillment(of: [reread], timeout: 3)
        XCTAssertEqual(reader.reads, 2); XCTAssertEqual(driver.list.invalidationRevision, 1)
        XCTAssertEqual(driver.list.value?.map(\.unread), [2, 0])
        XCTAssertEqual(batch.items.map { $0.conversation.unread }, [3, 3])
        XCTAssertEqual(batch.acknowledgedCount, 2)
    }
    func testPartialUnknownAlsoRereadsAndKeepsOriginalJournal() async throws {
        let reader = Reader(), writer = Writer(), driver = Driver()
        let initial = expectation(description: "initial list")
        driver.didDisplay = { _ in initial.fulfill() }
        host(driver, reader); defer { closeHost() }; await fulfillment(of: [initial], timeout: 3)
        driver.didDisplay = nil
        writer.errors[2] = URLError(.timedOut)
        let (batch, owners) = try make(reader, writer)
        let model = makeModel(batch, reader, driver.list); model.observe()
        let reread = expectation(description: "read after partial result")
        reader.didRead = { reread.fulfill() }
        let token = try XCTUnwrap(model.prepare(appearance: model.appearance))
        await model.perform(token); await fulfillment(of: [reread], timeout: 3)
        XCTAssertEqual(reader.reads, 2); XCTAssertEqual(driver.list.invalidationRevision, 1)
        XCTAssertEqual(batch.acknowledgedCount, 1); XCTAssertEqual(batch.unknownCount, 1)
        XCTAssertEqual(owners[2]?.visibleState, .outcomeUnknown(.read(conversationID: 2)))
        XCTAssertNil(model.prepare(appearance: model.appearance))
    }
    func testFailedReadbackShowsReadErrorAndNeverFabricatesBadges() async throws {
        let reader = Reader(), writer = Writer(), driver = Driver()
        let initial = expectation(description: "initial list")
        driver.didDisplay = { _ in initial.fulfill() }
        host(driver, reader); defer { closeHost() }; await fulfillment(of: [initial], timeout: 3)
        driver.didDisplay = nil
        let (batch, _) = try make(reader, writer)
        let model = makeModel(batch, reader, driver.list); model.observe(); reader.fail = true
        let reread = expectation(description: "failed readback")
        reader.didRead = { reread.fulfill() }
        let token = try XCTUnwrap(model.prepare(appearance: model.appearance))
        await model.perform(token); await fulfillment(of: [reread], timeout: 3)
        // Allow the shipping read task to process the synchronous mock failure.
        await Task.yield()
        XCTAssertEqual(driver.displayed.flatMap { $0 }.compactMap(\.unread), [3, 3])
        XCTAssertNil(driver.list.value); XCTAssertNotNil(driver.list.issue)
        XCTAssertEqual(batch.acknowledgedCount, 2)
    }
    func testQueuedConfirmationCloseBeforeExecutionWritesNothing() async throws {
        let reader = Reader(), writer = Writer(), list = MessagingReadScreenModel<[MessagingConversation]>()
        let (batch, owners) = try make(reader, writer), model = makeModel(batch, reader, list)
        model.observe(); let token = try XCTUnwrap(model.prepare(appearance: model.appearance))
        model.dismiss(); await model.perform(token)
        XCTAssertTrue(writer.mutations.isEmpty); XCTAssertEqual(list.invalidationRevision, 0)
        XCTAssertEqual(owners[1]?.visibleState, .idle); XCTAssertNil(model.appearance)
        XCTAssertEqual(model.phase, .cancelled)
    }
    func testQueuedTokenCannotReviveAfterCloseAndNewAppearance() async throws {
        let reader = Reader(), writer = Writer(), list = MessagingReadScreenModel<[MessagingConversation]>()
        let (batch, _) = try make(reader, writer), model = makeModel(batch, reader, list)
        model.observe(); let old = try XCTUnwrap(model.prepare(appearance: model.appearance))
        model.dismiss(); model.observe()
        XCTAssertNil(model.prepare(appearance: model.appearance)); await model.perform(old)
        XCTAssertTrue(writer.mutations.isEmpty); XCTAssertFalse(model.isActionPending)
    }
    func testCloseInFlightStopsFurtherItemsAndStillRefreshesVisibleList() async throws {
        let reader = Reader(), writer = Writer(), driver = Driver()
        let initial = expectation(description: "initial list")
        driver.didDisplay = { _ in initial.fulfill() }
        host(driver, reader); defer { closeHost() }; await fulfillment(of: [initial], timeout: 3)
        driver.didDisplay = nil
        let (batch, owners) = try make(reader, writer), model = makeModel(batch, reader, driver.list)
        model.observe(); let token = try XCTUnwrap(model.prepare(appearance: model.appearance))
        writer.suspendID = 1
        let suspended = expectation(description: "first write suspended")
        writer.didSuspend = { suspended.fulfill() }
        let task = Task { await model.perform(token) }
        await fulfillment(of: [suspended], timeout: 2)
        let refreshed = expectation(description: "readback after close")
        reader.didRead = { refreshed.fulfill() }
        model.dismiss(); reader.rows = try [Reader.row(1, unread: 0), Reader.row(2)]
        writer.resume(); await task.value; await fulfillment(of: [refreshed], timeout: 3)
        XCTAssertEqual(writer.mutations, [.read(conversationID: 1)])
        XCTAssertEqual(owners[1]?.visibleState, .acknowledged(.read))
        XCTAssertEqual(driver.list.invalidationRevision, 1); XCTAssertNil(model.appearance)
        XCTAssertEqual(model.phase, .cancelled)
    }
    func testOffscreenCompletionOnlyInvalidatesAndNextAppearanceReads() async throws {
        let reader = Reader(), writer = Writer(), list = MessagingReadScreenModel<[MessagingConversation]>()
        let first = try XCTUnwrap(list.appear(reader: reader, refreshRevision: 0))
        await list.perform(first) { try await reader.messagingConversations() }
        let (batch, _) = try make(reader, writer), model = makeModel(batch, reader, list)
        model.observe(); let token = try XCTUnwrap(model.prepare(appearance: model.appearance))
        writer.suspendID = 1
        let suspended = expectation(description: "write suspended")
        writer.didSuspend = { suspended.fulfill() }
        let task = Task { await model.perform(token) }
        await fulfillment(of: [suspended], timeout: 2)
        model.dismiss(); list.disappear(); writer.resume(); await task.value
        XCTAssertEqual(reader.reads, 1); XCTAssertEqual(list.invalidationRevision, 1)
        XCTAssertNil(list.appearance); XCTAssertNil(list.loadedInput)
        let next = try XCTUnwrap(list.appear(reader: reader, refreshRevision: 0))
        await list.perform(next) { try await reader.messagingConversations() }
        XCTAssertEqual(reader.reads, 2)
    }
    func testOldBatchCannotInvalidateReplacementReaderWithSameAccount() async throws {
        let reader = Reader(), replacement = Reader(), writer = Writer()
        let list = MessagingReadScreenModel<[MessagingConversation]>()
        let first = try XCTUnwrap(list.appear(reader: reader, refreshRevision: 0))
        await list.perform(first) { try await reader.messagingConversations() }
        let (batch, _) = try make(reader, writer), model = makeModel(batch, reader, list)
        model.observe(); let token = try XCTUnwrap(model.prepare(appearance: model.appearance))
        writer.suspendID = 1
        let suspended = expectation(description: "write suspended")
        writer.didSuspend = { suspended.fulfill() }
        let task = Task { await model.perform(token) }
        await fulfillment(of: [suspended], timeout: 2)
        model.dismiss()
        let next = try XCTUnwrap(list.updateInput(reader: replacement, refreshRevision: 0, appearance: list.appearance))
        await list.perform(next) { try await replacement.messagingConversations() }
        writer.resume(); await task.value
        XCTAssertEqual(list.invalidationRevision, 0); XCTAssertNotNil(list.value)
        XCTAssertEqual(writer.mutations.count, 1)
    }
    func testQueuedAuthorityRevokedAndRestoredDoesNotReuseConsumedToken() async throws {
        let reader = Reader(), writer = Writer(), list = MessagingReadScreenModel<[MessagingConversation]>()
        let (batch, _) = try make(reader, writer), model = makeModel(batch, reader, list)
        model.observe(); let token = try XCTUnwrap(model.prepare(appearance: model.appearance))
        reader.isConfigured = false; await model.perform(token)
        reader.isConfigured = true; await model.perform(token)
        XCTAssertNil(model.prepare(appearance: model.appearance)); XCTAssertTrue(writer.mutations.isEmpty)
    }
    func testDoubleTapAndRepeatedPerformConsumeConfirmationOnlyOnce() async throws {
        let reader = Reader(), writer = Writer(), list = MessagingReadScreenModel<[MessagingConversation]>()
        let (batch, _) = try make(reader, writer), model = makeModel(batch, reader, list)
        model.observe(); let token = try XCTUnwrap(model.prepare(appearance: model.appearance))
        XCTAssertNil(model.prepare(appearance: model.appearance))
        await model.perform(token); await model.perform(token)
        XCTAssertEqual(writer.mutations.count, 2); XCTAssertFalse(model.isActionPending)
    }

    private func make(_ reader: Reader, _ writer: Writer) throws -> (IMConversationReadAll, [Int: IMExpandedCoordinator]) {
        let identity = try XCTUnwrap(reader.identity)
        let owners = try Dictionary(uniqueKeysWithValues: reader.rows.map { row in
            (row.id, IMExpandedCoordinator(scope: try IMScope(identity: identity, conversationID: row.id), writer: writer))
        })
        return (IMConversationReadAll(conversations: reader.rows, identity: identity, reader: reader,
            coordinator: { owners[$0] }), owners)
    }
    private func makeModel(_ batch: IMConversationReadAll, _ reader: Reader,
                       _ list: MessagingReadScreenModel<[MessagingConversation]>) -> IMConversationReadAllReviewModel {
        IMConversationReadAllReviewModel(batch: batch) { list.invalidate(reader: reader, identity: batch.identity) }
    }
    private func host(_ driver: Driver, _ reader: Reader) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: Host(driver: driver, reader: reader))
        self.window = window; window.makeKeyAndVisible()
    }
    @MainActor private final class Driver: ObservableObject {
        let list = MessagingReadScreenModel<[MessagingConversation]>()
        var displayed: [[MessagingConversation]] = []
        var didDisplay: (([MessagingConversation]) -> Void)?
        func display(_ rows: [MessagingConversation]) { displayed.append(rows); didDisplay?(rows) }
    }
    @MainActor private struct Host: View {
        @ObservedObject var driver: Driver
        let reader: Reader
        var body: some View {
            NavigationStack {
                MessagingReadScreen(reader: reader, accessibilityPrefix: "im.readAll.test", model: driver.list,
                    load: { try await reader.messagingConversations() }) { rows in
                        Text(verbatim: rows.map { String($0.unread ?? -1) }.joined(separator: ","))
                            .onAppear { driver.display(rows) }
                    }
            }
        }
    }
    @MainActor private final class Reader: MessagingReading {
        var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
        var isConfigured = true, fail = false
        var reads = 0
        var rows = (try? [Reader.row(1), Reader.row(2)]) ?? []
        var didRead: (() -> Void)?
        static func row(_ id: Int, unread: Int = 3) throws -> MessagingConversation {
            try JSONDecoder().decode(MessagingConversation.self, from: Data("{\"conversationId\":\(id),\"type\":1,\"unread\":\(unread),\"muted\":0}".utf8))
        }
        func messagingConversations() async throws -> [MessagingConversation] {
            reads += 1; didRead?()
            if fail { throw URLError(.notConnectedToInternet) }
            return rows
        }
        func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage { throw APIError.notConfigured }
    }
    @MainActor private final class Writer: IMExpandedWriting {
        var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
        var isConfigured = true
        var mutations: [IMMutation] = []
        var errors: [Int: Error] = [:]
        var suspendID: Int?, didSuspend: (() -> Void)?
        private var pending: CheckedContinuation<Void, Never>?
        func resume() { let continuation = pending; pending = nil; continuation?.resume() }
        func perform(_ mutation: IMMutation, expectedIdentity: MessagingReadIdentity) async throws -> IMMutationReceipt {
            mutations.append(mutation)
            let id = mutation.conversationID ?? 0
            if suspendID == id { await withCheckedContinuation { pending = $0; didSuspend?() } }
            if let error = errors[id] { throw error }
            return .read
        }
        func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, expectedIdentity: MessagingReadIdentity) async throws -> URL { throw APIError.notConfigured }
    }
}
