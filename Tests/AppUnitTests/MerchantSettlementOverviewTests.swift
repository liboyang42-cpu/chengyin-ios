import XCTest
@testable import Questify

@MainActor private final class SettlementOverviewReader: MerchantBusinessReading {
    var scope: MerchantBusinessScope? = .init(realm: "synthetic", accountID: 99, epoch: 1)
    var isConfigured = true
    var isOfflineExample = true
    var canExecuteSyntheticMutation = false
    var authorizationGeneration: UUID? = UUID()
    var failingSections: Set<MerchantSettlementOverviewSection> = []
    private(set) var counts: [MerchantBusinessQuery: Int] = [:]
    var onRead: ((MerchantBusinessQuery) -> Void)?

    private func make(_ query: MerchantBusinessQuery) throws -> MerchantBusinessSnapshot {
        let access = try MerchantBusinessAccess(XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object))
        var payload = try MerchantBusinessSyntheticFixtures.payload(query)
        if case .entries = query {
            let entry = try MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.entry)
            payload = .object(["rows": .array([entry]), "total": .int(21), "pageNum": .int(query.page), "pageSize": .int(20),
                               "summary": .object([:])])
        }
        return try MerchantBusinessSnapshot(access: access, document: MerchantBusinessDocument(query: query, payload: payload))
    }
    func access() async throws -> MerchantBusinessAccess { try make(.overview).access }
    func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
        counts[query, default: 0] += 1
        onRead?(query)
        let section: MerchantSettlementOverviewSection
        switch query {
        case .overview: section = .overview
        case .entries: section = .entries
        default: section = .batches
        }
        if failingSections.contains(section) { throw MerchantBusinessFailure.malformed }
        return try make(query)
    }
    func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
        XCTFail("Settlement overview must not write"); throw MerchantBusinessFailure.disabled
    }
}

@MainActor final class MerchantSettlementOverviewTests: XCTestCase {
    private func model(_ reader: SettlementOverviewReader) -> MerchantSettlementOverviewModel {
        let model = MerchantSettlementOverviewModel(reader: reader)
        model.appear(active: true)
        return model
    }
    private func settle(_ condition: @escaping () -> Bool) async {
        for _ in 0..<50 where !condition() { await Task.yield() }
    }

    func testOneFailedSectionKeepsOtherSectionsLoaded() async throws {
        let reader = SettlementOverviewReader(); reader.failingSections = [.entries]
        let model = model(reader)
        await model.loadAll()
        XCTAssertEqual(model.state.section(.overview).phase, .loaded)
        XCTAssertEqual(model.state.section(.entries).phase, .failed)
        XCTAssertNil(model.state.section(.entries).snapshot)
        XCTAssertEqual(model.state.section(.batches).phase, .loaded)
    }

    func testRetryReadsOnlyTheFailedSection() async throws {
        let reader = SettlementOverviewReader(); reader.failingSections = [.entries]
        let model = model(reader)
        await model.loadAll()
        reader.failingSections = []
        let overviewReads = reader.counts[.overview] ?? 0
        await model.load(.entries, page: 1)
        XCTAssertEqual(model.state.section(.entries).phase, .loaded)
        XCTAssertEqual(reader.counts[.overview] ?? 0, overviewReads)
    }

    func testEntriesPaginationDoesNotMoveBatches() async throws {
        let reader = SettlementOverviewReader()
        let model = model(reader)
        await model.loadAll()
        model.move(.entries, by: 1)
        await settle { model.state.section(.entries).page == 2 && model.state.section(.entries).phase == .loaded }
        XCTAssertEqual(model.state.section(.entries).page, 2)
        XCTAssertEqual(model.state.section(.batches).page, 1)
        XCTAssertEqual(reader.counts[.entries(source: "all", page: 2)] ?? 0, 1)
    }

    func testScopeChangeDuringReadCannotFillAndDisappearClears() async throws {
        let reader = SettlementOverviewReader()
        let model = model(reader)
        reader.onRead = { _ in reader.scope = .init(realm: "synthetic", accountID: 99, epoch: 2) }
        await model.load(.overview, page: 1)
        XCTAssertNil(model.state.section(.overview).snapshot)
        reader.onRead = nil
        model.ownerChanged()
        XCTAssertEqual(model.state.section(.overview).phase, .notLoaded)
        model.disappear()
        XCTAssertNil(model.state.merchantID)
    }

    func testReturnFromBatchDetailRefreshesOnlyBatches() async throws {
        let reader = SettlementOverviewReader()
        let model = model(reader)
        await model.loadAll()
        let entriesReads = reader.counts[.entries(source: "all", page: 1)] ?? 0
        model.refreshBatchesAfterReturn()
        await settle { (reader.counts[.batches(page: 1)] ?? 0) == 2 }
        XCTAssertEqual(reader.counts[.batches(page: 1)] ?? 0, 2)
        XCTAssertEqual(reader.counts[.entries(source: "all", page: 1)] ?? 0, entriesReads)
    }
}
