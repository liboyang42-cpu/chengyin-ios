import Foundation
import XCTest
@testable import QuestifyCore

/// Local protocol fixtures only. No real friend operation or deployment grant is enabled.
@MainActor final class NativeFriendRequestReviewClosureTests: XCTestCase {
    private final class IntentStorage: ProjectEditDataStorage {
        var rows: [String: Data] = [:]
        func read(_ key: String) throws -> Data? { rows[key] }
        func write(_ data: Data, key: String) throws { rows[key] = data }
        func remove(_ key: String) throws { rows.removeValue(forKey: key) }
    }
    private final class Journal: OperationPendingListing {
        let intentStorage = IntentStorage()
        var records: [OperationPendingRecord] = []
        var failWrites = false
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey } }
        func pendingRecords(ownerKey: String) throws -> [OperationPendingRecord] { records.filter { $0.ownerKey == ownerKey } }
        func write(_ record: OperationPendingRecord) throws { if failWrites { throw NativeFriendFailure.unavailable }; records.append(record) }
        func clear(_ record: OperationPendingRecord) throws { records.removeAll { $0 == record } }
    }
    private final class Service: NativeFriendServing {
        let viewerID: Int64 = 2
        var allowed = true
        var expiresAt = Date.distantFuture
        var isCurrent: Bool { allowed && Date() < expiresAt }
        var canWrite = true
        var reads = 0
        var incoming: [NativeFriendItem] = []
        var outgoing: [NativeFriendItem] = []
        var friends: [NativeFriendItem] = []
        var reviews: [NativeFriendReview] = []
        var writes: [NativeFriendCommand] = []
        var recovered: [String] = []
        var beforeWrite: ((NativeFriendCommand) -> Void)?
        var holdWrite = false
        var writeGate: CheckedContinuation<Void, Never>?
        var writeFailure: NativeFriendFailure?
        var readFailure = false
        var unknown = false; var wrongProof = false
        var relation: NativeFriendRelation = .friend
        func page(requests: Bool, cursor: Int64) async throws -> NativeFriendPage {
            reads += 1
            if readFailure { throw NativeFriendFailure.unknown }
            return .init(viewerID: viewerID, incoming: requests ? incoming : [], outgoing: requests ? outgoing : [],
                friends: requests ? [] : friends, hasMore: false, nextCursor: nil, reviews: requests ? reviews : [])
        }
        func relationship(peerID: Int64) async throws -> NativeFriendRelationship {
            .init(viewerID: viewerID, peerID: peerID, state: relation, version: 8, conversationID: relation == .friend ? 71 : nil)
        }
        func write(_ command: NativeFriendCommand) async throws -> NativeFriendReceipt {
            beforeWrite?(command); writes.append(command)
            if holdWrite { await withCheckedContinuation { writeGate = $0 } }
            if let writeFailure { throw writeFailure }
            return try await receiptValue(peerID: command.peerID, action: command.action, requestID: command.requestID)
        }
        func receipt(peerID: Int64, action: NativeFriendAction, requestID: String) async throws -> NativeFriendReceipt {
            recovered.append(requestID)
            return try await receiptValue(peerID: peerID, action: action, requestID: requestID)
        }
        private func receiptValue(peerID: Int64, action: NativeFriendAction, requestID: String) async throws -> NativeFriendReceipt {
            .init(viewerID: viewerID, peerID: peerID, action: action, requestID: requestID,
                outcome: unknown ? "UNKNOWN" : "APPLIED", relationship: try await relationship(peerID: peerID), payloadHash: wrongProof ? "wrong-original-proof" : writes.first { $0.requestID == requestID }?.originalIntentProof)
        }
    }
    private func item(_ peer: Int64 = 9, version: Int64 = 3, state: NativeFriendRelation = .pendingIncoming) -> NativeFriendItem {
        .init(peerID: peer, nickname: "Synthetic peer \(peer)", state: state, version: version,
            message: "Application version \(version)", expiresAtMS: 1_900_000_000_000)
    }
    private func setup() async -> (NativeFriendFlow, Service, Journal) {
        let service = Service(), journal = Journal()
        service.incoming = [item()]; service.outgoing = [item(11, state: .pendingOutgoing)]; service.friends = [item(12, state: .friend)]
        let flow = NativeFriendFlow(service: service, journal: journal, ownerKey: "deployment|owner-2", intentJournal: NativeFriendIntentJournal(storage: journal.intentStorage, ownerKey: "deployment|owner-2"))
        await flow.load(); return (flow, service, journal)
    }
    func testMissingIntentJournalCannotEnableReviewedWrite() async {
        let service = Service(), journal = Journal()
        service.incoming = [item()]
        let flow = NativeFriendFlow(service: service, journal: journal, ownerKey: "deployment|owner-2")
        await flow.load(); flow.reviewAction(.accept, item: item()); await flow.confirmReview()
        XCTAssertFalse(flow.canWrite); XCTAssertNil(flow.actionReview)
        XCTAssertTrue(service.writes.isEmpty); XCTAssertTrue(journal.records.isEmpty)
    }
    func testWrongOriginalProofRetainsBothJournalsAndNeverReposts() async throws {
        let (flow, service, journal) = await setup()
        service.wrongProof = true; flow.reviewAction(.accept, item: item())
        let original = try XCTUnwrap(flow.actionReview?.command)
        await flow.confirmReview(); await flow.recover()
        XCTAssertEqual(service.writes, [original]); XCTAssertEqual(service.recovered, [original.requestID])
        XCTAssertEqual(journal.records.count, 1); XCTAssertNil(flow.relationship)
        XCTAssertEqual(try NativeFriendIntentJournal(storage: journal.intentStorage, ownerKey: "deployment|owner-2").restore(), original)
    }
    private func waitForWrite(_ service: Service) async {
        for _ in 0..<100 { if service.writeGate != nil { return }; await Task.yield() }
        XCTFail("held write did not start")
    }
    func testExactIncomingReviewCancelAndReopenUseOneImmutablePeerAndVersion() async throws {
        let (flow, service, journal) = await setup()
        flow.reviewAction(.accept, item: item())
        let review = try XCTUnwrap(flow.actionReview)
        XCTAssertEqual(review.command.peerID, 9); XCTAssertEqual(review.command.expectedVersion, 3)
        XCTAssertEqual(review.message, "Application version 3")
        flow.reviewAction(.reject, item: item(11, state: .pendingOutgoing))
        XCTAssertEqual(flow.actionReview, review, "a second selection cannot retarget an open review")
        flow.cancelReview(); await flow.confirmReview()
        XCTAssertTrue(service.writes.isEmpty); XCTAssertTrue(journal.records.isEmpty)
        flow.reviewAction(.reject, item: item()); await flow.confirmReview()
        XCTAssertEqual(service.writes.count, 1); XCTAssertEqual(service.writes.first?.action, .reject)
        XCTAssertNotEqual(service.writes.first?.requestID, review.command.requestID)
    }
    func testStaleWithdrawnAndReaddedApplicationCannotReuseOldReview() async {
        let (flow, service, _) = await setup()
        let old = item(); flow.reviewAction(.accept, item: old)
        service.incoming = [item(version: 5)]
        await flow.load(); XCTAssertNil(flow.actionReview)
        flow.reviewAction(.accept, item: old); await flow.confirmReview()
        XCTAssertTrue(service.writes.isEmpty)
        flow.reviewAction(.accept, item: item(version: 5)); await flow.confirmReview()
        XCTAssertEqual(service.writes.first?.expectedVersion, 5)
    }
    func testVersionConflictRefreshesReplacementApplicationWithoutAutomaticRetry() async throws {
        let (flow, service, journal) = await setup()
        let old = item(); flow.reviewAction(.accept, item: old)
        service.incoming = [item(version: 5)]; service.writeFailure = .rejected(409)
        await flow.confirmReview()
        XCTAssertEqual(flow.incoming.first?.version, 5); XCTAssertEqual(flow.issue, "friend.conflict")
        XCTAssertTrue(journal.records.isEmpty); XCTAssertEqual(service.writes.count, 1)
        flow.reviewAction(.accept, item: old); await flow.confirmReview()
        XCTAssertNil(flow.actionReview); XCTAssertEqual(service.writes.count, 1)
        service.writeFailure = nil; flow.reviewAction(.accept, item: item(version: 5)); await flow.confirmReview()
        XCTAssertEqual(service.writes.map(\.expectedVersion), [3, 5])
        // Preserve failure evidence without aborting the complete serial test process.
        let firstWrite = try XCTUnwrap(service.writes.first)
        let secondWrite = try XCTUnwrap(service.writes.dropFirst().first)
        XCTAssertNotEqual(firstWrite.requestID, secondWrite.requestID)
    }
    func testFailedRefreshRetiresUnsentReviewAndCannotDispatchStaleVersion() async {
        let (flow, service, journal) = await setup()
        flow.reviewAction(.reject, item: item()); service.readFailure = true
        await flow.load(); await flow.confirmReview()
        XCTAssertNil(flow.actionReview); XCTAssertTrue(service.writes.isEmpty); XCTAssertTrue(journal.records.isEmpty)
        XCTAssertFalse(flow.canWrite)
    }
    func testRequestReviewCapturesTypedPeerAndMessageAndCancelDoesNotPersist() async throws {
        let (flow, service, journal) = await setup()
        flow.reviewRequest(peerID: 9, message: "One reviewed message")
        let review = try XCTUnwrap(flow.actionReview)
        flow.reviewRequest(peerID: 11, message: "Different message")
        XCTAssertEqual(flow.actionReview, review)
        flow.cancelReview(); XCTAssertTrue(journal.records.isEmpty); XCTAssertTrue(service.writes.isEmpty)
        flow.reviewRequest(peerID: 11, message: "Different message"); await flow.confirmReview()
        XCTAssertEqual(service.writes.first?.peerID, 11); XCTAssertEqual(service.writes.first?.message, "Different message")
    }
    func testDoubleConfirmPersistsBeforeDispatchAndInterruptedSuccessRequiresOriginalReceipt() async throws {
        let (flow, service, journal) = await setup()
        flow.reviewAction(.accept, item: item()); let command = try XCTUnwrap(flow.actionReview?.command)
        service.beforeWrite = { sent in
            XCTAssertEqual(journal.records.count, 1)
            XCTAssertEqual(journal.records.first?.operationID.uuidString, sent.requestID)
            XCTAssertEqual(try? NativeFriendIntentJournal(storage: journal.intentStorage, ownerKey: "deployment|owner-2").restore(), sent)
        }
        service.holdWrite = true
        let first = Task { await flow.confirmReview() }
        await waitForWrite(service); await flow.confirmReview()
        XCTAssertEqual(service.writes, [command]); XCTAssertNil(flow.actionReview)
        flow.invalidate(); service.writeGate?.resume(); service.writeGate = nil; await first.value
        XCTAssertNil(flow.relationship); XCTAssertEqual(flow.phase, .closed)
        XCTAssertEqual(journal.records.count, 1)
        let returned = NativeFriendFlow(service: service, journal: journal, ownerKey: "deployment|owner-2", intentJournal: NativeFriendIntentJournal(storage: journal.intentStorage, ownerKey: "deployment|owner-2"))
        await returned.load(); XCTAssertEqual(returned.phase, .unknown)
        await returned.recover()
        XCTAssertEqual(service.recovered, [command.requestID]); XCTAssertEqual(service.writes, [command])
        XCTAssertTrue(journal.records.isEmpty); XCTAssertEqual(returned.phase, .ready)
    }
    func testUnknownReceiptCannotBeInferredFromCurrentFriendshipOrMissingListRow() async throws {
        let (flow, service, journal) = await setup()
        flow.reviewAction(.accept, item: item()); let original = try XCTUnwrap(flow.actionReview?.command.requestID)
        service.writeFailure = .unknown; await flow.confirmReview()
        service.incoming = []; service.friends = [item(state: .friend)]; service.unknown = true
        await flow.load(); await flow.recover()
        XCTAssertNotNil(flow.pending); XCTAssertEqual(flow.phase, .unknown)
        XCTAssertEqual(journal.records.first?.operationID.uuidString, original)
        XCTAssertEqual(service.recovered, [original]); XCTAssertEqual(service.writes.count, 1)
        XCTAssertNil(flow.relationship)
    }
    func testReviewCancellationCapturesOriginalProposalInsteadOfAnotherReviewForSamePeer() async throws {
        let (flow, service, journal) = await setup()
        let original = NativeFriendReview(id: 71, peerID: 9, requestID: UUID().uuidString, state: .pending,
            version: 3, message: "Private application", expiresAtMS: 1_900_000_000_000)
        service.reviews = [original]; await flow.load(); flow.reviewCancellation(original)
        let command = try XCTUnwrap(flow.actionReview?.command)
        XCTAssertEqual(command.reviewID, 71); XCTAssertEqual(command.expectedVersion, 3)
        service.reviews = [.init(id: 72, peerID: 9, requestID: UUID().uuidString, state: .pending,
            version: 1, message: "Replacement application", expiresAtMS: 1_900_000_000_000)]
        await flow.load(); flow.reviewCancellation(original); await flow.confirmReview()
        XCTAssertNil(flow.actionReview); XCTAssertTrue(service.writes.isEmpty); XCTAssertTrue(journal.records.isEmpty)
    }
    func testSilentExpiryAndWithdrawalHidePrivateSnapshotsAndRetireWithoutNetworkReads() async throws {
        for expiry in [false, true] {
            let (flow, service, _) = await setup()
            flow.reviewAction(.accept, item: item()); let reads = service.reads
            if expiry { service.expiresAt = .distantPast } else { service.allowed = false }
            XCTAssertTrue(flow.incoming.isEmpty); XCTAssertTrue(flow.outgoing.isEmpty); XCTAssertTrue(flow.friends.isEmpty)
            XCTAssertTrue(flow.reviews.isEmpty); XCTAssertNil(flow.relationship); XCTAssertNil(flow.actionReview)
            XCTAssertFalse(flow.canWrite); XCTAssertFalse(flow.canRecover)
            try await Task.sleep(nanoseconds: 350_000_000)
            XCTAssertEqual(flow.phase, .closed); XCTAssertEqual(service.reads, reads)
            service.allowed = true; service.expiresAt = .distantFuture
            await flow.load(); XCTAssertFalse(flow.isCurrent); XCTAssertEqual(service.reads, reads)
        }
    }
    func testAuthorityLossDuringDispatchKeepsOriginalJournalButCannotPublishSuccess() async throws {
        let (flow, service, journal) = await setup()
        flow.reviewAction(.reject, item: item()); service.holdWrite = true
        let task = Task { await flow.confirmReview() }; await waitForWrite(service)
        let original = try XCTUnwrap(journal.records.first)
        service.allowed = false; XCTAssertFalse(flow.validateAuthority())
        service.writeGate?.resume(); service.writeGate = nil; await task.value
        XCTAssertNil(flow.relationship); XCTAssertTrue(flow.incoming.isEmpty)
        XCTAssertEqual(journal.records, [original]); XCTAssertFalse(flow.canRecover)
        let other = NativeFriendFlow(service: nil, journal: journal, ownerKey: "another-deployment|owner-2", intentJournal: NativeFriendIntentJournal(storage: journal.intentStorage, ownerKey: "another-deployment|owner-2"))
        await other.load(); XCTAssertNil(other.pending)
    }
    func testReviewPersistFailureAndBackgroundBeforeConfirmationSendNothing() async {
        let (flow, service, journal) = await setup()
        flow.reviewAction(.accept, item: item()); flow.invalidate(); await flow.confirmReview()
        XCTAssertTrue(service.writes.isEmpty); XCTAssertTrue(journal.records.isEmpty)
        await flow.load(); flow.reviewAction(.accept, item: item()); journal.failWrites = true
        await flow.confirmReview(); XCTAssertTrue(service.writes.isEmpty)
        XCTAssertEqual(flow.issue, "friend.storageFailure"); XCTAssertTrue(journal.records.isEmpty)
    }
}
