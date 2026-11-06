import Foundation
import XCTest
@testable import QuestifyCore

/// Same protected intent survives loss of the originating channel. Synthetic storage/services only.
@MainActor final class NativeFriendIndependentRecoveryTests: XCTestCase {
    private final class Storage: ProjectEditDataStorage {
        var values: [String: Data] = [:]
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { values[key] = data }
        func remove(_ key: String) throws { values.removeValue(forKey: key) }
    }
    private final class Journal: OperationPendingListing {
        var rows: [OperationPendingRecord] = []
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
            rows.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey }
        }
        func pendingRecords(ownerKey: String) throws -> [OperationPendingRecord] { rows.filter { $0.ownerKey == ownerKey } }
        func write(_ record: OperationPendingRecord) throws { rows.removeAll { $0.ownerKey == record.ownerKey && $0.targetKey == record.targetKey }; rows.append(record) }
        func clear(_ record: OperationPendingRecord) throws { rows.removeAll { $0 == record } }
    }
    private final class Service: NativeFriendServing {
        var viewerID: Int64 = 2
        var isCurrent = true
        var canWrite = true
        var pageFailure = false
        var writes: [NativeFriendCommand] = []
        var lookups: [String] = []
        var receiptIntent: NativeFriendCommand?
        var terminal = false
        var wrongProof = false
        var holdReceipt = false
        var receiptGate: CheckedContinuation<Void, Never>?
        func page(requests: Bool, cursor: Int64) async throws -> NativeFriendPage {
            if pageFailure { throw NativeFriendFailure.unknown }
            return .init(viewerID: viewerID, incoming: [], outgoing: [], friends: [], hasMore: false, nextCursor: nil)
        }
        func relationship(peerID: Int64) async throws -> NativeFriendRelationship {
            .init(viewerID: viewerID, peerID: peerID, state: .none, version: 1, conversationID: nil)
        }
        func write(_ command: NativeFriendCommand) async throws -> NativeFriendReceipt {
            writes.append(command); receiptIntent = command; throw NativeFriendFailure.unknown
        }
        func receipt(peerID: Int64, action: NativeFriendAction, requestID: String) async throws -> NativeFriendReceipt {
            lookups.append(requestID)
            if holdReceipt { await withCheckedContinuation { receiptGate = $0 } }
            return .init(viewerID: viewerID, peerID: peerID, action: action, requestID: requestID,
                outcome: terminal ? "APPLIED" : "UNKNOWN", relationship: try await relationship(peerID: peerID),
                payloadHash: wrongProof ? String(repeating: "0", count: 64) : receiptIntent?.originalIntentProof)
        }
    }
    private let owner = "https://friend.test/base|cn|2"
    private func flow(_ service: Service?, _ journal: Journal, _ storage: Storage, owner: String? = nil) -> NativeFriendFlow {
        let key = owner ?? self.owner
        return .init(service: service, journal: journal, ownerKey: key,
            intentJournal: .init(storage: storage, ownerKey: key))
    }
    private func original(_ service: Service, _ journal: Journal, _ storage: Storage) async throws -> NativeFriendCommand {
        let source = flow(service, journal, storage)
        await source.load()
        source.reviewRequest(peerID: 9, message: "Original channel request", source: try .init(channelID: 77))
        let review = try XCTUnwrap(source.actionReview)
        await source.confirmReview(expected: review)
        XCTAssertEqual(source.phase, .unknown)
        XCTAssertEqual(journal.rows.count, 1)
        XCTAssertEqual(service.writes, [review.command])
        source.invalidate()
        return review.command
    }
    func testChannelLossThenIndependentRestartRecoversExactOriginalWithoutReplay() async throws {
        let channel = Service(), journal = Journal(), storage = Storage()
        let command = try await original(channel, journal, storage)
        channel.isCurrent = false
        let independent = Service(); independent.receiptIntent = command; independent.terminal = true
        let home = flow(independent, journal, storage)
        await home.load()
        XCTAssertEqual(home.pending?.operationID, UUID(uuidString: command.requestID))
        XCTAssertTrue(home.canRecover); XCTAssertFalse(home.canRetryOriginal)
        XCTAssertTrue(independent.writes.isEmpty); XCTAssertTrue(independent.lookups.isEmpty)
        await home.retryOriginal()
        XCTAssertTrue(independent.writes.isEmpty); XCTAssertTrue(independent.lookups.isEmpty)
        await home.recover()
        XCTAssertEqual(independent.lookups, [command.requestID.uppercased()])
        XCTAssertTrue(independent.writes.isEmpty); XCTAssertNil(home.pending); XCTAssertTrue(journal.rows.isEmpty)
        XCTAssertNil(try NativeFriendIntentJournal(storage: storage, ownerKey: owner).restore())
        XCTAssertEqual(home.relationship?.state, NativeFriendRelation.none) // The historical result does not invent friendship.
        XCTAssertFalse(channel.isCurrent) // Recovery never restores channel authority.
    }
    func testUnknownReceiptAndEmptyCurrentListsDoNotResolveOriginal() async throws {
        let service = Service(), journal = Journal(), storage = Storage()
        let command = try await original(service, journal, storage)
        let home = flow(service, journal, storage); await home.load(); await home.recover()
        XCTAssertEqual(home.phase, .unknown); XCTAssertEqual(home.pending?.operationID, UUID(uuidString: command.requestID))
        XCTAssertEqual(journal.rows.count, 1); XCTAssertEqual(service.writes.count, 1)
        XCTAssertEqual(try NativeFriendIntentJournal(storage: storage, ownerKey: owner).restore(), command)
    }
    func testMismatchedReceiptProofCannotClearProtectedIntent() async throws {
        let service = Service(), journal = Journal(), storage = Storage()
        let command = try await original(service, journal, storage)
        service.terminal = true; service.wrongProof = true
        let home = flow(service, journal, storage); await home.load(); await home.recover()
        XCTAssertEqual(home.phase, .unknown); XCTAssertEqual(journal.rows.count, 1)
        XCTAssertEqual(try NativeFriendIntentJournal(storage: storage, ownerKey: owner).restore(), command)
        XCTAssertEqual(service.writes.count, 1)
    }
    func testAnotherAccountCannotReadOrRecoverPreviousOwnerOriginal() async throws {
        let service = Service(), journal = Journal(), storage = Storage()
        let command = try await original(service, journal, storage)
        let other = Service(); other.viewerID = 3
        let home = flow(other, journal, storage, owner: "https://friend.test/base|cn|3")
        await home.load(); await home.recover()
        XCTAssertNil(home.pending); XCTAssertFalse(home.canRecover); XCTAssertTrue(other.lookups.isEmpty)
        XCTAssertEqual(journal.rows.first?.operationID, UUID(uuidString: command.requestID))
        XCTAssertEqual(try NativeFriendIntentJournal(storage: storage, ownerKey: owner).restore(), command)
    }
    func testMissingIndependentGrantKeepsOriginalButCannotDispatch() async throws {
        let service = Service(), journal = Journal(), storage = Storage()
        let command = try await original(service, journal, storage)
        let closed = flow(nil, journal, storage); await closed.load(); await closed.recover(); await closed.retryOriginal()
        XCTAssertEqual(closed.phase, .unknown); XCTAssertFalse(closed.canRecover); XCTAssertFalse(closed.canWrite)
        XCTAssertEqual(closed.pending?.operationID, UUID(uuidString: command.requestID)); XCTAssertTrue(service.lookups.isEmpty)
        XCTAssertEqual(journal.rows.count, 1); XCTAssertEqual(service.writes.count, 1)
    }
    func testReadFailureStillAllowsExplicitReceiptRecoveryWithoutNewWrite() async throws {
        let service = Service(), journal = Journal(), storage = Storage()
        _ = try await original(service, journal, storage)
        service.pageFailure = true; service.terminal = true
        let home = flow(service, journal, storage); await home.load()
        XCTAssertTrue(home.canRecover); XCTAssertEqual(home.phase, .unknown)
        await home.recover()
        XCTAssertNil(home.pending); XCTAssertEqual(home.phase, .failed)
        XCTAssertEqual(home.issue, "friend.loadFailure"); XCTAssertEqual(service.writes.count, 1)
        XCTAssertTrue(journal.rows.isEmpty)
    }
    func testRevokedGlobalVisitCannotReviveAfterReapproval() async throws {
        let service = Service(), journal = Journal(), storage = Storage()
        let command = try await original(service, journal, storage)
        let home = flow(service, journal, storage); await home.load()
        service.isCurrent = false; XCTAssertFalse(home.validateAuthority())
        service.isCurrent = true; await home.recover()
        XCTAssertFalse(home.isCurrent); XCTAssertTrue(service.lookups.isEmpty); XCTAssertEqual(journal.rows.count, 1)
        let fresh = Service(); fresh.receiptIntent = command; fresh.terminal = true
        let replacement = flow(fresh, journal, storage); await replacement.load(); await replacement.recover()
        XCTAssertNil(replacement.pending); XCTAssertTrue(fresh.writes.isEmpty)
    }
    func testLateReceiptAfterAccountRevocationCannotSettleOriginal() async throws {
        let service = Service(), journal = Journal(), storage = Storage()
        let command = try await original(service, journal, storage)
        service.terminal = true; service.holdReceipt = true
        let home = flow(service, journal, storage); await home.load()
        let work = Task { await home.recover() }
        for _ in 0..<200 where service.receiptGate == nil { await Task.yield() }
        let gate = try XCTUnwrap(service.receiptGate)
        service.isCurrent = false; XCTAssertFalse(home.validateAuthority()); gate.resume(); await work.value
        XCTAssertEqual(journal.rows.count, 1); XCTAssertNil(home.relationship); XCTAssertFalse(home.canRecover)
        XCTAssertEqual(try NativeFriendIntentJournal(storage: storage, ownerKey: owner).restore(), command)
    }
}
