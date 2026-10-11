import XCTest
@testable import QuestifyCore

final class TemplateRewardKindsTests: XCTestCase {
    private func filled() -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft(title: "Reward types")
        draft.rewardEnabled = true; draft.couponId = 42; draft.feedbackText = "Well done"
        draft.medalName = "Explorer"; draft.medalImg = "custom:medal"; draft.medalStyle = "enamel"
        draft.storyText = "Keep story"; draft.audioUrl = "keep audio"
        return draft
    }
    func testInferenceMatchesExistingStoredValuesWithoutMutation() {
        let original = filled(), before = original
        XCTAssertEqual(TemplateRewardKinds.inferred(from: original), [.coupon, .feedback, .medal])
        XCTAssertEqual(original, before)
        XCTAssertTrue(TemplateRewardKinds.inferred(from: .init()).isEmpty)
    }
    func testPartialAndWhitespaceValuesRemainPresentWhileStyleOnlyDoesNotReviveMedal() {
        var draft = TemplateAuthoringDraft(); draft.couponId = -2; draft.feedbackText = " \n"; draft.medalName = "Name only"
        draft.medalStyle = "unknown-style"
        XCTAssertEqual(TemplateRewardKinds.inferred(from: draft), [.feedback, .medal])
        draft.medalName = nil
        XCTAssertEqual(TemplateRewardKinds.inferred(from: draft), [.feedback])
        XCTAssertEqual(draft.couponId, -2); XCTAssertEqual(draft.medalStyle, "unknown-style")
    }
    func testEachOffSwitchClearsOnlyItsOwnContent() throws {
        let original = filled()
        for kind in TemplateRewardKind.allCases {
            var expected = original
            switch kind { case .coupon: expected.couponId = nil; case .feedback: expected.feedbackText = nil; case .medal: expected.medalImg = nil; expected.medalName = nil }
            let next = try XCTUnwrap(TemplateRewardKinds.disabling(kind, in: original))
            XCTAssertEqual(next, expected); XCTAssertTrue(next.rewardEnabled)
            XCTAssertEqual(next.medalStyle, "enamel")
        }
    }
    func testDisabledModuleCannotBeChangedByARewardTypeCallback() {
        var draft = filled(); draft.rewardEnabled = false
        for kind in TemplateRewardKind.allCases { XCTAssertNil(TemplateRewardKinds.disabling(kind, in: draft)) }
    }
    func testTurningAllKindsOffPreservesModuleAndExistingValidation() throws {
        var draft = filled()
        for kind in TemplateRewardKind.allCases { draft = try XCTUnwrap(TemplateRewardKinds.disabling(kind, in: draft)) }
        XCTAssertTrue(draft.rewardEnabled); XCTAssertTrue(TemplateRewardKinds.inferred(from: draft).isEmpty)
        XCTAssertTrue(draft.publishIssues.contains("templateAuthor.validation.reward"))
        XCTAssertEqual(draft.medalStyle, "enamel")
    }
    func testExistingPayloadIncludesRemainingKindsAndLocalEnvelopeRestoresTheirInference() throws {
        let draft = try XCTUnwrap(TemplateRewardKinds.disabling(.medal, in: filled()))
        let payload = try TemplateAuthoringContract.payload(draft)
        XCTAssertEqual(payload["couponId"], .number(42)); XCTAssertEqual(payload["feedbackText"], .string("Well done"))
        XCTAssertNil(payload["medalImg"]); XCTAssertNil(payload["medalName"]); XCTAssertNil(payload["medalStyle"])
        let restored = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored, draft); XCTAssertEqual(TemplateRewardKinds.inferred(from: restored), [.coupon, .feedback])
    }
}
