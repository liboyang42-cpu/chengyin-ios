import XCTest
@testable import QuestifyCore

final class RoamExperienceContractTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }
    func testUnknownRecoveryStateIsNotMissing() {
        XCTAssertThrowsError(try decode(RoamSessionFact.self, #"{"state":"RETRY_LATER"}"#))
    }
    func testCompleteSettlementRequiresAllFactsAndExplicitCompleteFlag() throws {
        let result = try decode(RoamSessionFact.self, RoamExperienceSyntheticFixtures.settled)
        XCTAssertTrue(result.hasCompleteSettlement); XCTAssertEqual(result.result?.totalXp, 32)
        let partial = try decode(RoamSessionFact.self, RoamExperienceSyntheticFixtures.incomplete)
        XCTAssertFalse(partial.hasCompleteSettlement)
        let falselyComplete = RoamExperienceSyntheticFixtures.incomplete.replacingOccurrences(of: "false", with: "true")
        XCTAssertFalse(try decode(RoamSessionFact.self, falselyComplete).hasCompleteSettlement)
        let blankMedal = RoamExperienceSyntheticFixtures.settled.replacingOccurrences(of: "\"sessionShops\":2", with: "\"sessionShops\":2,\"medal\":\"   \"")
        XCTAssertNil(try decode(RoamSessionFact.self, blankMedal).result?.medal)
    }
    func testActiveAndMissingNeverExposeSettlementRewards() throws {
        let active = try decode(RoamSessionFact.self, #"{"state":"ACTIVE","sessionId":2,"result":{"totalXp":999}}"#)
        XCTAssertNil(active.result); XCTAssertFalse(active.hasCompleteSettlement)
        let missing = try decode(RoamSessionFact.self, RoamExperienceSyntheticFixtures.missing)
        XCTAssertEqual(missing.state, .notFound); XCTAssertNil(missing.result)
    }
    func testActiveRequiresValidServerSessionID() {
        for json in [#"{"state":"ACTIVE"}"#, #"{"state":"ACTIVE","sessionId":0}"#, #"{"state":"FINISHED","sessionId":"abc"}"#] {
            XCTAssertThrowsError(try decode(RoamSessionFact.self, json))
        }
    }
    func testNegativeRewardsAreMalformed() {
        XCTAssertThrowsError(try decode(RoamSessionFact.self, RoamExperienceSyntheticFixtures.settled.replacingOccurrences(of: "\"totalXp\":32", with: "\"totalXp\":-1")))
    }
    func testRecoveryQueryIsExclusiveAndRejectsInvalidInput() throws {
        XCTAssertEqual(RoamRecoveryQuery.sessionID(901).fields, ["sessionId": "901"])
        XCTAssertEqual(RoamRecoveryQuery.clientSessionKey("sample-key").fields, ["clientSessionKey": "sample-key"])
        for query in [RoamRecoveryQuery.sessionID(0), .clientSessionKey(""), .clientSessionKey(" bad "), .clientSessionKey("bad\nkey")] {
            XCTAssertThrowsError(try query.validate())
        }
    }
    func testRecoveryQueryChecksIdentity() throws {
        let fact = try decode(RoamSessionFact.self, RoamExperienceSyntheticFixtures.settled)
        XCTAssertTrue(RoamRecoveryQuery.sessionID(901).matches(fact))
        XCTAssertFalse(RoamRecoveryQuery.sessionID(902).matches(fact))
        XCTAssertFalse(RoamRecoveryQuery.clientSessionKey("other").matches(fact))
    }
    func testUnsubmittedStampVisibleRejectedAndUnknownWithheld() throws {
        let page = try decode(RoamAlbumPage.self, RoamExperienceSyntheticFixtures.album)
        XCTAssertEqual(page.list.filter(\.isVisible).map(\.id), [901, 902])
        XCTAssertFalse(try decode(RoamAlbumStamp.self, #"{"id":904,"checkState":99}"#).isVisible)
    }
    func testAlbumPaginationUsesServerTotalsNotVisibleCount() throws {
        let page = try decode(RoamAlbumPage.self, RoamExperienceSyntheticFixtures.album.replacingOccurrences(of: "\"total\":3", with: "\"total\":21"))
        XCTAssertTrue(page.hasMore)
        XCTAssertThrowsError(try decode(RoamAlbumPage.self, #"{"list":[],"total":1,"pageNum":0,"pageSize":20}"#))
        XCTAssertThrowsError(try decode(RoamAlbumPage.self, #"{"list":[],"total":1,"pageNum":1,"pageSize":0}"#))
    }
    func testHistoryPreservesUnknownStatsAndNumericStringCoordinates() throws {
        let rows = try decode([RoamHistoryRecord].self, RoamExperienceSyntheticFixtures.history)
        XCTAssertEqual(rows[0].distance, 1.4); XCTAssertEqual(rows[0].track[0].lat, 1)
        XCTAssertEqual(rows[0].durationText, "20:30")
        XCTAssertNil(rows[1].distance); XCTAssertNil(rows[1].durationText); XCTAssertNil(rows[1].shops)
        let summary = RoamHistorySummary(rows)
        XCTAssertEqual(summary.trips, 2); XCTAssertEqual(summary.tripsWithDistance, 1); XCTAssertEqual(summary.tripsWithShops, 1)
    }
    func testCorruptHistoryPointsInvalidateWholeRecord() {
        for json in [#"{"ts":1,"track":[{"lat":91,"lng":0}]}"#, #"{"ts":1,"pois":[{"name":"bad","lat":"NaN","lng":0}]}"#, #"{"ts":1,"track":"wrong"}"#, #"{"ts":"NaN"}"#, #"{"ts":true}"#] {
            XCTAssertThrowsError(try decode(RoamHistoryRecord.self, json))
        }
    }
    func testZeroIsKnownAndPlaceholderZoneIsNotARealPlace() throws {
        let row = try decode(RoamHistoryRecord.self, #"{"ts":1,"zone":"这片街区","distance":0,"durSec":0,"shops":0}"#)
        XCTAssertEqual(row.distance, 0); XCTAssertEqual(row.durationText, "00:00"); XCTAssertNil(row.meaningfulZone)
    }
    func testHistoryRoundTripAndLegacyPhotoReferences() throws {
        let row = try decode(RoamHistoryRecord.self, #"{"ts":"1700000000000","photos":["local-reference",{"path":"other-reference"},{"url":"third-reference"}]}"#)
        XCTAssertEqual(row.photos.count, 3)
        XCTAssertEqual(try JSONDecoder().decode(RoamHistoryRecord.self, from: JSONEncoder().encode(row)), row)
    }
    func testVoucherCodeDoesNotDependOnQRCodeImageAndTTLMatchesSourceImplementation() throws {
        let snapshot = try decode(RoamVoucherSnapshot.self, #"{"code":"SYNTHETIC-NOT-REDEEMABLE","qrcodeUrl":"","ttlMs":1000}"#)
        XCTAssertTrue(snapshot.hasCode); XCTAssertEqual(snapshot.countdownSeconds, 1)
        XCTAssertEqual(try decode(RoamVoucherSnapshot.self, "{}").countdownSeconds, 300)
        XCTAssertEqual(try decode(RoamVoucherSnapshot.self, #"{"ttlMs":-1}"#).countdownSeconds, 300)
    }
    func testVoucherExpiryUsesAbsoluteTimeAfterBackgrounding() throws {
        let snapshot = try decode(RoamVoucherSnapshot.self, #"{"ttlMs":2000}"#)
        let start = Date(timeIntervalSince1970: 100)
        let clock = RoamVoucherClock(snapshot: snapshot, receivedAt: start)
        XCTAssertEqual(clock.remaining(at: start), 2)
        XCTAssertEqual(clock.remaining(at: start.addingTimeInterval(0.5)), 2)
        XCTAssertEqual(clock.remaining(at: start.addingTimeInterval(600)), 0)
    }
    func testCaptionUsesSourceUTF16Units() {
        XCTAssertTrue(RoamExperienceMath.validCaption(String(repeating: "a", count: 30)))
        XCTAssertFalse(RoamExperienceMath.validCaption(String(repeating: "a", count: 31)))
        XCTAssertTrue(RoamExperienceMath.validCaption(String(repeating: "😀", count: 15)))
        XCTAssertFalse(RoamExperienceMath.validCaption(String(repeating: "😀", count: 16)))
    }
    func testStampBarcodeMatchesIndependentFlutterGolden() {
        let bars = RoamExperienceMath.stampBarcode(serial: 7)
        XCTAssertEqual(bars.map(\.width), [1,2,1,1,1,1,3,2,1,1,2,1,2,3,2,1,1,2,2,3,1,2,3,1,2,1,1,1,1,3,1,1,2,1,3,2,2,2,2,2,3,2,2,1,2,1])
        XCTAssertEqual(bars.map(\.gap), [2,2,2,2,2,1,2,2,2,1,1,2,2,1,1,1,2,2,2,1,2,1,1,2,2,1,1,2,1,2,1,2,2,2,2,2,2,2,1,2,2,1,2,1,2,2])
    }
    func testGeohashAndDistanceNeverBecomeRewards() throws {
        let point = try XCTUnwrap(RoamCoordinate(latitude: 0, longitude: 0))
        XCTAssertEqual(RoamExperienceMath.tileKey(point), "s000000")
        XCTAssertEqual(RoamExperienceMath.distanceMeters(point, point), 0)
        XCTAssertNil(RoamExperienceMath.tileKey(point, precision: 0))
        XCTAssertFalse(RoamExperienceMath.isValidTile("INVALID"))
        XCTAssertFalse(RoamExperienceCapabilities.location); XCTAssertFalse(RoamExperienceCapabilities.presence)
        XCTAssertFalse(RoamExperienceCapabilities.settlement); XCTAssertFalse(RoamExperienceCapabilities.voucherIssue)
        XCTAssertFalse(RoamExperienceCapabilities.redemption); XCTAssertFalse(RoamExperienceCapabilities.mediaUpload)
        XCTAssertFalse(RoamExperienceCapabilities.stampExchange); XCTAssertFalse(RoamExperienceCapabilities.legacyHangout)
    }
    func testRouteSketchRequiresTwoTrackPointsAndIncludesPOIBounds() throws {
        let rows = try decode([RoamHistoryRecord].self, RoamExperienceSyntheticFixtures.history)
        let sketch = RoamRouteSketch(track: rows[0].track, places: rows[0].pois.map(\.point))
        XCTAssertEqual(sketch.track.count, 3); XCTAssertEqual(sketch.places.count, 1)
        XCTAssertTrue((sketch.track + sketch.places).allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
        XCTAssertTrue(RoamRouteSketch(track: [], places: rows[0].pois.map(\.point)).track.isEmpty)
    }
    func testDeviceFixRequiresFiniteAccuracyAndKeepsDatumExplicit() throws {
        let coordinate = try XCTUnwrap(RoamCoordinate(latitude: 1, longitude: 1))
        XCTAssertThrowsError(try RoamDeviceFix(coordinate: coordinate, accuracyMeters: -.infinity, measuredAt: Date(), datum: .wgs84))
        let fix = try RoamDeviceFix(coordinate: coordinate, accuracyMeters: 10, measuredAt: Date(), datum: .wgs84)
        XCTAssertEqual(fix.datum, .wgs84)
    }
}

@MainActor private final class LocalWalkStorageFixture: RoamHistoryDataStoring {
    var bytes: [String: Data] = [:]
    var reads = 0, writes = 0
    var failRead = false
    var onRead: (() -> Void)?
    func read(key: String) throws -> Data? {
        reads += 1; onRead?()
        if failRead { throw RoamLiveFailure.journalUnavailable }
        return bytes[key]
    }
    func write(_ data: Data, key: String) throws { writes += 1; bytes[key] = data }
}
@MainActor final class RoamLocalWalkReadingTests: XCTestCase {
    private func scope(_ account: Int = 7) throws -> RoamHistoryScope {
        try .init(market: "cn", deployment: XCTUnwrap(URL(string: "https://example.com/roam")), accountID: account, namespace: "local-history")
    }
    private func session(_ scope: RoamHistoryScope, epoch: UInt64 = 1) throws -> RoamExperienceSession {
        try .init(scope: scope, epoch: epoch, token: "synthetic-token")
    }
    private func record(_ scope: RoamHistoryScope) -> RoamLiveRecord {
        .init(scope: scope, clientSessionKey: String(repeating: "a", count: 32), startedAt: Date(timeIntervalSince1970: 1000))
    }
    func testOptionalJournalAndMissingRecordAreDistinctWithoutAnyWrite() throws {
        let storage = LocalWalkStorageFixture(), s = try scope(), owner = try session(s)
        let store = RoamHistoryStore(storage: storage, currentScope: { s })
        let unavailable = RoamExperienceSessionReader(service: nil, store: store, currentSession: { owner })
        XCTAssertEqual(try unavailable.localWalkStatus(), .unavailable); XCTAssertEqual(storage.reads, 0)
        let reader = RoamExperienceSessionReader(service: nil, store: store,
            localJournal: RoamLiveJournal(storage: storage), currentSession: { owner })
        XCTAssertFalse(reader.isConfigured) // Remote approval is not local-storage read permission.
        XCTAssertEqual(try reader.localWalkStatus(), .none); XCTAssertEqual(storage.reads, 1)
        XCTAssertEqual(storage.writes, 0); XCTAssertTrue(storage.bytes.isEmpty)
    }
    func testOnlyValidatedMetadataClassifiesUnfinishedOrPendingFinish() throws {
        let storage = LocalWalkStorageFixture(), s = try scope(), owner = try session(s)
        let journal = RoamLiveJournal(storage: storage)
        let reader = RoamExperienceSessionReader(service: nil,
            store: RoamHistoryStore(storage: storage, currentScope: { s }), localJournal: journal, currentSession: { owner })
        var value = record(s); try journal.write(value)
        var writes = storage.writes
        XCTAssertEqual(try reader.localWalkStatus(), .unfinished); XCTAssertEqual(storage.writes, writes)
        value.finishRequested = true; try journal.write(value); writes = storage.writes
        XCTAssertEqual(try reader.localWalkStatus(), .finishPending); XCTAssertEqual(storage.writes, writes)
        value.finishRequested = false; value.pendingWrite = .finish; try journal.write(value); writes = storage.writes
        XCTAssertEqual(try reader.localWalkStatus(), .finishPending); XCTAssertEqual(storage.writes, writes)
        value.pendingWrite = .reveal; try journal.write(value); writes = storage.writes
        XCTAssertEqual(try reader.localWalkStatus(), .unfinished); XCTAssertEqual(storage.writes, writes)
    }
    func testUnreadableAndCorruptJournalNeverBecomeMissingAndBytesRemainUnchanged() throws {
        let storage = LocalWalkStorageFixture(), s = try scope(), owner = try session(s)
        let journal = RoamLiveJournal(storage: storage); try journal.write(record(s))
        let reader = RoamExperienceSessionReader(service: nil,
            store: RoamHistoryStore(storage: storage, currentScope: { s }), localJournal: journal, currentSession: { owner })
        storage.failRead = true; let original = storage.bytes, writes = storage.writes
        XCTAssertThrowsError(try reader.localWalkStatus()); XCTAssertEqual(storage.bytes, original)
        storage.failRead = false
        for key in Array(storage.bytes.keys) { storage.bytes[key] = Data("corrupt".utf8) }
        let corrupt = storage.bytes
        XCTAssertThrowsError(try reader.localWalkStatus()); XCTAssertEqual(storage.bytes, corrupt)
        XCTAssertEqual(storage.writes, writes)
        storage.bytes = original
        XCTAssertEqual(try reader.localWalkStatus(), .unfinished) // Only a new successful read clears failure.
    }
    func testAccountAndEpochReplacementDuringReadRejectOldMetadata() throws {
        for changeAccount in [false, true] {
            let storage = LocalWalkStorageFixture(), s = try scope()
            var owner: RoamExperienceSession? = try session(s)
            let replacement = try session(changeAccount ? scope(8) : s, epoch: 2)
            let journal = RoamLiveJournal(storage: storage); try journal.write(record(s))
            let reader = RoamExperienceSessionReader(service: nil,
                store: RoamHistoryStore(storage: storage, currentScope: { owner?.identity.scope }),
                localJournal: journal, currentSession: { owner })
            storage.onRead = { owner = replacement }
            XCTAssertThrowsError(try reader.localWalkStatus()) { XCTAssertTrue($0 is CancellationError) }
        }
    }
    func testOtherAccountDoesNotReadFirstAccountRecordAndLogoutDoesNotTouchStorage() throws {
        let storage = LocalWalkStorageFixture(), first = try scope(), second = try scope(8)
        let journal = RoamLiveJournal(storage: storage); try journal.write(record(first))
        var owner: RoamExperienceSession? = try session(second)
        let reader = RoamExperienceSessionReader(service: nil,
            store: RoamHistoryStore(storage: storage, currentScope: { owner?.identity.scope }),
            localJournal: journal, currentSession: { owner })
        XCTAssertEqual(try reader.localWalkStatus(), .none)
        let reads = storage.reads, writes = storage.writes; owner = nil
        XCTAssertThrowsError(try reader.localWalkStatus()) { XCTAssertEqual($0 as? APIError, .unauthorized) }
        XCTAssertEqual(storage.reads, reads); XCTAssertEqual(storage.writes, writes)
    }
}

extension RoamExperienceContractTests {
    func testHistoryShopSummaryMissingMeasurementsHaveNoMeasuredRows() throws {
        let rows = try JSONDecoder().decode([RoamHistoryRecord].self, from: Data(#"[{"ts":1},{"ts":2}]"#.utf8))
        let summary = RoamHistorySummary(rows)
        XCTAssertEqual(summary.trips, 2); XCTAssertEqual(summary.tripsWithShops, 0)
        // The UI requires measured rows before presenting this accumulator as a real zero.
        XCTAssertEqual(summary.knownShops, 0)
    }
    func testHistoryShopSummaryPreservesMeasuredZeroAndPartialCoverage() throws {
        let rows = try JSONDecoder().decode([RoamHistoryRecord].self, from: Data(#"[{"ts":1,"shops":0},{"ts":2}]"#.utf8))
        let summary = RoamHistorySummary(rows)
        XCTAssertEqual(summary.knownShops, 0); XCTAssertEqual(summary.tripsWithShops, 1); XCTAssertEqual(summary.trips, 2)
    }
    func testHistoryShopSummaryUsesVisitsAcrossWalksNotUniqueMerchantCount() throws {
        let rows = try JSONDecoder().decode([RoamHistoryRecord].self, from: Data(#"[{"ts":1,"shops":2},{"ts":2,"shops":3}]"#.utf8))
        let summary = RoamHistorySummary(rows)
        XCTAssertEqual(summary.knownShops, 5); XCTAssertEqual(summary.tripsWithShops, 2)
        XCTAssertEqual(summary.tripsWithShops, summary.trips)
    }
    func testHistoryShopSummaryOverflowIsUnknownNotWrappedOrSaturatedSuccess() throws {
        let rows = try JSONDecoder().decode([RoamHistoryRecord].self, from: Data("[{\"ts\":1,\"shops\":\(Int.max)},{\"ts\":2,\"shops\":1}]".utf8))
        let summary = RoamHistorySummary(rows)
        XCTAssertNil(summary.knownShops); XCTAssertEqual(summary.tripsWithShops, 2)
    }
}

final class RoamFinishedStoryContractTests: XCTestCase {
    private func decode(_ story: Any? = nil, complete: Bool = true, state: String = "FINISHED",
                        removeTotal: Bool = false) throws -> RoamSessionFact {
        var result: [String: Any] = ["tileXp": 1, "poiXp": 2, "totalXp": 3,
            "newTiles": 4, "newPois": 5, "tilesEver": 6, "sessionShops": 7]
        if let story { result["routeStory"] = story }
        if removeTotal { result.removeValue(forKey: "totalXp") }
        let object: [String: Any] = ["state": state, "sessionId": 12,
            "resultComplete": complete, "result": result]
        return try JSONDecoder().decode(RoamSessionFact.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testMissingNullAndMalformedOptionalStoryKeepOldSettlementFacts() throws {
        let original = try decode()
        XCTAssertTrue(original.hasCompleteSettlement); XCTAssertNil(original.result?.routeStory)
        for value in [NSNull(), 0, true, ["text": "Not a string"], ["Not a string"]] as [Any] {
            let fact = try decode(value)
            XCTAssertEqual(fact, original)
            XCTAssertTrue(fact.hasCompleteSettlement); XCTAssertNil(fact.result?.routeStory)
        }
    }
    func testStoryPreservesReturnedUnicodeAndSurroundingWhitespaceBytes() throws {
        for text in ["  e\u{301} 与 👩🏽‍🚀\r\n", "\u{00A0}Returned reflection\u{2003}", "  **Received text**  "] {
            let returned = try XCTUnwrap(decode(text).result?.routeStory)
            XCTAssertEqual(Array(returned.utf8), Array(text.utf8))
        }
        for blank in ["", " \t\r\n", "\u{00A0}\u{2003}"] {
            XCTAssertNil(try decode(blank).result?.routeStory)
            XCTAssertTrue(try decode(blank).hasCompleteSettlement)
        }
    }
    func testConsumerDoesNotTruncateOrRejectReceivedTextAtEightyUTF16Units() throws {
        for text in [String(repeating: "a", count: 80), String(repeating: "a", count: 81),
                     String(repeating: "😀", count: 40), String(repeating: "😀", count: 40) + "x",
                     String(repeating: "\u{00A0}", count: 80) + "x", String(repeating: "\u{2003}", count: 80) + "x"] {
            let returned = try XCTUnwrap(decode(text).result?.routeStory)
            XCTAssertEqual(Array(returned.utf8), Array(text.utf8))
            XCTAssertTrue(try decode(text).hasCompleteSettlement)
        }
    }
    func testStoryNeverMakesIncompleteActiveOrMissingFactsComplete() throws {
        XCTAssertFalse(try decode("Returned reflection", complete: false).hasCompleteSettlement)
        XCTAssertFalse(try decode("Returned reflection", removeTotal: true).hasCompleteSettlement)
        for state in ["ACTIVE", "NOT_FOUND"] {
            let fact = try decode("Returned reflection", state: state)
            XCTAssertNil(fact.result); XCTAssertFalse(fact.hasCompleteSettlement)
        }
    }
}
