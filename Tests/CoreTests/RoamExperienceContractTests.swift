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
