import XCTest
@testable import QuestifyCore

final class TemplateNarrationAudioRemovalTests: XCTestCase {
    private func draft(_ reference: String? = "unknown://narration", duration: Int? = 45) -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft()
        draft.voiceEnabled = true; draft.audioUrl = reference; draft.audioDuration = duration
        draft.title = "Keep title"; draft.storyText = "Keep story"; draft.questionAudio = "Keep question audio"
        return draft
    }

    func testClearsBothFieldsAndPreservesEverythingElse() throws {
        let original = draft(), removal = TemplateNarrationAudioRemoval(draft: original)
        let result = try XCTUnwrap(removal.applying(to: original))
        var expected = original; expected.audioUrl = nil; expected.audioDuration = nil
        XCTAssertEqual(result, expected); XCTAssertTrue(result.voiceEnabled)
        XCTAssertTrue(result.publishIssues.contains("templateAuthor.validation.audio"))
        let payload = try TemplateAuthoringContract.payload(result)
        XCTAssertNil(payload["audioUrl"]); XCTAssertNil(payload["audioDuration"])
        XCTAssertNil(removal.applying(to: result))
    }

    func testEmptyWhitespaceOpaqueAndDurationOnlyValuesCanBeCleared() throws {
        let inputs: [(String?, Int?)] = [("", nil), (" \n", nil), ("custom:opaque", 0), (nil, 45), (nil, -1)]
        for (reference, duration) in inputs {
            let original = draft(reference, duration: duration)
            let result = try XCTUnwrap(TemplateNarrationAudioRemoval(draft: original).applying(to: original))
            XCTAssertNil(result.audioUrl); XCTAssertNil(result.audioDuration)
        }
    }

    func testAlreadyEmptyAndDisabledModuleStayUntouched() {
        let empty = draft(nil, duration: nil)
        XCTAssertFalse(TemplateNarrationAudioRemoval(draft: empty).canRemove)
        XCTAssertNil(TemplateNarrationAudioRemoval(draft: empty).applying(to: empty))
        var disabled = draft(); disabled.voiceEnabled = false
        XCTAssertFalse(TemplateNarrationAudioRemoval(draft: disabled).canRemove)
        XCTAssertNil(TemplateNarrationAudioRemoval(draft: draft()).applying(to: disabled))
    }

    func testChangedReferenceOrDurationRejectsRetainedRemoval() {
        let original = draft(), removal = TemplateNarrationAudioRemoval(draft: original)
        var changed = original; changed.audioUrl = "unknown://replacement"
        XCTAssertNil(removal.applying(to: changed))
        changed = original; changed.audioDuration = 46
        XCTAssertNil(removal.applying(to: changed))
        changed = original; changed.audioDuration = nil
        XCTAssertNil(removal.applying(to: changed))
    }

    func testCanonicalEquivalentButByteDifferentReferenceIsNotTheCapturedTarget() {
        let original = draft("custom:caf\u{00E9}"), removal = TemplateNarrationAudioRemoval(draft: original)
        var changed = original; changed.audioUrl = "custom:cafe\u{0301}"
        XCTAssertEqual(original.audioUrl, changed.audioUrl)
        XCTAssertNil(removal.applying(to: changed))
    }

    func testRemovalPreservesNewUnrelatedFieldsRatherThanRestoringSnapshot() throws {
        let original = draft(), removal = TemplateNarrationAudioRemoval(draft: original)
        var changed = original; changed.title = "New title"; changed.storyImg = "new-story-image"
        let result = try XCTUnwrap(removal.applying(to: changed))
        XCTAssertEqual(result.title, "New title"); XCTAssertEqual(result.storyImg, "new-story-image")
    }
}
