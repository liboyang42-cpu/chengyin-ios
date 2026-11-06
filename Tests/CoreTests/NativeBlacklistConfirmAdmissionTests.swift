import XCTest
@testable import QuestifyCore

/// Authored only. Synthetic original service and journal fixtures; no real unblock.
@MainActor final class NativeBlacklistConfirmAdmissionTests: XCTestCase {
    private typealias Service = NativeBlacklistFlowTests.Service
    private typealias Journal = NativeBlacklistFlowTests.Journal
    private func flow(_ s: Service, _ j: Journal, owner: String = "owner-2") -> NativeBlacklistFlow {
        .init(service: s, journal: j, ownerKey: owner)
    }
    func testCancelledOldConfirmationCannotUnblockNewPeer() async throws {
        let s = Service(), j = Journal(), f = flow(s,j)
        // The original reader returns strict descending block IDs, not insertion order.
        s.items.insert(.init(blockID: 31, peerID: 10, nickname: "Second fixture"), at: 0)
        await f.load(); XCTAssertEqual(f.phase, .ready); XCTAssertEqual(f.items.map(\.blockID), [31, 30])
        let firstPeer = try XCTUnwrap(f.items.first { $0.peerID == 9 })
        let secondPeer = try XCTUnwrap(f.items.first { $0.peerID == 10 })
        await f.reviewUnblock(firstPeer); let old = try XCTUnwrap(f.review)
        f.cancelReview(); await f.reviewUnblock(secondPeer); let replacement = try XCTUnwrap(f.review)
        XCTAssertEqual(old.peerID, 9); XCTAssertEqual(old.expectedBlockID, 30)
        XCTAssertEqual(replacement.peerID, 10); XCTAssertEqual(replacement.expectedBlockID, 31)
        await f.confirm(expected: old)
        XCTAssertEqual(f.review, replacement); XCTAssertEqual(s.writes,0); XCTAssertTrue(j.records.isEmpty)
    }
    func testSamePeerNewReviewCannotReuseOldRequestConsent() async throws {
        let s = Service(), j = Journal(), f = flow(s,j)
        await f.load(); let item = try XCTUnwrap(f.items.first); await f.reviewUnblock(item); let old = try XCTUnwrap(f.review)
        f.cancelReview(); await f.reviewUnblock(item); let next = try XCTUnwrap(f.review)
        XCTAssertNotEqual(old.requestID,next.requestID); await f.confirm(expected: old)
        XCTAssertEqual(f.review,next); XCTAssertEqual(s.writes,0)
    }
    func testNormalExactConfirmationUsesOriginalReceiptAndCurrent() async throws {
        let s = Service(), j = Journal(), f = flow(s,j)
        await f.load(); await f.reviewUnblock(try XCTUnwrap(f.items.first)); let original = try XCTUnwrap(f.review)
        await f.confirm(expected: original)
        XCTAssertEqual(f.result?.requestID,original.requestID.uuidString.lowercased())
        XCTAssertEqual(f.result?.outcome,"APPLIED"); XCTAssertEqual(f.current?.blocked,false)
        XCTAssertEqual(s.writes,1); XCTAssertTrue(j.records.isEmpty)
    }
    func testDuplicateConfirmedTapCannotDispatchTwice() async throws {
        let s = Service(), j = Journal(), f = flow(s,j)
        await f.load(); await f.reviewUnblock(try XCTUnwrap(f.items.first)); let original = try XCTUnwrap(f.review)
        await f.confirm(expected: original); await f.confirm(expected: original)
        XCTAssertEqual(s.writes,1); XCTAssertTrue(j.records.isEmpty)
    }
    func testRetiredPresentationCannotConfirmAfterReload() async throws {
        let s = Service(), j = Journal(), f = flow(s,j)
        await f.load(); await f.reviewUnblock(try XCTUnwrap(f.items.first)); let original = try XCTUnwrap(f.review)
        f.invalidate(); await f.load(); await f.reviewUnblock(try XCTUnwrap(f.items.first)); await f.confirm(expected: original)
        XCTAssertEqual(s.writes,0); XCTAssertTrue(j.records.isEmpty)
    }
    func testUnknownRestartRetainsOriginalAndOnlyReadsReceipt() async throws {
        let s = Service(), j = Journal(), f = flow(s,j); s.loseResponse = true
        await f.load(); await f.reviewUnblock(try XCTUnwrap(f.items.first)); let original = try XCTUnwrap(f.review)
        await f.confirm(expected: original); f.invalidate()
        let reopened = flow(s,j); await reopened.load(); XCTAssertEqual(reopened.pendingCommand,original)
        await reopened.recover(); XCTAssertEqual(s.writes,1); XCTAssertEqual(s.receipts,1)
        XCTAssertEqual(reopened.result?.outcome,"APPLIED"); XCTAssertTrue(j.records.isEmpty)
    }
    func testRevocationBeforeConfirmationKeepsOriginalAuthorityClosed() async throws {
        let s = Service(), j = Journal(), f = flow(s,j)
        await f.load(); await f.reviewUnblock(try XCTUnwrap(f.items.first)); let original = try XCTUnwrap(f.review)
        s.isCurrent = false; await f.confirm(expected: original)
        XCTAssertEqual(s.writes,0); XCTAssertTrue(j.records.isEmpty)
    }
    func testAfterDispatchRetirementPreservesSameUUIDForOwnerOnly() async throws {
        let s = Service(), j = Journal(), f = flow(s,j)
        await f.load(); await f.reviewUnblock(try XCTUnwrap(f.items.first)); let original = try XCTUnwrap(f.review)
        s.afterWrite = { f.invalidate() }; await f.confirm(expected: original)
        XCTAssertEqual(s.writes,1); XCTAssertEqual(j.records.first?.operationID,original.requestID)
        let other = flow(s,j,owner:"owner-8"); await other.load()
        XCTAssertNil(other.pending); XCTAssertEqual(j.records.count,1)
    }
}
