import XCTest
@testable import QuestifyCore

final class MerchantDecorTagDraftTests: XCTestCase {
    func testSourceLibraryHasThreeDistinctGroupsAndEighteenValues() {
        XCTAssertEqual(MerchantDecorTagDraft.groups.map(\.key), ["space", "experience", "audience"])
        XCTAssertEqual(MerchantDecorTagDraft.groups.flatMap(\.values).count, 18)
        XCTAssertEqual(Set(MerchantDecorTagDraft.groups.flatMap(\.values)).count, 18)
    }
    func testOpeningPreservesUnknownDuplicateAndOverLimitValues() {
        let source = ["future", "future"] + (0..<12).map { "custom-\($0)" }
        let draft = MerchantDecorTagDraft(selected: source)
        XCTAssertTrue(MerchantDecorTagDraft.equal(draft.selected, source)); XCTAssertFalse(draft.canApply)
    }
    func testThirteenthSelectionFailsWithoutChangingExistingOrder() throws {
        let source = (0..<12).map { "tag-\($0)" }; var draft = MerchantDecorTagDraft(selected: source)
        XCTAssertThrowsError(try draft.toggle("老街")); XCTAssertEqual(draft.selected, source)
        try draft.toggle("tag-2"); try draft.toggle("老街")
        XCTAssertEqual(draft.selected.last, "老街"); XCTAssertEqual(draft.selected.count, 12)
    }
    func testHistoricalOverLimitCanOnlyBeCorrectedByExplicitRemoval() {
        var draft = MerchantDecorTagDraft(selected: (0..<13).map { "tag-\($0)" })
        XCTAssertFalse(draft.canApply); draft.remove(at: 12); XCTAssertTrue(draft.canApply)
        XCTAssertEqual(draft.selected, (0..<12).map { "tag-\($0)" })
    }
    func testCustomDuplicateAtLimitDoesNotAppendOrReorder() throws {
        let source = (0..<12).map { "tag-\($0)" }; var draft = MerchantDecorTagDraft(selected: source)
        try draft.addCustom(" tag-3 "); XCTAssertEqual(draft.selected, source)
        XCTAssertThrowsError(try draft.addCustom("new")); XCTAssertEqual(draft.selected, source)
    }
    func testCustomEmptyAndLengthLimitNeverTruncateOrAppend() throws {
        var draft = MerchantDecorTagDraft(selected: [])
        for bad in ["", " \n", String(repeating: "a", count: 17), String(repeating: "😀", count: 9)] {
            XCTAssertThrowsError(try draft.addCustom(bad)); XCTAssertTrue(draft.selected.isEmpty)
        }
        try draft.addCustom(String(repeating: "a", count: 16)); XCTAssertEqual(draft.selected.count, 1)
    }
    func testSourceTrimAndLiteralComparisonDoNotNormalizeCustomLabels() throws {
        var draft = MerchantDecorTagDraft(selected: [])
        try draft.addCustom("\u{FEFF}Cafe\u{FEFF}"); XCTAssertEqual(draft.selected, ["Cafe"])
        try draft.addCustom("\u{0085}X\u{0085}"); XCTAssertTrue(draft.contains("\u{0085}X\u{0085}"))
        try draft.addCustom("é"); try draft.addCustom("e\u{0301}")
        XCTAssertEqual(draft.selected.count, 4)
        XCTAssertFalse(MerchantDecorTagDraft.equal("é", "e\u{0301}"))
    }
    func testRemovingTagsCanExplicitlyClearAllAndKeepsOtherDuplicates() throws {
        var draft = MerchantDecorTagDraft(selected: ["legacy", "legacy"])
        try draft.toggle("legacy"); XCTAssertEqual(draft.selected, ["legacy"])
        draft.remove(at: 0); XCTAssertTrue(draft.selected.isEmpty); XCTAssertTrue(draft.canApply)
        draft.remove(at: 5); XCTAssertTrue(draft.selected.isEmpty)
    }
}
