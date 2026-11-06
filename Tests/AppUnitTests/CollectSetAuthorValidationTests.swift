import Foundation
import XCTest
@testable import Questify

@MainActor final class CollectSetAuthorValidationTests: XCTestCase {
    private func draft() -> ProjectEditDraft {
        var value = ProjectEditSyntheticFixtures.draft()
        value.chapters[0].nodes[0].localMetadata["id"] = .number(31)
        return value
    }
    func testNewEmptySetExplainsBothRequiredInputsWithoutWriting() {
        let original = draft(), before = ProjectEditPendingMaterials.exactData(original)
        let check = CollectSetAuthorValidation(values: [.init(key: "new", title: "", nodeIds: [])], draft: original)
        XCTAssertEqual(check.rows, [[.titleRequired, .nodesRequired]])
        XCTAssertFalse(check.canSave)
        XCTAssertFalse(check.hasUnexplainedFailure)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(original), before)
    }
    func testUTF16LimitMatchesOriginalValidatorWithoutTruncatingInput() {
        let exact = String(repeating: "😀", count: 60)
        let over = exact + "x"
        let valid = CollectSetAuthorDefinition(key: "one", title: exact, nodeIds: [31])
        let invalid = CollectSetAuthorDefinition(key: "one", title: over, nodeIds: [31])
        XCTAssertTrue(CollectSetAuthorValidation(values: [valid], draft: draft()).canSave)
        let check = CollectSetAuthorValidation(values: [invalid], draft: draft())
        XCTAssertEqual(check.rows, [[.titleTooLong]])
        XCTAssertFalse(check.canSave)
        XCTAssertEqual(invalid.title, over)
        XCTAssertThrowsError(try CollectSetAuthoring.applying([invalid], to: draft()))
    }
    func testNodeSelectionLimitsAndRecoveryRemainDistinct() {
        let allowed = Set(1...201)
        XCTAssertEqual(CollectSetAuthorValidation.issues(.init(key: "a", title: "A", nodeIds: Array(1...200)), available: allowed), [])
        XCTAssertEqual(CollectSetAuthorValidation.issues(.init(key: "a", title: "A", nodeIds: Array(1...201)), available: allowed), [.tooManyNodes])
        XCTAssertEqual(CollectSetAuthorValidation.issues(.init(key: "a", title: "A", nodeIds: [1, 1]), available: allowed), [.duplicateNodes])
        XCTAssertEqual(CollectSetAuthorValidation.issues(.init(key: "a", title: "A", nodeIds: [999]), available: allowed), [.missingNodes])
    }
    func testWholeGraphFailuresStillUseTheOriginalValidator() {
        let row = CollectSetAuthorDefinition(key: "same", title: "A", nodeIds: [31])
        let duplicate = CollectSetAuthorValidation(values: [row, row], draft: draft())
        XCTAssertFalse(duplicate.canSave)
        XCTAssertTrue(duplicate.hasUnexplainedFailure)
        var ambiguous = draft(); ambiguous.preserved["routeGraphJson"] = .string("{\"collectSets\":[],\"collectSets\":[]}")
        XCTAssertFalse(CollectSetAuthorValidation(values: [], draft: ambiguous).canSave)
    }
    func testValidEditsAndRemovingAllGroupsRemainSaveable() {
        XCTAssertTrue(CollectSetAuthorValidation(values: [], draft: draft()).canSave)
        let row = CollectSetAuthorDefinition(key: "a", title: "Valid", nodeIds: [31])
        let result = CollectSetAuthorValidation(values: [row], draft: draft())
        XCTAssertTrue(result.canSave)
        XCTAssertEqual(result.rows, [[]])
        XCTAssertFalse(result.hasUnexplainedFailure)
    }
    func testIssueCopyExistsInBothLanguages() {
        for issue in [CollectSetAuthorValidation.Issue.titleRequired, .titleTooLong, .nodesRequired, .tooManyNodes, .duplicateNodes, .missingNodes, .invalidKey] {
            let en = CollectSetAuthorValidation.text(issue.key, locale: Locale(identifier: "en"))
            let zh = CollectSetAuthorValidation.text(issue.key, locale: Locale(identifier: "zh-Hans"))
            XCTAssertNotEqual(en, issue.key); XCTAssertNotEqual(zh, issue.key); XCTAssertNotEqual(en, zh)
        }
    }
}
