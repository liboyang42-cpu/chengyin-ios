import XCTest
@testable import Questify

@MainActor final class MerchantBusinessListModelTests: XCTestCase {
    @MainActor private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "synthetic://list-tools", accountID: 99001, epoch: 1)
        let isConfigured = true
        let isOfflineExample = true
        let canExecuteSyntheticMutation = false
        var authorizationGeneration: UUID?
        var merchantID = 610
        var includeCRM = true
        var failure: MerchantBusinessFailure?
        var calls: [MerchantBusinessQuery] = []
        var suspendQuery: MerchantBusinessQuery?
        var suspended: CheckedContinuation<Void, Never>?
        func access() async throws -> MerchantBusinessAccess {
            if let failure { throw failure }
            var fields = try MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!
            fields["merchant"] = .object(["id": .int(merchantID), "name": .string("Synthetic workshop")])
            if !includeCRM { fields["permissions"] = .array((fields["permissions"]?.array ?? []).filter { $0.string != "merchant:crm:read" }) }
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
    func testLoadedPageSearchRetainsEarlierMatchesWithoutChangingSnapshot() async throws {
        let reader = Reader()
        let model = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await model.load(.aftercare(.pending, page: 1)); model.listFilters.aftercareKeyword = "Alice"
        await model.loadMoreAftercare()
        let snapshot = try XCTUnwrap(model.coordinator.snapshot)
        XCTAssertEqual(snapshot.document.query, .aftercare(.pending, page: 2))
        XCTAssertEqual(snapshot.document.rows.map(\.id), ["62021"])
        XCTAssertEqual(model.aftercareLoadedPages?.rows.count, 21)
        XCTAssertEqual(model.visibleRows(in: snapshot.document.sections[0], query: snapshot.document.query).map(\.id), ["62001"])
        XCTAssertEqual(model.coordinator.snapshot, snapshot)
        model.listFilters.aftercareKeyword = "21"
        XCTAssertEqual(model.visibleRows(in: snapshot.document.sections[0], query: snapshot.document.query).map(\.id), ["62021"])
        model.listFilters.aftercareKeyword = ""
        XCTAssertEqual(model.visibleRows(in: snapshot.document.sections[0], query: snapshot.document.query).count, 21)
        await model.loadMoreAftercare()
        XCTAssertEqual(reader.calls, [.aftercare(.pending, page: 1), .aftercare(.pending, page: 2)])
        XCTAssertEqual(model.coordinator.snapshot, snapshot)
    }
    func testBucketAndRefreshReplaceAllLoadedRowsAndRetainKeyword() async throws {
        let reader = Reader()
        let model = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await model.load(.aftercare(.pending, page: 1)); await model.loadMoreAftercare()
        model.listFilters.aftercareKeyword = "21"
        await model.load(.aftercare(.pending, page: 2)) // Explicit refresh resets to page one.
        XCTAssertEqual(model.coordinator.snapshot?.document.query, .aftercare(.pending, page: 1))
        XCTAssertEqual(model.aftercareLoadedPages?.rows.count, 20)
        XCTAssertFalse(model.aftercareLoadedPages?.rows.contains { $0.id == "62021" } ?? true)
        XCTAssertEqual(model.listFilters.aftercareKeyword, "21")
        await model.loadMoreAftercare()
        await model.load(.aftercare(.processing, page: 1))
        XCTAssertEqual(model.aftercareLoadedPages?.bucket, .processing)
        XCTAssertEqual(model.aftercareLoadedPages?.rows.count, 20)
        XCTAssertTrue(model.aftercareLoadedPages?.rows.allSatisfy { $0.fields.mbText("bucket") == "PROCESSING" } ?? false)
        XCTAssertEqual(model.listFilters.aftercareKeyword, "21")
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
        XCTAssertNil(model.aftercareLoadedPages)
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
        reader.failure = .denied; await model.loadMoreAftercare()
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
    func testFailedLoadMoreClearsAccumulationAndRefreshCanRecover() async {
        let reader = Reader()
        let tracked = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await tracked.load(.aftercare(.pending, page: 1)); tracked.listFilters.aftercareKeyword = "Alice"
        reader.failure = .denied; await tracked.loadMoreAftercare()
        XCTAssertNil(tracked.aftercareLoadedPages); XCTAssertNil(tracked.coordinator.snapshot)
        XCTAssertEqual(tracked.listFilters.aftercareKeyword, "Alice")
        reader.failure = nil; await tracked.load(.aftercare(.pending, page: 1))
        XCTAssertEqual(tracked.aftercareLoadedPages?.rows.count, 20)
    }
    func testMerchantOrPermissionChangeDuringAppendCannotMixRows() async {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1)); model.listFilters.aftercareKeyword = "Alice"
        reader.merchantID = 611
        await model.loadMoreAftercare()
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(model.listFilters, .init())
        XCTAssertEqual(model.aftercareLoadFailureKey, "merchant.business.stale")
        await model.load(.aftercare(.pending, page: 1))
        reader.includeCRM = false
        await model.loadMoreAftercare()
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(model.aftercareLoadFailureKey, "merchant.business.stale")
    }
    func testRefreshDuringSuspendedAppendFencesOlderGeneration() async throws {
        let reader = Reader()
        let tracked = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await tracked.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let older = Task { await tracked.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { older.cancel(); return XCTFail("Synthetic append did not suspend") }
        await tracked.load(.aftercare(.pending, page: 1))
        tracked.listFilters.aftercareKeyword = "Alice"
        continuation.resume(); await older.value
        XCTAssertEqual(tracked.aftercareLoadedPages?.rows.count, 20)
        XCTAssertEqual(tracked.aftercareLoadedPages?.page, 1)
        XCTAssertEqual(tracked.coordinator.snapshot?.document.query, .aftercare(.pending, page: 1))
        XCTAssertEqual(tracked.listFilters.aftercareKeyword, "Alice")
    }
    func testBucketChangeDuringSuspendedAppendFencesOldRows() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let older = Task { await model.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { older.cancel(); return XCTFail("Synthetic append did not suspend") }
        await model.load(.aftercare(.processing, page: 1))
        continuation.resume(); await older.value
        XCTAssertEqual(model.aftercareLoadedPages?.bucket, .processing)
        XCTAssertEqual(model.aftercareLoadedPages?.rows.count, 20)
        XCTAssertTrue(model.aftercareLoadedPages?.rows.allSatisfy { $0.fields.mbText("bucket") == "PROCESSING" } ?? false)
    }
    func testCancelledAppendCannotRestoreAccumulation() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let pending = Task { await model.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { pending.cancel(); return XCTFail("Synthetic append did not suspend") }
        pending.cancel(); continuation.resume(); await pending.value
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertNil(model.coordinator.snapshot)
    }
    func testAuthorizationChangeBeforeLoadMoreClearsWithoutReading() async {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1)); model.listFilters.aftercareKeyword = "Alice"
        reader.authorizationGeneration = UUID()
        await model.loadMoreAftercare()
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(model.listFilters, .init())
        XCTAssertEqual(reader.calls, [.aftercare(.pending, page: 1)])
    }
    func testAuthorizationChangeDuringAppendDiscardsAllRows() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let pending = Task { await model.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { pending.cancel(); return XCTFail("Synthetic append did not suspend") }
        reader.authorizationGeneration = UUID()
        continuation.resume(); await pending.value
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertNil(model.coordinator.snapshot)
    }
    func testRepeatedLoadMoreWhileBusyDoesNotReadOrAppendTwice() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let pending = Task { await model.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { pending.cancel(); return XCTFail("Synthetic append did not suspend") }
        await model.loadMoreAftercare()
        XCTAssertEqual(reader.calls, [.aftercare(.pending, page: 1), .aftercare(.pending, page: 2)])
        continuation.resume(); await pending.value
        XCTAssertEqual(model.aftercareLoadedPages?.rows.count, 21)
    }
    func testScopeChangeDuringAppendClearsOldAccountRows() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let older = Task { await model.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { older.cancel(); return XCTFail("Synthetic append did not suspend") }
        reader.scope = .init(realm: "synthetic://list-tools", accountID: 99002, epoch: 2)
        await model.load(.aftercare(.pending, page: 1))
        continuation.resume(); await older.value
        XCTAssertEqual(model.aftercareLoadedPages?.scope.accountID, 99002)
        XCTAssertEqual(model.aftercareLoadedPages?.page, 1)
        XCTAssertEqual(model.aftercareLoadedPages?.rows.count, 20)
    }
    func testDismissalDuringAppendCannotRepopulateClosedList() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1))
        reader.suspendQuery = .aftercare(.pending, page: 2)
        let older = Task { await model.loadMoreAftercare() }
        for _ in 0..<100 where reader.suspended == nil { await Task.yield() }
        guard let continuation = reader.suspended else { older.cancel(); return XCTFail("Synthetic append did not suspend") }
        model.invalidate()
        continuation.resume(); await older.value
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(model.listFilters, .init())
    }
    func testAccumulatedNavigationKeepsExactDetailAndUnknownIntent() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let intent = MerchantBusinessIntent(scope: try XCTUnwrap(reader.scope), merchantID: 610, target: "refund:62001", requestID: "synthetic-unknown")
        try journal.reserve(intent)
        let model = MerchantBusinessViewModel(reader: reader, journal: journal)
        await model.load(.aftercare(.pending, page: 1)); await model.loadMoreAftercare()
        let first = try XCTUnwrap(model.aftercareLoadedPages?.rows.first)
        XCTAssertEqual(first.destination, .refund(try .init(62001)))
        XCTAssertEqual(model.coordinator.snapshot?.document.rows.map(\.id), ["62021"])
        XCTAssertTrue(model.coordinator.isLocked); XCTAssertNil(model.coordinator.confirmation)
        model.prepare(.aftercare(refund: try .init(62001), decision: .agree, content: "", evidenceKey: nil))
        XCTAssertNil(model.coordinator.confirmation); XCTAssertEqual(try journal.intents(), [intent])
        model.invalidate()
        XCTAssertNil(model.aftercareLoadedPages); XCTAssertEqual(try journal.intents(), [intent])
    }

}
