import SwiftUI
import UIKit
import XCTest
@testable import Questify

/// App-hosted tests exercise the real MessagingReadScreen refresh hook. The
/// transport is synthetic; these do not establish live IM or device acceptance.
@MainActor final class IMConversationRowActionsAppTests: XCTestCase {
    private var window: UIWindow?
    private func closeHost() { window?.isHidden = true; window = nil }

    func testAcceptedActionRefreshesServerSnapshotWithoutLocalBadgePatch() async throws {
        let reader = Reader(), writer = Writer(), driver = Driver()
        let initial = expectation(description: "initial conversation snapshot")
        driver.didDisplay = { rows in if rows.first?.unread == 3 { initial.fulfill() } }
        host(driver, reader); defer { closeHost() }; await fulfillment(of: [initial], timeout: 3)
        let actions = try make(reader, writer)
        let model = IMConversationRowReviewModel(actions: actions) {
            driver.listModel.invalidate(reader: reader, identity: actions.identity)
        }
        XCTAssertTrue(actions.prepare(.markRead)); model.observe()
        let refreshed = expectation(description: "server conversation readback")
        driver.didDisplay = { rows in if rows.first?.unread == 0 { refreshed.fulfill() } }
        reader.unread = 0
        let accepted = try await confirm(model); XCTAssertTrue(accepted)
        await fulfillment(of: [refreshed], timeout: 3)
        XCTAssertEqual(reader.reads, 2); XCTAssertEqual(writer.mutations, [.read(conversationID: 9)])
        XCTAssertEqual(actions.conversation.unread, 3)
        XCTAssertEqual(driver.displayed.last?.first?.unread, 0)
    }
    func testUnknownResultAndDismissalKeepOriginalIntentWithoutReadback() async throws {
        let reader = Reader(), writer = Writer(), driver = Driver()
        let initial = expectation(description: "initial conversation snapshot")
        driver.didDisplay = { _ in initial.fulfill() }; host(driver, reader); defer { closeHost() }
        await fulfillment(of: [initial], timeout: 3); driver.didDisplay = nil
        writer.fail = true
        let actions = try make(reader, writer)
        let model = IMConversationRowReviewModel(actions: actions) {
            driver.listModel.invalidate(reader: reader, identity: actions.identity)
        }
        XCTAssertTrue(actions.prepare(.setMuted(true))); model.observe()
        let accepted = try await confirm(model); XCTAssertFalse(accepted)
        model.dismiss()
        XCTAssertEqual(driver.listModel.invalidationRevision, 0); XCTAssertEqual(reader.reads, 1)
        XCTAssertEqual(actions.state, .outcomeUnknown(.mute(conversationID: 9, muted: true)))
        XCTAssertEqual(driver.displayed.last?.first?.muted, false)
    }
    func testFailedReadbackDoesNotPublishAnInventedZeroBadge() async throws {
        let reader = Reader(), writer = Writer(), driver = Driver()
        let initial = expectation(description: "initial snapshot")
        driver.didDisplay = { _ in initial.fulfill() }; host(driver, reader); defer { closeHost() }
        await fulfillment(of: [initial], timeout: 3); driver.didDisplay = nil
        let actions = try make(reader, writer)
        let model = IMConversationRowReviewModel(actions: actions) {
            driver.listModel.invalidate(reader: reader, identity: actions.identity)
        }
        XCTAssertTrue(actions.prepare(.markRead)); model.observe(); reader.fail = true
        let reread = expectation(description: "failed server reread")
        reader.didRead = { reread.fulfill() }
        let accepted = try await confirm(model); XCTAssertTrue(accepted)
        await fulfillment(of: [reread], timeout: 3)
        XCTAssertEqual(reader.reads, 2)
        XCTAssertEqual(driver.displayed.flatMap { $0 }.map(\.unread), [3])
        XCTAssertEqual(actions.conversation.unread, 3)
    }
    func testReopenedPanelNeverRetriesPendingMessageOrChangesAccount() async throws {
        let reader = Reader(), writer = Writer(), actions = try make(reader, writer)
        writer.fail = true
        let intent = try IMOutgoingIntent(scope: actions.coordinator.scope, payload: .route(topicID: 42))
        XCTAssertTrue(actions.coordinator.review(.send(intent))); await actions.coordinator.confirm()
        XCTAssertFalse(actions.prepare(.markRead))
        let model = IMConversationRowReviewModel(actions: actions); model.observe()
        XCTAssertNil(model.prepare(.retryUnchanged, appearance: model.appearance))
        XCTAssertEqual(writer.mutations, [.send(intent)])
        reader.identity = .init(accountID: 8, epoch: 2)
        XCTAssertFalse(actions.isCurrent)
    }
    func testQueuedUnknownRetryDismissedBeforeExecutionDoesNotDispatch() async throws {
        let reader = Reader(), writer = Writer(), actions = try make(reader, writer)
        writer.fail = true; XCTAssertTrue(actions.prepare(.setMuted(true)))
        _ = await actions.confirm()
        let model = IMConversationRowReviewModel(actions: actions); model.observe()
        let appearance = model.appearance
        let queued = try XCTUnwrap(model.prepare(.retryUnchanged, appearance: appearance))
        model.dismiss()
        let accepted = await model.perform(queued)
        XCTAssertFalse(accepted); XCTAssertEqual(writer.mutations.count, 1)
        XCTAssertEqual(actions.state, .outcomeUnknown(.mute(conversationID: 9, muted: true)))
        XCTAssertNil(model.appearance)
    }
    func testOldRetryTokenCannotConsumeOrClearNewAppearanceRetry() async throws {
        let reader = Reader(), writer = Writer(), actions = try make(reader, writer)
        writer.fail = true; XCTAssertTrue(actions.prepare(.markRead)); _ = await actions.confirm()
        let model = IMConversationRowReviewModel(actions: actions); model.observe()
        let oldAppearance = model.appearance
        let old = try XCTUnwrap(model.prepare(.retryUnchanged, appearance: oldAppearance))
        model.dismiss(); model.observe()
        XCTAssertNil(model.prepare(.retryUnchanged, appearance: oldAppearance))
        let current = try XCTUnwrap(model.prepare(.retryUnchanged, appearance: model.appearance))
        let staleAccepted = await model.perform(old); XCTAssertFalse(staleAccepted)
        XCTAssertTrue(model.isActionPending); XCTAssertEqual(writer.mutations.count, 1)
        writer.fail = false
        let accepted = await model.perform(current); XCTAssertTrue(accepted)
        let duplicate = await model.perform(current); XCTAssertFalse(duplicate)
        XCTAssertEqual(writer.mutations, [.read(conversationID: 9), .read(conversationID: 9)])
    }
    func testQueuedConfirmCannotOutliveClosedReview() async throws {
        let reader = Reader(), writer = Writer(), actions = try make(reader, writer)
        XCTAssertTrue(actions.prepare(.markRead))
        let model = IMConversationRowReviewModel(actions: actions); model.observe()
        let token = try XCTUnwrap(model.prepare(.confirm, appearance: model.appearance))
        model.dismiss(); let accepted = await model.perform(token)
        XCTAssertFalse(accepted); XCTAssertTrue(writer.mutations.isEmpty)
        XCTAssertEqual(actions.state, .idle)
    }
    func testInFlightRetryCompletionCannotNotifyOrOverwriteDismissedSheet() async throws {
        let reader = Reader(), writer = Writer(), actions = try make(reader, writer)
        writer.fail = true; XCTAssertTrue(actions.prepare(.markRead)); _ = await actions.confirm()
        let model = IMConversationRowReviewModel(actions: actions); model.observe()
        let token = try XCTUnwrap(model.prepare(.retryUnchanged, appearance: model.appearance))
        writer.fail = false; writer.suspend = true
        let waiting = expectation(description: "retry reached writer")
        writer.onSuspend = { waiting.fulfill() }
        let task = Task { await model.perform(token) }
        await fulfillment(of: [waiting], timeout: 2)
        model.dismiss(); XCTAssertNil(model.appearance)
        writer.resume(); let accepted = await task.value
        XCTAssertFalse(accepted); XCTAssertEqual(model.state, .idle)
        XCTAssertFalse(model.isActionPending)
        // The underlying outcome may acknowledge, but the departed sheet stays retired.
        XCTAssertEqual(actions.state, .acknowledged(.read))
    }
    func testQueuedAppearanceReadAfterDisappearanceNeverCallsReader() async throws {
        let reader = Reader(), model = MessagingReadScreenModel<[MessagingConversation]>()
        let token = try XCTUnwrap(model.appear(reader: reader, refreshRevision: 0))
        model.disappear()
        await model.perform(token) { try await reader.messagingConversations() }
        XCTAssertEqual(reader.reads, 0); XCTAssertNil(model.value); XCTAssertNil(model.appearance)
    }
    func testOldReadTokenCannotConsumeReplacementAppearanceRequest() async throws {
        let reader = Reader(), model = MessagingReadScreenModel<[MessagingConversation]>()
        let old = try XCTUnwrap(model.appear(reader: reader, refreshRevision: 0))
        let oldAppearance = model.appearance
        let input = MessagingReadScreenInput(reader: reader, refreshRevision: 0)
        model.disappear()
        let current = try XCTUnwrap(model.appear(reader: reader, refreshRevision: 0))
        XCTAssertNil(model.prepareRefresh(appearance: oldAppearance, input: input))
        await model.perform(old) { try await reader.messagingConversations() }
        XCTAssertEqual(reader.reads, 0); XCTAssertTrue(model.isLoading)
        await model.perform(current) { try await reader.messagingConversations() }
        XCTAssertEqual(reader.reads, 1); XCTAssertEqual(model.value?.first?.unread, 3)
    }
    func testQueuedOlderRevisionCannotCancelOrRebindNewRevision() async throws {
        let reader = Reader(), model = MessagingReadScreenModel<[MessagingConversation]>()
        let initial = try XCTUnwrap(model.appear(reader: reader, refreshRevision: 0))
        await model.perform(initial) { try await reader.messagingConversations() }
        let old = try XCTUnwrap(model.updateInput(reader: reader, refreshRevision: 1, appearance: model.appearance))
        let current = try XCTUnwrap(model.updateInput(reader: reader, refreshRevision: 2, appearance: model.appearance))
        await model.perform(old) { try await reader.messagingConversations() }
        XCTAssertEqual(reader.reads, 1); XCTAssertTrue(model.isLoading)
        XCTAssertEqual(model.input?.refreshRevision, 2)
        XCTAssertNil(model.updateInput(reader: reader, refreshRevision: 1, appearance: model.appearance))
        reader.unread = 0
        await model.perform(current) { try await reader.messagingConversations() }
        await model.perform(current) { try await reader.messagingConversations() }
        XCTAssertEqual(reader.reads, 2); XCTAssertEqual(model.loadedInput?.refreshRevision, 2)
        XCTAssertEqual(model.value?.first?.unread, 0)
    }
    func testOldInFlightReadSuccessOrFailureCannotOverwriteNewRevision() async throws {
        for failure in [false, true] {
            let reader = Reader(), model = MessagingReadScreenModel<[MessagingConversation]>()
            reader.suspend = true
            let initial = try XCTUnwrap(model.appear(reader: reader, refreshRevision: 0))
            let waiting = expectation(description: "initial read suspended")
            reader.onSuspend = { waiting.fulfill() }
            let oldTask = Task { await model.perform(initial) { try await reader.messagingConversations() } }
            await fulfillment(of: [waiting], timeout: 2)
            reader.suspend = false; reader.unread = 0
            let current = try XCTUnwrap(model.updateInput(reader: reader, refreshRevision: 1, appearance: model.appearance))
            await model.perform(current) { try await reader.messagingConversations() }
            reader.resume(failure: failure); await oldTask.value
            XCTAssertEqual(model.value?.first?.unread, 0); XCTAssertNil(model.issue)
            XCTAssertFalse(model.isLoading); XCTAssertEqual(model.loadedInput?.refreshRevision, 1)
        }
    }
    func testOldToolbarAndRetryInputsCannotBindToNewAccountOrReader() async throws {
        let reader = Reader(), model = MessagingReadScreenModel<[MessagingConversation]>()
        let old = try XCTUnwrap(model.appear(reader: reader, refreshRevision: 0))
        let captured = MessagingReadScreenInput(reader: reader, refreshRevision: 0)
        reader.identity = .init(accountID: 8, epoch: 2)
        let current = try XCTUnwrap(model.updateInput(reader: reader, refreshRevision: 0, appearance: model.appearance))
        XCTAssertNil(model.prepareRefresh(appearance: model.appearance, input: captured))
        await model.perform(old) { try await reader.messagingConversations() }
        XCTAssertEqual(reader.reads, 0)
        let replacement = Reader(); replacement.identity = reader.identity
        let replacementToken = try XCTUnwrap(model.updateInput(reader: replacement, refreshRevision: 0, appearance: model.appearance))
        await model.perform(current) { try await reader.messagingConversations() }
        XCTAssertEqual(reader.reads, 0)
        await model.perform(replacementToken) { try await replacement.messagingConversations() }
        XCTAssertEqual(replacement.reads, 1)
        XCTAssertEqual(model.loadedInput?.readerID, ObjectIdentifier(replacement))
    }
    func testCancelledQueuedReadDoesNotDispatchOrKeepSpinnerLocked() async throws {
        let reader = Reader(), model = MessagingReadScreenModel<[MessagingConversation]>()
        let token = try XCTUnwrap(model.appear(reader: reader, refreshRevision: 0))
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await model.perform(token) { try await reader.messagingConversations() }
        }
        await task.value
        XCTAssertEqual(reader.reads, 0); XCTAssertFalse(model.isLoading); XCTAssertNotNil(model.issue)
        XCTAssertNotNil(model.prepareRefresh(appearance: model.appearance,
            input: MessagingReadScreenInput(reader: reader, refreshRevision: 0)))
    }
    func testDeclinedTokenIsConsumedEvenWhenReadAuthorityReturns() async throws {
        let reader = Reader(), model = MessagingReadScreenModel<[MessagingConversation]>()
        let token = try XCTUnwrap(model.appear(reader: reader, refreshRevision: 0))
        reader.isConfigured = false
        await model.perform(token) { try await reader.messagingConversations() }
        reader.isConfigured = true
        await model.perform(token) { try await reader.messagingConversations() }
        XCTAssertEqual(reader.reads, 0); XCTAssertFalse(model.isLoading)
    }
    func testDeclinedRetryTokenCannotReviveAfterReaderRestores() async throws {
        let reader = Reader(), writer = Writer(), actions = try make(reader, writer)
        writer.fail = true; XCTAssertTrue(actions.prepare(.markRead)); _ = await actions.confirm()
        let model = IMConversationRowReviewModel(actions: actions); model.observe()
        let token = try XCTUnwrap(model.prepare(.retryUnchanged, appearance: model.appearance))
        reader.isConfigured = false
        let denied = await model.perform(token); XCTAssertFalse(denied)
        reader.isConfigured = true; writer.fail = false
        let repeated = await model.perform(token); XCTAssertFalse(repeated)
        XCTAssertEqual(writer.mutations.count, 1); XCTAssertFalse(model.isActionPending)
        XCTAssertEqual(actions.state, .outcomeUnknown(.read(conversationID: 9)))
    }
    func testCloseDuringAcceptedMutationRefreshesVisibleListWithoutRevivingSheet() async throws {
        let reader = Reader(), writer = Writer(), driver = Driver()
        let initial = expectation(description: "visible list initially unread")
        driver.didDisplay = { rows in if rows.first?.unread == 3 { initial.fulfill() } }
        host(driver, reader); defer { closeHost() }
        await fulfillment(of: [initial], timeout: 3)
        let actions = try make(reader, writer)
        let model = IMConversationRowReviewModel(actions: actions) {
            driver.listModel.invalidate(reader: reader, identity: actions.identity)
        }
        XCTAssertTrue(actions.prepare(.markRead)); model.observe()
        let token = try XCTUnwrap(model.prepare(.confirm, appearance: model.appearance))
        writer.suspend = true
        let sent = expectation(description: "confirmation reached writer")
        writer.onSuspend = { sent.fulfill() }
        let task = Task { await model.perform(token) }
        await fulfillment(of: [sent], timeout: 2)
        model.dismiss() // The list remains mounted; no parent onAppear is simulated.
        let refreshed = expectation(description: "visible list rereads after closed-sheet ack")
        driver.didDisplay = { rows in if rows.first?.unread == 0 { refreshed.fulfill() } }
        reader.unread = 0; writer.resume()
        let notifySheet = await task.value; XCTAssertFalse(notifySheet)
        await fulfillment(of: [refreshed], timeout: 3)
        XCTAssertNil(model.appearance); XCTAssertEqual(model.state, .idle)
        XCTAssertEqual(driver.listModel.invalidationRevision, 1)
        XCTAssertEqual(reader.reads, 2); XCTAssertEqual(driver.listModel.value?.first?.unread, 0)
    }
    func testAckWhileListIsAwayOnlyInvalidatesAndReturnStartsFreshRead() async throws {
        let reader = Reader(), writer = Writer(), list = MessagingReadScreenModel<[MessagingConversation]>()
        let firstRead = try XCTUnwrap(list.appear(reader: reader, refreshRevision: 0))
        await list.perform(firstRead) { try await reader.messagingConversations() }
        let oldAppearance = list.appearance
        let input = MessagingReadScreenInput(reader: reader, refreshRevision: 0)
        let actions = try make(reader, writer)
        let model = IMConversationRowReviewModel(actions: actions) {
            list.invalidate(reader: reader, identity: actions.identity)
        }
        XCTAssertTrue(actions.prepare(.markRead)); model.observe()
        let token = try XCTUnwrap(model.prepare(.confirm, appearance: model.appearance))
        writer.suspend = true
        let sent = expectation(description: "confirmation suspended")
        writer.onSuspend = { sent.fulfill() }
        let task = Task { await model.perform(token) }
        await fulfillment(of: [sent], timeout: 2)
        model.dismiss(); list.disappear(); reader.unread = 0; writer.resume()
        let notifySheet = await task.value; XCTAssertFalse(notifySheet)
        XCTAssertEqual(list.invalidationRevision, 1); XCTAssertNil(list.appearance)
        XCTAssertEqual(reader.reads, 1); XCTAssertNil(list.loadedInput)
        XCTAssertNil(list.prepareRefresh(appearance: oldAppearance, input: input))
        let returnedRead = try XCTUnwrap(list.appear(reader: reader, refreshRevision: 0))
        await list.perform(returnedRead) { try await reader.messagingConversations() }
        XCTAssertEqual(reader.reads, 2); XCTAssertEqual(list.value?.first?.unread, 0)
        XCTAssertNil(model.appearance); XCTAssertEqual(model.state, .idle)
    }
    func testClosedSheetUnknownOutcomeNeverInvalidatesConfirmedList() async throws {
        let reader = Reader(), writer = Writer(), list = MessagingReadScreenModel<[MessagingConversation]>()
        let first = try XCTUnwrap(list.appear(reader: reader, refreshRevision: 0))
        await list.perform(first) { try await reader.messagingConversations() }
        let actions = try make(reader, writer)
        let model = IMConversationRowReviewModel(actions: actions) {
            list.invalidate(reader: reader, identity: actions.identity)
        }
        XCTAssertTrue(actions.prepare(.setMuted(true))); model.observe()
        let token = try XCTUnwrap(model.prepare(.confirm, appearance: model.appearance))
        writer.fail = true; writer.suspend = true
        let sent = expectation(description: "uncertain confirmation suspended")
        writer.onSuspend = { sent.fulfill() }
        let task = Task { await model.perform(token) }
        await fulfillment(of: [sent], timeout: 2)
        model.dismiss(); writer.resume(); let notifySheet = await task.value
        XCTAssertFalse(notifySheet); XCTAssertEqual(list.invalidationRevision, 0)
        XCTAssertEqual(list.value?.first?.unread, 3); XCTAssertEqual(list.value?.first?.muted, false)
        XCTAssertEqual(reader.reads, 1)
        XCTAssertEqual(actions.state, .outcomeUnknown(.mute(conversationID: 9, muted: true)))
    }
    func testOldReceiptCannotInvalidateReplacementReaderOrAccountSnapshot() async throws {
        let reader = Reader(), replacement = Reader(), list = MessagingReadScreenModel<[MessagingConversation]>()
        let first = try XCTUnwrap(list.appear(reader: reader, refreshRevision: 0))
        await list.perform(first) { try await reader.messagingConversations() }
        let oldIdentity = try XCTUnwrap(reader.identity)
        let next = try XCTUnwrap(list.updateInput(reader: replacement, refreshRevision: 0, appearance: list.appearance))
        await list.perform(next) { try await replacement.messagingConversations() }
        XCTAssertFalse(list.invalidate(reader: reader, identity: oldIdentity))
        XCTAssertEqual(list.invalidationRevision, 0); XCTAssertNotNil(list.value)
        replacement.identity = .init(accountID: 8, epoch: 2)
        let changed = try XCTUnwrap(list.updateInput(reader: replacement, refreshRevision: 0, appearance: list.appearance))
        await list.perform(changed) { try await replacement.messagingConversations() }
        XCTAssertFalse(list.invalidate(reader: replacement, identity: oldIdentity))
        XCTAssertEqual(list.invalidationRevision, 0); XCTAssertEqual(list.loadedInput?.identity?.accountID, 8)
    }
    func testInvalidationDiscardsAlreadyStartedPreMutationReadWithoutCancellingNetwork() async throws {
        let reader = Reader(), list = MessagingReadScreenModel<[MessagingConversation]>()
        reader.suspend = true
        let first = try XCTUnwrap(list.appear(reader: reader, refreshRevision: 0))
        let started = expectation(description: "pre-mutation read suspended")
        reader.onSuspend = { started.fulfill() }
        let oldTask = Task { await list.perform(first) { try await reader.messagingConversations() } }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(list.invalidate(reader: reader, identity: try XCTUnwrap(reader.identity)))
        XCTAssertEqual(reader.reads, 1); XCTAssertNil(list.loadedInput)
        reader.suspend = false; reader.unread = 0
        let current = try XCTUnwrap(list.prepareRefresh(appearance: list.appearance,
            input: MessagingReadScreenInput(reader: reader, refreshRevision: 0)))
        await list.perform(current) { try await reader.messagingConversations() }
        reader.resume(failure: false); await oldTask.value
        XCTAssertEqual(list.value?.first?.unread, 0); XCTAssertEqual(reader.reads, 2)
    }
    private func confirm(_ model: IMConversationRowReviewModel) async throws -> Bool {
        let token = try XCTUnwrap(model.prepare(.confirm, appearance: model.appearance))
        return await model.perform(token)
    }
    private func make(_ reader: Reader, _ writer: Writer) throws -> IMConversationRowActions {
        let identity = try XCTUnwrap(reader.identity)
        return .init(conversation: try Reader.row(3), identity: identity,
            coordinator: .init(scope: try IMScope(identity: identity, conversationID: 9), writer: writer), reader: reader)
    }
    private func host(_ driver: Driver, _ reader: Reader) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: Host(driver: driver, reader: reader))
        self.window = window; window.makeKeyAndVisible()
    }
    @MainActor private final class Driver: ObservableObject {
        let listModel = MessagingReadScreenModel<[MessagingConversation]>()
        var displayed: [[MessagingConversation]] = []
        var didDisplay: (([MessagingConversation]) -> Void)?
        func display(_ rows: [MessagingConversation]) { displayed.append(rows); didDisplay?(rows) }
    }
    @MainActor private struct Host: View {
        @ObservedObject var driver: Driver
        let reader: Reader
        var body: some View {
            NavigationStack {
                MessagingReadScreen(reader: reader, accessibilityPrefix: "im.row.test", model: driver.listModel,
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
        var reads = 0, unread = 3
        var didRead: (() -> Void)?
        var suspend = false, onSuspend: (() -> Void)?
        private var pending: CheckedContinuation<[MessagingConversation], Error>?
        func resume(failure: Bool) {
            let continuation = pending; pending = nil
            if failure { continuation?.resume(throwing: URLError(.notConnectedToInternet)) }
            else { continuation?.resume(returning: (try? [Self.row(3)]) ?? []) }
        }
        static func row(_ unread: Int) throws -> MessagingConversation {
            try JSONDecoder().decode(MessagingConversation.self, from: Data("{\"conversationId\":9,\"unread\":\(unread),\"muted\":0}".utf8))
        }
        func messagingConversations() async throws -> [MessagingConversation] {
            reads += 1; didRead?()
            if suspend { return try await withCheckedThrowingContinuation { pending = $0; onSuspend?() } }
            if fail { throw URLError(.notConnectedToInternet) }; return [try Self.row(unread)]
        }
        func messagingMessages(conversationID: Int, cursor: Int) async throws -> MessagingPage { throw APIError.notConfigured }
    }
    @MainActor private final class Writer: IMExpandedWriting {
        var identity: MessagingReadIdentity? = .init(accountID: 7, epoch: 1)
        var isConfigured = true, fail = false
        var mutations: [IMMutation] = []
        var suspend = false, onSuspend: (() -> Void)?
        private var pending: CheckedContinuation<Void, Never>?
        func resume() { let continuation = pending; pending = nil; continuation?.resume() }
        func perform(_ mutation: IMMutation, expectedIdentity: MessagingReadIdentity) async throws -> IMMutationReceipt {
            mutations.append(mutation)
            if suspend { await withCheckedContinuation { pending = $0; onSuspend?() } }
            if fail { throw URLError(.timedOut) }
            switch mutation { case .read: return .read; case .mute(_, let muted): return .muted(muted); default: throw APIError.invalidRequest }
        }
        func upload(_ selection: IMMediaSelection, consent: IMMediaConsent, expectedIdentity: MessagingReadIdentity) async throws -> URL { throw APIError.notConfigured }
    }
}
