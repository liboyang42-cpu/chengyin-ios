import Foundation
import XCTest
@testable import QuestifyCore

/// AUTHORED, NOT_RUN. In-memory fixtures, no endpoint or real account.
@MainActor final class NativeBlacklistFlowTests: XCTestCase {
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
    func testOwnerListReviewExactPeerCancelThenUnblockAndAuthoritativeEmptyReturn() async {
        let service = Service(), journal = Journal(), flow = makeFlow(service, journal)
        await flow.load(); let item = flow.items[0]; await flow.reviewUnblock(item)
        XCTAssertEqual(flow.review?.peerID, 9); XCTAssertEqual(flow.review?.expectedBlockID, 30); XCTAssertEqual(service.writes, 0)
        flow.cancelReview(); XCTAssertNil(flow.review); await flow.reviewUnblock(item); await flow.confirm()
        XCTAssertEqual(flow.result?.outcome, "APPLIED"); XCTAssertEqual(flow.current?.blocked, false)
        XCTAssertTrue(flow.items.isEmpty); XCTAssertTrue(journal.records.isEmpty); XCTAssertEqual(service.writes, 1)
        await flow.load(); XCTAssertEqual(flow.phase, .ready); XCTAssertTrue(flow.items.isEmpty)
    }
    func testLostResponseColdRecoveryDoesNotNeedConversationOrOldBlockRowAndNeverResends() async {
        let service = Service(), journal = Journal(), first = makeFlow(service, journal); service.loseResponse = true
        await first.load(); await first.reviewUnblock(first.items[0]); await first.confirm(); let original = first.pendingCommand
        XCTAssertEqual(first.phase, .unknown); first.invalidate(); XCTAssertNil(first.pendingCommand); XCTAssertEqual(journal.records.count, 1)
        let reopened = makeFlow(service, journal); await reopened.load(); XCTAssertEqual(reopened.pendingCommand, original); XCTAssertTrue(reopened.items.isEmpty)
        await reopened.recover(); XCTAssertEqual(reopened.result?.outcome, "APPLIED"); XCTAssertEqual(service.writes, 1); XCTAssertEqual(service.receipts, 1)
    }
    func testUnknownReadAndReopenCannotClearOriginalOrStartAnotherWrite() async {
        let service = Service(), journal = Journal(), flow = makeFlow(service, journal); service.unknown = true
        await flow.load(); await flow.reviewUnblock(flow.items[0]); await flow.confirm(); let original = flow.pendingCommand
        await flow.recover(); await flow.confirm(); await flow.load()
        XCTAssertEqual(flow.pendingCommand, original); XCTAssertEqual(flow.phase, .unknown); XCTAssertEqual(service.writes, 1); XCTAssertFalse(flow.canReview)
        XCTAssertFalse(journal.records.isEmpty)
    }
    func testNewBlockAfterOriginalAppliedIsDisplayedWithoutReplayingMutation() async {
        let service = Service(), journal = Journal(), flow = makeFlow(service, journal); service.loseResponse = true
        await flow.load(); await flow.reviewUnblock(flow.items[0]); await flow.confirm()
        service.items = [.init(blockID: 50, peerID: 9, nickname: "Same peer again")]; await flow.recover()
        XCTAssertEqual(flow.result?.expectedBlockID, 30); XCTAssertEqual(flow.result?.outcome, "APPLIED")
        XCTAssertEqual(flow.current?.blockID, 50); XCTAssertEqual(service.writes, 1)
    }
    func testExplicitExactSettlementOnlyAndNoMutationRetry() async {
        let service = Service(), journal = Journal(), flow = makeFlow(service, journal); service.unknown = true
        await flow.load(); await flow.reviewUnblock(flow.items[0]); await flow.confirm(); let original = flow.pendingCommand!
        await flow.settleOriginal(confirmed: .init(peerID: 9, expectedBlockID: 30)); XCTAssertEqual(service.settles, 0)
        await flow.settleOriginal(confirmed: original); XCTAssertEqual(service.settles, 1); XCTAssertEqual(service.writes, 1)
        XCTAssertEqual(flow.result?.reason, "FINALIZED_WITHOUT_CHANGE"); XCTAssertEqual(flow.current?.blocked, true)
    }
    func testStorageFailurePreventsDispatchAndProvenNotSentCanClear() async {
        let service = Service(), journal = Journal(), flow = makeFlow(service, journal); journal.failWrite = true
        await flow.load(); await flow.reviewUnblock(flow.items[0]); await flow.confirm(); XCTAssertEqual(service.writes, 0)
        journal.failWrite = false; service.notSent = true; await flow.confirm(); XCTAssertTrue(journal.records.isEmpty); XCTAssertNil(flow.pending)
    }
    func testStaleReviewAndUnknownReadbackAreNotInventedSuccess() async {
        let service = Service(), flow = makeFlow(service); await flow.load(); let item = flow.items[0]
        service.items = [.init(blockID: 31, peerID: 9, nickname: "new")]; await flow.reviewUnblock(item)
        XCTAssertNil(flow.review); XCTAssertEqual(flow.phase, .failed); XCTAssertEqual(service.writes, 0)
        await flow.load(); await flow.reviewUnblock(flow.items[0]); service.afterWrite = { service.failReadback = true }; await flow.confirm()
        XCTAssertEqual(flow.result?.outcome, "APPLIED"); XCTAssertNil(flow.current); XCTAssertNotNil(flow.issue)
        service.failReadback = false; await flow.retryReadback(); XCTAssertEqual(flow.current?.blocked, false); XCTAssertEqual(service.writes, 1)
    }
    func testRevocationLateResultErasesPresentationButKeepsDurableOriginal() async {
        let service = Service(), journal = Journal(), flow = makeFlow(service, journal)
        await flow.load(); await flow.reviewUnblock(flow.items[0]); service.afterWrite = { service.isCurrent = false }; await flow.confirm()
        XCTAssertEqual(flow.phase, .closed); XCTAssertNil(flow.result); XCTAssertNil(flow.pending); XCTAssertTrue(flow.items.isEmpty)
        XCTAssertEqual(journal.records.count, 1)
        let other = Service(); other.viewerID = 8; other.items = []; let otherFlow = self.makeFlow(other, journal, owner: "owner-8")
        await otherFlow.load(); XCTAssertNil(otherFlow.pending); XCTAssertEqual(journal.records.count, 1)
    }
    func testDefaultClosedMakesNoCallsAndReadOnlyCannotReview() async {
        let closed = makeFlow(nil); await closed.load(); XCTAssertEqual(closed.phase, .closed)
        let service = Service(); service.canWrite = false; service.canSettle = false
        let readonly = makeFlow(service); await readonly.load(); await readonly.reviewUnblock(readonly.items[0]); await readonly.confirm()
        XCTAssertNil(readonly.review); XCTAssertEqual(service.writes, 0)
    }
    func testOwnerWideFenceStopsSecondScreenBeforeDispatch() async {
        let service = Service(), journal = Journal(), a = makeFlow(service,journal), b = makeFlow(service,journal); service.unknown = true
        await a.load(); await b.load(); await a.reviewUnblock(a.items[0]); await b.reviewUnblock(b.items[0])
        await a.confirm(); await b.confirm(); XCTAssertEqual(service.writes, 1); XCTAssertEqual(a.pendingCommand, b.pendingCommand)
    }
    func testSilentGrantRevocationPurgesAndCannotReviveSameFlow() async {
        let service = Service(), flow = makeFlow(service); await flow.load(); await flow.reviewUnblock(flow.items[0])
        service.isCurrent = false; XCTAssertFalse(flow.validateAuthority()); XCTAssertNil(flow.review); XCTAssertTrue(flow.items.isEmpty)
        service.isCurrent = true; await flow.load(); XCTAssertEqual(flow.phase, .closed); XCTAssertFalse(flow.canConfirm)
    }
    func testPaginationFailureRetainsRowsAndRetriesSameCursorToAuthoritativeEnd() async {
        let service = Service(), flow = makeFlow(service)
        let items = (51...100).reversed().map { NativeBlacklistItem(blockID: Int64($0), peerID: Int64($0 + 100), nickname: "") }
        service.pageValues[0] = .init(viewerID: 2, items: items, hasMore: true, nextCursor: 51, writeEnabled: true)
        service.pageValues[51] = .init(viewerID: 2, items: [], writeEnabled: true)
        await flow.load(); XCTAssertEqual(flow.items.count, 50); service.failCursors = [51]
        await flow.loadMore(); XCTAssertEqual(flow.items.count, 50); XCTAssertEqual(flow.nextCursor, 51); XCTAssertNotNil(flow.issue)
        service.failCursors = []; await flow.loadMore(); XCTAssertEqual(flow.items.count, 50); XCTAssertNil(flow.nextCursor); XCTAssertNil(flow.issue)
        let reads = service.pages; await flow.loadMore(); XCTAssertEqual(service.pages, reads)
    }
}
