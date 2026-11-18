import XCTest
@testable import QuestifyCore

/// F03 letter pool: pure slot/candidate arrangement and SUBMIT_HANGMAN / SUBMIT_QA
/// payload contracts. Neutral synthetic fixtures only; the client never sees an answer.
final class HangmanPoolTests: XCTestCase {
    private func wire(_ json: String) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8)) }
    /// Five slots: two blanks, a separator, a blank, a prefilled letter.
    private let poolSegment = #"{"length":5,"blankCount":3,"caseSensitive":false,"solved":false,"display":"__-_D","inputMode":"pool","pool":["C","X","A","Y","B","A"],"poolRemoved":0,"slots":[{"i":0,"kind":"BLANK"},{"i":1,"kind":"BLANK"},{"i":2,"ch":"-","kind":"SEPARATOR"},{"i":3,"kind":"BLANK"},{"i":4,"ch":"D","kind":"PREFILLED"}]}"#
    private func projection(_ json: String? = nil) throws -> PlayHangmanProjection { try PlayHangmanProjection(wire(json ?? poolSegment)) }

    func testPoolProjectionParsesModeCandidatesAndSlotKinds() throws {
        let value = try projection()
        XCTAssertEqual(value.inputMode, .pool)
        XCTAssertEqual(value.pool, ["C", "X", "A", "Y", "B", "A"])
        XCTAssertEqual(value.poolRemoved, 0)
        XCTAssertEqual(value.slots.map(\.kind), [.blank, .blank, .separator, .blank, .prefilled])
        XCTAssertEqual(value.fillableSlots.map(\.index), [0, 1, 3])
        XCTAssertFalse(value.solved)
    }
    func testKeyboardModeIsDefaultWithoutPoolFields() throws {
        let value = try projection(#"{"length":2,"blankCount":2,"solved":false,"slots":[{"i":0,"kind":"BLANK"},{"i":1,"ch":"B","kind":"FILLED"}]}"#)
        XCTAssertEqual(value.inputMode, .keyboard); XCTAssertTrue(value.pool.isEmpty)
        XCTAssertNil(LetterPoolState(hangman: value))
        XCTAssertEqual(value.keyboardDraft, "")
        XCTAssertEqual(value.keyboardPayload("AB"), ["slots": .object(["0": .string("A"), "1": .string("B")])])
        XCTAssertNil(value.keyboardPayload("A"))
        let explicit = try projection(#"{"inputMode":"keyboard","slots":[{"i":0,"ch":"A","kind":"FILLED"},{"i":1,"kind":"BLANK"}]}"#)
        XCTAssertEqual(explicit.inputMode, .keyboard); XCTAssertEqual(explicit.keyboardDraft, "A")
    }
    func testMalformedProjectionsReject() {
        for json in [
            #"{"slots":[]}"#,
            #"{"slots":[{"i":1,"kind":"BLANK"}]}"#,
            #"{"slots":[{"i":0,"kind":"OTHER"}]}"#,
            #"{"slots":[{"i":0,"ch":"-","kind":"SEPARATOR"}]}"#,
            #"{"slots":[{"i":0,"ch":"AB","kind":"FILLED"}]}"#,
            #"{"slots":[{"i":0,"ch":"A","kind":"BLANK"}]}"#,
            #"{"inputMode":"wheel","slots":[{"i":0,"kind":"BLANK"}]}"#,
            #"{"inputMode":"pool","slots":[{"i":0,"kind":"BLANK"}]}"#,
            #"{"inputMode":"pool","pool":["AB"],"slots":[{"i":0,"kind":"BLANK"}]}"#,
            #"{"inputMode":"pool","pool":["A"],"poolRemoved":-1,"slots":[{"i":0,"kind":"BLANK"}]}"#,
            #"{"length":3,"slots":[{"i":0,"kind":"BLANK"}]}"#
        ] {
            XCTAssertThrowsError(try projection(json), json)
        }
    }
    func testTapCandidateFillsFirstEmptyFillableSlotAndSkipsFixedSlots() throws {
        var state = try XCTUnwrap(LetterPoolState(hangman: projection()))
        XCTAssertTrue(state.isEmpty); XCTAssertFalse(state.isComplete)
        XCTAssertTrue(state.pick(2)) // A -> slot 0
        XCTAssertTrue(state.pick(4)) // B -> slot 1
        XCTAssertTrue(state.pick(0)) // C -> slot 3 (separator at 2 skipped)
        XCTAssertEqual(state.slots.map { state.text(of: $0) }, ["A", "B", "-", "C", "D"])
        XCTAssertTrue(state.isComplete)
        XCTAssertFalse(state.pick(1), "A full row ignores further candidates")
        XCTAssertFalse(state.pick(2), "A used candidate cannot be placed twice")
        XCTAssertEqual(state.usedPoolIndexes, [0, 2, 4])
    }
    func testTapFilledSlotReturnsCharacterAndFixedSlotsAreNotTappable() throws {
        var state = try XCTUnwrap(LetterPoolState(hangman: projection()))
        state.pick(2); state.pick(4); state.pick(0)
        XCTAssertFalse(state.clear(slotID: 2)); XCTAssertFalse(state.clear(slotID: 4))
        XCTAssertTrue(state.clear(slotID: 1)); XCTAssertFalse(state.isUsed(4))
        XCTAssertFalse(state.clear(slotID: 1), "An empty slot has nothing to return")
        XCTAssertTrue(state.pick(5)) // second A refills the first empty slot (1)
        XCTAssertEqual(state.slots.map { state.text(of: $0) }, ["A", "A", "-", "C", "D"])
        state.clearAll()
        XCTAssertTrue(state.isEmpty); XCTAssertTrue(state.usedPoolIndexes.isEmpty)
        XCTAssertEqual(state.slots.map { state.text(of: $0) }, [nil, nil, "-", nil, "D"])
    }
    func testHangmanPayloadUsesOnlyFillableIndicesAndValidates() throws {
        let value = try projection()
        var state = try XCTUnwrap(LetterPoolState(hangman: value))
        state.pick(2); state.pick(4); state.pick(0)
        let payload = state.hangmanPayload
        XCTAssertEqual(payload, ["slots": .object(["0": .string("A"), "1": .string("B"), "3": .string("C")])])
        XCTAssertNoThrow(try value.validate(payload))
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind: "hangman", action: "SUBMIT_HANGMAN", payload: payload, segment: wire(poolSegment)))
        XCTAssertNoThrow(try PlayKitActionCatalog.payload(kind: "hangman", action: "SUBMIT_HANGMAN", detail: payload))
    }
    func testPayloadRejectsFixedIndicesForeignOrOverusedCharactersAndGaps() throws {
        let value = try projection()
        let cases: [[String: PlayWireValue]] = [
            ["slots": .object(["0": .string("A"), "1": .string("B"), "2": .string("C"), "3": .string("C")])],
            ["slots": .object(["0": .string("A"), "1": .string("B"), "3": .string("Z")])],
            ["slots": .object(["0": .string("B"), "1": .string("B"), "3": .string("C")])],
            ["slots": .object(["0": .string("A"), "1": .string("B")])],
            ["slots": .object(["0": .string("AB"), "1": .string("B"), "3": .string("C")])],
            ["slots": .object(["00": .string("A"), "1": .string("B"), "3": .string("C")])],
            ["input": .string("ABC")],
            ["slots": .object([:])]
        ]
        for payload in cases { XCTAssertThrowsError(try value.validate(payload), "\(payload)") }
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "hangman", action: "SUBMIT_QA", payload: cases[0], segment: wire(poolSegment)))
    }
    func testSolvedHangmanIsCompleteAndRejectsFurtherSubmission() throws {
        let solved = poolSegment.replacingOccurrences(of: #""solved":false"#, with: #""solved":true"#)
        XCTAssertTrue(PlayKitScreenProjection(kind: .hangman, segment: try wire(solved)).complete)
        XCTAssertFalse(PlayKitScreenProjection(kind: .hangman, segment: try wire(poolSegment)).complete)
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "hangman", action: "SUBMIT_HANGMAN", payload: ["slots": .object(["0": .string("A"), "1": .string("B"), "3": .string("C")])], segment: wire(solved)))
    }
    func testWrongAnswerKeepsServerFilledCharactersOnTheirCandidates() throws {
        let afterWrong = #"{"solved":false,"inputMode":"pool","pool":["C","X","A","Y","B","A"],"poolRemoved":0,"slots":[{"i":0,"ch":"A","kind":"FILLED"},{"i":1,"ch":"X","kind":"FILLED"},{"i":2,"ch":"-","kind":"SEPARATOR"},{"i":3,"ch":"C","kind":"FILLED"},{"i":4,"ch":"D","kind":"PREFILLED"}]}"#
        let value = try projection(afterWrong)
        var state = try XCTUnwrap(LetterPoolState(hangman: value))
        XCTAssertEqual(state.slots.map { state.text(of: $0) }, ["A", "X", "-", "C", "D"])
        XCTAssertEqual(state.usedPoolIndexes, [0, 1, 2])
        XCTAssertTrue(state.clear(slotID: 1)); XCTAssertTrue(state.pick(4))
        XCTAssertEqual(state.hangmanPayload, ["slots": .object(["0": .string("A"), "1": .string("B"), "3": .string("C")])])
        XCTAssertNoThrow(try value.validate(state.hangmanPayload))
    }
    func testFilledCharacterOutsideVisiblePoolIsCarriedButNotResent() throws {
        let revealed = #"{"solved":false,"inputMode":"pool","pool":["A","Y"],"slots":[{"i":0,"ch":"B","kind":"FILLED"},{"i":1,"kind":"BLANK"}]}"#
        let value = try projection(revealed)
        var state = try XCTUnwrap(LetterPoolState(hangman: value))
        XCTAssertEqual(state.text(of: state.slots[0]), "B"); XCTAssertNil(state.slots[0].poolIndex)
        XCTAssertFalse(state.hasPlacedCandidates)
        state.pick(0)
        XCTAssertTrue(state.isComplete)
        XCTAssertEqual(state.hangmanPayload, ["slots": .object(["1": .string("A")])])
        XCTAssertNoThrow(try value.validate(state.hangmanPayload))
        XCTAssertFalse(state.clear(slotID: 0), "A carried server fill has no candidate to return")
        state.clearAll()
        XCTAssertEqual(state.text(of: state.slots[0]), "B"); XCTAssertNil(state.text(of: state.slots[1]))
    }
    func testTrimmedPoolRebaseKeepsStillVisiblePicksAndDropsRemovedOnes() throws {
        var before = try XCTUnwrap(LetterPoolState(hangman: projection()))
        before.pick(1) // X (a decoy) -> slot 0
        before.pick(4) // B -> slot 1
        let trimmed = #"{"solved":false,"inputMode":"pool","pool":["C","A","B","A"],"poolRemoved":2,"slots":[{"i":0,"kind":"BLANK"},{"i":1,"kind":"BLANK"},{"i":2,"ch":"-","kind":"SEPARATOR"},{"i":3,"kind":"BLANK"},{"i":4,"ch":"D","kind":"PREFILLED"}]}"#
        let value = try projection(trimmed)
        XCTAssertEqual(value.poolRemoved, 2)
        let after = try XCTUnwrap(LetterPoolState(hangman: value)).rebased(keeping: before)
        XCTAssertEqual(after.slots.map { after.text(of: $0) }, [nil, "B", "-", nil, "D"])
        XCTAssertEqual(after.usedPoolIndexes, [2])
    }
    func testFitsCountsDuplicates() {
        XCTAssertTrue(LetterPoolState.fits(["A", "A", "B"], in: ["A", "B", "A", "C"]))
        XCTAssertFalse(LetterPoolState.fits(["A", "A", "A"], in: ["A", "B", "A"]))
        XCTAssertFalse(LetterPoolState.fits(["Z"], in: ["A"]))
        XCTAssertTrue(LetterPoolState.fits([], in: []))
    }
    // MARK: TYPE question letter pool
    private let questionSegment = #"{"mode":"TYPE","question":"Sample station question","finished":false,"letterPool":{"chars":["丙","甲","丁","乙"],"answerLength":2,"removed":0}}"#
    func testQuestionLetterPoolParsesAndJoinsPickedCharactersInSlotOrder() throws {
        let pool = try XCTUnwrap(PlayQuestionLetterPool(question: wire(questionSegment)))
        XCTAssertEqual(pool.chars, ["丙", "甲", "丁", "乙"]); XCTAssertEqual(pool.answerLength, 2); XCTAssertEqual(pool.removed, 0)
        var state = try XCTUnwrap(LetterPoolState(question: pool))
        XCTAssertEqual(state.slots.count, 2)
        state.pick(1); state.pick(3)
        XCTAssertEqual(state.joinedInput, "甲乙")
        XCTAssertEqual(state.questionPayload, ["input": .string("甲乙")])
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind: "qa", action: "SUBMIT_QA", payload: state.questionPayload, segment: wire(questionSegment)))
        XCTAssertTrue(state.clear(slotID: 0)); state.pick(0)
        XCTAssertEqual(state.joinedInput, "丙乙")
    }
    func testQuestionLetterPoolSubmissionMustUseVisibleCharactersAndAnswerLength() throws {
        let segment = try wire(questionSegment)
        for input in ["甲", "甲乙丙", "甲戊", "甲甲"] {
            XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "qa", action: "SUBMIT_QA", payload: ["input": .string(input)], segment: segment), input)
        }
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind: "qa", action: "SUBMIT_QA", payload: ["input": .string("free text")], segment: wire(#"{"mode":"TYPE","finished":false}"#)))
    }
    func testQuestionWithoutPoolOrNonTypeModeHasNoLetterPoolAndMalformedPoolThrows() throws {
        XCTAssertNil(try PlayQuestionLetterPool(question: wire(#"{"mode":"TYPE"}"#)))
        XCTAssertNil(try PlayQuestionLetterPool(question: wire(#"{"mode":"PICK","letterPool":{"chars":["甲"],"answerLength":1}}"#)))
        for json in [#"{"letterPool":{"chars":[],"answerLength":1}}"#, #"{"letterPool":{"chars":["甲"],"answerLength":2}}"#,
                     #"{"letterPool":{"chars":["甲乙"],"answerLength":1}}"#, #"{"letterPool":{"chars":["甲"],"answerLength":0}}"#,
                     #"{"letterPool":{"chars":["甲"],"answerLength":1,"removed":-1}}"#, #"{"letterPool":"甲乙"}"#] {
            XCTAssertThrowsError(try PlayQuestionLetterPool(question: wire(json)), json)
        }
    }
    func testQuestionTrimKeepsPicksStillVisible() throws {
        var before = try XCTUnwrap(LetterPoolState(question: XCTUnwrap(PlayQuestionLetterPool(question: wire(questionSegment)))))
        before.pick(0); before.pick(3) // 丙 (decoy), 乙
        let trimmed = try XCTUnwrap(PlayQuestionLetterPool(question: wire(#"{"mode":"TYPE","letterPool":{"chars":["甲","乙"],"answerLength":2,"removed":2}}"#)))
        let after = try XCTUnwrap(LetterPoolState(question: trimmed)).rebased(keeping: before)
        XCTAssertEqual(after.slots.map { after.text(of: $0) }, [nil, "乙"])
        XCTAssertEqual(trimmed.removed, 2)
    }
    func testHangmanIsRegisteredAsNativeScreenAndCapabilityKeysUseServerNaming() throws {
        XCTAssertEqual(PlayKitScreenKind(rawValue: "hangman"), .hangman)
        XCTAssertEqual(PlayKitActionCatalog.actions["hangman"], ["SUBMIT_HANGMAN"])
        XCTAssertEqual(PlayKitScreenKind.priority.last, .bingo)
        XCTAssertTrue(PlayKitScreenKind.priority.contains(.hangman))
        XCTAssertTrue(Set(PlayClientCapabilities.keys).isSuperset(of: ["game.hangman", "hangman.pool", "qa.letterPool", "role.views"]))
        XCTAssertEqual(PlayClientCapabilities.declaration(["hangman.pool", "game.hangman"]), "game.hangman@1,hangman.pool@1")
    }
}
