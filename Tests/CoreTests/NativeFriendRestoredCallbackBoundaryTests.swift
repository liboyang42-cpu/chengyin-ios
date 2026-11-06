import Foundation
import XCTest
@testable import QuestifyCore

// Independent regression fixtures adapted from retained original test sources.
// No network, real account, or platform storage is accessed.

@MainActor final class NativeFriendRestoredCallbackTests: XCTestCase {
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

    func testPresentationCloseBeforeDispatchPreservesOriginalWithoutWrite() async throws {
        let s = Service(), j = Journal(), storage = Storage(), f = make(s, j, storage)
        await f.load(); f.reviewRequest(peerID: 9, message: "Original")
        let original = try XCTUnwrap(f.actionReview)
        f.onChange = { if f.busy { f.onChange = nil; f.invalidate() } }
        await f.confirmReview(expected: original)
        XCTAssertTrue(s.writes.isEmpty); XCTAssertEqual(j.records.count, 1)
        XCTAssertEqual(j.records.first?.operationID, UUID(uuidString: original.command.requestID))
        XCTAssertFalse(storage.values.isEmpty)
    }
    func testPresentationCloseBeforeRefreshDoesNotReadRetiredVisit() async {
        let s = Service(), j = Journal(), storage = Storage(), f = make(s, j, storage)
        f.onChange = { if f.busy { f.onChange = nil; f.invalidate() } }
        await f.load(); XCTAssertEqual(s.reads, 0); XCTAssertTrue(f.friends.isEmpty)
    }
}

@MainActor final class NativeFriendMetadataRestoredCallbackTests: XCTestCase {
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
        var reads = 0
        var writes: [NativeFriendMetadataCommand] = []; var lookups: [UUID] = []; var settlements: [UUID] = []
        var settled: Set<UUID> = []; var loseSettlement = false; var wrongHash = false
        var failure: NativeFriendFailure?; var unknown = false; var wrongOwner = false; var retireDuringWrite = false; var readsFail = false
        var current = NativeFriendMetadata(viewerID: 2, peerID: 9, friendVersion: 3, version: 0, remark: nil, groupID: nil, starred: 0, notificationEffect: "NOT_CONNECTED")
        var page = NativeFriendMetadataGroups(viewerID: 2, list: [.init(id: nil, name: "默认分组", position: 0, version: 0, isDefault: 1), .init(id: 4, name: "Bikes", position: 1, version: 2, isDefault: 0)])
        func read(peerID: Int64) async throws -> NativeFriendMetadata { reads += 1; if readsFail { throw NativeFriendFailure.unknown }; return current }
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

    func testPresentationCloseBeforeMetadataDispatchKeepsOwnerOriginal() async throws {
        let s = Service(), j = Journal(), f = make(s, j)
        await f.load(); f.reviewMetadata(remark: "Original", groupID: nil, starred: false)
        let original = try XCTUnwrap(f.review)
        f.onChange = { if f.busy { f.onChange = nil; f.invalidate() } }
        await f.confirm(expected: original)
        XCTAssertTrue(s.writes.isEmpty); XCTAssertEqual(j.rows.count, 1)
        XCTAssertEqual(j.rows.first?.operationID, original.requestID)
        XCTAssertNil(f.metadata); XCTAssertNil(f.review)
    }
    func testPresentationCloseBeforeMetadataReadDoesNotReadRetiredVisit() async {
        let s = Service(), j = Journal(), f = make(s, j)
        f.onChange = { if f.busy { f.onChange = nil; f.invalidate() } }
        await f.load(); XCTAssertEqual(s.reads, 0); XCTAssertNil(f.metadata)
    }
}

