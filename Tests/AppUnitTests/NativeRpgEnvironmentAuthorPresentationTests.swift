import Foundation
import XCTest
@testable import Questify

final class NativeRpgEnvironmentAuthorPresentationTests: XCTestCase {
    private let en = NativeRpgEnvironmentAuthorPresentation(locale: Locale(identifier: "en"))
    private let zh = NativeRpgEnvironmentAuthorPresentation(locale: Locale(identifier: "zh-Hans"))
    func testKnownStatesHaveBothPackagedLanguages() {
        for (source, key) in NativeRpgEnvironmentAuthorPresentation.keys {
            XCTAssertEqual(zh.message(source), source)
            XCTAssertNotEqual(en.message(source), source)
            XCTAssertNotEqual(en.message(source), key)
        }
    }
    func testUnsupportedCapabilitiesRemainExplicit() {
        let boundary = en.text("rpgEnvironment.copy.014")
        XCTAssertTrue(boundary.contains("not connected"))
        XCTAssertTrue(boundary.contains("neither live observations nor location authorization"))
        XCTAssertTrue(en.text("rpgEnvironment.copy.013").contains("remain unknown without a source"))
        XCTAssertTrue(en.text("rpgEnvironment.copy.013").contains("Do not enter player coordinates or credentials"))
    }
    func testLocalSaveFailureRetainsEditsWithoutClaimingPublication() {
        let failure = en.text("rpgEnvironment.copy.003")
        XCTAssertTrue(failure.contains("edits and preview are retained"))
        XCTAssertTrue(failure.contains("Nothing has been saved to the server or published"))
        XCTAssertTrue(en.text("rpgEnvironment.localOnly").contains("only the local draft"))
    }
    func testAllEightOriginalSwitchCombinationsStayUnchangedByDisplay() throws {
        for enabled in [false, true] {
            for authorOverrides in [false, true] {
                for location in [false, true] {
                    let raw = "{\"schemaVersion\":2,\"env\":{\"enabled\":\(enabled),\"authorOverride\":\(authorOverrides)},\"location\":{\"enabled\":\(location)}}"
                    let draft = try NativeRpgEnvironmentAuthorDraft(original: .string(raw))
                    let before = draft
                    for copy in [en, zh] { _ = copy.text("rpgEnvironment.copy.009"); _ = copy.text("rpgEnvironment.copy.010"); _ = copy.text("rpgEnvironment.copy.011") }
                    XCTAssertEqual(draft, before)
                    XCTAssertEqual(draft.enabled, enabled)
                    XCTAssertEqual(draft.authorOverride, authorOverrides)
                    XCTAssertEqual(draft.locationEnabled, location)
                    var original = ProjectEditDraft(); original.preserved["journeyRules"] = .string(raw)
                    let result = try draft.applying(to: original)
                    XCTAssertEqual(Array(try XCTUnwrap(result.preserved["journeyRules"]?.text).utf8), Array(raw.utf8))
                }
            }
        }
    }
    func testUnknownDetailsAndLanguageSwitchRemainLiteral() {
        let raw = "future_%@ e\u{301}"
        XCTAssertEqual(Array(en.message(raw).utf8), Array(raw.utf8))
        XCTAssertEqual(Array(zh.message(raw).utf8), Array(raw.utf8))
        XCTAssertEqual(en.text("rpgEnvironment.copy.018"), "Close without saving")
        XCTAssertEqual(zh.text("rpgEnvironment.copy.018"), "关闭环境编辑副本")
    }
}
