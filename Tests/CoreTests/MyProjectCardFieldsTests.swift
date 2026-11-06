import XCTest
@testable import QuestifyCore

/// Mini myproject card lines that come straight from `api/project/my` row fields.
final class MyProjectCardFieldsTests: XCTestCase {
    private func project(_ json: String) throws -> CreatorContentProject {
        try JSONDecoder().decode(CreatorContentProject.self, from: Data(json.utf8))
    }

    func testAddressIsTrimmedAndBlankHidesLine() throws {
        XCTAssertEqual(try project(#"{"id":1,"bizType":"topic","addressName":"  West Lake  "}"#).addressName, "West Lake")
        XCTAssertNil(try project(#"{"id":1,"bizType":"topic","addressName":"   "}"#).addressName)
        XCTAssertNil(try project(#"{"id":1,"bizType":"topic"}"#).addressName)
        XCTAssertNil(try project(#"{"id":1,"bizType":"topic","addressName":7}"#).addressName)
    }

    func testPendingVerifyAbsentIsNotZero() throws {
        XCTAssertEqual(try project(#"{"id":2,"bizType":"activity","pendingVerifyCount":0}"#).pendingVerifyCount, 0)
        XCTAssertEqual(try project(#"{"id":2,"bizType":"activity","pendingVerifyCount":3}"#).pendingVerifyCount, 3)
        XCTAssertNil(try project(#"{"id":2,"bizType":"activity"}"#).pendingVerifyCount)
        XCTAssertNil(try project(#"{"id":2,"bizType":"activity","pendingVerifyCount":"x"}"#).pendingVerifyCount)
    }

    func testAcceptanceTextOnlyForNonSelfRunTopics() throws {
        XCTAssertEqual(MyProjectListPresentation.acceptanceText(try project(#"{"id":3,"bizType":"topic","acceptStatus":"clubOpen","acceptStatusText":"等待承接"}"#)), "等待承接")
        XCTAssertNil(MyProjectListPresentation.acceptanceText(try project(#"{"id":3,"bizType":"topic","acceptStatus":"selfRun","acceptStatusText":"自办"}"#)))
        XCTAssertNil(MyProjectListPresentation.acceptanceText(try project(#"{"id":3,"bizType":"activity","acceptStatus":"clubOpen","acceptStatusText":"x"}"#)))
        XCTAssertNil(MyProjectListPresentation.acceptanceText(try project(#"{"id":3,"bizType":"topic","acceptStatus":"clubOpen"}"#)))
    }
}
