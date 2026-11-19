import XCTest
@testable import QuestifyCore

/// verify-1119 player-side items: hangman fill note, reference picture entry, record-only
/// photo stations, completion-mode labels and the on-device stage event log.
final class Verify1119PlayTests: XCTestCase {
    private func wire(_ json: String) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8)) }
    private let slots = #""slots":[{"i":0,"kind":"BLANK"},{"i":1,"kind":"BLANK"}]"#

    // CG-01-P2-5
    func testHangmanHowToIsDecodedAndHiddenWhenAbsentOrBlank() throws {
        let note = try PlayHangmanProjection(wire("{\(slots),\"howTo\":\"一格一个字母，V＝ü\"}"))
        XCTAssertEqual(note.howTo, "一格一个字母，V＝ü")
        XCTAssertNil(try PlayHangmanProjection(wire("{\(slots)}")).howTo)
        XCTAssertNil(try PlayHangmanProjection(wire("{\(slots),\"howTo\":\"  \"}")).howTo)
    }

    // CG-09-P2-5 / CG-10-D-3
    func testReferenceImageSourceAcceptsBothKeysAndIgnoresBlank() throws {
        XCTAssertEqual(PlayKitReferenceImage.source(in: try wire(#"{"referenceImage":"https://a.example/r.png"}"#)), "https://a.example/r.png")
        XCTAssertEqual(PlayKitReferenceImage.source(in: try wire(#"{"referenceImageUrl":" https://a.example/s.png "}"#)), "https://a.example/s.png")
        XCTAssertNil(PlayKitReferenceImage.source(in: try wire(#"{"referenceImage":""}"#)))
        XCTAssertNil(PlayKitReferenceImage.source(in: try wire(#"{"prompt":"x"}"#)))
    }

    // CG-ALL-12 / CG-02-D-4
    func testRecordOnlyPhotoStationAcceptsTextConfirmedSkip() throws {
        let record = try wire(#"{"photoMode":"record","passed":false}"#)
        XCTAssertTrue(PlayKitPhotoRecordMode.applies(record))
        XCTAssertTrue(PlayKitPhotoRecordMode.applies(try wire(#"{"photo_mode":"RECORD"}"#)))
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind: "photoCheck", action: "SUBMIT_PHOTO_CHECK", payload: PlayKitPhotoRecordMode.skipPayload, segment: record))
        XCTAssertNoThrow(try PlayKitInputContract.validate(kind: "photoCheck", action: "SUBMIT_PHOTO_CHECK", payload: ["imageUrl": .string("https://a.example/p.jpg")], segment: record))
    }
    func testOrdinaryPhotoCheckStillRequiresAPhoto() throws {
        let ordinary = try wire(#"{"passed":false}"#)
        XCTAssertFalse(PlayKitPhotoRecordMode.applies(ordinary))
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "photoCheck", action: "SUBMIT_PHOTO_CHECK", payload: PlayKitPhotoRecordMode.skipPayload, segment: ordinary))
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "photoCheck", action: "SUBMIT_PHOTO_CHECK", payload: ["skipped": .bool(false)], segment: try wire(#"{"photoMode":"record"}"#)))
    }

    // CG-07-P2-2 / CG-ALL-11
    func testCompletionModesMapToPlayerLabels() {
        XCTAssertEqual(PlayCompletionModePresentation(raw: "SOLVED"), .solved)
        XCTAssertEqual(PlayCompletionModePresentation(raw: "SKIPPED"), .assisted)
        XCTAssertEqual(PlayCompletionModePresentation(raw: "REVEALED"), .assisted)
        XCTAssertEqual(PlayCompletionModePresentation(raw: "ASSISTED_COMPLETION"), .assisted)
        XCTAssertEqual(PlayCompletionModePresentation(raw: "desk"), .desk)
        XCTAssertEqual(PlayCompletionModePresentation(raw: "ALT"), .alternate)
        XCTAssertNil(PlayCompletionModePresentation(raw: "CUSTOM_SERVER_TEXT"))
        XCTAssertNil(PlayCompletionModePresentation(raw: nil))
        XCTAssertEqual(PlayCompletionModePresentation.assisted.labelKey, "playx.completion.assisted")
        XCTAssertFalse(PlayCompletionModePresentation.solved.isAssisted)
    }
    func testCompletedBadgeShowsAssistedOnlyForCompletedNodes() {
        XCTAssertEqual(PlayTaskStatusPresentation.completed.labelKey(completionMode: "SKIPPED"), "playx.completion.assisted")
        XCTAssertEqual(PlayTaskStatusPresentation.completed.labelKey(completionMode: "DESK"), "playx.completion.desk")
        XCTAssertEqual(PlayTaskStatusPresentation.completed.labelKey(completionMode: "SOLVED"), "referenceTask.status.completed")
        XCTAssertEqual(PlayTaskStatusPresentation.completed.labelKey(completionMode: nil), "referenceTask.status.completed")
        XCTAssertEqual(PlayTaskStatusPresentation.available.labelKey(completionMode: "SKIPPED"), "referenceTask.status.available")
    }

    // CG-01-P2-9 / CG-09-P2-6
    func testStageEventNamesMatchTheAuditList() {
        XCTAssertEqual(Set(PlayStageEvent.allCases.map(\.rawValue)),
                       ["stage_enter", "hint_open", "skip", "assisted_complete", "wrong_answer", "reference_open"])
    }
    func testStageEventLogIsBoundedAndCarriesNoAnswerText() {
        let log = PlayStageEventLog()
        for index in 0..<(PlayStageEventLog.capacity + 5) { log.record(.stageEnter, nodeID: index, kind: "qa") }
        XCTAssertEqual(log.entries.count, PlayStageEventLog.capacity)
        XCTAssertEqual(log.entries.first?.nodeID, 5)
        log.record(.wrongAnswer, nodeID: 9, kind: "hangman")
        XCTAssertEqual(log.entries.last, PlayStageEventRecord(event: .wrongAnswer, nodeID: 9, kind: "hangman"))
        log.removeAll(); XCTAssertTrue(log.entries.isEmpty)
    }
}
