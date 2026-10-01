import XCTest
@testable import QuestifyCore

final class ActivityContractTests: XCTestCase {
    func decode(_ json:String) throws -> ActivitySummary {
        try JSONDecoder().decode(ActivitySummary.self,from:Data(json.utf8))
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
}
