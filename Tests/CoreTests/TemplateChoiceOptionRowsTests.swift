import XCTest
@testable import QuestifyCore

final class TemplateChoiceOptionRowsTests: XCTestCase {
    private func draft() -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft(title: "Choice draft")
        draft.finishEnabled = true; draft.validationMethod = .choice
        draft.questionA = "A text"; draft.questionB = "B text"
        draft.storyText = "keep story"; draft.audioUrl = "keep narration"
        return draft
    }
    private func full() -> TemplateAuthoringDraft {
        var value = draft(); value.questionC = "duplicate"; value.questionD = "duplicate"
        value.correctAnswer = "D"
        value.questionOptionMediaJson = #"{"A":{"img":"first"},"B":{"audio":"remove"},"C":{"img":" third ","audio":"custom:third"},"D":{"audio":"fourth"}}"#
        return value
    }
    func testProjectionDoesNotRewriteHistoricalBytesAndStartsAtTwoRows() {
        var original = draft(); original.questionOptionMediaJson = "  { } \n"
        let before = original, rows = TemplateChoiceOptionRows(draft: original)
        XCTAssertEqual(rows.letters, [.a, .b]); XCTAssertTrue(rows.canAdd); XCTAssertFalse(rows.canRemove)
        XCTAssertEqual(original, before); XCTAssertEqual(original.questionOptionMediaJson, "  { } \n")
    }
    func testAddCreatesPersistentBlankRowsUpToFourWithoutChangingAnswerOrMedia() throws {
        var current = draft(); current.correctAnswer = "B"; current.questionOptionMediaJson = #"{ "A": {"img":"keep"} }"#
        let raw = current.questionOptionMediaJson
        current = try XCTUnwrap(TemplateChoiceOptionRows(draft: current).applying(.add, to: current))
        XCTAssertEqual(current.questionC, ""); XCTAssertEqual(TemplateChoiceOptionRows(draft: current).letters.count, 3)
        current = try XCTUnwrap(TemplateChoiceOptionRows(draft: current).applying(.add, to: current))
        XCTAssertEqual(current.questionD, ""); XCTAssertEqual(TemplateChoiceOptionRows(draft: current).letters.count, 4)
        XCTAssertNil(TemplateChoiceOptionRows(draft: current).applying(.add, to: current))
        XCTAssertEqual(current.correctAnswer, "B"); XCTAssertEqual(current.questionOptionMediaJson, raw)
        let decoded = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(current))
        XCTAssertEqual(TemplateChoiceOptionRows(draft: decoded).letters.count, 4)
    }
    func testRemoveMiddleMovesTextAndBothMediaKindsAndRemapsCorrectAnswer() throws {
        let original = full(), rows = TemplateChoiceOptionRows(draft: original)
        let next = try XCTUnwrap(rows.applying(.remove(.b), to: original))
        XCTAssertEqual(next.questionA, "A text"); XCTAssertEqual(next.questionB, "duplicate")
        XCTAssertEqual(next.questionC, "duplicate"); XCTAssertNil(next.questionD)
        XCTAssertEqual(next.correctAnswer, "C")
        XCTAssertEqual(next.choiceOptionMedia.text(.a, .image), "first")
        XCTAssertEqual(next.choiceOptionMedia.text(.b, .image), " third ")
        XCTAssertEqual(next.choiceOptionMedia.text(.b, .audio), "custom:third")
        XCTAssertEqual(next.choiceOptionMedia.text(.c, .audio), "fourth")
        XCTAssertNil(next.choiceOptionMedia.text(.d, .audio))
        XCTAssertEqual(next.storyText, original.storyText); XCTAssertEqual(next.audioUrl, original.audioUrl)
    }
    func testRemovingCorrectOptionSelectsFirstAndRemovingEarlierOptionRetainsIdentity() throws {
        var original = full(); original.correctAnswer = "C"
        let removedCorrect = try XCTUnwrap(TemplateChoiceOptionRows(draft: original).applying(.remove(.c), to: original))
        XCTAssertEqual(removedCorrect.correctAnswer, "A")
        let shifted = try XCTUnwrap(TemplateChoiceOptionRows(draft: original).applying(.remove(.a), to: original))
        XCTAssertEqual(shifted.correctAnswer, "B"); XCTAssertEqual(shifted.questionB, original.questionC)
    }
    func testMinimumTwoAndMissingRowRemovalAreRejected() {
        let original = draft(), rows = TemplateChoiceOptionRows(draft: original)
        for letter in TemplateChoiceOptionMedia.Letter.allCases { XCTAssertNil(rows.applying(.remove(letter), to: original)) }
    }
    func testMalformedUnknownAndOversizedMediaCannotBeReordered() {
        for raw in ["[1]", "broken", #"{"A":{"unknown":"keep"}}"#, #"{"E":{"img":"keep"}}"#, String(repeating: "x", count: 2001)] {
            var original = full(); original.questionOptionMediaJson = raw
            let rows = TemplateChoiceOptionRows(draft: original)
            XCTAssertFalse(rows.supportsReordering); XCTAssertEqual(rows.letters.count, 4)
            XCTAssertNil(rows.applying(.remove(.b), to: original)); XCTAssertNil(rows.applying(.add, to: original))
            XCTAssertEqual(original.questionOptionMediaJson, raw)
        }
    }
    func testSparseMediaAndAnswerOnlyRowsAreNotHiddenOrDiscarded() throws {
        var original = draft(); original.questionOptionMediaJson = #"{"D":{"audio":"only-media"}}"#
        XCTAssertEqual(TemplateChoiceOptionRows(draft: original).letters.count, 4)
        let moved = try XCTUnwrap(TemplateChoiceOptionRows(draft: original).applying(.remove(.a), to: original))
        XCTAssertEqual(TemplateChoiceOptionRows(draft: moved).letters.count, 3)
        XCTAssertEqual(moved.choiceOptionMedia.text(.c, .audio), "only-media")
        original.questionOptionMediaJson = nil; original.correctAnswer = "D"
        let next = try XCTUnwrap(TemplateChoiceOptionRows(draft: original).applying(.remove(.d), to: original))
        XCTAssertEqual(TemplateChoiceOptionRows(draft: next).letters.count, 3)
        XCTAssertEqual(next.questionC, ""); XCTAssertEqual(next.correctAnswer, "A")
    }
    func testUnknownCorrectAnswerBlocksReorderWithoutGuessing() {
        var original = full(); original.correctAnswer = "future-answer"
        let rows = TemplateChoiceOptionRows(draft: original)
        XCTAssertFalse(rows.supportsReordering); XCTAssertNil(rows.applying(.remove(.c), to: original))
        XCTAssertEqual(original.correctAnswer, "future-answer")
    }
    func testSnapshotUsesExactBytesAndPreservesNewUnrelatedFields() throws {
        var original = full(); original.questionC = "caf\u{00E9}"
        let rows = TemplateChoiceOptionRows(draft: original)
        var changed = original; changed.questionC = "cafe\u{0301}"
        XCTAssertEqual(changed.questionC, original.questionC)
        XCTAssertNil(rows.applying(.remove(.a), to: changed))
        changed = original; changed.title = "New title"
        let next = try XCTUnwrap(rows.applying(.remove(.a), to: changed))
        XCTAssertEqual(next.title, "New title")
        changed = original; changed.validationMethod = .text
        XCTAssertNil(rows.applying(.remove(.a), to: changed))
    }
    func testRemovedOnlyAttachmentUsesExplicitEmptyWireFieldAndExistingPayload() throws {
        var original = draft(); original.questionC = "Third"; original.correctAnswer = "B"
        original.questionOptionMediaJson = #"{"C":{"img":"remove"}}"#
        let next = try XCTUnwrap(TemplateChoiceOptionRows(draft: original).applying(.remove(.c), to: original))
        XCTAssertEqual(next.questionOptionMediaJson, "")
        let payload = try TemplateAuthoringContract.payload(next)
        XCTAssertEqual(payload["questionOptionMediaJson"], .string(""))
        XCTAssertEqual(payload["questionA"], .string("A text")); XCTAssertEqual(payload["questionB"], .string("B text"))
        XCTAssertNil(payload["questionC"]); XCTAssertNil(payload["questionD"])
        XCTAssertEqual(payload["correctAnswer"], .string("B"))
    }
}
