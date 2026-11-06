import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class NativeFriendOriginalReplayBoundaryTests: XCTestCase {
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
        func write(_ record: OperationPendingRecord) throws { rows.append(record) }
        func clear(_ record: OperationPendingRecord) throws { rows.removeAll { $0 == record } }
    }
    private final class Service: NativeFriendServing {
        let viewerID: Int64 = 2
        var isCurrent = true, canWrite = true
        var writes: [NativeFriendCommand] = []
        var duringReceipt: (() throws -> Void)?
        func page(requests: Bool, cursor: Int64) async throws -> NativeFriendPage {
            .init(viewerID: viewerID, incoming: [], outgoing: [], friends: [], hasMore: false, nextCursor: nil)
        }
        func relationship(peerID: Int64) async throws -> NativeFriendRelationship {
            .init(viewerID: viewerID, peerID: peerID, state: .none, version: 0, conversationID: nil)
        }
        func write(_ command: NativeFriendCommand) async throws -> NativeFriendReceipt {
            writes.append(command); throw NativeFriendFailure.unknown
        }
        func receipt(peerID: Int64, action: NativeFriendAction, requestID: String) async throws -> NativeFriendReceipt {
            try duringReceipt?()
            return .init(viewerID: viewerID, peerID: peerID, action: action, requestID: requestID, outcome: "UNKNOWN", relationship: nil)
        }
    }
    private func exercise(_ change: @escaping (Journal, NativeFriendIntentJournal, NativeFriendCommand) throws -> Void) async throws {
        let storage = Storage(), journal = Journal(), service = Service()
        let intent = NativeFriendIntentJournal(storage: storage, ownerKey: "original-owner")
        let flow = NativeFriendFlow(service: service, journal: journal, ownerKey: "original-owner", intentJournal: intent)
        await flow.load()
        let command = NativeFriendCommand(peerID: 9, action: .request, message: "Original request")
        await flow.perform(command)
        XCTAssertEqual(service.writes, [command]); XCTAssertTrue(flow.canRetryOriginal)
        // Simulates another owner-scoped page completing/replacing the durable
        // record while this page awaits the original receipt.
        service.duringReceipt = { try change(journal, intent, command) }
        await flow.retryOriginal()
        XCTAssertEqual(service.writes, [command], "A stale UNKNOWN must not forward a settled or changed original")
        XCTAssertEqual(flow.phase, .unknown)
    }
    func testSettledRecordCannotBeReplayedFromCachedUnknown() async throws {
        try await exercise { journal, intent, command in
            for row in journal.rows { try journal.clear(row) }
            try intent.settle(command)
        }
    }
    func testReplacedRecordCannotBeReplayedFromCachedUnknown() async throws {
        try await exercise { journal, _, _ in
            let old = try XCTUnwrap(journal.rows.first)
            journal.rows = [.init(ownerKey: old.ownerKey, targetKey: old.targetKey)]
        }
    }
    func testChangedProtectedIntentCannotAuthorizeOldBody() async throws {
        try await exercise { _, intent, command in
            try intent.settle(command)
            try intent.save(.init(peerID: 9, action: .request, message: "New reviewed request"))
        }
    }
    func testUnchangedOriginalStillReplaysIdenticalCommand() async throws {
        let storage = Storage(), journal = Journal(), service = Service()
        let flow = NativeFriendFlow(service: service, journal: journal, ownerKey: "unchanged-owner",
            intentJournal: .init(storage: storage, ownerKey: "unchanged-owner"))
        await flow.load()
        let command = NativeFriendCommand(peerID: 9, action: .request, message: "Exact original")
        await flow.perform(command); await flow.retryOriginal()
        XCTAssertEqual(service.writes, [command, command]); XCTAssertEqual(journal.rows.count, 1)
        XCTAssertEqual(flow.pending?.operationID, UUID(uuidString: command.requestID))
    }
}
