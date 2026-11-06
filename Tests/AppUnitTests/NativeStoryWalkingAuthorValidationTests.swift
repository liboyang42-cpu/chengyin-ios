import Foundation
import XCTest
@testable import Questify

@MainActor final class NativeStoryWalkingAuthorValidationTests: XCTestCase {
    private func original() -> ProjectEditDraft {
        var value = ProjectEditSyntheticFixtures.draft()
        value.chapters[0].nodes[0].localMetadata["id"] = .number(31)
        value.preserved.removeValue(forKey: "themeRuntimeConfig")
        return value
    }
    private func node() -> NativeStoryWalkingAuthorDraft.Node {
        var value = NativeStoryWalkingAuthorDraft.Node(id: 31)
        value.region = "CN"
        return value
    }
    private func entrance() -> NativeStoryWalkingAuthorDraft.Entrance {
        var value = NativeStoryWalkingAuthorDraft.Entrance()
        value.label = "Main entrance"; value.source = "Author-provided source"
        value.longitude = "120"; value.latitude = "30"; value.datum = "WGS84"; value.closed = false
        return value
    }
    func testNewEntranceExplainsRequiredFieldsWithoutSupplyingValues() throws {
        var node = node(); node.entrance = .init()
        let before = node
        XCTAssertEqual(NativeStoryWalkingAuthorValidation.issues(node), [.label, .source, .longitude, .latitude, .datum, .closed])
        XCTAssertEqual(node, before)
    }
    func testValidRepairUsesOriginalAcceptanceAndDoesNotWrite() throws {
        let original = original(), bytes = ProjectEditPendingMaterials.exactData(original)
        var editor = try NativeStoryWalkingAuthorDraft(draft: original)
        editor.ttl = "60"; var node = node(); node.entrance = entrance(); editor.nodes = [node]
        let check = NativeStoryWalkingAuthorValidation(editor, original: original)
        XCTAssertTrue(check.canApply); XCTAssertTrue(check.global.isEmpty); XCTAssertEqual(check.nodes[31], [])
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(original), bytes)
        XCTAssertNoThrow(try editor.applying(to: original))
    }
    func testTTLUsesCanonicalOriginalIntegerContract() throws {
        let original = original()
        for text in ["", "0", "301", "01", " 60", "1.0"] {
            var editor = try NativeStoryWalkingAuthorDraft(draft: original); editor.ttl = text
            let result = NativeStoryWalkingAuthorValidation(editor, original: original)
            XCTAssertTrue(result.global.contains(.ttl), text); XCTAssertFalse(result.canApply, text)
        }
    }
    func testNonfiniteOutOfRangeCoordinatesAndExplicitDatumAreRequired() {
        var node = node(); var entrance = entrance()
        entrance.longitude = "nan"; entrance.latitude = "91"; entrance.datum = "unknown"; entrance.closed = nil; node.entrance = entrance
        XCTAssertEqual(NativeStoryWalkingAuthorValidation.issues(node), [.longitude, .latitude, .datum, .closed])
        entrance.longitude = "-180"; entrance.latitude = "90"; entrance.datum = "BD09"; entrance.closed = true; node.entrance = entrance
        XCTAssertEqual(NativeStoryWalkingAuthorValidation.issues(node), [])
    }
    func testUTF16BoundsNullAndRegionHaveSpecificErrors() {
        var node = node(); var entrance = entrance()
        node.region = "cn"; entrance.label = String(repeating: "😀", count: 151); entrance.floor = "\0"
        node.entrance = entrance
        XCTAssertEqual(NativeStoryWalkingAuthorValidation.issues(node), [.region, .label, .floor])
    }
    func testLegacyViewOnlyAndUndeclaredEntranceRemainAllowed() throws {
        let original = original()
        var editor = try NativeStoryWalkingAuthorDraft(draft: original)
        editor.schema = 1; editor.ttl = ""
        let legacy = NativeStoryWalkingAuthorValidation(editor, original: original)
        XCTAssertTrue(legacy.canApply); XCTAssertTrue(legacy.global.isEmpty)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try editor.applying(to: original)), ProjectEditPendingMaterials.exactData(original))
        editor.schema = 2; editor.ttl = "1"; editor.nodes = [node()]
        XCTAssertTrue(NativeStoryWalkingAuthorValidation(editor, original: original).canApply)
        XCTAssertNil(editor.nodes[0].entrance)
    }
    func testMissingNodeAndChangedOriginalStayRejected() throws {
        let original = original()
        var editor = try NativeStoryWalkingAuthorDraft(draft: original); editor.ttl = "10"
        var missing = NativeStoryWalkingAuthorDraft.Node(id: 999); missing.region = "CN"; editor.nodes = [missing]
        let check = NativeStoryWalkingAuthorValidation(editor, original: original)
        XCTAssertEqual(check.nodes[999], [.nodeIdentity]); XCTAssertFalse(check.canApply)
        editor.nodes = [node()]
        var changed = original; changed.preserved["unrelated"] = .string("new")
        let stale = NativeStoryWalkingAuthorValidation(editor, original: changed)
        XCTAssertFalse(stale.canApply); XCTAssertTrue(stale.global.contains(.originalContract))
    }
}
