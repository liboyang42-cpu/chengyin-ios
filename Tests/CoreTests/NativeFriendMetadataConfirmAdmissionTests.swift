import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class NativeFriendMetadataConfirmAdmissionTests: XCTestCase {
    private final class Journal: OperationPendingListing {
        var rows: [OperationPendingRecord] = []; var fail = false
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { rows.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey } }
        func pendingRecords(ownerKey: String) throws -> [OperationPendingRecord] { rows.filter { $0.ownerKey == ownerKey } }
        func write(_ record: OperationPendingRecord) throws { if fail { throw NativeFriendFailure.unavailable }; rows.append(record) }
        func clear(_ record: OperationPendingRecord) throws { rows.removeAll { $0 == record } }
    }
    private final class Service: NativeFriendMetadataServing {
        var canReadGroups = true; var canManageGroups = true; var canStarWrite = true; var canAssignGroup = true; var canProgressWrite = true
        var viewerID: Int64 = 2; var canWrite = true; var canSettle = true; var isCurrent = true
        var writes: [NativeFriendMetadataCommand] = []; var lookups: [UUID] = []; var settlements: [UUID] = []
        var settled: Set<UUID> = []; var loseSettlement = false; var wrongHash = false
        var failure: NativeFriendFailure?; var unknown = false; var wrongOwner = false; var retireDuringWrite = false; var readsFail = false
        var current = NativeFriendMetadata(viewerID: 2, peerID: 9, friendVersion: 3, version: 0, remark: nil, groupID: nil, starred: 0, notificationEffect: "NOT_CONNECTED")
        var page = NativeFriendMetadataGroups(viewerID: 2, list: [.init(id: nil, name: "默认分组", position: 0, version: 0, isDefault: 1), .init(id: 4, name: "Bikes", position: 1, version: 2, isDefault: 0)])
        func read(peerID: Int64) async throws -> NativeFriendMetadata { if readsFail { throw NativeFriendFailure.unknown }; return current }
        func groups() async throws -> NativeFriendMetadataGroups { page }
        func write(_ command: NativeFriendMetadataCommand) async throws -> NativeFriendMetadataReceipt {
            writes.append(command); if retireDuringWrite { isCurrent = false }; if let failure { throw failure }
            if command.action == .remark { current = .init(viewerID: viewerID, peerID: command.targetID, friendVersion: 3, version: 1, remark: command.remark, groupID: command.groupID, starred: command.starred ?? 0, notificationEffect: "NOT_CONNECTED") }
            return answer(command.action, command.targetID, command.requestID)
        }
        func receipt(action: NativeFriendMetadataAction, targetID: Int64, requestID: UUID) async throws -> NativeFriendMetadataReceipt {
            lookups.append(requestID); return answer(action, targetID, requestID)
        }
        func settle(action: NativeFriendMetadataAction, targetID: Int64, requestID: UUID, payloadHash: String) async throws -> NativeFriendMetadataReceipt {
            guard canSettle else { throw NativeFriendFailure.notSent }
            settlements.append(requestID); settled.insert(requestID)
            if loseSettlement { throw NativeFriendFailure.unknown }
            return answer(action, targetID, requestID)
        }
        private func answer(_ action: NativeFriendMetadataAction, _ target: Int64, _ identity: UUID) -> NativeFriendMetadataReceipt {
            let outcome = settled.contains(identity) ? "REJECTED" : (unknown ? "UNKNOWN" : "APPLIED")
            return .init(viewerID: wrongOwner ? 3 : viewerID, requestID: identity.uuidString, action: action, targetID: target,
                  outcome: outcome, current: action == .remark && outcome == "APPLIED" ? current : nil,
                  groups: action != .remark && outcome == "APPLIED" ? page : nil,
                  payloadHash: wrongHash ? String(repeating: "0", count: 64) : (try? writes.first(where: { $0.requestID == identity })?.fingerprint()))
        }
    }
    private func make(_ s: Service, _ j: Journal, owner: String = "owner-2") -> NativeFriendMetadataFlow { .init(peerID:9,service:s,journal:j,ownerKey:owner) }
    func testCancelledRemarkCannotDispatchReplacementText() async throws {
        let s=Service(),j=Journal(),f=make(s,j); await f.load(); f.reviewMetadata(remark:"first",groupID:nil,starred:false); let old=try XCTUnwrap(f.review)
        f.cancelReview(); f.reviewMetadata(remark:"second",groupID:nil,starred:false); let replacement=try XCTUnwrap(f.review); await f.confirm(expected:old)
        XCTAssertEqual(f.review,replacement); XCTAssertTrue(s.writes.isEmpty); XCTAssertTrue(j.rows.isEmpty)
    }
    func testOldRemarkCannotBecomeGroupDeletion() async throws {
        let s=Service(),j=Journal(),f=make(s,j); await f.load(); f.reviewMetadata(remark:"first",groupID:nil,starred:false); let old=try XCTUnwrap(f.review)
        f.cancelReview(); f.reviewDeleteGroup(id:4,moveTo:nil); let next=try XCTUnwrap(f.review); XCTAssertEqual(next.action,.groupDelete)
        await f.confirm(expected:old); XCTAssertEqual(f.review,next); XCTAssertTrue(s.writes.isEmpty)
    }
    func testSamePayloadNewUUIDStillNeedsItsOwnConsent() async throws {
        let s=Service(),j=Journal(),f=make(s,j); await f.load(); f.reviewMetadata(remark:"first",groupID:nil,starred:false); let old=try XCTUnwrap(f.review)
        f.cancelReview(); f.reviewMetadata(remark:"first",groupID:nil,starred:false); let next=try XCTUnwrap(f.review); XCTAssertNotEqual(old.requestID,next.requestID)
        await f.confirm(expected:old); XCTAssertEqual(f.review,next); XCTAssertTrue(s.writes.isEmpty)
    }
    func testExactNormalWritePreservesHashReceiptAndCurrent() async throws {
        let s=Service(),j=Journal(),f=make(s,j); await f.load(); f.reviewMetadata(remark:"first",groupID:nil,starred:false); let original=try XCTUnwrap(f.review)
        await f.confirm(expected:original); XCTAssertEqual(s.writes,[original]); XCTAssertTrue(f.didApply); XCTAssertEqual(f.metadata?.remark,"first"); XCTAssertTrue(j.rows.isEmpty)
    }
    func testDuplicateConfirmedTapIsNotAnotherWrite() async throws {
        let s=Service(),j=Journal(),f=make(s,j); await f.load(); f.reviewMetadata(remark:"first",groupID:nil,starred:false); let original=try XCTUnwrap(f.review)
        await f.confirm(expected:original); await f.confirm(expected:original); XCTAssertEqual(s.writes.count,1)
    }
    func testRetiredReviewCannotApplyAfterReload() async throws {
        let s=Service(),j=Journal(),f=make(s,j); await f.load(); f.reviewMetadata(remark:"first",groupID:nil,starred:false); let old=try XCTUnwrap(f.review)
        f.invalidate(); await f.load(); f.reviewMetadata(remark:"next",groupID:nil,starred:false); await f.confirm(expected:old); XCTAssertTrue(s.writes.isEmpty)
    }
    func testUnknownRestartUsesOriginalProofOnlyReceipt() async throws {
        let s=Service(),j=Journal(),f=make(s,j); await f.load(); f.reviewMetadata(remark:"private",groupID:nil,starred:false); let original=try XCTUnwrap(f.review)
        s.failure = .unknown; await f.confirm(expected:original); f.invalidate(); let next=make(s,j); await next.load(); XCTAssertEqual(next.pending?.operationID,original.requestID)
        s.unknown=true; await next.recover(); XCTAssertNotNil(next.pending); XCTAssertEqual(s.writes.count,1); XCTAssertEqual(s.lookups,[original.requestID]); XCTAssertTrue(s.settlements.isEmpty)
    }
    func testRevocationAndOtherOwnerCannotUseOldConsentOrPending() async throws {
        let s=Service(),j=Journal(),f=make(s,j); await f.load(); f.reviewMetadata(remark:"private",groupID:nil,starred:false); let original=try XCTUnwrap(f.review)
        s.isCurrent=false; await f.confirm(expected:original); XCTAssertTrue(s.writes.isEmpty)
        s.isCurrent=true; s.failure = .unknown; await f.confirm(expected:original); let other=make(s,j,owner:"owner-8"); await other.load(); XCTAssertNil(other.pending)
    }
}
