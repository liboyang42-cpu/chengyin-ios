import XCTest
@testable import QuestifyCore

final class PlayWordFillDraftTests: XCTestCase {
    private func context(_ slots: [PlayWordFillQuestion.Slot], revision: UUID = UUID()) throws -> PlayWordFillContext {
        .init(revision: revision, question: try .init(slots: slots))
    }
    private func fill(_ draft: inout PlayWordFillDraft, _ text: String, _ index: Int, _ current: PlayWordFillContext) {
        XCTAssertTrue(draft.update(text, at: index, current: current, mountID: draft.mountID))
    }

    func testRebuildsOnlyBlankPositionsWithUntouchedPrefilledCharacters() throws {
        let current = try context([.prefilled("城"), .blank, .prefilled("·"), .blank, .prefilled("!")])
        var draft = PlayWordFillDraft(); draft.mount(current)
        fill(&draft, "瘾", 1, current); fill(&draft, "A", 3, current)
        XCTAssertEqual(draft.submission(current: current, mountID: draft.mountID)?.input, "城瘾·A!")
        XCTAssertFalse(draft.update("改", at: 0, current: current, mountID: draft.mountID))
        XCTAssertEqual(draft.submission(current: current, mountID: draft.mountID)?.input, "城瘾·A!")
    }
    func testUnderscoreAndSpacesAreLiteralPrefilledTextNeverMaskSyntax() throws {
        let current = try context([.prefilled("_"), .blank, .prefilled(" "), .prefilled("＿")])
        var draft = PlayWordFillDraft(); draft.mount(current); fill(&draft, "a", 1, current)
        XCTAssertEqual(draft.submission(current: current, mountID: draft.mountID)?.input, "_a ＿")
    }
    func testDoesNotGuessAdditionalOccurrencesOfTheSameCharacter() throws {
        let current = try context([.blank, .prefilled("人"), .blank])
        var draft = PlayWordFillDraft(); draft.mount(current); fill(&draft, "人", 0, current)
        XCTAssertEqual(draft.input(at: 2, current: current, mountID: draft.mountID), "")
        XCTAssertNil(draft.submission(current: current, mountID: draft.mountID))
        fill(&draft, "人", 2, current)
        XCTAssertEqual(draft.submission(current: current, mountID: draft.mountID)?.input, "人人人")
    }
    func testIncompleteClearedAndMultiCharacterInputsCannotSubmit() throws {
        let current = try context([.blank, .blank])
        var draft = PlayWordFillDraft(); draft.mount(current)
        XCTAssertNil(draft.submission(current: current, mountID: draft.mountID))
        fill(&draft, "城", 0, current); fill(&draft, "shi", 1, current)
        XCTAssertEqual(draft.input(at: 1, current: current, mountID: draft.mountID), "shi") // IME draft is preserved.
        XCTAssertNil(draft.submission(current: current, mountID: draft.mountID))
        fill(&draft, "瘾", 1, current)
        XCTAssertEqual(draft.submission(current: current, mountID: draft.mountID)?.input, "城瘾")
        fill(&draft, "", 1, current)
        XCTAssertNil(draft.submission(current: current, mountID: draft.mountID))
    }
    func testUsesGraphemeCharactersWithoutTruncatingEmojiOrCombiningMarks() throws {
        let current = try context([.blank, .blank])
        var draft = PlayWordFillDraft(); draft.mount(current)
        let accent = "e\u{301}", family = "👩‍👩‍👧‍👦"
        fill(&draft, accent, 0, current); fill(&draft, family, 1, current)
        let submission = try XCTUnwrap(draft.submission(current: current, mountID: draft.mountID))
        XCTAssertEqual(Array(submission.input.utf8), Array((accent + family).utf8))
    }
    func testDoesNotNormalizeCaseWidthOrUnicodeWhenRebuilding() throws {
        let prefill = "e\u{301}"
        let current = try context([.prefilled(prefill), .blank, .blank])
        var draft = PlayWordFillDraft(); draft.mount(current)
        fill(&draft, "Ａ", 1, current); fill(&draft, "b", 2, current)
        XCTAssertEqual(Array(try XCTUnwrap(draft.submission(current: current, mountID: draft.mountID)).input.utf8), Array((prefill + "Ａb").utf8))
    }
    func testWhitespaceAndControlInputCannotSatisfyABlank() throws {
        let current = try context([.blank])
        var draft = PlayWordFillDraft(); draft.mount(current)
        for value in [" ", "\t", "\n", "\r\n", "\u{00a0}", "\u{3000}", "\u{0000}", "\u{007f}"] {
            fill(&draft, value, 0, current)
            XCTAssertNil(draft.submission(current: current, mountID: draft.mountID), value.debugDescription)
        }
    }
    func testMissingAndChangedContextCannotReadEditOrSubmitOldInput() throws {
        let first = try context([.prefilled("城"), .blank])
        let second = try context(first.question.slots)
        var draft = PlayWordFillDraft(); draft.mount(first); fill(&draft, "瘾", 1, first)
        for current in [nil, second] {
            XCTAssertEqual(draft.input(at: 1, current: current, mountID: draft.mountID), "")
            XCTAssertFalse(draft.update("旧", at: 1, current: current, mountID: draft.mountID))
            XCTAssertNil(draft.submission(current: current, mountID: draft.mountID))
        }
    }
    func testQuestionChangeIsDetectedEvenIfHostForgotToRotateRevision() throws {
        let first = try context([.prefilled("城"), .blank])
        let second = try context([.blank, .prefilled("城")], revision: first.revision)
        var draft = PlayWordFillDraft(); draft.mount(first); fill(&draft, "瘾", 1, first)
        XCTAssertNil(draft.submission(current: second, mountID: draft.mountID))
        XCTAssertFalse(draft.update("旧", at: 0, current: second, mountID: draft.mountID))
    }
    func testByteDifferentPrefillInvalidatesOldContextDespiteCanonicalEquivalence() throws {
        let first = try context([.prefilled("e\u{301}"), .blank])
        let second = try context([.prefilled("é"), .blank], revision: first.revision)
        XCTAssertNotEqual(first, second)
        var draft = PlayWordFillDraft(); draft.mount(first); fill(&draft, "x", 1, first)
        XCTAssertNil(draft.submission(current: second, mountID: draft.mountID))
    }
    func testRetiredBindingCannotActAfterSameContextRemount() throws {
        let current = try context([.blank])
        var draft = PlayWordFillDraft(); draft.mount(current)
        let oldMount = draft.mountID
        fill(&draft, "旧", 0, current)
        draft.clear(); draft.mount(current)
        XCTAssertNotEqual(oldMount, draft.mountID)
        XCTAssertFalse(draft.update("迟", at: 0, current: current, mountID: oldMount))
        XCTAssertEqual(draft.input(at: 0, current: current, mountID: oldMount), "")
        XCTAssertNil(draft.submission(current: current, mountID: oldMount))
        XCTAssertNil(draft.submission(current: current, mountID: draft.mountID))
    }
    func testFrozenSubmissionIsNotChangedBySubsequentEditsAndRetiresWithContext() throws {
        let current = try context([.prefilled("A"), .blank])
        var draft = PlayWordFillDraft(); draft.mount(current); fill(&draft, "b", 1, current)
        let submission = try XCTUnwrap(draft.submission(current: current, mountID: draft.mountID))
        fill(&draft, "c", 1, current)
        XCTAssertEqual(submission.input, "Ab")
        XCTAssertEqual(draft.submission(current: current, mountID: draft.mountID)?.input, "Ac")
        XCTAssertTrue(submission.isCurrent(current))
        XCTAssertFalse(submission.isCurrent(nil))
        XCTAssertFalse(submission.isCurrent(try context(current.question.slots)))
    }
    func testInvalidQuestionAndIndicesFailClosed() throws {
        for slots: [PlayWordFillQuestion.Slot] in [[], [.prefilled("城")], [.prefilled(""), .blank], [.prefilled("城瘾"), .blank], Array(repeating: .blank, count: 4097)] {
            XCTAssertThrowsError(try PlayWordFillQuestion(slots: slots))
        }
        let current = try context([.blank])
        var draft = PlayWordFillDraft(); draft.mount(current)
        for index in [-1, 1, Int.max] {
            XCTAssertFalse(draft.update("x", at: index, current: current, mountID: draft.mountID))
            XCTAssertEqual(draft.input(at: index, current: current, mountID: draft.mountID), "")
        }
        XCTAssertFalse(draft.update(String(repeating: "x", count: 4097), at: 0, current: current, mountID: draft.mountID))
    }
    func testNewInstanceStartsEmptyAndNeverInfersAcceptedAttemptFromFilledInput() throws {
        let current = try context([.prefilled("城"), .blank])
        var beforeRestart = PlayWordFillDraft(); beforeRestart.mount(current); fill(&beforeRestart, "瘾", 1, current)
        XCTAssertNotNil(beforeRestart.submission(current: current, mountID: beforeRestart.mountID))
        var afterRestart = PlayWordFillDraft(); afterRestart.mount(current)
        XCTAssertNil(afterRestart.submission(current: current, mountID: afterRestart.mountID))
        XCTAssertEqual(afterRestart.input(at: 1, current: current, mountID: afterRestart.mountID), "")
    }
    func testOriginalLevelTwoCompactNDLESRebuildsENDLESS() throws {
        // Original 1.3 lines 2760–2761: E____ S; input NDLES -> ENDLESS.
        // The prose is not a mask grammar. This explicit public fixture follows
        // the stated input/output, with five blanks between fixed E and final S.
        let current = try context([.prefilled("E")] + Array(repeating: .blank, count: 5) + [.prefilled("S")])
        var draft = PlayWordFillDraft(); draft.mount(current)
        XCTAssertTrue(draft.replaceBlankInput("NDLES", current: current, mountID: draft.mountID))
        XCTAssertEqual(draft.blankInput(current: current, mountID: draft.mountID), "NDLES")
        XCTAssertEqual(draft.submission(current: current, mountID: draft.mountID)?.input, "ENDLESS")
        XCTAssertEqual(draft.input(at: 4, current: current, mountID: draft.mountID), "E")
        XCTAssertEqual(draft.input(at: 5, current: current, mountID: draft.mountID), "S")
    }
    func testOriginalLevelThreePreservesPrefilledANDAndSpaces() throws {
        let connector = " AND ".map { PlayWordFillQuestion.Slot.prefilled(String($0)) }
        let current = try context(Array(repeating: .blank, count: 7) + connector + Array(repeating: .blank, count: 8))
        var draft = PlayWordFillDraft(); draft.mount(current)
        XCTAssertTrue(draft.replaceBlankInput("NICOLASPERNELLE", current: current, mountID: draft.mountID))
        XCTAssertEqual(draft.blankInput(current: current, mountID: draft.mountID), "NICOLASPERNELLE")
        XCTAssertEqual(draft.submission(current: current, mountID: draft.mountID)?.input, "NICOLAS AND PERNELLE")
        for index in 7..<12 { XCTAssertFalse(draft.update("X", at: index, current: current, mountID: draft.mountID)) }
        XCTAssertEqual(draft.submission(current: current, mountID: draft.mountID)?.input, "NICOLAS AND PERNELLE")
    }
    func testFullAnswerIsNotSilentlyConsumedAsBlankOnlyInput() throws {
        let current = try context([.prefilled("E")] + Array(repeating: .blank, count: 5) + [.prefilled("S")])
        var draft = PlayWordFillDraft(); draft.mount(current)
        XCTAssertTrue(draft.replaceBlankInput("ENDLESS", current: current, mountID: draft.mountID))
        XCTAssertEqual(draft.blankInput(current: current, mountID: draft.mountID), "ENDLESS")
        XCTAssertNil(draft.submission(current: current, mountID: draft.mountID))
        // Mixing a per-slot edit into compact input must not discard overflow.
        XCTAssertFalse(draft.update("N", at: 1, current: current, mountID: draft.mountID))
        XCTAssertEqual(draft.blankInput(current: current, mountID: draft.mountID), "ENDLESS")
        XCTAssertNil(draft.submission(current: current, mountID: draft.mountID))
    }
    func testCompactPartialDeletionAndReplacementLeavePrefilledPositionsIntact() throws {
        let current = try context([.prefilled("A"), .blank, .prefilled(" "), .blank])
        var draft = PlayWordFillDraft(); draft.mount(current)
        for value in ["x", "xy", "x", "", "uv"] {
            XCTAssertTrue(draft.replaceBlankInput(value, current: current, mountID: draft.mountID))
            XCTAssertEqual(draft.blankInput(current: current, mountID: draft.mountID), value)
            XCTAssertEqual(draft.input(at: 1, current: current, mountID: draft.mountID), String(value.prefix(1)))
            if value.count == 2 {
                XCTAssertEqual(draft.submission(current: current, mountID: draft.mountID)?.input, "A" + String(value.prefix(1)) + " " + String(value.suffix(1)))
            } else { XCTAssertNil(draft.submission(current: current, mountID: draft.mountID)) }
        }
    }
    func testCompactKeyboardCallbackCannotActAfterContextChangeOrRemount() throws {
        let current = try context([.blank])
        var draft = PlayWordFillDraft(); draft.mount(current)
        let oldMount = draft.mountID
        XCTAssertFalse(draft.replaceBlankInput("x", current: nil, mountID: oldMount))
        XCTAssertFalse(draft.replaceBlankInput("x", current: try context([.blank]), mountID: oldMount))
        draft.clear(); draft.mount(current)
        XCTAssertFalse(draft.replaceBlankInput("x", current: current, mountID: oldMount))
        XCTAssertEqual(draft.blankInput(current: current, mountID: oldMount), "")
        XCTAssertNil(draft.submission(current: current, mountID: draft.mountID))
    }
    func testFormatUnderscoresProduceOnlyBlankSlots() throws {
        let question = try PlayWordFillQuestion(format: "E_____S")
        XCTAssertEqual(question.slots, [.prefilled("E")] + Array(repeating: .blank, count: 5) + [.prefilled("S")])
        let current = PlayWordFillContext(revision: UUID(), question: question)
        var draft = PlayWordFillDraft(); draft.mount(current)
        XCTAssertTrue(draft.replaceBlankInput("NDLES", current: current, mountID: draft.mountID))
        XCTAssertEqual(draft.submission(current: current, mountID: draft.mountID)?.input, "ENDLESS")
    }
    func testFormatRebuildsConnectorWordsAndSpacesWithoutTypingThem() throws {
        let question = try PlayWordFillQuestion(format: "_______ AND ________")
        let current = PlayWordFillContext(revision: UUID(), question: question)
        var draft = PlayWordFillDraft(); draft.mount(current)
        XCTAssertTrue(draft.replaceBlankInput("NICOLASPERNELLE", current: current, mountID: draft.mountID))
        XCTAssertEqual(draft.submission(current: current, mountID: draft.mountID)?.input, "NICOLAS AND PERNELLE")
        XCTAssertTrue(draft.replaceBlankInput("NICOLAS AND PERNELLE", current: current, mountID: draft.mountID))
        XCTAssertNil(draft.submission(current: current, mountID: draft.mountID))
    }
    func testAmbiguousProseMaskIsNotSilentlyChangedToFitAnExpectedAnswer() throws {
        let question = try PlayWordFillQuestion(format: "E____ S")
        XCTAssertEqual(question.slots.filter { $0 == .blank }.count, 4)
        XCTAssertEqual(question.slots[5], .prefilled(" "))
        let current = PlayWordFillContext(revision: UUID(), question: question)
        var draft = PlayWordFillDraft(); draft.mount(current)
        XCTAssertTrue(draft.replaceBlankInput("NDLES", current: current, mountID: draft.mountID))
        XCTAssertNil(draft.submission(current: current, mountID: draft.mountID))
        XCTAssertEqual(draft.blankInput(current: current, mountID: draft.mountID), "NDLES")
    }
    func testFormatPreservesLiteralUnicodeAndOnlyASCIIUnderscoreMeansBlank() throws {
        let prefix = "e\u{301}＿"
        let question = try PlayWordFillQuestion(format: prefix + "_!")
        XCTAssertEqual(question.slots.filter { $0 == .blank }.count, 1)
        let current = PlayWordFillContext(revision: UUID(), question: question)
        var draft = PlayWordFillDraft(); draft.mount(current)
        XCTAssertTrue(draft.replaceBlankInput("瘾", current: current, mountID: draft.mountID))
        XCTAssertEqual(Array(try XCTUnwrap(draft.submission(current: current, mountID: draft.mountID)).input.utf8), Array((prefix + "瘾!").utf8))
    }
    func testFormatWithoutBlankOrOverBudgetRemainsUnavailable() {
        for format in ["", "ENDLESS", "NICOLAS AND PERNELLE", "＿", String(repeating: "_", count: 4097)] {
            XCTAssertThrowsError(try PlayWordFillQuestion(format: format))
        }
    }
}
