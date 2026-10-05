import XCTest
@testable import QuestifyCore

final class TemplateMetadataCategorySelectionTests: XCTestCase {
    func testUntouchedUnknownWhitespaceNilAndEmptyCSVPreserveExactBytes() {
        for raw in [nil, "", " 99,4, 8 "] as [String?] {
            let selection = TemplateMetadataCategorySelection(raw: raw)
            XCTAssertTrue(selection.isSupported); XCTAssertFalse(selection.hasChanges)
            XCTAssertEqual(selection.savedValue, raw)
        }
        XCTAssertEqual(TemplateMetadataCategorySelection(raw: " 99,4, 8 ").selectedIDs, [99, 4, 8])
    }
    func testOrderedUnlimitedEditsRetainUnknownIDsAndOnlySaveExplicitChanges() {
        var selection = TemplateMetadataCategorySelection(raw: " 99,4, 8 ")
        for id in 101...120 { selection.toggle(id) }
        XCTAssertEqual(selection.selectedIDs, [99, 4, 8] + Array(101...120))
        XCTAssertEqual(selection.savedValue, ([99, 4, 8] + Array(101...120)).map(String.init).joined(separator: ","))
        for id in 101...120 { selection.toggle(id) }
        XCTAssertFalse(selection.hasChanges); XCTAssertEqual(selection.savedValue, " 99,4, 8 ")
        selection.toggle(4); selection.toggle(4)
        XCTAssertEqual(selection.selectedIDs, [99, 8, 4]); XCTAssertEqual(selection.savedValue, "99,8,4")
    }
    func testMalformedDuplicateOverflowAndAlternateIDsRemainRawUntilReplacement() {
        for raw in ["4,4", "4,", ",4", " ", "4x,2", "0", "-2", "01", "+2", "999999999999999999999999", "４"] {
            var selection = TemplateMetadataCategorySelection(raw: raw)
            XCTAssertFalse(selection.isSupported, raw); XCTAssertEqual(selection.savedValue, raw)
            selection.toggle(12); XCTAssertEqual(selection.savedValue, raw)
            selection.replaceUnsupportedSelection(); XCTAssertTrue(selection.isSupported)
            XCTAssertEqual(selection.savedValue, ""); selection.toggle(12); XCTAssertEqual(selection.savedValue, "12")
        }
    }
}
