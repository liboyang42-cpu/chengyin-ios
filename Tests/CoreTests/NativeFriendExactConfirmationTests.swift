import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class NativeFriendExactConfirmationTests: XCTestCase {
    private final class Journal: OperationPendingListing {
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
        var unknown = false
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
                outcome: unknown ? "UNKNOWN" : "APPLIED", relationship: try await relationship(peerID: peerID), payloadHash: writes.first { $0.requestID == requestID }?.originalIntentProof)
        }
    }
    private final class Storage: ProjectEditDataStorage {
        var values: [String: Data] = [:]
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { values[key] = data }
        func remove(_ key: String) throws { values.removeValue(forKey:key) }
    }
    private func item(_ peer: Int64 = 9) -> NativeFriendItem { .init(peerID:peer,nickname:"Fixture",state:.pendingIncoming,version:3,message:"Original",expiresAtMS:1_900_000_000_000) }
    private func make(_ s: Service, _ j: Journal, _ storage: Storage, owner: String = "deployment|owner-2") -> NativeFriendFlow {
        .init(service:s,journal:j,ownerKey:owner,intentJournal:.init(storage:storage,ownerKey:owner))
    }
    func testOldAcceptCannotBecomeNewReject() async throws {
        let s=Service(),j=Journal(),storage=Storage(),f=make(s,j,storage);s.incoming=[item()];await f.load();f.reviewAction(.accept,item:item());let old=try XCTUnwrap(f.actionReview)
        f.cancelReview();f.reviewAction(.reject,item:item());let next=try XCTUnwrap(f.actionReview);await f.confirmReview(expected:old)
        XCTAssertEqual(f.actionReview,next);XCTAssertTrue(s.writes.isEmpty);XCTAssertTrue(j.records.isEmpty);XCTAssertTrue(storage.values.isEmpty)
    }
    func testOldPeerConfirmationCannotDispatchAnotherPeer() async throws {
        let s=Service(),j=Journal(),storage=Storage(),f=make(s,j,storage);s.incoming=[item(),item(10)];await f.load();f.reviewAction(.accept,item:item());let old=try XCTUnwrap(f.actionReview)
        f.cancelReview();f.reviewAction(.accept,item:item(10));await f.confirmReview(expected:old);XCTAssertEqual(f.actionReview?.command.peerID,10);XCTAssertTrue(s.writes.isEmpty)
    }
    func testSameRequestTextWithNewUUIDNeedsFreshConsent() async throws {
        let s=Service(),j=Journal(),storage=Storage(),f=make(s,j,storage);await f.load();f.reviewRequest(peerID:9,message:"hello");let old=try XCTUnwrap(f.actionReview)
        f.cancelReview();f.reviewRequest(peerID:9,message:"hello");let next=try XCTUnwrap(f.actionReview);XCTAssertNotEqual(old.command.requestID,next.command.requestID)
        await f.confirmReview(expected:old);XCTAssertEqual(f.actionReview,next);XCTAssertTrue(s.writes.isEmpty)
    }
    func testNormalExactAcceptUsesOriginalHashReceiptAndCurrent() async throws {
        let s=Service(),j=Journal(),storage=Storage(),f=make(s,j,storage);s.incoming=[item()];await f.load();f.reviewAction(.accept,item:item());let original=try XCTUnwrap(f.actionReview)
        await f.confirmReview(expected:original);XCTAssertEqual(s.writes,[original.command]);XCTAssertEqual(f.relationship?.state,.friend);XCTAssertNil(f.pending);XCTAssertTrue(j.records.isEmpty);XCTAssertTrue(storage.values.isEmpty)
        await f.confirmReview(expected:original);XCTAssertEqual(s.writes.count,1)
    }
    func testUnknownRestartOnlyRecoversOriginalProof() async throws {
        let s=Service(),j=Journal(),storage=Storage(),f=make(s,j,storage);s.incoming=[item()];await f.load();f.reviewAction(.accept,item:item());let original=try XCTUnwrap(f.actionReview)
        s.writeFailure = .unknown;await f.confirmReview(expected:original);f.invalidate();let next=make(s,j,storage);await next.load();XCTAssertNotNil(next.pending)
        s.unknown=true;await next.recover();XCTAssertNotNil(next.pending);XCTAssertEqual(s.recovered,[original.command.requestID]);XCTAssertEqual(s.writes.count,1)
        s.unknown=false;await next.recover();XCTAssertNil(next.pending);XCTAssertTrue(j.records.isEmpty);XCTAssertTrue(storage.values.isEmpty);XCTAssertEqual(s.writes.count,1)
    }
    func testRevokedAuthorityCannotConsumeConfirmedReview() async throws {
        let s=Service(),j=Journal(),storage=Storage(),f=make(s,j,storage);s.incoming=[item()];await f.load();f.reviewAction(.accept,item:item());let original=try XCTUnwrap(f.actionReview)
        s.allowed=false;await f.confirmReview(expected:original);XCTAssertTrue(s.writes.isEmpty);XCTAssertTrue(j.records.isEmpty)
    }
    func testBackgroundAfterDispatchKeepsOwnerOriginal() async throws {
        let s=Service(),j=Journal(),storage=Storage(),f=make(s,j,storage);s.incoming=[item()];await f.load();f.reviewAction(.accept,item:item());let original=try XCTUnwrap(f.actionReview)
        s.beforeWrite={_ in f.invalidate()};await f.confirmReview(expected:original);XCTAssertEqual(j.records.count,1);XCTAssertFalse(storage.values.isEmpty)
        let other=make(s,j,storage,owner:"other-owner");await other.load();XCTAssertNil(other.pending);XCTAssertEqual(j.records.count,1);XCTAssertEqual(s.writes,[original.command])
    }
}
