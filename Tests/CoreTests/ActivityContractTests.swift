import XCTest
@testable import QuestifyCore

final class ActivityContractTests: XCTestCase {
    func decode(_ json:String) throws -> ActivitySummary {
        try JSONDecoder().decode(ActivitySummary.self,from:Data(json.utf8))
    }
    func testLinkedTopicRequiresPositiveSafeIdentifier() throws {
        for raw in ["7", "\"7\"", "9007199254740991"] {
            XCTAssertNotNil(try decode("{\"id\":1,\"name\":\"A\",\"topicId\":\(raw)}").linkedTopicID)
        }
        for raw in ["null", "0", "-1", "1.5", "true", "{}", "[]", "\"bad\"", "\"7?token=x\"", "9007199254740992"] {
            XCTAssertNil(try decode("{\"id\":1,\"name\":\"A\",\"topicId\":\(raw)}").linkedTopicID)
        }
        XCTAssertNil(try decode(#"{"id":1,"name":"A"}"#).linkedTopicID)
    }
    func testClubGateDoesNotDecodeHiddenTopicLink() throws {
        let gate = try JSONDecoder().decode(ActivityDetailAccess.self, from: Data(#"{"gate":true,"clubId":9,"topicId":7}"#.utf8))
        XCTAssertEqual(gate, .clubRequired(clubID:9, message:nil))
    }
    func testMissingPriceIsNotFree() throws {
        let item=try decode(#"{"id":1,"name":"A"}"#)
        XCTAssertNil(item.minimumAmount);XCTAssertFalse(item.hasZeroStartingPrice)
    }
    func testWirePriceTypoAndDecimalPrecision() throws {
        let item=try decode(#"{"id":1,"name":"A","minAmout":19.99}"#)
        XCTAssertEqual(item.minimumAmount,Decimal(string:"19.99"))
    }
    func testWrongPriceFieldDoesNotInventValue() throws {
        let item=try decode(#"{"id":1,"name":"A","minAmount":0}"#)
        XCTAssertNil(item.minimumAmount)
    }
    func testZeroStartingPriceIsExplicit() throws {
        XCTAssertTrue(try decode(#"{"id":1,"name":"A","minAmout":0}"#).hasZeroStartingPrice)
    }
    func testCoordinatesAreOptionalAndRangeChecked() throws {
        XCTAssertFalse(try decode(#"{"id":1,"name":"A"}"#).hasValidCoordinates)
        XCTAssertFalse(try decode(#"{"id":1,"name":"A","latitude":95,"longitude":0}"#).hasValidCoordinates)
        XCTAssertTrue(try decode(#"{"id":1,"name":"A","latitude":"40.7","longitude":"-74.0"}"#).hasValidCoordinates)
    }
    func testDislikedIsDistinctFromNoInteraction() throws {
        XCTAssertEqual(try decode(#"{"id":1,"name":"A","isLiked":2}"#).likeState,.disliked)
        XCTAssertEqual(try decode(#"{"id":1,"name":"A","isLiked":99}"#).likeState,.none)
    }
    func testBothProductTypesRemainRepresentable() throws {
        for type in [1,2] { XCTAssertEqual(try decode("{\"id\":1,\"name\":\"A\",\"productType\":\(type)}").productType,type) }
    }
    func testInvalidIDIsRejected() { XCTAssertThrowsError(try decode(#"{"id":0,"name":"A"}"#)) }
    func testNestedAndRootListEnvelopes() throws {
        for json in [#"{"code":200,"data":{"rows":[{"id":1,"name":"A"}]}}"#, #"{"code":200,"rows":[{"id":1,"name":"A"}]}"#] {
            let response=try JSONDecoder().decode(ActivityListResponse.self,from:Data(json.utf8))
            XCTAssertEqual(response.rows.count,1)
        }
    }
    func testBusinessErrorAndMissingRowsAreNotEmptySuccess() {
        for json in [#"{"code":500}"#, #"{"code":200}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(ActivityListResponse.self,from:Data(json.utf8)))
        }
    }
    func testDetailPrimaryActionMirrorsSourceSignUpAndCancellationStates() throws {
        func detail(_ fields: String) throws -> ActivityDetail {
            try JSONDecoder().decode(ActivityDetail.self, from: Data((#"{"id":1,"name":"A""# + fields + "}").utf8))
        }
        let now = try XCTUnwrap(ActivityPrimaryAction.chinaDate("2026-10-19 12:00:00"))
        XCTAssertEqual(try detail("").primaryAction(now: now), .signUp)
        XCTAssertEqual(try detail(#","isSignUp":0"#).primaryAction(now: now), .signUp)
        XCTAssertNil(try detail(#","isSignUp":2"#).signUpFlag)
        XCTAssertNil(try detail(#","isSignUp":"1""#).signUpFlag)
        XCTAssertEqual(try detail(#","isSignUp":1,"startDate":"2026-10-20 09:00:00","endDate":"2026-10-21""#).primaryAction(now: now), .viewRegistration)
        XCTAssertEqual(try detail(#","isSignUp":1,"startDate":"2026-10-18 09:00:00","endDate":"2026-10-19""#).primaryAction(now: now), .continueExploring)
        XCTAssertEqual(try detail(#","isSignUp":1,"startDate":"2026-10-10 09:00:00","endDate":"2026-10-18 20:00:00""#).primaryAction(now: now), .viewTrace)
        XCTAssertEqual(try detail(#","isSignUp":1"#).primaryAction(now: now), .continueExploring)
        let cancelled = try detail(#","isSignUp":1,"cancelTime":"2026-10-18 10:00:00","cancelReason":"  Weather  ""#)
        XCTAssertEqual(cancelled.primaryAction(now: now), .cancelled); XCTAssertEqual(cancelled.cancelReason, "Weather")
        XCTAssertTrue(try detail(#","cancelTime":1760000000000"#).isCancelled)
        XCTAssertFalse(try detail(#","cancelTime":"  ","cancelReason":"x""#).isCancelled)
        XCTAssertEqual(ActivityPrimaryAction.signUp.titleKey, "activity.cta.signUp")
        XCTAssertEqual(ActivityPrimaryAction.cancelled.titleKey, "activity.cta.cancelled")
    }
}
