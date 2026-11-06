import XCTest
@testable import QuestifyCore

final class RoamPassportServerHistoryContractTests: XCTestCase {
    private func fact(_ id: String, extra: String = "") -> String { "{\"sessionId\":\"\(id)\"\(extra)}" }
    private func page(_ rows: [String], more: Bool = false, cursor: String = "null") -> Data {
        Data("{\"items\":[\(rows.joined(separator: ","))],\"hasMore\":\(more),\"nextBefore\":\(cursor)}".utf8)
    }
    func testCanonicalLongIDsAreNotRounded() throws {
        let ids = ["9223372036854775807", "9007199254740993", "9007199254740992", "99", "9"]
        let result = try RoamPassportHistoryContract.page(page(ids.map { fact($0) }))
        XCTAssertEqual(result.items.map(\.sessionID), ids)
        for id in ["0", "01", "-1", "1.0", "1e2", " 1", "١", "9223372036854775808"] {
            XCTAssertFalse(RoamPassportHistoryContract.isSessionID(id), id)
            XCTAssertThrowsError(try RoamPassportHistoryContract.record(Data(fact(id).utf8), sessionID: id))
        }
    }
    func testNumbersNeverSubstituteForStringIdentity() {
        XCTAssertThrowsError(try RoamPassportHistoryContract.record(Data("{\"sessionId\":12}".utf8), sessionID: "12"))
    }
    func testPageMustAdvanceStrictlyFromRequestedCursor() throws {
        XCTAssertEqual(try RoamPassportHistoryContract.page(page([fact("9"), fact("8")], more: true, cursor: "\"8\""), before: "10").nextBefore, "8")
        for rows in [[fact("10")], [fact("9"),fact("9")], [fact("8"),fact("9")]] {
            XCTAssertThrowsError(try RoamPassportHistoryContract.page(page(rows), before: "10"))
        }
        XCTAssertThrowsError(try RoamPassportHistoryContract.page(page([]), before: "01"))
    }
    func testNonterminalPageRequiresLastRowCursorAndAtMostThirtyRows() {
        XCTAssertThrowsError(try RoamPassportHistoryContract.page(page([], more: true, cursor: "\"8\"")))
        XCTAssertThrowsError(try RoamPassportHistoryContract.page(page([fact("9")], more: true, cursor: "\"8\"")))
        XCTAssertThrowsError(try RoamPassportHistoryContract.page(page((1...31).reversed().map { fact(String($0)) })))
    }
    func testTerminalCursorDoesNotAuthorizeAnotherPage() throws {
        XCTAssertNil(try RoamPassportHistoryContract.page(page([fact("9")], cursor: "{\"ignored\":true}")).nextBefore)
        XCTAssertTrue(try RoamPassportHistoryContract.page(page([])).items.isEmpty)
    }
    func testUnknownCountsStayUnknownAndZeroIsReal() throws {
        let unknown = try RoamPassportHistoryContract.record(Data(fact("9").utf8), sessionID: "9")
        XCTAssertNil(unknown.distanceKM); XCTAssertNil(unknown.shops); XCTAssertNil(unknown.durationSeconds)
        let zero = try RoamPassportHistoryContract.record(Data(fact("9", extra: ",\"distanceM\":0,\"shops\":0,\"startedAt\":0,\"finishedAt\":0").utf8), sessionID: "9")
        XCTAssertEqual(zero.distanceKM, 0); XCTAssertEqual(zero.shops, 0); XCTAssertEqual(zero.durationSeconds, 0)
    }
    func testCountsRejectStringsBooleansNegativeFractionAndUnsafeNumber() {
        for value in ["\"2\"", "true", "-1", "1.5", "9007199254740992"] {
            for key in ["startedAt", "finishedAt", "distanceM", "shops"] {
                XCTAssertThrowsError(try RoamPassportHistoryContract.record(Data(fact("9", extra: ",\"\(key)\":\(value)").utf8), sessionID: "9"))
            }
        }
    }
    func testDurationAndDistanceUseOriginalUnitsWithoutInventingDuration() throws {
        let value = try RoamPassportHistoryContract.record(Data(fact("9", extra: ",\"startedAt\":1000,\"finishedAt\":3499,\"distanceM\":1500").utf8), sessionID: "9")
        XCTAssertEqual(value.durationSeconds, 2); XCTAssertEqual(value.distanceKM, 1.5); XCTAssertEqual(value.timestamp, 3499)
        let reversed = try RoamPassportHistoryContract.record(Data(fact("9", extra: ",\"startedAt\":2000,\"finishedAt\":1000").utf8), sessionID: "9")
        XCTAssertNil(reversed.durationSeconds)
    }
    func testDetailCannotReturnAnotherSession() {
        XCTAssertThrowsError(try RoamPassportHistoryContract.record(Data(fact("8").utf8), sessionID: "9"))
    }
    func testServerSummaryRequiresTripsAndDoesNotDefaultUnknownMetrics() throws {
        let result = try JSONDecoder().decode(RoamPassportServerSummary.self, from: Data("{\"trips\":0}".utf8))
        XCTAssertEqual(result.trips, 0); XCTAssertNil(result.distanceM); XCTAssertNil(result.days); XCTAssertNil(result.shops)
        for json in ["{}", "{\"trips\":null}", "{\"trips\":true}", "{\"trips\":-1}", "{\"trips\":1,\"shops\":\"2\"}"] {
            XCTAssertThrowsError(try JSONDecoder().decode(RoamPassportServerSummary.self, from: Data(json.utf8)))
        }
    }
}

