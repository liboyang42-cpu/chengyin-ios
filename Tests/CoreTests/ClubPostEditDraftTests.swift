import XCTest
@testable import QuestifyCore

final class ClubPostEditDraftTests: XCTestCase {
    private func draft(_ text: String, _ images: [String] = []) -> ClubPostEditDraft { .init(content: text, images: images) }
    func testExactOriginalIsClean() { XCTAssertEqual(draft("hello", ["a"]), draft("hello", ["a"])) }
    func testTextChangeIsDirty() { XCTAssertNotEqual(draft("hello"), draft("changed")) }
    func testWhitespaceIsNotTrimmed() { XCTAssertNotEqual(draft(" hello "), draft("hello")) }
    func testLineBreakChangeIsDirty() { XCTAssertNotEqual(draft("a\nb"), draft("a\r\nb")) }
    func testCanonicallyEquivalentTextBytesStillDiffer() { XCTAssertNotEqual(draft("\u{00E9}"), draft("e\u{0301}")) }
    func testImageOrderMatters() { XCTAssertNotEqual(draft("", ["a", "b"]), draft("", ["b", "a"])) }
    func testDuplicateImageRemovalMatters() { XCTAssertNotEqual(draft("", ["a", "a"]), draft("", ["a"])) }
    func testImageBytesMatter() { XCTAssertNotEqual(draft("", ["\u{00E9}"]), draft("", ["e\u{0301}"])) }
    func testReturningToOriginalIsClean() { var current = draft("new"); current = draft("old"); XCTAssertEqual(current, draft("old")) }
    func testEmptyDraftAndEmptyImageReferenceDiffer() { XCTAssertNotEqual(draft(""), draft("", [""])) }
}
