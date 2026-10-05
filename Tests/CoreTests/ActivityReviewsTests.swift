import XCTest
@testable import QuestifyCore

final class ActivityReviewsTests: XCTestCase {
    private func decode(_ fields: String = "") throws -> ActivityReviews {
        try JSONDecoder().decode(ActivityDetail.self, from: Data("{\"id\":17,\"name\":\"Fixture\"\(fields)}".utf8)).reviews
    }

    func testReadsServerScoreAndTotalSeparatelyFromPreview() throws {
        let reviews = try decode(#", "averageRating":4.2,"commentCount":12,"commentList":[{"id":99,"memberId":32,"memberNickname":"Player","createTime":"2030-01-02 10:00","rating":4,"contents":"A good walk."},{"rating":5,"contents":"Another view."}]"#)
        XCTAssertEqual(reviews.averageRating, 4.2)
        XCTAssertEqual(reviews.commentCount, 12)
        XCTAssertEqual(reviews.preview.count, 2)
        XCTAssertEqual(reviews.preview[0].authorName, "Player")
        XCTAssertEqual(reviews.preview[0].createTime, "2030-01-02 10:00")
        XCTAssertEqual(reviews.preview[0].rating, 4)
        XCTAssertEqual(reviews.preview[0].contents, "A good walk.")
        XCTAssertFalse(reviews.hasConfirmedNoReviews)
    }

    func testMissingAndNullMetadataStayUnknown() throws {
        for fields in ["", #", "averageRating":null,"commentCount":null,"commentList":null"#] {
            let reviews = try decode(fields)
            XCTAssertNil(reviews.averageRating)
            XCTAssertNil(reviews.commentCount)
            XCTAssertTrue(reviews.preview.isEmpty)
            XCTAssertFalse(reviews.hasConfirmedNoReviews)
        }
        let reviews = try decode(#", "commentList":[{"rating":5}]"#)
        XCTAssertNil(reviews.commentCount, "A preview never establishes a total")
        XCTAssertNil(reviews.averageRating, "A preview never establishes the server average")
    }

    func testKnownZeroIsDistinctFromAnUnavailablePreview() throws {
        let empty = try decode(#", "averageRating":0,"commentCount":0"#)
        XCTAssertEqual(empty.averageRating, 0)
        XCTAssertEqual(empty.commentCount, 0)
        XCTAssertTrue(empty.hasConfirmedNoReviews)
        XCTAssertFalse(try decode(#", "commentCount":7,"commentList":[]"#).hasConfirmedNoReviews)
        XCTAssertFalse(try decode(#", "commentCount":0,"commentList":[{"contents":"Present row"}]"#).hasConfirmedNoReviews)
    }

    func testRatingsAndCountsAreValidatedWithoutCoercionOrClamping() throws {
        for raw in ["0", "2.5", "5"] {
            XCTAssertNotNil(try decode(",\"averageRating\":\(raw)").averageRating)
        }
        for raw in ["-1", "5.1", "true", "\"4\"", "{}", "[]"] {
            XCTAssertNil(try decode(",\"averageRating\":\(raw)").averageRating)
        }
        for raw in ["0", "12"] {
            XCTAssertNotNil(try decode(",\"commentCount\":\(raw)").commentCount)
        }
        for raw in ["-1", "1.5", "true", "\"12\"", "{}", "[]"] {
            XCTAssertNil(try decode(",\"commentCount\":\(raw)").commentCount)
        }
        for raw in ["0", "1", "5"] {
            XCTAssertNotNil(try decode(",\"commentList\":[{\"rating\":\(raw)}]").preview[0].rating)
        }
        for raw in ["null", "-1", "6", "3.5", "true", "\"4\"", "{}", "[]"] {
            XCTAssertNil(try decode(",\"commentList\":[{\"rating\":\(raw)}]").preview[0].rating)
        }
    }

    func testMalformedListsAndRowsCannotBecomeEmptySuccess() {
        for raw in ["{}", "true", "1", "\"bad\"", "[null]", "[1]", "[[]]"] {
            XCTAssertThrowsError(try decode(",\"commentList\":\(raw)"))
        }
        for key in ["memberNickname", "createTime", "contents"] {
            XCTAssertThrowsError(try decode(",\"commentList\":[{\"\(key)\":42}]"))
        }
    }

    func testPreviewIsBoundedToFiveRowsWithoutDeduplicatingUnnamedReviews() throws {
        let row = #"{"contents":"Same text"}"#
        let five = Array(repeating: row, count: 5).joined(separator: ",")
        XCTAssertEqual(try decode(",\"commentList\":[\(five)]").preview.count, 5)
        XCTAssertThrowsError(try decode(",\"commentList\":[\(five),\(row)]"))
    }

    func testBlankDisplayFieldsStayUnavailableAndRealTextIsPreserved() throws {
        let review = try decode(#", "commentList":[{"memberNickname":"  ","createTime":"\n","contents":""},{"contents":"  **literal**\nSecond line  "}]"#).preview
        XCTAssertNil(review[0].authorName)
        XCTAssertNil(review[0].createTime)
        XCTAssertNil(review[0].contents)
        XCTAssertNil(review[0].rating)
        XCTAssertEqual(review[1].contents, "  **literal**\nSecond line  ")
    }

    func testClubGateNeverDecodesHiddenReviews() throws {
        let access = try JSONDecoder().decode(ActivityDetailAccess.self, from: Data(#"{"gate":true,"clubId":9,"averageRating":5,"commentCount":100,"commentList":"hidden"}"#.utf8))
        XCTAssertEqual(access, .clubRequired(clubID: 9, message: nil))
    }
}
