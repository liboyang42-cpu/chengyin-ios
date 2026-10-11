import XCTest
@testable import QuestifyCore

final class TemplateStoryImageRemovalTests: XCTestCase {
    func testRemovesOnlySelectedDuplicateOccurrence() {
        let images = ["same", "middle", "same"]
        XCTAssertEqual(TemplateStoryImageRemoval(index: 2, images: images).applying(to: images), ["same", "middle"])
    }
    func testRejectsInvalidIndexesAndChangedSnapshot() {
        let images = ["a", "b"]
        for index in [-1, 2, Int.max] {
            XCTAssertNil(TemplateStoryImageRemoval(index: index, images: images).applying(to: images))
        }
        let action = TemplateStoryImageRemoval(index: 0, images: images)
        XCTAssertNil(action.applying(to: ["b"]))
        XCTAssertNil(action.applying(to: ["b", "a"]))
        XCTAssertNil(action.applying(to: ["a", "c"]))
    }
    func testExactUnicodeSnapshot() {
        let action = TemplateStoryImageRemoval(index: 0, images: ["é"])
        XCTAssertNil(action.applying(to: ["e\u{301}"]))
    }
    func testAllowsFinalImageAndOversizedHistoryReduction() {
        XCTAssertEqual(TemplateStoryImageRemoval(index: 0, images: ["a"]).applying(to: ["a"]), [])
        let images = (0..<9).map(String.init)
        XCTAssertEqual(TemplateStoryImageRemoval(index: 4, images: images).applying(to: images), ["0", "1", "2", "3", "5", "6", "7", "8"])
    }
    func testRetainsUntouchedReferenceBytes() throws {
        let images = ["  inert://first\n ", "remove", "e\u{301}"]
        let output = try XCTUnwrap(TemplateStoryImageRemoval(index: 1, images: images).applying(to: images))
        XCTAssertTrue(output[0].utf8.elementsEqual(images[0].utf8))
        XCTAssertTrue(output[1].utf8.elementsEqual(images[2].utf8))
    }
}
