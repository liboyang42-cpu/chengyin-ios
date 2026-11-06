import XCTest
@testable import Questify

/// Authored, NOT_RUN. In-memory read fixtures only; no mutation is permitted.
@MainActor final class MerchantBusinessCancelledReadTests: XCTestCase {
    private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "synthetic://cancelled-business-read", accountID: 99001, epoch: 1)
        let isConfigured = true
        let isOfflineExample = true
        let canExecuteSyntheticMutation = false
        var calls: [MerchantBusinessQuery] = []
        func access() async throws -> MerchantBusinessAccess {
            try .init(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!)
        }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            calls.append(query)
            let grant = try await access()
            return try .init(access: grant, document: .init(query: query, payload: MerchantBusinessSyntheticFixtures.listToolsPayload(query)))
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            XCTFail("Read-only regression must never dispatch")
            throw MerchantBusinessFailure.disabled
        }
    }
    func testCancelledCoreLoadPreservesCurrentSnapshotAndJournal() async throws {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let flow = MerchantBusinessCoordinator(reader: reader, journal: journal)
        await flow.load(.reviews(page: 1))
        let baseline = try XCTUnwrap(flow.snapshot)
        let record = MerchantBusinessIntent(scope: try XCTUnwrap(reader.scope), merchantID: baseline.access.merchantID, target: "synthetic-original", requestID: "original-request")
        try journal.reserve(record)
        let task = Task { @MainActor in await flow.load(.reviews(page: 2)) }
        task.cancel(); await task.value
        XCTAssertEqual(flow.snapshot, baseline)
        XCTAssertNil(flow.failure)
        XCTAssertFalse(flow.isBusy)
        XCTAssertEqual(reader.calls, [.reviews(page: 1)])
        XCTAssertEqual(try journal.intents(), [record])
    }
    func testCancelledViewModelLoadPreservesLoadedPagesAndRevision() async throws {
        let reader = Reader()
        let model = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        await model.load(.reviews(page: 1))
        let baseline = try XCTUnwrap(model.coordinator.snapshot)
        let count = try XCTUnwrap(model.reviewLoadedPages).rows.count
        let revision = model.revision
        let task = Task { @MainActor in await model.load(.reviews(page: 2)) }
        task.cancel(); await task.value
        XCTAssertEqual(model.coordinator.snapshot, baseline)
        XCTAssertEqual(model.reviewLoadedPages?.rows.count, count)
        XCTAssertEqual(model.revision, revision)
        XCTAssertEqual(reader.calls, [.reviews(page: 1)])
    }
    func testFreshExplicitReloadStillRunsAfterCancelledRead() async throws {
        let reader = Reader()
        let model = MerchantBusinessViewModel(reader: reader, journal: MerchantBusinessMemoryIntentStore())
        let task = Task { @MainActor in await model.load(.reviews(page: 1)) }
        task.cancel(); await task.value
        XCTAssertTrue(reader.calls.isEmpty)
        await model.load(.reviews(page: 1))
        XCTAssertNotNil(model.coordinator.snapshot)
        XCTAssertEqual(reader.calls, [.reviews(page: 1)])
    }
}
