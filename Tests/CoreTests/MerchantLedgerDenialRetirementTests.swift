import XCTest
@testable import QuestifyCore

final class MerchantLedgerDenialRetirementTests: XCTestCase {
    private func owner() -> MerchantLedgerSettlementOwner {
        .init(scope: .init(realm: "fixture", accountID: 42, epoch: 1), authorizationGeneration: UUID())
    }
    private func snapshot(_ query: MerchantBusinessQuery) throws -> MerchantBusinessSnapshot {
        let access = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object)
        return try .init(access: .init(access), document: .init(query: query, payload: MerchantBusinessSyntheticFixtures.payload(query)))
    }
    func testCurrentDenialClearsSiblingsCoverAndInflightWithoutChangingOwner() throws {
        var state = MerchantLedgerSettlementRead(); let original = owner()
        let entries = try XCTUnwrap(state.begin(.entries, page: 1, owner: original))
        XCTAssertEqual(state.succeed(.entries, generation: entries, owner: original, snapshot: try snapshot(.entries(source: "all", page: 1))), .stored)
        let late = try XCTUnwrap(state.begin(.overview, page: 1, owner: original))
        let denied = try XCTUnwrap(state.begin(.batches, page: 1, owner: original))
        let cover = state.presentBatch(66001)
        XCTAssertTrue(state.fail(.batches, generation: denied, owner: original, key: "merchant.business.denied"))
        XCTAssertEqual(state.owner, original); XCTAssertNil(state.cover)
        for section in MerchantLedgerSettlementSection.allCases {
            XCTAssertNil(state.section(section).snapshot)
            XCTAssertEqual(state.section(section).failureKey, "merchant.business.denied")
            XCTAssertFalse(state.section(section).isLoading)
        }
        XCTAssertFalse(state.consumePop(cover))
        XCTAssertEqual(state.succeed(.overview, generation: late, owner: original, snapshot: try snapshot(.overview)), .ignored)
        let fresh = try XCTUnwrap(state.begin(.overview, page: 1, owner: original))
        XCTAssertFalse(state.fail(.batches, generation: denied, owner: original, key: "merchant.business.denied"))
        XCTAssertTrue(state.overview.isLoading)
        XCTAssertEqual(state.succeed(.overview, generation: fresh, owner: original, snapshot: try snapshot(.overview)), .stored)
    }
    func testOrdinaryFailurePreservesSiblingAndOldCoverCannotDenyReplacement() throws {
        var state = MerchantLedgerSettlementRead(); let original = owner()
        let entries = try XCTUnwrap(state.begin(.entries, page: 1, owner: original))
        _ = state.succeed(.entries, generation: entries, owner: original, snapshot: try snapshot(.entries(source: "all", page: 1)))
        let batches = try XCTUnwrap(state.begin(.batches, page: 1, owner: original))
        XCTAssertTrue(state.fail(.batches, generation: batches, owner: original, key: "merchant.business.loadFailed"))
        XCTAssertNotNil(state.entries.snapshot)
        let old = state.presentBatch(66001), fresh = state.presentBatch(66002)
        XCTAssertFalse(state.denyFromBatch(old)); XCTAssertNotNil(state.entries.snapshot)
        XCTAssertTrue(state.denyFromBatch(fresh)); XCTAssertNil(state.entries.snapshot)
        let next = owner(); _ = state.replaceOwner(next)
        let ticket = try XCTUnwrap(state.begin(.overview, page: 1, owner: next))
        XCTAssertFalse(state.denyFromBatch(fresh)); XCTAssertFalse(state.fail(.overview, generation: ticket, owner: original, key: "merchant.business.denied"))
        XCTAssertTrue(state.overview.isLoading)
    }
}
