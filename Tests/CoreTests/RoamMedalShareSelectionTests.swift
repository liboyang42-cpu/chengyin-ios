import XCTest
@testable import QuestifyCore

@MainActor final class RoamMedalShareSelectionTests: XCTestCase {
    private final class Reader: RoamExperienceReading {
        var identity: RoamExperienceIdentity?
        var isConfigured = true
        var isOfflineExample = true
        var records: [RoamHistoryRecord] = []
        var readCount = 0
        var failure: Error?
        var duringRead: (() -> Void)?
        func history() throws -> [RoamHistoryRecord] {
            readCount += 1; duringRead?()
            if let failure { throw failure }; return records
        }
        func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { throw APIError.notConfigured }
        func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
        func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
        func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
    }
    private func record(_ fields: [String: Any] = [:]) throws -> RoamHistoryRecord {
        let base: [String: Any] = ["ts": 1700000000000, "medal": "Saved journey medal", "shopMedalName": "Saved shop medal"]
        return try JSONDecoder().decode(RoamHistoryRecord.self, from: JSONSerialization.data(withJSONObject: base.merging(fields) { _, new in new }))
    }
    private func identity(account: Int = 7, epoch: UInt64 = 1, namespace: String = "medal-tests", realm: String = "https://example.com/", market: String = "cn") throws -> RoamExperienceIdentity {
        .init(scope: try .init(market: market, deployment: URL(string: realm)!, accountID: account, namespace: namespace), epoch: epoch)
    }
    private func reader(_ records: [RoamHistoryRecord]) throws -> Reader {
        let reader = Reader(); reader.identity = try identity(); reader.records = records; return reader
    }
    private func authority(_ reader: Reader, _ record: RoamHistoryRecord) throws -> RoamMedalShareAuthority {
        try XCTUnwrap(RoamMedalShareAuthority(selection: XCTUnwrap(.init(record: record, kind: .journey)), reader: reader))
    }
    func testBothRecordedMedalKindsStayDistinctEvenWhenNamesEqual() throws {
        let record = try record(["medal": "Same name", "shopMedalName": "Same name"])
        let values = RoamMedalShareSelection.selections(for: record)
        XCTAssertEqual(values.map(\.id), [.journey, .shop]); XCTAssertEqual(values.map(\.card.name), ["Same name", "Same name"])
    }
    func testAbsentBlankAndWhitespaceNamesNeverCreateAnAward() throws {
        for empty in [NSNull(), "", " \n\t"] as [Any] {
            let record = try record(["medal": empty, "shopMedalName": empty, "shops": 999, "distance": 999])
            XCTAssertTrue(RoamMedalShareSelection.selections(for: record).isEmpty)
        }
    }
    func testExactEarnedNameIsNotReplacedByAThresholdOrCatalogue() throws {
        let record = try record(["medal": "  城市漫游 · Café 🏅  "])
        let value = try XCTUnwrap(RoamMedalShareSelection(record: record, kind: .journey))
        XCTAssertEqual(Array(value.card.name.utf8), Array("  城市漫游 · Café 🏅  ".utf8))
        XCTAssertEqual(value.card.recordedAt, Date(timeIntervalSince1970: 1700000000))
    }
    func testCardProjectionExcludesAllLocationMediaAndAccountFields() throws {
        let record = try record(["zone": "PRIVATE", "photos": ["https://example.com/private.jpg"], "serverSessionID": 999,
                                 "track": [["lat": 1, "lng": 2]], "pois": [["name": "PRIVATE", "lat": 1, "lng": 2]]])
        let value = try XCTUnwrap(RoamMedalShareSelection(record: record, kind: .journey))
        XCTAssertEqual(Set(Mirror(reflecting: value.card).children.compactMap(\.label)), ["kind", "name", "recordedAt"])
    }
    func testUnknownDateRemainsAbsent() throws {
        let record = try record(["ts": 0])
        XCTAssertNil(RoamMedalShareSelection(record: record, kind: .journey)?.card.recordedAt)
    }
    func testExactCurrentRecordCanPrepareAndSave() throws {
        let record = try record(), reader = try reader([record]), gate = try authority(reader, record)
        XCTAssertTrue(gate.matchesOwner(reader)); XCTAssertTrue(gate.isCurrent(reader)); XCTAssertEqual(reader.readCount, 1)
    }
    func testNoAuthorityWithoutIdentityOrReadConfiguration() throws {
        let record = try record(), reader = try reader([record]), value = try XCTUnwrap(RoamMedalShareSelection(record: record, kind: .journey))
        reader.identity = nil; XCTAssertNil(RoamMedalShareAuthority(selection: value, reader: reader))
        reader.identity = try identity(); reader.isConfigured = false
        XCTAssertNil(RoamMedalShareAuthority(selection: value, reader: reader)); XCTAssertEqual(reader.readCount, 0)
    }
    func testReplacementReaderCannotReuseSameAccountAuthority() throws {
        let record = try record(), old = try reader([record]), next = try reader([record]), gate = try authority(old, record)
        XCTAssertFalse(gate.isCurrent(next)); XCTAssertEqual(next.readCount, 0)
    }
    func testOwnerEpochMarketRealmAndExactNamespaceAreFencedBeforeRead() throws {
        let record = try record(), reader = try reader([record]), gate = try authority(reader, record)
        let replacements = [try identity(account: 8), try identity(epoch: 2), try identity(market: "us"), try identity(realm: "https://other.example.com/"), try identity(namespace: "other")]
        for next in replacements { reader.identity = next; XCTAssertFalse(gate.isCurrent(reader)) }
        reader.identity = nil; XCTAssertFalse(gate.isCurrent(reader)); XCTAssertEqual(reader.readCount, 0)
    }
    func testCanonicallyEquivalentNamespaceBytesAreDifferentOwners() throws {
        let record = try record(), reader = try reader([record])
        reader.identity = try identity(namespace: "e\u{301}"); let gate = try authority(reader, record)
        reader.identity = try identity(namespace: "\u{e9}")
        XCTAssertFalse(gate.isCurrent(reader)); XCTAssertEqual(reader.readCount, 0)
    }
    func testMissingDuplicateOrEditedRecordFailsClosed() throws {
        let record = try record(), reader = try reader([record]), gate = try authority(reader, record)
        for rows in [[], [record, record], [try self.record(["medal": "Different medal"])], [try self.record(["distance": 4])]] {
            reader.records = rows; XCTAssertFalse(gate.isCurrent(reader))
        }
    }
    func testReadFailureNeverAuthorizesExport() throws {
        let record = try record(), reader = try reader([record]), gate = try authority(reader, record)
        reader.failure = RoamExperienceFailure.historyUnreadable; XCTAssertFalse(gate.isCurrent(reader))
    }
    func testOwnerMutationDuringSynchronousReadIsRejected() throws {
        let record = try record(), reader = try reader([record]), gate = try authority(reader, record)
        reader.duringRead = { reader.identity = nil }; XCTAssertFalse(gate.isCurrent(reader))
    }
    func testDisabledReaderCannotReadOrExport() throws {
        let record = try record(), reader = try reader([record]), gate = try authority(reader, record)
        reader.isConfigured = false; XCTAssertFalse(gate.isCurrent(reader)); XCTAssertEqual(reader.readCount, 0)
    }
}