@MainActor final class NativeBlacklistRestoredCallbackTests: XCTestCase {
    final class Journal: OperationPendingListing {
        var records: [OperationPendingRecord] = []; var failWrite = false
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey } }
        func pendingRecords(ownerKey: String) throws -> [OperationPendingRecord] { records.filter { $0.ownerKey == ownerKey } }
        func write(_ value: OperationPendingRecord) throws { if failWrite { throw NativeBlacklistFailure.invalid }; records.append(value) }
        func clear(_ value: OperationPendingRecord) throws { records.removeAll { $0 == value } }
    }
    final class Service: NativeBlacklistServing {
        var viewerID: Int64 = 2, isCurrent = true, canWrite = true, canSettle = true
        var items = [NativeBlacklistItem(blockID: 30, peerID: 9, nickname: "Synthetic peer")]
        var writes = 0, receipts = 0, settles = 0, pages = 0, reads = 0
        var pageValues: [Int64: NativeBlacklistPage] = [:]
        var failCursors: Set<Int64> = []
        var loseResponse = false, failReadback = false, unknown = false, notSent = false
        var afterWrite: (() -> Void)?
        var terminal: [UUID: NativeBlacklistReceipt] = [:]
        func page(cursor: Int64) async throws -> NativeBlacklistPage {
            pages += 1
            if failCursors.contains(cursor) { throw NativeBlacklistFailure.unknown }
            return pageValues[cursor] ?? .init(viewerID: viewerID, items: items, writeEnabled: canWrite)
        }
        func current(peerID: Int64) async throws -> NativeBlacklistCurrent {
            reads += 1; if failReadback { throw NativeBlacklistFailure.unknown }
            let item = items.first { $0.peerID == peerID }; return .init(viewerID: viewerID, peerID: peerID, blocked: item != nil, blockID: item?.blockID)
        }
        func unblock(_ c: NativeBlacklistCommand) async throws -> NativeBlacklistReceipt {
            if notSent { throw NativeBlacklistFailure.notSent }; writes += 1
            if unknown { throw NativeBlacklistFailure.unknown }
            let receipt = NativeBlacklistReceipt(viewerID: viewerID, command: c, outcome: "APPLIED", reason: "UNBLOCKED")
            terminal[c.requestID] = receipt; items.removeAll { $0.blockID == c.expectedBlockID }; afterWrite?()
            if loseResponse { throw NativeBlacklistFailure.unknown }; return receipt
        }
        func receipt(_ c: NativeBlacklistCommand) async throws -> NativeBlacklistReceipt {
            receipts += 1; return terminal[c.requestID] ?? .init(viewerID: viewerID, command: c, outcome: "UNKNOWN")
        }
        func settle(_ c: NativeBlacklistCommand) async throws -> NativeBlacklistReceipt {
            settles += 1; let receipt = terminal[c.requestID] ?? .init(viewerID: viewerID, command: c, outcome: "REJECTED", reason: "FINALIZED_WITHOUT_CHANGE")
            terminal[c.requestID] = receipt; return receipt
        }
    }
    private func makeFlow(_ service: Service?, _ journal: Journal? = nil, owner: String = "owner-2") -> NativeBlacklistFlow {
        .init(service: service, journal: journal ?? Journal(), ownerKey: owner)
    }

    func testPresentationCloseBeforeUnblockKeepsExactDurableOriginal() async throws {
        let s = Service(), j = Journal(), f = makeFlow(s, j)
        await f.load(); await f.reviewUnblock(try XCTUnwrap(f.items.first))
        let original = try XCTUnwrap(f.review)
        f.onChange = { if f.busy { f.onChange = nil; f.invalidate() } }
        await f.confirm(expected: original)
        XCTAssertEqual(s.writes, 0); XCTAssertEqual(j.records.count, 1)
        XCTAssertEqual(j.records.first?.operationID, original.requestID)
        XCTAssertTrue(f.items.isEmpty); XCTAssertNil(f.review)
    }
    func testPresentationCloseBeforeBlacklistReadDoesNotReadRetiredVisit() async {
        let s = Service(), j = Journal(), f = makeFlow(s, j)
        f.onChange = { if f.busy { f.onChange = nil; f.invalidate() } }
        await f.load(); XCTAssertEqual(s.pages, 0); XCTAssertTrue(f.items.isEmpty)
    }
}

