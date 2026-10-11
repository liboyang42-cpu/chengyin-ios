import XCTest
@testable import QuestifyCore

@MainActor final class RoamPassportOverviewTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func record(_ ts: Int64, shops: Int? = nil, distance: Double? = nil, date: String? = nil) throws -> RoamHistoryRecord {
        var fields: [String: Any] = ["ts": ts]
        if let shops { fields["shops"] = shops }; if let distance { fields["distance"] = distance }; if let date { fields["date"] = date }
        return try JSONDecoder().decode(RoamHistoryRecord.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    private func ts(_ text: String) throws -> Int64 { Int64(try XCTUnwrap(ISO8601DateFormatter().date(from: text)).timeIntervalSince1970 * 1000) }
    private func identity(account: Int = 1, epoch: UInt64 = 1, namespace: String = "test", market: String = "cn", host: String = "https://example.com") throws -> RoamExperienceIdentity {
        .init(scope: try RoamHistoryScope(market: market, deployment: URL(string: host)!, accountID: account, namespace: namespace), epoch: epoch)
    }
    private func loaded(_ state: RoamPassportOverviewState, _ reader: Reader, file: StaticString = #filePath, line: UInt = #line) throws -> RoamPassportSummary {
        guard case .loaded(let summary) = state.phase(reader: reader) else { XCTFail("Expected owned summary", file: file, line: line); throw APIError.invalidRequest }
        return summary
    }
    private func isUnloaded(_ state: RoamPassportOverviewState, _ reader: Reader) -> Bool { if case .unloaded = state.phase(reader: reader) { return true }; return false }
    func testSuccessfulEmptyIsKnownZeroNotFailure() throws {
        let summary = try RoamPassportSummary(records: [], timeZone: utc)
        XCTAssertEqual(summary.trips, 0); XCTAssertEqual(summary.knownKilometers, 0); XCTAssertEqual(summary.knownShopVisits, 0); XCTAssertEqual(summary.activeDays, 0)
        XCTAssertFalse(summary.hasPartialMetrics)
    }
    func testExistingCheckedTripDistanceAndShopSumsAreReused() throws {
        let records = try [record(1_700_000_000_000, shops: 2, distance: 1.4), record(1_700_086_400_000, shops: 3, distance: 2.1)]
        let summary = try RoamPassportSummary(records: records, timeZone: utc)
        XCTAssertEqual(summary.trips, 2); XCTAssertEqual(summary.knownShopVisits, 5); XCTAssertEqual(summary.knownKilometers!, 3.5, accuracy: 0.00001)
        XCTAssertEqual(summary.activeDays, 2); XCTAssertFalse(summary.hasPartialMetrics)
    }
    func testMissingDistanceAndShopFieldsStayUnknown() throws {
        let summary = try RoamPassportSummary(records: [record(1_700_000_000_000)], timeZone: utc)
        XCTAssertNil(summary.knownKilometers); XCTAssertNil(summary.knownShopVisits)
        XCTAssertEqual(summary.tripsWithDistance, 0); XCTAssertEqual(summary.tripsWithShops, 0); XCTAssertTrue(summary.hasPartialMetrics)
    }
    func testPartialCoveragePreservesRealZero() throws {
        let summary = try RoamPassportSummary(records: [record(1_700_000_000_000, shops: 0, distance: 0), record(1_700_000_000_001)], timeZone: utc)
        XCTAssertEqual(summary.knownShopVisits, 0); XCTAssertEqual(summary.knownKilometers, 0)
        XCTAssertEqual(summary.tripsWithDistance, 1); XCTAssertEqual(summary.tripsWithShops, 1); XCTAssertTrue(summary.hasPartialMetrics)
    }
    func testShopTotalOverflowIsNotZeroOrWrapped() throws {
        let summary = try RoamPassportSummary(records: [record(1, shops: Int.max), record(2, shops: 1)], timeZone: utc)
        XCTAssertNil(summary.knownShopVisits); XCTAssertEqual(summary.tripsWithShops, 2); XCTAssertTrue(summary.hasPartialMetrics)
    }
    func testDistanceTotalOverflowIsUnknown() throws {
        let summary = try RoamPassportSummary(records: [record(1, distance: Double.greatestFiniteMagnitude), record(2, distance: Double.greatestFiniteMagnitude)], timeZone: utc)
        XCTAssertNil(summary.knownKilometers); XCTAssertEqual(summary.tripsWithDistance, 2)
    }
    func testMultipleWalksInSameLocalDayCountOnce() throws {
        let summary = try RoamPassportSummary(records: [record(ts("2026-10-11T01:00:00Z")), record(ts("2026-10-11T22:00:00Z"))], timeZone: utc)
        XCTAssertEqual(summary.activeDays, 1); XCTAssertEqual(summary.tripsWithDate, 2)
    }
    func testTimeZoneDeterminesLocalDayWithoutChangingSavedData() throws {
        let records = try [record(ts("2026-10-10T23:30:00Z")), record(ts("2026-10-11T00:30:00Z"))]
        let inUTC = try RoamPassportSummary(records: records, timeZone: utc)
        let inChina = try RoamPassportSummary(records: records, timeZone: XCTUnwrap(TimeZone(identifier: "Asia/Shanghai")))
        XCTAssertEqual(inUTC.activeDays, 2); XCTAssertEqual(inChina.activeDays, 1); XCTAssertEqual(inChina.timeZoneIdentifier, "Asia/Shanghai")
    }
    func testDSTRepeatedHourDoesNotInventAnActiveDay() throws {
        let summary = try RoamPassportSummary(records: [record(ts("2026-11-01T05:30:00Z")), record(ts("2026-11-01T06:30:00Z"))], timeZone: XCTUnwrap(TimeZone(identifier: "America/New_York")))
        XCTAssertEqual(summary.activeDays, 1); XCTAssertEqual(summary.tripsWithDate, 2)
    }
    func testSameMonthDayAcrossYearsCountsDistinctDays() throws {
        let summary = try RoamPassportSummary(records: [record(ts("2025-10-11T12:00:00Z"), date: "10.11"), record(ts("2026-10-11T12:00:00Z"), date: "10.11")], timeZone: utc)
        XCTAssertEqual(summary.activeDays, 2)
    }
    func testMissingTimestampDoesNotGuessLegacyDateText() throws {
        let summary = try RoamPassportSummary(records: [record(0, date: "2026-10-11")], timeZone: utc)
        XCTAssertNil(summary.activeDays); XCTAssertEqual(summary.tripsWithDate, 0); XCTAssertEqual(summary.trips, 1)
    }
    func testUnrepresentableTimestampIsExcludedFromDateCoverage() throws {
        let summary = try RoamPassportSummary(records: [record(-1), record(300_000_000_000_000), record(1_700_000_000_000)], timeZone: utc)
        XCTAssertEqual(summary.activeDays, 1); XCTAssertEqual(summary.tripsWithDate, 1); XCTAssertEqual(summary.trips, 3)
    }
    func testDuplicateSavedRecordCannotDoubleCount() throws {
        let entry = try record(1)
        XCTAssertThrowsError(try RoamPassportSummary(records: [entry, entry], timeZone: utc)) { XCTAssertEqual($0 as? RoamExperienceFailure, .historyUnreadable) }
    }
    func testOnlyBoundedLocalContractIsAccepted() throws {
        let records = try (1...51).map { try record(Int64($0)) }
        XCTAssertThrowsError(try RoamPassportSummary(records: records, timeZone: utc))
        XCTAssertEqual(try RoamPassportSummary(records: Array(records.prefix(50)), timeZone: utc).trips, 50)
    }
    func testConstructionPerformsNoReadAndLoadingUsesOnlyHistory() throws {
        let reader = Reader(identity: try identity()); var state = RoamPassportOverviewState()
        XCTAssertEqual(reader.reads, 0); XCTAssertTrue(isUnloaded(state, reader))
        state.load(reader: reader, timeZone: utc)
        XCTAssertEqual(try loaded(state, reader).trips, 0); XCTAssertEqual(reader.reads, 1); XCTAssertEqual(reader.remoteReads, 0)
    }
    func testLocalHistoryWorksWithoutRemoteExperienceConfiguration() throws {
        let reader = Reader(identity: try identity()); reader.isConfigured = false; reader.records = try [record(1, shops: 1, distance: 1)]
        var state = RoamPassportOverviewState(); state.load(reader: reader)
        XCTAssertEqual(try loaded(state, reader).trips, 1); XCTAssertEqual(reader.reads, 1); XCTAssertEqual(reader.remoteReads, 0)
    }
    func testSignedOutDoesNotReadOrShowZero() {
        let reader = Reader(identity: nil); var state = RoamPassportOverviewState(); state.load(reader: reader)
        guard case .failed(let error) = state.phase(reader: reader) else { return XCTFail() }
        XCTAssertEqual(error as? APIError, .unauthorized); XCTAssertEqual(reader.reads, 0)
    }
    func testCorruptReadIsErrorNotSuccessfulEmpty() throws {
        let reader = Reader(identity: try identity()); reader.failure = RoamExperienceFailure.historyUnreadable
        var state = RoamPassportOverviewState(); state.load(reader: reader)
        guard case .failed(let error) = state.phase(reader: reader) else { return XCTFail() }
        XCTAssertEqual(error as? RoamExperienceFailure, .historyUnreadable)
    }
    func testRetryCanReplaceFailureWithActualData() throws {
        let reader = Reader(identity: try identity()); reader.failure = APIError.httpStatus(503)
        var state = RoamPassportOverviewState(); state.load(reader: reader)
        reader.failure = nil; reader.records = try [record(1, shops: 2)]
        state.load(reader: reader); XCTAssertEqual(try loaded(state, reader).knownShopVisits, 2); XCTAssertEqual(reader.reads, 2)
    }
    func testRefreshReplacesPreviousTotalsIncludingRealDeletion() throws {
        let reader = Reader(identity: try identity()); reader.records = try [record(1)]
        var state = RoamPassportOverviewState(); state.load(reader: reader); XCTAssertEqual(try loaded(state, reader).trips, 1)
        reader.records = []; state.load(reader: reader); XCTAssertEqual(try loaded(state, reader).trips, 0)
        XCTAssertEqual(reader.remoteReads, 0)
    }
    func testFailedRefreshNeverKeepsStaleSuccess() throws {
        let reader = Reader(identity: try identity()); var state = RoamPassportOverviewState(); state.load(reader: reader)
        reader.failure = RoamExperienceFailure.historyUnreadable; state.load(reader: reader)
        guard case .failed = state.phase(reader: reader) else { return XCTFail() }
    }
    func testReaderReplacementCannotDisplayOldSnapshot() throws {
        let original = Reader(identity: try identity()), replacement = Reader(identity: try identity())
        var state = RoamPassportOverviewState(); state.load(reader: original)
        XCTAssertTrue(isUnloaded(state, replacement)); XCTAssertEqual(replacement.reads, 0)
    }
    func testEveryOwnerDimensionImmediatelyHidesLoadedValues() throws {
        let values = try [identity(account: 2), identity(epoch: 2), identity(namespace: "other"), identity(market: "us"), identity(host: "https://example.org")]
        for value in values {
            let reader = Reader(identity: try identity()); var state = RoamPassportOverviewState(); state.load(reader: reader)
            reader.identity = value; XCTAssertTrue(isUnloaded(state, reader))
        }
    }
    func testCanonicallyEqualUnicodeNamespacesRemainByteDistinct() throws {
        let reader = Reader(identity: try identity(namespace: "\u{00E9}")); var state = RoamPassportOverviewState(); state.load(reader: reader)
        reader.identity = try identity(namespace: "e\u{0301}")
        XCTAssertTrue(isUnloaded(state, reader))
    }
    func testIdentityChangedInsideReadRejectsLateResults() throws {
        let reader = Reader(identity: try identity()); let changed = try identity(epoch: 2)
        reader.onRead = { reader.identity = changed }
        var state = RoamPassportOverviewState(); state.load(reader: reader)
        XCTAssertTrue(isUnloaded(state, reader))
    }
    func testIdentityChangedInsideFailingReadDoesNotLeakOldError() throws {
        let reader = Reader(identity: try identity()); reader.failure = RoamExperienceFailure.historyUnreadable
        reader.onRead = { reader.identity = nil }
        var state = RoamPassportOverviewState(); state.load(reader: reader)
        XCTAssertTrue(isUnloaded(state, reader))
    }
    func testDisappearInvalidatesPrivateSummaryAndReturnReloads() throws {
        let reader = Reader(identity: try identity()); var state = RoamPassportOverviewState(); state.load(reader: reader)
        state.invalidate(); XCTAssertTrue(isUnloaded(state, reader))
        reader.records = try [record(1)]; state.load(reader: reader); XCTAssertEqual(try loaded(state, reader).trips, 1)
    }
    func testInvalidReaderRecordSetBecomesReadError() throws {
        let reader = Reader(identity: try identity()); let entry = try record(1); reader.records = [entry, entry]
        var state = RoamPassportOverviewState(); state.load(reader: reader)
        guard case .failed(let error) = state.phase(reader: reader) else { return XCTFail() }
        XCTAssertEqual(error as? RoamExperienceFailure, .historyUnreadable)
    }
    @MainActor private final class Reader: RoamExperienceReading {
        var identity: RoamExperienceIdentity?
        var isConfigured = true
        var isOfflineExample = true
        var records: [RoamHistoryRecord] = []
        var failure: Error?
        var onRead: (() -> Void)?
        var reads = 0
        var remoteReads = 0
        init(identity: RoamExperienceIdentity?) { self.identity = identity }
        func history() throws -> [RoamHistoryRecord] { reads += 1; onRead?(); if let failure { throw failure }; return records }
        func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { remoteReads += 1; throw APIError.notConfigured }
        func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { remoteReads += 1; throw APIError.notConfigured }
        func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { remoteReads += 1; throw APIError.notConfigured }
        func shopBadge() async throws -> RoamShopBadge? { remoteReads += 1; throw APIError.notConfigured }
    }
}
