import XCTest
@testable import QuestifyCore

final class MemberTemplateReviewFeedbackTests: XCTestCase {
    func testOwnDetailKeepsDecodedReviewFeedbackButNotAnswers() throws {
        let json = #"{"id":901,"title":"Owned","draftStatus":0,"reason":" Replace the photo &amp; retry ","questionAnswer":"A"}"#
        let detail = try JSONDecoder().decode(MemberTemplateDetail.self, from: Data(json.utf8))
        XCTAssertEqual(detail.reviewFeedback, "Replace the photo & retry")
        XCTAssertFalse(String(describing: detail).contains("questionAnswer"))
        let none = try JSONDecoder().decode(MemberTemplateDetail.self, from: Data(#"{"id":901,"reason":"  "}"#.utf8))
        XCTAssertNil(none.reviewFeedback)
    }
}
