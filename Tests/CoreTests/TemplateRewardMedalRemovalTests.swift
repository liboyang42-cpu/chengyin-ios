import XCTest
@testable import QuestifyCore

final class TemplateRewardMedalRemovalTests: XCTestCase {
    private func draft() -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft(title: "Medal reward")
        draft.rewardEnabled = true; draft.medalImg = "custom:medal"; draft.medalName = "City medal"; draft.medalStyle = "enamel"
        draft.couponId = 22; draft.feedbackText = "Keep feedback"; draft.storyText = "Keep story"
        return draft
    }
    func testClearsThePairAndResetsStyleWithoutTouchingOtherRewards() throws {
        let original = draft(), removal = TemplateRewardMedalRemoval(draft: original)
        let next = try XCTUnwrap(removal.applying(to: original))
        var expected = original; expected.medalImg = nil; expected.medalName = nil; expected.medalStyle = "glow"
        XCTAssertEqual(next, expected); XCTAssertTrue(next.rewardEnabled)
        XCTAssertNil(removal.applying(to: next))
    }
    func testOpeningDoesNotNormalizeUnknownOrWhitespaceFields() {
        var original = draft(); original.medalImg = " \n"; original.medalName = "  "; original.medalStyle = "future-style"
        let before = original, removal = TemplateRewardMedalRemoval(draft: original)
        XCTAssertTrue(removal.canRemove); XCTAssertEqual(original, before)
        XCTAssertEqual(original.medalImg, " \n"); XCTAssertEqual(original.medalStyle, "future-style")
    }
    func testPartialAndStyleOnlyMedalsCanBeExplicitlyCleared() throws {
        let values: [(String?, String?, String?)] = [(nil, "Name only", "glow"), ("opaque", nil, "glow"), (nil, nil, "enamel"), (nil, nil, nil), ("", "", "glow")]
        for (image, name, style) in values {
            var original = draft(); original.medalImg = image; original.medalName = name; original.medalStyle = style
            let next = try XCTUnwrap(TemplateRewardMedalRemoval(draft: original).applying(to: original))
            XCTAssertNil(next.medalImg); XCTAssertNil(next.medalName); XCTAssertEqual(next.medalStyle, "glow")
        }
    }
    func testDefaultEmptyAndDisabledRewardAreNotRemovable() {
        var empty = TemplateAuthoringDraft(); empty.rewardEnabled = true
        XCTAssertFalse(TemplateRewardMedalRemoval(draft: empty).canRemove)
        XCTAssertNil(TemplateRewardMedalRemoval(draft: empty).applying(to: empty))
        var disabled = draft(); disabled.rewardEnabled = false
        XCTAssertFalse(TemplateRewardMedalRemoval(draft: disabled).canRemove)
        XCTAssertNil(TemplateRewardMedalRemoval(draft: draft()).applying(to: disabled))
    }
    func testChangedImageNameOrStyleAndCanonicalAliasRejectOldSnapshot() {
        var original = draft(); original.medalName = "caf\u{00E9}"
        let removal = TemplateRewardMedalRemoval(draft: original)
        for key in [\TemplateAuthoringDraft.medalImg, \.medalName, \.medalStyle] {
            var changed = original; changed[keyPath: key] = "replacement"
            XCTAssertNil(removal.applying(to: changed))
        }
        var changed = original; changed.medalName = "cafe\u{0301}"
        XCTAssertEqual(changed.medalName, original.medalName); XCTAssertNil(removal.applying(to: changed))
    }
    func testExistingPayloadAndRewardValidationRemainAuthoritative() throws {
        let original = draft(), removal = TemplateRewardMedalRemoval(draft: original)
        var changed = original; changed.feedbackText = "New feedback"
        let next = try XCTUnwrap(removal.applying(to: changed)), payload = try TemplateAuthoringContract.payload(next)
        XCTAssertEqual(payload["couponId"], .number(22)); XCTAssertEqual(payload["feedbackText"], .string("New feedback"))
        XCTAssertNil(payload["medalImg"]); XCTAssertNil(payload["medalName"]); XCTAssertNil(payload["medalStyle"])
        XCTAssertFalse(next.publishIssues.contains("templateAuthor.validation.reward"))
        var onlyMedal = original; onlyMedal.couponId = nil; onlyMedal.feedbackText = nil
        let emptyReward = try XCTUnwrap(TemplateRewardMedalRemoval(draft: onlyMedal).applying(to: onlyMedal))
        XCTAssertTrue(emptyReward.publishIssues.contains("templateAuthor.validation.reward"))
    }
}
