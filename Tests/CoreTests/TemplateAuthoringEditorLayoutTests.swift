import XCTest
@testable import QuestifyCore

/// 2026-11-19 主人：编辑页先放完成方式，选填项收进记住展开状态的「高级设置」；
/// 预览/发布按钮保持禁用，首个未填必填项在该字段下方显示红字。
final class TemplateAuthoringEditorLayoutTests: XCTestCase {
    private func complete() -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft(title: "Layout")
        draft.description = "Short"; draft.players = "1-2"; draft.duration = 10
        draft.categoryId = 4; draft.feedbackText = "Well done"
        return draft
    }

    func testAdvancedSettingsAreCollapsedByDefaultUnderOneRememberedKey() {
        XCTAssertEqual(TemplateAuthoringEditorLayout.advancedSettingsExpandedKey, "templateEditor.advancedSettingsExpanded")
        XCTAssertFalse(TemplateAuthoringEditorLayout.advancedSettingsExpandedDefault)
    }

    func testCompleteDraftHasNoFieldIssue() {
        let draft = complete()
        XCTAssertEqual(draft.publishIssues, [])
        XCTAssertNil(draft.firstPublishIssue)
    }

    func testBlankDraftPointsAtTitleFirst() {
        let draft = TemplateAuthoringDraft()
        XCTAssertEqual(draft.firstPublishIssue, TemplateAuthoringPublishIssue(key: "templateAuthor.validation.title", anchor: .field("title")))
    }

    func testFinishMethodFieldsComeBeforeBasicsBecauseTheyAreShownFirst() {
        var draft = TemplateAuthoringDraft(title: "Layout")
        draft.validationMethod = .text
        XCTAssertTrue(draft.publishIssues.contains("templateAuthor.validation.description"))
        XCTAssertEqual(draft.firstPublishIssue, TemplateAuthoringPublishIssue(key: "templateAuthor.validation.answer", anchor: .field("questionName")))
        draft.questionName = "Which tower?"
        XCTAssertEqual(draft.firstPublishIssue, TemplateAuthoringPublishIssue(key: "templateAuthor.validation.answer", anchor: .field("questionAnswer")))
        draft.questionAnswer = "Bell"
        XCTAssertEqual(draft.firstPublishIssue?.anchor, .metadata)

        var disabled = TemplateAuthoringDraft(title: "Layout")
        disabled.finishEnabled = false
        XCTAssertEqual(disabled.firstPublishIssue, TemplateAuthoringPublishIssue(key: "templateAuthor.validation.finish", anchor: .finish))
    }

    func testChoiceIssuesAnchorUnderTheirFields() {
        var draft = complete()
        draft.validationMethod = .choice
        XCTAssertEqual(draft.firstPublishIssue, TemplateAuthoringPublishIssue(key: "templateAuthor.validation.question", anchor: .field("questionName")))
        draft.questionName = "Pick one"
        XCTAssertEqual(draft.firstPublishIssue, TemplateAuthoringPublishIssue(key: "templateAuthor.validation.choices", anchor: .finish))
    }

    func testMetadataComesBeforeDescription() {
        var draft = complete()
        draft.players = nil; draft.description = ""
        XCTAssertEqual(draft.firstPublishIssue, TemplateAuthoringPublishIssue(key: "templateAuthor.validation.players", anchor: .metadata))
        draft.players = "1-2"
        XCTAssertEqual(draft.firstPublishIssue, TemplateAuthoringPublishIssue(key: "templateAuthor.validation.description", anchor: .field("description")))
        draft.description = String(repeating: "x", count: 31)
        XCTAssertEqual(draft.firstPublishIssue, TemplateAuthoringPublishIssue(key: "templateAuthor.validation.descriptionLength", anchor: .field("description")))
    }

    func testOptionalExtrasPointAtTheFoldedGroupLast() {
        var draft = complete()
        draft.feedbackText = nil
        XCTAssertEqual(draft.publishIssues, ["templateAuthor.validation.reward"])
        XCTAssertEqual(draft.firstPublishIssue, TemplateAuthoringPublishIssue(key: "templateAuthor.validation.reward", anchor: .advancedSettings))
        draft.description = ""
        XCTAssertEqual(draft.firstPublishIssue?.anchor, .field("description"))
        XCTAssertEqual(draft.issueAnchor(for: "templateAuthor.validation.medal"), .advancedSettings)
        XCTAssertEqual(draft.issueAnchor(for: "templateAuthor.validation.audio"), .advancedSettings)
        XCTAssertEqual(draft.issueAnchor(for: "templateStory.unsupported"), .advancedSettings)
    }

    func testUnknownAndGameIssuesStayInTheFinishSection() {
        let draft = complete()
        XCTAssertEqual(draft.issueAnchor(for: "creatorRoot.issue.example"), .finish)
        XCTAssertEqual(draft.issueAnchor(for: "templateAuthor.validation.correctAnswer"), .finish)
    }
}