final class RoamPassportP7TrackContractTests: XCTestCase {
    private func fact(_ track: String) throws -> RoamPassportHistoryFact {
        try RoamPassportHistoryContract.record(Data("{\"sessionId\":\"9223372036854775807\",\"distanceM\":15,\"track\":\(track)}".utf8), sessionID: "9223372036854775807")
    }
    func testExactP7TrackRetainsOriginalPairsWithoutSynthesizingGeometry() throws {
        let value = try fact("[[31.2,121.4],[31.3,121.5]]")
        XCTAssertEqual(value.track.map(\.lat), [31.2,31.3]); XCTAssertEqual(value.track.map(\.lng), [121.4,121.5])
        XCTAssertEqual(value.sessionID, "9223372036854775807"); XCTAssertNil(value.shops)
    }
    func testNullExpiredAndMissingTrackRemainEmptyWithKnownDistance() throws {
        XCTAssertTrue(try fact("null").track.isEmpty)
        let value = try RoamPassportHistoryContract.record(Data(#"{"sessionId":"1","distanceM":999}"#.utf8), sessionID:"1")
        XCTAssertTrue(value.track.isEmpty); XCTAssertEqual(value.distanceM,999)
    }
    func testMalformedOptionalTrackDropsWholeTrackButNotServerFact() throws {
        for bad in [#"[[31,121],[91,121]]"#, #"[[31,121],[31,"121"]]"#, #"[[31,121,3]]"#, #"{"lat":31}"#, #"[[true,121]]"#] {
            XCTAssertTrue(try fact(bad).track.isEmpty,bad); XCTAssertEqual(try fact(bad).distanceM,15)
        }
    }
    func testSingleValidPointDoesNotInventLineOrPlaces() throws {
        let value = try fact("[[31,121]]")
        XCTAssertEqual(value.track.count,1); XCTAssertTrue(RoamRouteSketch(track:value.track,places:[]).track.isEmpty)
    }
    func testSafeCountersRejectNumericOverflowAndNonIntegerWithoutLosingLongID() throws {
        for bad in ["-1","9007199254740992","1.5","true","\"1\""] {
            XCTAssertThrowsError(try RoamPassportHistoryContract.record(Data("{\"sessionId\":\"1\",\"shops\":\(bad)}".utf8),sessionID:"1"))
        }
    }
    func testServerSummaryIsNotCalculatedFromLocalOrLoadedPages() throws {
        let value = try JSONDecoder().decode(RoamPassportServerSummary.self,from:Data(#"{"trips":100,"distanceM":null,"days":null,"shops":0}"#.utf8))
        XCTAssertEqual(value.trips,100); XCTAssertEqual(value.shops,0); XCTAssertNil(value.distanceM); XCTAssertNil(value.days)
    }
}
