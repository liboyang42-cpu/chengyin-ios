import Foundation
import XCTest
@testable import Questify

final class NativeRpgResourceAuthorPresentationTests: XCTestCase {
    private let en = NativeRpgResourceAuthorPresentation(locale: Locale(identifier: "en"))
    private let zh = NativeRpgResourceAuthorPresentation(locale: Locale(identifier: "zh-Hans"))
    func testEveryKnownDiagnosticHasEnglishAndOriginalChinese() {
        for (source, key) in NativeRpgResourceAuthorPresentation.keys {
            XCTAssertEqual(zh.message(source), source)
            XCTAssertNotEqual(en.message(source), source)
            XCTAssertNotEqual(en.message(source), key)
        }
    }
    func testResourceNamesNeverChangeWireValues() {
        XCTAssertEqual(NativeRpgResourceAuthorDraft.names, ["hp", "morale", "luck", "inspiration"])
        XCTAssertEqual(en.resource("hp"), "Health")
        XCTAssertEqual(zh.resource("hp"), "生命值")
        XCTAssertEqual(en.resource("future_%@"), "future_%@")
    }
    func testUnknownDiagnosticBytesArePreserved() {
        let raw = "future_%@ e\u{301} 👩🏽‍💻"
        XCTAssertEqual(Array(en.message(raw).utf8), Array(raw.utf8))
        XCTAssertEqual(Array(zh.message(raw).utf8), Array(raw.utf8))
    }
    func testAllResourceValidationStatesKeepAuthorDraftUnchanged() throws {
        var original = ProjectEditDraft()
        original.preserved["journeyRules"] = .string("{\"schemaVersion\":2}")
        for name in NativeRpgResourceAuthorDraft.names {
            var draft = try NativeRpgResourceAuthorDraft(draft: original)
            draft.edit(name, "max", "9999")
            draft.edit(name, "init", "invalid")
            let before = draft
            XCTAssertFalse(draft.issues.isEmpty)
            for issue in draft.issues {
                XCTAssertNotEqual(en.message(issue), issue)
                XCTAssertEqual(zh.message(issue), issue)
            }
            XCTAssertEqual(draft, before)
            XCTAssertThrowsError(try draft.applying(to: original))
        }
    }
    func testOriginalReviewBytesAndOptionalFloorAreNotModifiedByDisplay() throws {
        var original = ProjectEditDraft()
        original.preserved["journeyRules"] = .string("{\"schemaVersion\":2,\"morale\":{\"enabled\":true,\"max\":10,\"init\":2}}")
        let draft = try NativeRpgResourceAuthorDraft(draft: original)
        XCTAssertEqual(draft.stageMoraleFloorText, "")
        for copy in [en, zh] { _ = copy.resource("morale"); _ = draft.issues.map(copy.message) }
        let applied = try draft.applying(to: original)
        XCTAssertEqual(Array(try XCTUnwrap(applied.preserved["journeyRules"]?.text).utf8), Array(try XCTUnwrap(original.preserved["journeyRules"]?.text).utf8))
        XCTAssertTrue(en.text("rpgResource.localOnly").contains("Does not save to the server"))
    }
}
