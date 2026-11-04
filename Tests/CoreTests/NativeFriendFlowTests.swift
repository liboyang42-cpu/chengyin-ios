import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class NativeFriendFlowTests: XCTestCase {
    private final class IntentStorage: ProjectEditDataStorage {
        var rows: [String: Data] = [:]
        func read(_ key: String) throws -> Data? { rows[key] }
        func write(_ data: Data, key: String) throws { rows[key] = data }
        func remove(_ key: String) throws { rows.removeValue(forKey: key) }
    }
    private final class Journal: OperationPendingListing {
        let intentStorage = IntentStorage()
        var records: [OperationPendingRecord] = []; var failWrites = false
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey } }
        func pendingRecords(ownerKey: String) throws -> [OperationPendingRecord] { records.filter { $0.ownerKey == ownerKey } }
        func write(_ record: OperationPendingRecord) throws { if failWrites { throw NativeFriendFailure.unavailable }; records.append(record) }
        func clear(_ record: OperationPendingRecord) throws { records.removeAll { $0 == record } }
    }
    private final class Service: NativeFriendServing {
        var receiptCommands: (() -> [NativeFriendCommand])?
        var viewerID: Int64 = 2; var canWrite = true; var isCurrent = true
        var writes: [NativeFriendCommand] = []; var lookups: [String] = []; var failure: NativeFriendFailure?
        var review: NativeFriendReview?; var reviews: [NativeFriendReview] = []; var reviewHasMore = false; var reviewNextCursor: Int64?; var reviewLookups: [Int64] = []; var outcome = "APPLIED"; var invalidateOnPage = false
        var pageFailure = false; var unknownReceipt = false; var wrongViewer = false; var invalidateOnWrite = false
        var relation = NativeFriendRelationship(viewerID: 2, peerID: 9, state: .pendingOutgoing, version: 1, conversationID: nil)
        var incoming: [NativeFriendItem] = []; var outgoing: [NativeFriendItem] = []; var friends: [NativeFriendItem] = []
        func page(requests: Bool, cursor: Int64) async throws -> NativeFriendPage {
            if invalidateOnPage { isCurrent = false }
            if pageFailure { throw NativeFriendFailure.unknown }
            return .init(viewerID: viewerID, incoming: requests ? incoming : [], outgoing: requests ? outgoing : [], friends: requests ? [] : friends, hasMore: false, nextCursor: nil, reviews: requests ? reviews : nil, reviewHasMore: reviewHasMore, reviewNextCursor: reviewNextCursor)
        }
        func reviewPage(cursor: Int64) async throws -> NativeFriendPage { reviewLookups.append(cursor); return try await page(requests: true, cursor: cursor) }
        func relationship(peerID: Int64) async throws -> NativeFriendRelationship { relation }
        func write(_ command: NativeFriendCommand) async throws -> NativeFriendReceipt {
            writes.append(command); if invalidateOnWrite { isCurrent = false }
            if let failure { throw failure };return answer(peer: command.peerID, action: command.action, id: command.requestID)
        }
        func receipt(peerID: Int64, action: NativeFriendAction, requestID: String) async throws -> NativeFriendReceipt {
            lookups.append(requestID); return answer(peer: peerID, action: action, id: requestID)
        }
        private func answer(peer: Int64, action: NativeFriendAction, id: String) -> NativeFriendReceipt {
            .init(viewerID: wrongViewer ? 8 : viewerID, peerID: peer, action: action, requestID: id, outcome: unknownReceipt ? "UNKNOWN" : outcome, relationship: unknownReceipt ? nil : relation, review: unknownReceipt ? nil : review, payloadHash: (receiptCommands?() ?? writes).first { $0.requestID == id }?.originalIntentProof)
        }
    }
    private func setup() async -> (NativeFriendFlow, Service, Journal) {
        let service = Service(), journal = Journal(), flow = NativeFriendFlow(service: service, journal: journal, ownerKey: "deployment|account-2", intentJournal: NativeFriendIntentJournal(storage: journal.intentStorage, ownerKey: "deployment|account-2"))
        await flow.load(); return (flow, service, journal)
    }
    func testRequestSuccessUsesServerResultAndClearsOnlyMatchedJournal() async {
        let (flow, service, journal) = await setup();let command = NativeFriendCommand(peerID: 9, action: .request, message: "hello")
        await flow.perform(command)
        XCTAssertEqual(service.writes, [command]);XCTAssertEqual(flow.relationship, service.relation)
        XCTAssertEqual(flow.phase, .ready);XCTAssertTrue(journal.records.isEmpty)
    }
    func testLostResponseBlocksNewWriteAndRecoveryKeepsOriginalIdentityWithoutResending() async {
        let (flow, service, journal) = await setup();let command = NativeFriendCommand(peerID: 9, action: .request, message: "hello")
        service.failure = .unknown;await flow.perform(command);await flow.perform(command)
        XCTAssertEqual(flow.phase, .unknown);XCTAssertEqual(service.writes.count, 1);XCTAssertEqual(journal.records.count, 1)
        service.unknownReceipt = true;await flow.recover();XCTAssertNotNil(flow.pending)
        service.unknownReceipt = false;await flow.recover()
        XCTAssertEqual(service.lookups, [command.requestID, command.requestID]);XCTAssertEqual(service.writes.count, 1)
        XCTAssertEqual(flow.phase, .ready);XCTAssertTrue(journal.records.isEmpty)
    }
    func testPersistFailureDispatchesNothing() async {
        let (flow, service, journal) = await setup();journal.failWrites = true
        await flow.perform(.init(peerID: 9, action: .request, message: "hello"))
        XCTAssertTrue(service.writes.isEmpty);XCTAssertEqual(flow.issue, "friend.storageFailure")
    }
    func testDefinitiveRejectionAndNotSentUnlockButUnknownDoesNot() async {
        for error in [NativeFriendFailure.notSent, .rejected(409)] {
            let (flow, service, journal) = await setup();service.failure = error
            await flow.perform(.init(peerID: 9, action: .accept, expectedVersion: 4))
            XCTAssertNil(flow.pending);XCTAssertTrue(journal.records.isEmpty);XCTAssertTrue(flow.canWrite)
        }
    }
    func testWrongViewerReceiptCannotClearOrPublish() async {
        let (flow, service, journal) = await setup();service.wrongViewer = true
        await flow.perform(.init(peerID: 9, action: .reject, expectedVersion: 4))
        XCTAssertEqual(flow.phase, .unknown);XCTAssertNil(flow.relationship);XCTAssertEqual(journal.records.count, 1)
    }
    func testAccountChangeDuringWriteSuppressesResultAndRetainsRecoveryIdentity() async {
        let (flow, service, journal) = await setup();service.invalidateOnWrite = true
        await flow.perform(.init(peerID: 9, action: .cancel, expectedVersion: 4))
        XCTAssertNil(flow.relationship);XCTAssertEqual(journal.records.count, 1);XCTAssertFalse(flow.canWrite)
        flow.invalidate();XCTAssertEqual(journal.records.count, 1)
    }
    func testRecreatedFlowSameAccountFindsPendingButOtherAccountDoesNot() async {
        let (flow, service, journal) = await setup();service.failure = .unknown
        await flow.perform(.init(peerID: 9, action: .request, message: "hello"))
        let same = NativeFriendFlow(service: service, journal: journal, ownerKey: "deployment|account-2", intentJournal: NativeFriendIntentJournal(storage: journal.intentStorage, ownerKey: "deployment|account-2"))
        await same.load();XCTAssertEqual(same.pending?.operationID, flow.pending?.operationID)
        let other = NativeFriendFlow(service: nil, journal: journal, ownerKey: "deployment|account-3", intentJournal: NativeFriendIntentJournal(storage: journal.intentStorage, ownerKey: "deployment|account-3"))
        await other.load();XCTAssertNil(other.pending);XCTAssertEqual(other.phase, .closed)
    }
    func testKnownSuccessRemainsResolvedWhenListRefreshFails() async {
        let (flow, service, journal) = await setup();service.pageFailure = true
        await flow.perform(.init(peerID: 9, action: .accept, expectedVersion: 4))
        XCTAssertNotNil(flow.relationship);XCTAssertTrue(journal.records.isEmpty);XCTAssertEqual(flow.issue, "friend.loadFailure")
    }
    func testExistingConversationOnlyUsesAuthoritativeReadNeverCreatesOne() async {
        let (flow, service, _) = await setup();let absent = await flow.existingConversation(peerID: 9);XCTAssertNil(absent)
        service.relation = .init(viewerID: 2, peerID: 9, state: .friend, version: 4, conversationID: 71)
        let existing = await flow.existingConversation(peerID: 9);XCTAssertEqual(existing, 71);XCTAssertTrue(service.writes.isEmpty)
    }
    func testReadOnlyApprovalStillListsButCannotMutate() async {
        let (flow, service, _) = await setup();service.canWrite = false
        await flow.perform(.init(peerID: 9, action: .request, message: "hello"));XCTAssertTrue(service.writes.isEmpty)
    }
    func testDefinitePrewriteModerationRefusalUnlocksForCorrectedExplicitGesture() async {
        let (flow, service, journal) = await setup();service.failure = .rejected(403)
        let first = NativeFriendCommand(peerID: 9, action: .request, message: "unapproved application")
        await flow.perform(first);XCTAssertNil(flow.pending);XCTAssertTrue(journal.records.isEmpty);XCTAssertTrue(flow.canWrite)
        service.failure = nil
        let corrected = NativeFriendCommand(peerID: 9, action: .request, message: "corrected application")
        await flow.perform(corrected)
        XCTAssertEqual(service.writes, [first, corrected]);XCTAssertNotEqual(first.requestID, corrected.requestID)
        XCTAssertEqual(flow.phase, .ready);XCTAssertEqual(flow.relationship, service.relation)
    }

    func testTwoReadyFlowsShareOwnerWideUnknownFenceWithRealDefaultsJournal() async throws {
        let suite = "NativeFriendFlowTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite));defer { defaults.removePersistentDomain(forName: suite) }
        let journal = OperationDefaultsJournal(defaults: defaults), aService = Service(), bService = Service()
        let intentStorage = IntentStorage()
        // Both client instances query one server's original command receipt ledger.
        bService.receiptCommands = { aService.writes }
        let a = NativeFriendFlow(service: aService, journal: journal, ownerKey: "same-owner", intentJournal: NativeFriendIntentJournal(storage: intentStorage, ownerKey: "same-owner"))
        let b = NativeFriendFlow(service: bService, journal: journal, ownerKey: "same-owner", intentJournal: NativeFriendIntentJournal(storage: intentStorage, ownerKey: "same-owner"))
        await a.load();await b.load();XCTAssertTrue(a.canWrite);XCTAssertTrue(b.canWrite)
        aService.failure = .unknown
        await a.perform(.init(peerID: 9, action: .request, message: "first"))
        await b.perform(.init(peerID: 11, action: .request, message: "different peer"))
        XCTAssertEqual(aService.writes.count, 1);XCTAssertTrue(bService.writes.isEmpty)
        XCTAssertEqual(b.pending?.operationID, a.pending?.operationID);XCTAssertEqual(b.phase, .unknown)
        XCTAssertEqual(try journal.pendingRecords(ownerKey: "same-owner").count, 1)
        await b.recover();await a.recover()
        XCTAssertEqual(a.phase, .ready);XCTAssertEqual(b.phase, .ready)
        XCTAssertTrue(try journal.pendingRecords(ownerKey: "same-owner").isEmpty)
        XCTAssertEqual(aService.writes.count, 1);XCTAssertTrue(bService.writes.isEmpty)
    }

    private func review(_ id: String, state: NativeFriendReviewState = .pending, reviewID: Int64 = 71, peer: Int64 = 9) -> NativeFriendReview {
        .init(id: reviewID, peerID: peer, requestID: id, state: state, version: state == .pending ? 1 : 2, message: "private application", expiresAtMS: 1_900_000_000_000)
    }
    func testPendingReviewIsConfirmedPrivateResultNotFriendOrDelivery() async {
        let (flow, service, journal) = await setup();let command = NativeFriendCommand(peerID: 9, action: .request, message: "private application")
        service.relation = .init(viewerID: 2, peerID: 9, state: .none, version: 0, conversationID: nil)
        service.review = review(command.requestID);service.reviews = [service.review!];service.outcome = "PENDING_REVIEW"
        await flow.perform(command)
        XCTAssertEqual(flow.lastReview?.state, .pending);XCTAssertEqual(flow.relationship?.state, NativeFriendRelation.none)
        XCTAssertNil(flow.relationship?.conversationID)
        XCTAssertTrue(flow.incoming.isEmpty);XCTAssertTrue(flow.outgoing.isEmpty);XCTAssertTrue(journal.records.isEmpty)
        XCTAssertEqual(flow.reviews, service.reviews);XCTAssertTrue(flow.canWrite)
    }
    func testRefreshFailureRetainsConfirmedReviewButDisablesWritesUntilReadSucceeds() async {
        let (flow, service, _) = await setup();let command = NativeFriendCommand(peerID: 9, action: .request, message: "private application")
        service.review = review(command.requestID);service.reviews = [service.review!];service.outcome = "PENDING_REVIEW"
        await flow.perform(command);let confirmed = flow.relationship
        service.pageFailure = true;await flow.load()
        XCTAssertEqual(flow.reviews, service.reviews);XCTAssertEqual(flow.lastReview, service.review);XCTAssertEqual(flow.relationship, confirmed)
        XCTAssertEqual(flow.phase, .failed);XCTAssertFalse(flow.canWrite);XCTAssertEqual(flow.issue, "friend.loadFailure")
        service.pageFailure = false;await flow.load();XCTAssertTrue(flow.canWrite)
    }
    func testIdentityLossDuringFailedReadClearsPreviousPrivateReview() async {
        let (flow, service, _) = await setup();service.reviews = [review(UUID().uuidString)];await flow.load()
        service.invalidateOnPage = true;service.pageFailure = true;await flow.load()
        XCTAssertTrue(flow.reviews.isEmpty);XCTAssertNil(flow.lastReview);XCTAssertNil(flow.relationship);XCTAssertFalse(flow.canWrite)
    }
    func testExistingConversationForAnotherPeerCannotDisplayOldReview() async {
        let (flow, service, _) = await setup();let command = NativeFriendCommand(peerID: 9, action: .request, message: "private application")
        service.review = review(command.requestID);service.outcome = "PENDING_REVIEW";await flow.perform(command)
        service.relation = .init(viewerID: 2, peerID: 11, state: .friend, version: 4, conversationID: 81)
        let conversation = await flow.existingConversation(peerID: 11)
        XCTAssertEqual(conversation, 81);XCTAssertNil(flow.lastReview);XCTAssertEqual(flow.relationship?.peerID, 11)
    }
    func testRestartRecoversExactOriginalPendingReviewWithoutResubmitting() async {
        let (first, service, journal) = await setup();let command = NativeFriendCommand(peerID: 9, action: .request, message: "private application")
        service.failure = .unknown;await first.perform(command)
        let restarted = NativeFriendFlow(service: service, journal: journal, ownerKey: "deployment|account-2", intentJournal: NativeFriendIntentJournal(storage: journal.intentStorage, ownerKey: "deployment|account-2"))
        await restarted.load();service.review = review(command.requestID);service.outcome = "PENDING_REVIEW";await restarted.recover()
        XCTAssertEqual(restarted.lastReview?.requestID, command.requestID);XCTAssertTrue(journal.records.isEmpty)
        XCTAssertEqual(service.writes, [command]);XCTAssertEqual(service.lookups, [command.requestID])
    }
    func testReviewTerminalResultsResolveOriginalUnknownIdentityWithoutNewWrite() async {
        for terminal in [NativeFriendReviewState.rejected, .cancelled, .expired, .invalidated, .applied] {
            let (flow, service, journal) = await setup();let command = NativeFriendCommand(peerID: 9, action: .request, message: "private application")
            service.failure = .unknown;await flow.perform(command)
            service.review = review(command.requestID, state: terminal);service.outcome = terminal.rawValue;await flow.recover()
            XCTAssertEqual(flow.lastReview?.state, terminal);XCTAssertTrue(journal.records.isEmpty);XCTAssertEqual(service.writes.count, 1)
        }
    }
    func testReviewCancelRecoveryCannotClearDifferentProposalOrOrdinaryCancel() async {
        let (flow, service, journal) = await setup();let command = NativeFriendCommand(peerID: 9, action: .cancel, expectedVersion: 1, reviewID: 71)
        service.failure = .unknown;await flow.perform(command)
        XCTAssertTrue(journal.records[0].targetKey.hasSuffix(".cancel.review.71"))
        service.review = review(UUID().uuidString, state: .cancelled, reviewID: 72);await flow.recover()
        XCTAssertNotNil(flow.pending);XCTAssertEqual(flow.phase, .unknown)
        service.review = review(UUID().uuidString, state: .cancelled);await flow.recover()
        XCTAssertTrue(journal.records.isEmpty);XCTAssertEqual(service.writes, [command])
        service.failure = nil;await flow.perform(.init(peerID: 9, action: .cancel, expectedVersion: 1))
        XCTAssertNotNil(flow.pending, "ordinary relationship cancellation must not consume a review receipt")
    }
    func testReviewPaginationUsesIndependentCursorAndRetainsRowsOnFailure() async {
        let (flow, service, _) = await setup();service.reviews = [review(UUID().uuidString)];service.reviewHasMore = true;service.reviewNextCursor = 71
        await flow.load();service.pageFailure = true;await flow.loadMoreReviews();XCTAssertEqual(flow.reviews.count, 1);XCTAssertEqual(flow.reviewCursor, 71)
        service.pageFailure = false;service.reviews = [review(UUID().uuidString, reviewID: 72)];service.reviewHasMore = false
        await flow.loadMoreReviews();XCTAssertEqual(flow.reviews.map(\.id), [71,72]);XCTAssertNil(flow.reviewCursor);XCTAssertEqual(service.reviewLookups, [71,71])
    }

    func testSuccessfulRefreshRetiresPendingBannerWhenReviewHasBecomeTerminal() async {
        let (flow, service, _) = await setup();let command = NativeFriendCommand(peerID: 9, action: .request, message: "private application")
        service.review = review(command.requestID);service.outcome = "PENDING_REVIEW";await flow.perform(command)
        XCTAssertEqual(flow.lastReview?.state, .pending)
        service.reviews = [review(command.requestID, state: .rejected)];await flow.load()
        XCTAssertEqual(flow.reviews.first?.state, .rejected);XCTAssertNil(flow.lastReview);XCTAssertNil(flow.relationship)
    }

}
