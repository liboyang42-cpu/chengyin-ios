import XCTest
@testable import Questify

@MainActor final class MerchantBusinessListModelTests: XCTestCase {
    @MainActor private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "synthetic://list-tools", accountID: 99001, epoch: 1)
        let isConfigured = true
        let isOfflineExample = true
        let canExecuteSyntheticMutation = false
        var merchantID = 610
        var failure: MerchantBusinessFailure?
        var calls: [MerchantBusinessQuery] = []
        var suspendQuery: MerchantBusinessQuery?
        var suspended: CheckedContinuation<Void, Never>?
        func access() async throws -> MerchantBusinessAccess {
            if let failure { throw failure }
            var fields = try MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!
            fields["merchant"] = .object(["id": .int(merchantID), "name": .string("Synthetic workshop")])
            return try .init(fields)
        }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            calls.append(query)
            let grant = try await access()
            if query == suspendQuery { await withCheckedContinuation { suspended = $0 } }
            return try .init(access: grant, document: .init(query: query, payload: MerchantBusinessSyntheticFixtures.listToolsPayload(query)))
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            XCTFail("Presentation-only tests must not dispatch mutations")
            throw MerchantBusinessFailure.disabled
        }
    }
    func testChangingPresentationDoesNotReadAgainOrChangeBaseline() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.reviews(page: 1))
        let before = try XCTUnwrap(model.coordinator.snapshot)
        model.listFilters.review = .pending
        model.listFilters.aftercareKeyword = "Synthetic Alice"
        XCTAssertEqual(reader.calls, [.reviews(page: 1)])
        XCTAssertEqual(model.coordinator.snapshot, before)
        XCTAssertEqual(model.listFilters.rows(in: before.document.sections[0], query: before.document.query).map(\.id), ["63001"])
        XCTAssertEqual(before.document.summary["pendingReplyCount"], .int(7))
    }
    func testPageBucketAndRefreshRetainKeywordAndReplaceRows() async throws {
        let reader = Reader()
        let tracked = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await tracked.load(.aftercare(.pending, page: 1)); tracked.listFilters.aftercareKeyword = "Alice"
        await tracked.load(.aftercare(.pending, page: 2))
        let second = try XCTUnwrap(tracked.coordinator.snapshot?.document)
        XCTAssertEqual(second.rows.map(\.id), ["62021"])
        XCTAssertTrue(tracked.listFilters.rows(in: second.sections[0], query: second.query).isEmpty)
        XCTAssertEqual(tracked.listFilters.aftercareKeyword, "Alice")
        await tracked.load(.aftercare(.processing, page: 1))
        await tracked.load(.aftercare(.processing, page: 1))
        XCTAssertEqual(tracked.listFilters.aftercareKeyword, "Alice")
        XCTAssertEqual(reader.calls, [.aftercare(.pending, page: 1), .aftercare(.pending, page: 2), .aftercare(.processing, page: 1), .aftercare(.processing, page: 1)])
    }
    func testReviewFilterPersistsAcrossPagesButOnlyMatchesNewRows() async throws {
        let model = MerchantBusinessViewModel(reader: Reader(), journal: MerchantBusinessMemoryIntentStore())
        await model.load(.reviews(page: 1)); model.listFilters.review = .photos
        await model.load(.reviews(page: 2))
        let document = try XCTUnwrap(model.coordinator.snapshot?.document)
        XCTAssertEqual(model.listFilters.review, .photos)
        XCTAssertEqual(document.rows.map(\.id), ["63021"])
        XCTAssertTrue(model.listFilters.rows(in: document.sections[0], query: document.query).isEmpty)
        XCTAssertEqual(document.summary["replyRatePct"], .int(65))
    }
    func testScopeOrMerchantChangeClearsLocalSearch() async throws {
        let reader = Reader()
        let tracked = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await tracked.load(.aftercare(.pending, page: 1)); tracked.listFilters.aftercareKeyword = "Alice"
        reader.scope = .init(realm: "synthetic://list-tools", accountID: 99002, epoch: 2)
        await tracked.load(.aftercare(.pending, page: 1))
        XCTAssertEqual(tracked.listFilters, .init())
        tracked.listFilters.review = .pending; tracked.listFilters.aftercareKeyword = "Weather"
        reader.merchantID = 611
        await tracked.load(.reviews(page: 1))
        XCTAssertEqual(tracked.listFilters, .init())
        XCTAssertEqual(tracked.coordinator.snapshot?.access.merchantID, 611)
    }
    func testInvalidationClearsFiltersAndDataButPreservesUnknownIntent() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let intent = MerchantBusinessIntent(scope: try XCTUnwrap(reader.scope), merchantID: 610, target: "review:63001", requestID: "synthetic-pending")
        try journal.reserve(intent)
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.reviews(page: 1)); model.listFilters.review = .pending; model.listFilters.aftercareKeyword = "Alice"
        XCTAssertTrue(model.coordinator.isLocked)
        model.invalidate()
        XCTAssertEqual(model.listFilters, .init()); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(try journal.intents(), [intent])
        await model.load(.reviews(page: 1)); XCTAssertTrue(model.coordinator.isLocked)
        model.prepare(.review(id: try .init(63001), version: 0, action: .reply, content: "Synthetic reply"))
        XCTAssertNil(model.coordinator.confirmation)
        XCTAssertEqual(try journal.intents(), [intent])
    }
    func testFailedReplacementNeverKeepsOldRowsOrMetrics() async {
        let reader = Reader()
        let tracked = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await tracked.load(.reviews(page: 1)); tracked.listFilters.review = .photos
        reader.failure = .denied
        await tracked.load(.reviews(page: 2))
        XCTAssertNil(tracked.coordinator.snapshot); XCTAssertFalse(tracked.coordinator.isCurrent)
        XCTAssertEqual(tracked.coordinator.failure, .denied)
    }
    func testMerchantChangeAfterFailedLoadStillClearsPriorMerchantFilter() async {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1)); model.listFilters.aftercareKeyword = "Alice"
        reader.failure = .denied; await model.load(.aftercare(.pending, page: 2))
        XCTAssertNil(model.coordinator.snapshot)
        reader.failure = nil; reader.merchantID = 611
        await model.load(.aftercare(.pending, page: 1))
        XCTAssertEqual(model.listFilters, .init())
        XCTAssertEqual(model.coordinator.snapshot?.access.merchantID, 611)
    }
    func testOlderLoadCannotRestoreMerchantRowsOrOverwriteNewFilter() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.reviews(page: 1)); model.listFilters.review = .photos
        reader.suspendQuery = .reviews(page: 2)
        let older = Task { await model.load(.reviews(page: 2)) }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { older.cancel(); return XCTFail("Synthetic load did not suspend") }
        reader.merchantID = 611
        await model.load(.reviews(page: 1))
        XCTAssertEqual(model.listFilters, .init())
        model.listFilters.review = .low
        continuation.resume(); await older.value
        XCTAssertEqual(model.coordinator.snapshot?.access.merchantID, 611)
        XCTAssertEqual(model.coordinator.snapshot?.document.query, .reviews(page: 1))
        XCTAssertEqual(model.listFilters.review, .low)
        XCTAssertTrue(try journal.intents().isEmpty)
    }

}
