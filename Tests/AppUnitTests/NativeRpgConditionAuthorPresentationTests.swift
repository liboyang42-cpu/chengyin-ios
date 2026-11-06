import Foundation
import XCTest
@testable import Questify

final class NativeRpgConditionAuthorPresentationTests: XCTestCase {
    private let en = NativeRpgConditionAuthorPresentation(locale: Locale(identifier: "en"))
    private let zh = NativeRpgConditionAuthorPresentation(locale: Locale(identifier: "zh-Hans"))
    func testKnownStatesHaveBothPackagedLanguages() {
        for (source, key) in NativeRpgConditionAuthorPresentation.keys {
            XCTAssertEqual(zh.message(source), source)
            XCTAssertNotEqual(en.message(source), source)
            XCTAssertNotEqual(en.message(source), key)
        }
    }
    func testDurationsAndUnsupportedEffectsRemainExplicit() {
        let duration = en.text("rpgCondition.copy.011")
        XCTAssertTrue(duration.contains("3 nodes"))
        XCTAssertTrue(duration.contains("cold/heatstroke 4"))
        XCTAssertTrue(duration.contains("focus 1"))
        XCTAssertTrue(duration.contains("fear/excitement 2"))
        XCTAssertTrue(duration.contains("not on GET or re-entry"))
        XCTAssertTrue(en.text("rpgCondition.copy.015").contains("condition-effect editing is not connected"))
        XCTAssertTrue(en.text("rpgCondition.copy.015").contains("does not change player conditions or reset existing runs"))
    }
    func testBothOriginalSwitchStatesKeepExactReviewBytes() throws {
        for enabled in [false, true] {
            let raw = "{\"schemaVersion\":2,\"conditions\":{\"enabled\":\(enabled),\"maxActive\":5}}"
            let editor = try NativeRpgConditionAuthorDraft(original: .string(raw))
            let before = editor
            for copy in [en, zh] { _ = copy.text("rpgCondition.copy.009") }
            XCTAssertEqual(editor, before)
            XCTAssertEqual(editor.enabled, enabled)
            var original = ProjectEditDraft(); original.preserved["journeyRules"] = .string(raw)
            XCTAssertEqual(Array(try XCTUnwrap(editor.applying(to: original).preserved["journeyRules"]?.text).utf8), Array(raw.utf8))
        }
    }
    func testDisplayDoesNotSupplyMissingDeclarations() throws {
        let raw = "{\"schemaVersion\":2}"
        let editor = try NativeRpgConditionAuthorDraft(original: .string(raw))
        _ = en.text("rpgCondition.copy.010")
        XCTAssertNil(editor.rules["conditions"])
        var original = ProjectEditDraft(); original.preserved["journeyRules"] = .string(raw)
        XCTAssertThrowsError(try editor.applying(to: original))
    }
    func testUnknownDetailsAndLocalSaveBoundaryStayLiteral() {
        let unknown = "future_%@ e\u{301}"
        XCTAssertEqual(Array(en.message(unknown).utf8), Array(unknown.utf8))
        XCTAssertTrue(en.text("rpgCondition.copy.003").contains("edits and preview are retained"))
        XCTAssertTrue(en.text("rpgCondition.localOnly").contains("Does not save to the server"))
        XCTAssertEqual(zh.text("rpgCondition.copy.016"), "关闭状态编辑副本")
    }
}
