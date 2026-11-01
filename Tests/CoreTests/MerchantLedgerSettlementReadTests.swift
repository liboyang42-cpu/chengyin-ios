import XCTest
@testable import QuestifyCore

/// Generation retirement must clear loading. An older success, failure or cancel
/// must not write the read that replaced it.
final class MerchantLedgerSettlementReadTests: XCTestCase {
    func testOwnerChangeClearsLoadingAndStaleCompletionDoesNotStick() throws {
        let old = owner(1), fresh = owner(2)
        var detail = MerchantLedgerBatchDetailRead(owner: old)
        let failed = try XCTUnwrap(detail.begin(owner: old))
        XCTAssertTrue(detail.fail(generation: failed, owner: old, key: "merchant.business.denied"))
        let inflight = try XCTUnwrap(detail.begin(owner: old))
        XCTAssertTrue(detail.slot.isLoading)
        XCTAssertNil(detail.slot.failureKey)
        XCTAssertNil(detail.begin(owner: old))
        XCTAssertTrue(detail.replaceOwner(fresh))
        XCTAssertFalse(detail.slot.isLoading)
        XCTAssertNil(detail.slot.failureKey)
        XCTAssertNil(detail.slot.snapshot)
        let next = try XCTUnwrap(detail.begin(owner: fresh))
        XCTAssertNotEqual(next, inflight)
        let body = try snapshot(.batch(try MerchantBatchID(66001)))
        XCTAssertEqual(detail.succeed(generation: inflight, owner: old, batchID: 66001, snapshot: body), .ignored)
        XCTAssertFalse(detail.fail(generation: inflight, owner: old, key: "merchant.business.loadFailed"))
        detail.cancel(generation: inflight)
        XCTAssertTrue(detail.slot.isLoading)
        XCTAssertNil(detail.slot.failureKey)
        XCTAssertNil(detail.slot.snapshot)
        XCTAssertEqual(detail.succeed(generation: next, owner: fresh, batchID: 66001, snapshot: body), .stored)
        XCTAssertEqual(detail.slot.snapshot?.document.query, Optional(body.document.query))
        var denied = MerchantLedgerBatchDetailRead(owner: fresh)
        let deniedTicket = try XCTUnwrap(denied.begin(owner: fresh))
        XCTAssertEqual(denied.succeed(generation: deniedTicket, owner: fresh, batchID: 66001, snapshot: try snapshot(.batch(try MerchantBatchID(66001)), finance: false)), .rejected("merchant.business.denied"))
        XCTAssertNil(denied.slot.snapshot)

        var board = MerchantLedgerSettlementRead()
        XCTAssertNil(board.section(.entries).snapshot)
        let entriesTicket = try XCTUnwrap(board.begin(.entries, page: 1, owner: old))
        XCTAssertEqual(board.succeed(.entries, generation: entriesTicket, owner: old, snapshot: try snapshot(.entries(source: "all", page: 1))), .stored)
        let batchesTicket = try XCTUnwrap(board.begin(.batches, page: 1, owner: old))
        XCTAssertTrue(board.fail(.batches, generation: batchesTicket, owner: old, key: "merchant.business.loadFailed"))
        XCTAssertNotNil(board.section(.entries).snapshot)
        board.overviewDisappeared()
        XCTAssertNotNil(board.section(.entries).snapshot)
        XCTAssertEqual(board.section(.batches).failureKey, "merchant.business.loadFailed")
        let firstCover = board.presentBatch(66001)
        let secondCover = board.presentBatch(66001)
        XCTAssertFalse(board.consumePop(firstCover))
        XCTAssertTrue(board.consumePop(secondCover))
        XCTAssertNil(board.section(.batches).snapshot)
        XCTAssertNotNil(board.section(.entries).snapshot)
        XCTAssertFalse(board.section(.batches).isLoading)
        XCTAssertFalse(board.consumePop(secondCover))
        XCTAssertNotNil(board.begin(.batches, page: board.section(.batches).page, owner: old))
        let overviewTicket = try XCTUnwrap(board.begin(.overview, page: 1, owner: old))
        XCTAssertTrue(board.replaceOwner(fresh))
        XCTAssertFalse(board.section(.overview).isLoading)
        XCTAssertNil(board.section(.entries).snapshot)
        XCTAssertNil(board.section(.overview).failureKey)
        let reread = try XCTUnwrap(board.begin(.overview, page: 1, owner: fresh))
        XCTAssertEqual(board.succeed(.overview, generation: overviewTicket, owner: old, snapshot: try snapshot(.overview)), .ignored)
        board.cancel(.overview, generation: overviewTicket)
        XCTAssertTrue(board.section(.overview).isLoading)
        XCTAssertEqual(board.succeed(.overview, generation: reread, owner: fresh, snapshot: try snapshot(.overview)), .stored)
        board.leave()
        XCTAssertNil(board.section(.overview).snapshot)
        XCTAssertFalse(board.section(.overview).isLoading)
        XCTAssertFalse(board.consumePop(secondCover))
        XCTAssertNil(MerchantLedgerSettlementRead().section(.batches).snapshot)
    }

    private func owner(_ account: Int) -> MerchantLedgerSettlementOwner {
        .init(scope: .init(realm: "fixture", accountID: account, epoch: 1), authorizationGeneration: UUID())
    }
    private func snapshot(_ query: MerchantBusinessQuery, finance: Bool = true) throws -> MerchantBusinessSnapshot {
        var access = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object)
        if !finance {
            access["permissions"] = .array([])
            access["canManageOperators"] = .bool(false)
        }
        return try .init(access: .init(access), document: .init(query: query, payload: MerchantBusinessSyntheticFixtures.payload(query)))
    }
}
