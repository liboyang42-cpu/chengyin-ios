import XCTest
@testable import QuestifyCore

final class PlayQATextInputTests: XCTestCase {
    private let revision = "synthetic-reader:1:701:2"
    private func edit(_ input: inout PlayQATextInput, _ value: String) {
        XCTAssertTrue(input.update(value, current: revision, mountID: input.mountID))
    }
    func testOverlongPasteIsRetainedAndCannotProduceReviewInput() {
        var input = PlayQATextInput(); input.mount(revision: revision)
        let original = String(repeating: "a", count: 4096) + "important suffix"
        edit(&input, original)
        XCTAssertEqual(Array(input.text(current: revision, mountID: input.mountID).utf8), Array(original.utf8))
        XCTAssertTrue(input.isOverLimit(current: revision, mountID: input.mountID))
        XCTAssertNil(input.reviewInput(current: revision, mountID: input.mountID))
    }
    func testPlayerMustExplicitlyShortenTheAnswerBeforeReview() {
        var input = PlayQATextInput(); input.mount(revision: revision)
        edit(&input, String(repeating: "a", count: 4097))
        XCTAssertNil(input.reviewInput(current: revision, mountID: input.mountID))
        let corrected = String(repeating: "b", count: 4096)
        edit(&input, corrected)
        XCTAssertEqual(input.reviewInput(current: revision, mountID: input.mountID), corrected)
        XCTAssertFalse(input.isOverLimit(current: revision, mountID: input.mountID))
    }
    func testUTF16BoundaryDoesNotSplitEmojiOrCanonicalCombiningCharacters() {
        var input = PlayQATextInput(); input.mount(revision: revision)
        let boundary = String(repeating: "😀", count: 2048)
        edit(&input, boundary)
        XCTAssertEqual(input.reviewInput(current: revision, mountID: input.mountID), boundary)
        let beyond = boundary + "e\u{301}"
        edit(&input, beyond)
        XCTAssertEqual(Array(input.text(current: revision, mountID: input.mountID).utf8), Array(beyond.utf8))
        XCTAssertNil(input.reviewInput(current: revision, mountID: input.mountID))
    }
    func testReviewPreservesExactWhitespaceWidthCaseAndUnicodeBytes() {
        var input = PlayQATextInput(); input.mount(revision: revision)
        let original = "  e\u{301}Ａb\n"
        edit(&input, original)
        XCTAssertEqual(Array(input.reviewInput(current: revision, mountID: input.mountID)!.utf8), Array(original.utf8))
    }
    func testEmptyAndWhitespaceCannotBeReviewedButIMEInputIsNotRewritten() {
        var input = PlayQATextInput(); input.mount(revision: revision)
        for blank in ["", " ", "\n\t", "　"] {
            edit(&input, blank)
            XCTAssertNil(input.reviewInput(current: revision, mountID: input.mountID))
        }
        for composition in ["n", "ni", "你"] {
            edit(&input, composition)
            XCTAssertEqual(input.text(current: revision, mountID: input.mountID), composition)
        }
    }
    func testFrozenReviewSnapshotCannotAcquireLaterEditedAnswer() {
        var input = PlayQATextInput(); input.mount(revision: revision); edit(&input, "first answer")
        let frozen = input.reviewInput(current: revision, mountID: input.mountID)
        edit(&input, "second answer")
        XCTAssertEqual(frozen, "first answer")
        XCTAssertEqual(input.reviewInput(current: revision, mountID: input.mountID), "second answer")
    }
    func testChangedOrMissingOwnerReadRevisionRejectsReadEditAndReview() {
        var input = PlayQATextInput(); input.mount(revision: revision); edit(&input, "private draft")
        for current in [nil, "different-owner:1:701:2", "synthetic-reader:1:701:3"] {
            XCTAssertEqual(input.text(current: current, mountID: input.mountID), "")
            XCTAssertFalse(input.update("late edit", current: current, mountID: input.mountID))
            XCTAssertNil(input.reviewInput(current: current, mountID: input.mountID))
        }
    }
    func testScopeEqualityRequiresExactUTF8Bytes() {
        var input = PlayQATextInput(); input.mount(revision: "e\u{301}")
        XCTAssertTrue(input.update("private", current: "e\u{301}", mountID: input.mountID))
        XCTAssertEqual(input.text(current: "é", mountID: input.mountID), "")
        XCTAssertNil(input.reviewInput(current: "é", mountID: input.mountID))
    }
    func testRetiredTextBindingCannotWriteAfterSameRevisionRemount() {
        var input = PlayQATextInput(); input.mount(revision: revision); edit(&input, "old")
        let oldMount = input.mountID
        input.clear(); input.mount(revision: revision)
        XCTAssertFalse(input.update("late", current: revision, mountID: oldMount))
        XCTAssertEqual(input.text(current: revision, mountID: oldMount), "")
        XCTAssertNil(input.reviewInput(current: revision, mountID: oldMount))
        XCTAssertEqual(input.text(current: revision, mountID: input.mountID), "")
    }
    func testClearingDoesNotInventRecoveredInputOrANewAction() {
        var input = PlayQATextInput(); input.mount(revision: revision); edit(&input, "unsent")
        input.clear()
        XCTAssertNil(input.reviewInput(current: revision, mountID: input.mountID))
        var reopened = PlayQATextInput(); reopened.mount(revision: revision)
        XCTAssertEqual(reopened.text(current: revision, mountID: reopened.mountID), "")
        XCTAssertNil(reopened.reviewInput(current: revision, mountID: reopened.mountID))
    }
}