@MainActor final class NativeFriendRemovalRestoredCallbackTests: XCTestCase {
    private final class Journal: OperationPendingListing {
        var rows: [OperationPendingRecord] = []; var failWrite = false; var failClear = false
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { rows.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey } }
        func pendingRecords(ownerKey: String) throws -> [OperationPendingRecord] { rows.filter { $0.ownerKey == ownerKey } }
        func write(_ record: OperationPendingRecord) throws { if failWrite { throw NativeFriendFailure.unavailable }; rows.append(record) }
        func clear(_ record: OperationPendingRecord) throws { if failClear { throw NativeFriendFailure.unavailable }; rows.removeAll { $0 == record } }
    }
    private final class Service: NativeFriendRemovalServing {
        var viewerID: Int64 = 2; var isCurrent = true; var canWrite = true; var canSettle = true
        var reads = 0
        var writes: [NativeFriendRemovalCommand] = []; var lookups: [NativeFriendRemovalCommand] = []; var settlements: [NativeFriendRemovalCommand] = []
        var failure: NativeFriendFailure?; var retireDuringWrite = false; var wrongOwner = false; var wrongPayload = false
        var beforeSend: (() -> Void)?; var outcome = "APPLIED"; var currentState: NativeFriendRelation = .friend; var version: Int64 = 3
        func relationship(peerID: Int64) async throws -> NativeFriendRelationship { reads += 1; return .init(viewerID: viewerID, peerID: peerID, state: currentState, version: version, conversationID: 80) }
        func remove(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt {
            beforeSend?(); writes.append(command); if retireDuringWrite { isCurrent = false }; if let failure { throw failure }; return try await answer(command)
        }
        func receipt(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt { lookups.append(command); return try await answer(command) }
        func settle(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt { settlements.append(command); outcome = "REJECTED"; return try await answer(command) }
        private func answer(_ command: NativeFriendRemovalCommand) async throws -> NativeFriendRemovalReceipt {
            let identity = wrongPayload ? NativeFriendRemovalCommand(requestID: command.requestID, peerID: command.peerID, expectedVersion: command.expectedVersion + 1) : command
            return .init(viewerID: wrongOwner ? 8 : viewerID, command: identity, outcome: outcome,
                         reason: outcome == "APPLIED" ? "REMOVED" : "FINALIZED_WITHOUT_REMOVAL", removedVersion: outcome == "APPLIED" ? identity.expectedVersion + 1 : nil, currentRelationship: try await relationship(peerID: command.peerID))
        }
    }
    private let item = NativeFriendItem(peerID: 9, nickname: "friend", state: .friend, version: 3, message: "", expiresAtMS: 0)
    private func setup() async -> (NativeFriendRemovalFlow, Service, Journal) {
        let service = Service(), journal = Journal(), flow = NativeFriendRemovalFlow(item: item, service: service, journal: journal, ownerKey: "owner-2")
        await flow.load(); return (flow, service, journal)
    }

    func testPresentationCloseBeforeRemovalKeepsExactDurableOriginal() async throws {
        let (f, s, j) = await setup(); f.reviewRemoval()
        let original = try XCTUnwrap(f.review)
        f.onChange = { if f.busy { f.onChange = nil; f.invalidate() } }
        await f.confirm()
        XCTAssertTrue(s.writes.isEmpty); XCTAssertEqual(j.rows.count, 1)
        XCTAssertEqual(j.rows.first?.operationID, original.requestID)
        XCTAssertNil(f.currentRelationship); XCTAssertNil(f.review)
    }
    func testPresentationCloseBeforeRelationshipReadDoesNotReadRetiredVisit() async {
        let s = Service(), j = Journal()
        let f = NativeFriendRemovalFlow(item: item, service: s, journal: j, ownerKey: "owner-2")
        f.onChange = { if f.busy { f.onChange = nil; f.invalidate() } }
        await f.load(); XCTAssertEqual(s.reads, 0); XCTAssertNil(f.currentRelationship)
    }
}
