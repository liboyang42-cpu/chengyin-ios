import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class NativeFriendRemovalFlowTests: XCTestCase {
    private final class Journal: OperationPendingListing {
        var rows: [OperationPendingRecord] = []; var failWrite = false; var failClear = false
        func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { rows.first { $0.ownerKey == ownerKey && $0.targetKey == targetKey } }
        func pendingRecords(ownerKey: String) throws -> [OperationPendingRecord] { rows.filter { $0.ownerKey == ownerKey } }
        func write(_ record: OperationPendingRecord) throws { if failWrite { throw NativeFriendFailure.unavailable }; rows.append(record) }
        func clear(_ record: OperationPendingRecord) throws { if failClear { throw NativeFriendFailure.unavailable }; rows.removeAll { $0 == record } }
    }
    private final class Service: NativeFriendRemovalServing {
        var viewerID: Int64 = 2; var isCurrent = true; var canWrite = true; var canSettle = true
        var writes: [NativeFriendRemovalCommand] = []; var lookups: [NativeFriendRemovalCommand] = []; var settlements: [NativeFriendRemovalCommand] = []
        var failure: NativeFriendFailure?; var retireDuringWrite = false; var wrongOwner = false; var wrongPayload = false
        var beforeSend: (() -> Void)?; var outcome = "APPLIED"; var currentState: NativeFriendRelation = .friend; var version: Int64 = 3
        func relationship(peerID: Int64) async throws -> NativeFriendRelationship { .init(viewerID: viewerID, peerID: peerID, state: currentState, version: version, conversationID: 80) }
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
    func testRealRowReviewCancelIsZeroWriteAndPersistsOriginalBeforeDispatch() async {
        let (flow, service, journal) = await setup(); flow.reviewRemoval(); flow.cancelReview(); XCTAssertTrue(service.writes.isEmpty); XCTAssertTrue(journal.rows.isEmpty)
        flow.reviewRemoval(); let original = flow.review; service.beforeSend = { XCTAssertEqual(journal.rows.first?.operationID, original?.requestID) }
        var refreshed = 0; flow.onResolved = { refreshed += 1 }; await flow.confirm()
        XCTAssertEqual(service.writes, [original!]); XCTAssertEqual(flow.result?.outcome, "APPLIED"); XCTAssertEqual(refreshed, 1); XCTAssertTrue(journal.rows.isEmpty)
    }
    func testLostResponseSurvivesMissingRowAndRestartWithoutRepost() async throws {
        let (flow, service, journal) = await setup(); service.failure = .unknown; flow.reviewRemoval(); let original = try XCTUnwrap(flow.review)
        await flow.confirm(); flow.invalidate(); service.currentState = .none; service.version = 4
        let reopened = NativeFriendRemovalFlow(service: service, journal: journal, ownerKey: "owner-2"); await reopened.load()
        XCTAssertEqual(reopened.pendingCommand, original); service.outcome = "UNKNOWN"; await reopened.recover(); XCTAssertEqual(reopened.phase, .unknown); XCTAssertNotNil(reopened.pending)
        service.outcome = "APPLIED"; await reopened.recover(); XCTAssertNil(reopened.pending); XCTAssertEqual(reopened.result?.outcome, "APPLIED")
        XCTAssertEqual(service.writes.count, 1); XCTAssertEqual(service.lookups, [original, original]); XCTAssertTrue(service.settlements.isEmpty)
    }
    func testAppliedOriginalAndCurrentReaddedFriendAreDistinct() async {
        let (flow, service, _) = await setup(); flow.reviewRemoval(); service.version = 9; service.currentState = .friend; await flow.confirm()
        XCTAssertEqual(flow.result?.removedVersion, 4); XCTAssertEqual(flow.currentRelationship?.version, 9); XCTAssertEqual(flow.currentRelationship?.state, .friend)
    }
    func testStorageFailurePreventsSendAndUnknownClearFailureRetainsIdentity() async {
        let (flow, service, journal) = await setup(); journal.failWrite = true; flow.reviewRemoval(); await flow.confirm(); XCTAssertTrue(service.writes.isEmpty)
        XCTAssertEqual(flow.phase, .unknown); XCTAssertNotNil(flow.pending); XCTAssertTrue(journal.rows.isEmpty)
        journal.failWrite = false; await flow.confirm(); XCTAssertTrue(service.writes.isEmpty)
        // Reload proves no durable original exists; a fresh review is required, never an automatic resend.
        await flow.load(); flow.reviewRemoval(); journal.failClear = true; await flow.confirm()
        XCTAssertEqual(service.writes.count, 1); XCTAssertNotNil(flow.pending); XCTAssertEqual(journal.rows.count, 1); XCTAssertNil(flow.result)
    }
    func testWrongPayloadOwnerAndLateAccountChangeCannotResolveOriginal() async {
        for scenario in 0..<3 {
            let (flow, service, journal) = await setup(); service.wrongOwner = scenario == 0; service.wrongPayload = scenario == 1; service.retireDuringWrite = scenario == 2
            flow.reviewRemoval(); await flow.confirm(); XCTAssertEqual(journal.rows.count, 1); XCTAssertNil(flow.result); XCTAssertFalse(flow.canReview)
            let other = NativeFriendRemovalFlow(service: nil, journal: journal, ownerKey: "owner-8"); await other.load(); XCTAssertNil(other.pending)
        }
    }
    func testApprovalWithdrawalKeepsOriginalKeyForReadOnlyReapproval() async {
        let (flow, service, journal) = await setup(); service.failure = .unknown; flow.reviewRemoval(); await flow.confirm()
        let original = flow.pendingCommand, savedRows = journal.rows
        service.isCurrent = false; await flow.load()
        XCTAssertNil(flow.pendingCommand); XCTAssertEqual(journal.rows, savedRows)
        XCTAssertFalse(flow.canRecover); XCTAssertFalse(flow.canRetryOriginal); XCTAssertEqual(flow.issue, "friendRemoval.closed")
        let fresh = Service(); fresh.canWrite = false; fresh.canSettle = false
        let reopened = NativeFriendRemovalFlow(service: fresh, journal: journal, ownerKey: "owner-2"); await reopened.load(); XCTAssertEqual(reopened.pendingCommand, original); await reopened.recover()
        XCTAssertEqual(reopened.result?.outcome, "APPLIED"); XCTAssertTrue(fresh.writes.isEmpty); XCTAssertTrue(fresh.settlements.isEmpty)
    }
    func testOwnerWideFenceAndOldRowCannotRemoveRebuiltRelationship() async {
        let (flow, service, journal) = await setup(); let second = NativeFriendRemovalFlow(item: item, service: service, journal: journal, ownerKey: "owner-2"); await second.load()
        flow.reviewRemoval(); second.reviewRemoval(); service.failure = .unknown; await flow.confirm(); await second.confirm(); XCTAssertEqual(service.writes.count, 1); XCTAssertEqual(second.pendingCommand, flow.pendingCommand)
        let clean = NativeFriendRemovalFlow(item: item, service: service, journal: Journal(), ownerKey: "owner-2"); service.version = 8; await clean.load(); XCTAssertFalse(clean.canReview); XCTAssertEqual(clean.phase, .unavailable)
    }
    func testUnsupportedSettlementNeverWritesOrDiscardsUnknownOriginal() async throws {
        let (flow, service, journal) = await setup(); service.failure = .unknown; flow.reviewRemoval(); await flow.confirm(); let original = try XCTUnwrap(flow.pendingCommand)
        service.canSettle = false; await flow.settleOriginal(confirmed: original); XCTAssertTrue(service.settlements.isEmpty)
        service.canSettle = true; await flow.settleOriginal(confirmed: .init(peerID: 9, expectedVersion: 3)); XCTAssertTrue(service.settlements.isEmpty)
        service.canWrite = false; await flow.settleOriginal(confirmed: original)
        XCTAssertFalse(flow.canSettle); XCTAssertTrue(service.settlements.isEmpty); XCTAssertNil(flow.result)
        XCTAssertEqual(flow.pendingCommand, original); XCTAssertEqual(journal.rows.count, 1); XCTAssertEqual(service.writes.count, 1)
        service.outcome = "UNKNOWN"; await flow.recover()
        XCTAssertEqual(flow.pendingCommand, original); XCTAssertEqual(service.lookups, [original]); XCTAssertEqual(service.writes.count, 1)
    }
    func testInvalidationWhileAwaitingNeverPublishesLateResponse() async {
        let (flow, service, journal) = await setup(); service.beforeSend = { flow.invalidate() }; flow.reviewRemoval(); await flow.confirm()
        XCTAssertNil(flow.result); XCTAssertEqual(journal.rows.count, 1)
    }
    func testDefaultsJournalRetainsOriginalAcrossFreshInstancesWithoutCrossOwnerLeak() async throws {
        let suite = "FriendRemovalJournalTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let service = Service(); service.failure = .unknown
        let first = NativeFriendRemovalFlow(item: item, service: service, journal: OperationDefaultsJournal(defaults: defaults), ownerKey: "deployment-A-owner-2")
        await first.load(); first.reviewRemoval(); let original = try XCTUnwrap(first.review); await first.confirm(); first.invalidate()
        let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let fresh = NativeFriendRemovalFlow(service: service, journal: OperationDefaultsJournal(defaults: reopenedDefaults), ownerKey: "deployment-A-owner-2")
        await fresh.load(); XCTAssertEqual(fresh.pendingCommand, original)
        for owner in ["deployment-A-owner-8", "deployment-B-owner-2"] {
            let other = NativeFriendRemovalFlow(service: nil, journal: OperationDefaultsJournal(defaults: reopenedDefaults), ownerKey: owner)
            await other.load(); XCTAssertNil(other.pending)
        }
        await fresh.recover(); XCTAssertEqual(fresh.result?.outcome, "APPLIED"); XCTAssertEqual(service.writes.count, 1)
    }
    func testTwoRecoveryScreensResolveSameTerminalButNeverClearReplacementRecord() async throws {
        let (first, service, journal) = await setup(); service.failure = .unknown; first.reviewRemoval(); await first.confirm()
        let second = NativeFriendRemovalFlow(service: service, journal: journal, ownerKey: "owner-2"); await second.load()
        await first.recover(); XCTAssertEqual(first.result?.outcome, "APPLIED"); XCTAssertTrue(journal.rows.isEmpty)
        await second.recover(); XCTAssertEqual(second.result?.outcome, "APPLIED"); XCTAssertNil(second.pending); XCTAssertEqual(service.writes.count, 1)
        let (third, otherService, otherJournal) = await setup(); otherService.failure = .unknown; third.reviewRemoval(); await third.confirm()
        let old = try XCTUnwrap(otherJournal.rows.first), replacement = OperationPendingRecord(operationID: UUID(), ownerKey: old.ownerKey, targetKey: old.targetKey)
        otherJournal.rows = [replacement]; await third.recover(); XCTAssertNil(third.result); XCTAssertEqual(otherJournal.rows, [replacement]); XCTAssertEqual(third.phase, .unknown)
    }
    func testMalformedVersionCannotTrapOrMatchAndFingerprintIsCrossPlatform() {
        let command = NativeFriendRemovalCommand(peerID: 9, expectedVersion: 3)
        XCTAssertEqual(command.fingerprint, "b425ad86f65dbf86ca3cc2472d8df550af5fbc340d1c4d1d027a8d47a7f17b34")
        for version in [Int64.min, -1, 0, Int64.max] {
            let malformed = NativeFriendRemovalCommand(peerID: 9, expectedVersion: version)
            XCTAssertFalse(NativeFriendRemovalReceipt(viewerID: 2, command: malformed, outcome: "APPLIED", reason: "REMOVED").matches(malformed, viewerID: 2))
        }
    }
}
