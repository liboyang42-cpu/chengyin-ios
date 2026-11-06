import XCTest
@testable import Questify

final class SocialCommentLengthTests: XCTestCase {
    private func blocked(_ text: String) -> Bool {
        SocialCommentLength.isTooLong(text, purpose: .comment, generation: .communityV1)
    }
    private func validate(_ text: String) throws {
        let target = SocialActionTarget.post(701)
        let snapshot = try SocialActionSnapshot(target: target, post: SquareReportFixtures.post())
        try SocialActionCommand.communityComment(text: text, requestID: "synthetic-request-1")
            .validate(target: target, snapshot: snapshot, identity: .init(accountID: 81, epoch: 1))
    }
    func testExactBoundaryMatchesRealCommentContract() throws {
        let accepted = String(repeating: "文", count: 2000)
        XCTAssertFalse(blocked(accepted))
        XCTAssertNoThrow(try validate(accepted))
        let oversized = accepted + "字"
        XCTAssertTrue(blocked(oversized))
        XCTAssertThrowsError(try validate(oversized))
        XCTAssertEqual(oversized.utf16.count, 2001)
    }
    func testEmojiCountsUTF16RatherThanVisibleCharacters() throws {
        let accepted = String(repeating: "🙂", count: 1000)
        XCTAssertEqual(accepted.count, 1000)
        XCTAssertFalse(blocked(accepted))
        XCTAssertNoThrow(try validate(accepted))
        let oversized = accepted + "🙂"
        XCTAssertTrue(blocked(oversized))
        XCTAssertThrowsError(try validate(oversized))
    }
    func testWhitespaceIsNotTrimmedToBypassTheCoreLengthLimit() {
        let text = "x" + String(repeating: " ", count: 2000)
        XCTAssertTrue(blocked(text))
        XCTAssertThrowsError(try validate(text))
        XCTAssertEqual(text.last, " ")
        XCTAssertFalse(blocked(" \n"), "The existing nonempty gate remains separate")
        XCTAssertThrowsError(try validate(" \n"))
    }
    func testShorteningRecoversWithoutChangingDraftBytes() throws {
        let original = String(repeating: "e\u{301}", count: 1001)
        XCTAssertTrue(blocked(original))
        let edited = String(original.dropLast())
        XCTAssertFalse(blocked(edited))
        XCTAssertNoThrow(try validate(edited))
        XCTAssertEqual(original.utf16.count, 2002, "Preflight must not truncate or normalize the draft")
    }
    func testLegacyCommentsAndOtherPurposesKeepTheirExistingContracts() {
        let text = String(repeating: "x", count: 2001)
        XCTAssertNil(SocialCommentLength.limit(purpose: .comment, generation: .legacySquare))
        XCTAssertFalse(SocialCommentLength.isTooLong(text, purpose: .comment, generation: .legacySquare))
        for purpose in [SocialEditorPurpose.createPost, .editPost, .like, .bookmark, .commentLike, .report, .toggleFollow, .startChat] {
            XCTAssertNil(SocialCommentLength.limit(purpose: purpose, generation: .communityV1))
            XCTAssertFalse(SocialCommentLength.isTooLong(text, purpose: purpose, generation: .communityV1))
        }
    }
}
