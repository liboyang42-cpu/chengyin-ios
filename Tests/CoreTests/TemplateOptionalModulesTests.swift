import XCTest
@testable import QuestifyCore

final class TemplateOptionalModulesTests: XCTestCase {
    private func fixture() -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft(title: "Optional modules"); draft.description = "Keep this"; draft.rewardEnabled = true; draft.storyEnabled = true; draft.voiceEnabled = true
        draft.couponId = 15; draft.feedbackText = "Well done"; draft.medalImg = "/medal.png"; draft.medalName = "Medal"; draft.medalStyle = "enamel"
        draft.storyText = "Story"; draft.storyJson = "[{\"text\":\"Beat\",\"tag\":\"tag\",\"imgs\":[\"/image.png\"]}]"; draft.storyImg = "/legacy.png"
        draft.audioUrl = "/audio.m4a"; draft.audioDuration = 15; draft.preferenceJson = "preserved preference"; return draft
    }
    func testInspectionDoesNotModifyOrNormalizeSource() {
        let draft = fixture(), before = draft, scope = TemplateOptionalModules(draft)
        XCTAssertEqual(scope.fields(.reward).map(\.id), ["couponId", "feedbackText", "medalImg", "medalName", "medalStyle"])
        XCTAssertEqual(scope.fields(.story).last?.value, draft.storyJson); XCTAssertEqual(scope.fields(.voice).last?.value, "15"); XCTAssertEqual(draft, before)
    }
    func testRewardRemovalMatchesSourceClearMapAndPreservesOthers() throws {
        let draft = fixture(), next = try XCTUnwrap(TemplateOptionalModules(draft).applying(.remove(.reward), to: draft))
        var expected = draft; expected.rewardEnabled = false; expected.couponId = 0; expected.feedbackText = ""; expected.medalImg = ""; expected.medalName = ""; expected.medalStyle = "glow"
        XCTAssertEqual(next, expected); XCTAssertFalse(TemplateOptionalModules(next).canRemove(.reward))
    }
    func testStoryRemovalClearsNativeBeatStorageButRetainsLegacyImage() throws {
        let draft = fixture(), next = try XCTUnwrap(TemplateOptionalModules(draft).applying(.remove(.story), to: draft))
        var expected = draft; expected.storyEnabled = false; expected.storyText = ""; expected.storyJson = ""; expected.storyTimelineEdited = true
        XCTAssertEqual(next, expected); XCTAssertEqual(next.storyImg, "/legacy.png"); XCTAssertTrue(try next.storyBeats().isEmpty)
    }
    func testVoiceRemovalUsesOptionalNativeDurationAndPreservesOthers() throws {
        let draft = fixture(), next = try XCTUnwrap(TemplateOptionalModules(draft).applying(.remove(.voice), to: draft))
        var expected = draft; expected.voiceEnabled = false; expected.audioUrl = ""; expected.audioDuration = nil; XCTAssertEqual(next, expected)
    }
    func testRemoveThenAddDoesNotResurrectClearedValues() throws {
        for module in TemplateOptionalModules.Module.allCases {
            let draft = fixture(), removed = try XCTUnwrap(TemplateOptionalModules(draft).applying(.remove(module), to: draft)), added = try XCTUnwrap(TemplateOptionalModules(removed).applying(.add(module), to: removed))
            XCTAssertTrue(TemplateOptionalModules(added).enabled(module))
            XCTAssertEqual(TemplateOptionalModules(added).fields(module).map(\.value), TemplateOptionalModules(removed).fields(module).map(\.value))
        }
    }
    func testAddOfOrdinarilyDisabledModulePreservesRetainedFields() throws {
        var draft = fixture(); draft.rewardEnabled = false; draft.storyEnabled = false; draft.voiceEnabled = false
        for module in TemplateOptionalModules.Module.allCases {
            let next = try XCTUnwrap(TemplateOptionalModules(draft).applying(.add(module), to: draft))
            XCTAssertEqual(TemplateOptionalModules(next).fields(module).map(\.value), TemplateOptionalModules(draft).fields(module).map(\.value))
        }
    }
    func testDisabledStoredContentCanStillBeExplicitlyRemoved() throws {
        var draft = fixture(); draft.rewardEnabled = false; draft.storyEnabled = false; draft.voiceEnabled = false
        for module in TemplateOptionalModules.Module.allCases { XCTAssertTrue(TemplateOptionalModules(draft).canRemove(module)); XCTAssertNotNil(TemplateOptionalModules(draft).applying(.remove(module), to: draft)) }
    }
    func testAlreadyAddedAndEmptyDisabledModulesAreNoOps() {
        var draft = TemplateAuthoringDraft(); draft.rewardEnabled = false
        let scope = TemplateOptionalModules(draft)
        for module in TemplateOptionalModules.Module.allCases { XCTAssertFalse(scope.canRemove(module)); XCTAssertNil(scope.applying(.remove(module), to: draft)) }
        draft = fixture(); for module in TemplateOptionalModules.Module.allCases { XCTAssertNil(TemplateOptionalModules(draft).applying(.add(module), to: draft)) }
    }
    func testMalformedStoryRemainsReadableUntilExplicitRemoval() throws {
        var draft = fixture(); draft.storyJson = "{not a known story}"
        let scope = TemplateOptionalModules(draft); XCTAssertEqual(scope.fields(.story).last?.value, draft.storyJson)
        let next = try XCTUnwrap(scope.applying(.remove(.story), to: draft)); XCTAssertEqual(next.storyJson, ""); XCTAssertEqual(next.storyImg, draft.storyImg)
    }
    func testExactSnapshotRejectsOtherChangesIncludingUnicodeNormalization() {
        var draft = fixture(); draft.title = "\u{00E9}"; let scope = TemplateOptionalModules(draft)
        draft.title = "e\u{0301}"; XCTAssertFalse(scope.isCurrent(draft)); XCTAssertNil(scope.applying(.remove(.reward), to: draft))
    }
    func testFinishAdvancedPreferenceAndIdentityAlwaysRemainUnchanged() throws {
        var draft = fixture(); draft.validationMethod = .preference; draft.advanced.setCreatorEnabled(.dailySign, true)
        let before = draft
        for module in TemplateOptionalModules.Module.allCases { draft = try XCTUnwrap(TemplateOptionalModules(draft).applying(.remove(module), to: draft)) }
        XCTAssertEqual(draft.finishEnabled, before.finishEnabled); XCTAssertEqual(draft.validationMethod, before.validationMethod); XCTAssertEqual(draft.advanced, before.advanced); XCTAssertEqual(draft.preferenceJson, before.preferenceJson); XCTAssertEqual(draft.id, before.id); XCTAssertEqual(draft.originalTemplateID, before.originalTemplateID)
    }
    func testRemoveReAddJSONRoundTripUsesExistingDraftContract() throws {
        var draft = fixture()
        for module in TemplateOptionalModules.Module.allCases { draft = try XCTUnwrap(TemplateOptionalModules(draft).applying(.remove(module), to: draft)); draft = try XCTUnwrap(TemplateOptionalModules(draft).applying(.add(module), to: draft)) }
        XCTAssertEqual(try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(draft)), draft)
    }
}
