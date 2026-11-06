import XCTest
@testable import QuestifyCore

final class MerchantSettlementOverviewTests: XCTestCase {
    private let context = MerchantSettlementOverviewContext(
        scope: MerchantBusinessScope(realm: "synthetic", accountID: 99, epoch: 1),
        authorizationGeneration: UUID(uuidString: "00000000-0000-0000-0000-000000000001"))

    private func snapshot(_ query: MerchantBusinessQuery, merchantID: Int = 610) throws -> MerchantBusinessSnapshot {
        var accessObject = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object)
        if merchantID != 610 {
            accessObject["merchant"] = .object(["id": .int(merchantID), "name": .string("Other")])
        }
        return try MerchantBusinessSnapshot(access: MerchantBusinessAccess(accessObject),
                                            document: MerchantBusinessDocument(query: query, payload: MerchantBusinessSyntheticFixtures.payload(query)))
    }

    func testSectionsSucceedAndFailIndependentlyWithoutBecomingZero() throws {
        var state = MerchantSettlementOverviewState()
        let overviewGen = try XCTUnwrap(state.begin(.overview, context: context))
        let entriesGen = try XCTUnwrap(state.begin(.entries, context: context))
        let batchesGen = try XCTUnwrap(state.begin(.batches, context: context))
        XCTAssertTrue(state.succeed(.overview, generation: overviewGen, context: context, snapshot: try snapshot(.overview)))
        XCTAssertTrue(state.fail(.entries, generation: entriesGen, context: context, key: "merchant.business.loadFailed"))
        XCTAssertEqual(state.section(.overview).phase, .loaded)
        XCTAssertEqual(state.section(.entries).phase, .failed)
        XCTAssertNil(state.section(.entries).snapshot)
        XCTAssertEqual(state.section(.batches).phase, .loading)
        XCTAssertTrue(state.succeed(.batches, generation: batchesGen, context: context, snapshot: try snapshot(.batches(page: 1))))
        XCTAssertEqual(state.section(.batches).rows.count, 1)
    }

    func testDuplicateBeginWhileLoadingIsRejectedAndInvalidateRejectsOldCompletion() throws {
        var state = MerchantSettlementOverviewState()
        let generation = try XCTUnwrap(state.begin(.entries, context: context))
        XCTAssertNil(state.begin(.entries, context: context))
        state.invalidateAll()
        XCTAssertFalse(state.succeed(.entries, generation: generation, context: context,
                                     snapshot: try snapshot(.entries(source: "all", page: 1))))
        XCTAssertEqual(state.section(.entries).phase, .notLoaded)
    }

    func testContextChangeClearsAllFinanceSectionsAndMerchant() throws {
        var state = MerchantSettlementOverviewState()
        let generation = try XCTUnwrap(state.begin(.overview, context: context))
        XCTAssertTrue(state.succeed(.overview, generation: generation, context: context, snapshot: try snapshot(.overview)))
        XCTAssertEqual(state.merchantID, 610)
        let changed = MerchantSettlementOverviewContext(
            scope: MerchantBusinessScope(realm: "synthetic", accountID: 99, epoch: 2),
            authorizationGeneration: context.authorizationGeneration)
        XCTAssertTrue(state.bind(changed))
        XCTAssertNil(state.merchantID)
        for section in MerchantSettlementOverviewSection.allCases {
            XCTAssertEqual(state.section(section).phase, .notLoaded)
            XCTAssertNil(state.section(section).snapshot)
        }
        let permissionChanged = MerchantSettlementOverviewContext(scope: changed.scope, authorizationGeneration: UUID())
        XCTAssertTrue(state.bind(permissionChanged))
    }

    func testWrongQueryOrOtherMerchantCompletionIsRejected() throws {
        var state = MerchantSettlementOverviewState()
        let overviewGen = try XCTUnwrap(state.begin(.overview, context: context))
        XCTAssertTrue(state.succeed(.overview, generation: overviewGen, context: context, snapshot: try snapshot(.overview)))
        let entriesGen = try XCTUnwrap(state.begin(.entries, context: context))
        XCTAssertFalse(state.succeed(.entries, generation: entriesGen, context: context,
                                     snapshot: try snapshot(.batches(page: 1))))
        XCTAssertFalse(state.succeed(.entries, generation: entriesGen, context: context,
                                     snapshot: try snapshot(.entries(source: "all", page: 1), merchantID: 611)))
        XCTAssertEqual(state.section(.entries).phase, .loading)
    }

    func testStatementUsesOnlyReturnedCountsAndServerTotal() throws {
        let document = try MerchantBusinessDocument(query: .batch(try MerchantBatchID(66001)),
                                                    payload: MerchantBusinessSyntheticFixtures.payload(.batch(try MerchantBatchID(66001))))
        let statement = try XCTUnwrap(MerchantSettlementStatement(document: document))
        XCTAssertEqual(statement.returnedEarningsCount, 0)
        XCTAssertEqual(statement.returnedAdjustmentsCount, 1)
        XCTAssertEqual(statement.returnedDetailCount, 1)
        XCTAssertEqual(statement.serverTotalDisplay, "CNY 0.00")
        XCTAssertFalse(statement.hasCompleteDetailContract)
        let overview = try MerchantBusinessDocument(query: .overview, payload: MerchantBusinessSyntheticFixtures.payload(.overview))
        XCTAssertNil(MerchantSettlementStatement(document: overview))
    }
}
