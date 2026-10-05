import XCTest
@testable import QuestifyCore

final class TemplateAuthoringRuleStepsTests: XCTestCase {
    func testReadProjectsLFAndTrimsWithoutRewritingHistoricalBytes() throws {
        let raw = " \r\n  First\t \r\n\u{FEFF} Second \u{00A0}\n\n"
        var editor = TemplateAuthoringRuleSteps(raw: raw)
        XCTAssertEqual(editor.rows.map(\.text), ["First", "Second"])
        XCTAssertEqual(editor.originalText, raw); XCTAssertEqual(editor.storedText, raw)
        try editor.update(id: editor.rows[0].id, text: "First")
        XCTAssertEqual(editor.storedText, raw)
        try editor.update(id: editor.rows[0].id, text: " Changed ")
        XCTAssertEqual(editor.storedText, "Changed\nSecond")
        XCTAssertEqual(editor.originalText, raw)
    }
    func testNilEmptyAndWhitespaceRemainDistinctUntilExplicitAction() throws {
        for raw in [nil, "", " \t\n\r\u{FEFF}"] as [String?] {
            var editor = TemplateAuthoringRuleSteps(raw: raw)
            XCTAssertEqual(editor.rows.map(\.text), [""])
            XCTAssertEqual(editor.storedText, raw)
            try editor.update(id: editor.rows[0].id, text: "")
            XCTAssertEqual(editor.storedText, raw)
            XCTAssertThrowsError(try editor.remove(id: editor.rows[0].id))
            XCTAssertEqual(editor.storedText, raw)
            try editor.add()
            XCTAssertEqual(editor.rows.count, 2); XCTAssertEqual(editor.storedText, "")
        }
    }
    func testAddIsCappedAtTwelveIncludingEmptyRowsWithoutTruncation() throws {
        var editor = TemplateAuthoringRuleSteps(raw: "Keep")
        for _ in 1..<12 { try editor.add() }
        XCTAssertEqual(editor.rows.count, 12); XCTAssertFalse(editor.canAdd)
        let previous = editor
        XCTAssertThrowsError(try editor.add()) { XCTAssertEqual($0 as? TemplateAuthoringRuleSteps.EditError, .rowLimit) }
        XCTAssertEqual(editor, previous); XCTAssertEqual(editor.storedText, "Keep")
        XCTAssertEqual(TemplateAuthoringRuleSteps(raw: editor.storedText).rows.count, 1)
    }
    func testDeleteKeepsOrderAndStableSurvivingIDsAndCannotDeleteLast() throws {
        var editor = TemplateAuthoringRuleSteps(raw: "A\nB\nC")
        let ids = editor.rows.map(\.id)
        try editor.remove(id: ids[1])
        XCTAssertEqual(editor.rows.map(\.id), [ids[0], ids[2]])
        XCTAssertEqual(editor.storedText, "A\nC")
        let previous = editor
        XCTAssertThrowsError(try editor.update(id: ids[1], text: "late"))
        XCTAssertThrowsError(try editor.remove(id: UUID()))
        XCTAssertEqual(editor, previous)
        try editor.remove(id: ids[0])
        XCTAssertEqual(editor.storedText, "C"); XCTAssertFalse(editor.canRemove)
        XCTAssertThrowsError(try editor.remove(id: ids[2]))
        XCTAssertEqual(editor.storedText, "C")
    }
    func testExplicitEditFiltersBlankRowsAndRetainsEmbeddedLF() throws {
        var editor = TemplateAuthoringRuleSteps(raw: "One\nTwo")
        try editor.update(id: editor.rows[0].id, text: " \t ")
        XCTAssertEqual(editor.storedText, "Two"); XCTAssertEqual(editor.rows.count, 2)
        try editor.update(id: editor.rows[1].id, text: " inside\nnewline ")
        XCTAssertEqual(editor.rows[1].text, " inside\nnewline ")
        XCTAssertEqual(editor.storedText, "inside\nnewline")
        try editor.update(id: editor.rows[1].id, text: "")
        XCTAssertEqual(editor.storedText, "")
    }
    func testECMAScriptWhitespaceDoesNotUseFoundationWiderTrim() {
        let sourceWhitespace = "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D} \u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}"
        XCTAssertEqual(TemplateAuthoringRuleSteps.sourceTrim(sourceWhitespace + "keep" + sourceWhitespace), "keep")
        for character in ["\u{0085}", "\u{180E}", "\u{200B}"] {
            XCTAssertEqual(TemplateAuthoringRuleSteps.sourceTrim(character + "keep" + character), character + "keep" + character)
        }
    }
    func testOnlyVerifiedASCII60BoundaryRejectsWithoutReplacingDraft() throws {
        var editor = TemplateAuthoringRuleSteps(raw: nil)
        let id = editor.rows[0].id, maximum = String(repeating: "x", count: 60)
        try editor.update(id: id, text: maximum)
        let previous = editor
        XCTAssertThrowsError(try editor.update(id: id, text: maximum + "x")) { XCTAssertEqual($0 as? TemplateAuthoringRuleSteps.EditError, .asciiLength) }
        XCTAssertEqual(editor, previous)
        // Unicode counting is deliberately not guessed from the source's WXML maxlength.
        for text in [String(repeating: "😀", count: 61), String(repeating: "e\u{301}", count: 61), String(repeating: "中", count: 61)] {
            try editor.update(id: id, text: text); XCTAssertEqual(editor.storedText, text)
        }
    }
    func testCRLFLengthAmbiguityIsDeferredRatherThanAssumingCodeUnits() throws {
        var editor = TemplateAuthoringRuleSteps(raw: nil)
        let text = String(repeating: "x", count: 30) + "\r\n" + String(repeating: "x", count: 29)
        XCTAssertEqual(text.utf16.count, 61); XCTAssertEqual(text.count, 60)
        try editor.update(id: editor.rows[0].id, text: text)
        XCTAssertEqual(editor.rows[0].text, text); XCTAssertEqual(editor.storedText, text)
        XCTAssertEqual(TemplateAuthoringRuleSteps(raw: text).rows.map(\.text), [String(repeating: "x", count: 30), String(repeating: "x", count: 29)])
    }
    func testUnsupportedHistoricalTextIsReadOnlyAndRoundTripsUnchanged() throws {
        let vectors = [(1...13).map { "Step \($0)" }.joined(separator: "\n"), String(repeating: "x", count: 61)]
        for raw in vectors {
            var editor = TemplateAuthoringRuleSteps(raw: raw)
            XCTAssertFalse(editor.isEditable); XCTAssertEqual(editor.storedText, raw)
            let previous = editor
            XCTAssertThrowsError(try editor.add())
            XCTAssertThrowsError(try editor.update(id: editor.rows[0].id, text: "replacement"))
            XCTAssertThrowsError(try editor.remove(id: editor.rows[0].id))
            XCTAssertEqual(editor, previous)
            var draft = TemplateAuthoringDraft(title: "Historical"); draft.ruleInstructions = raw
            let decoded = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(draft))
            XCTAssertEqual(decoded.ruleInstructions, raw)
            XCTAssertEqual(try TemplateAuthoringContract.payload(decoded)["ruleInstructions"], .string(raw))
        }
    }
    func testModesZeroThroughFiveRetainWireFieldAndSixSevenRemainLocalOnly() throws {
        for method in TemplateAuthoringMethod.allCases {
            var draft = TemplateAuthoringDraft(title: "Local"); draft.validationMethod = method
            draft.ruleInstructions = "  unchanged\r\nraw \n"
            if method.isLocalConfigurationOnly {
                XCTAssertThrowsError(try TemplateAuthoringContract.payload(draft))
            } else {
                XCTAssertEqual(try TemplateAuthoringContract.payload(draft)["ruleInstructions"], .string("  unchanged\r\nraw \n"))
            }
        }
    }
}
