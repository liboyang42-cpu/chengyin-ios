import XCTest
@testable import Questify

/// Model/lifecycle tests only. These do not claim a rendered SwiftUI or device pass.
@MainActor final class MerchantNPCKnowledgeDraftViewTests: XCTestCase {
    private func harness() async -> (MerchantOperationsViewModel, MerchantOperationsFixtureReader, MerchantNPCKnowledgeDraftModel) {
        let reader = MerchantOperationsFixtureReader()
        let document = MerchantOperationsViewModel(reader: reader, destination: .character)
        await document.load()
        return (document, reader, MerchantNPCKnowledgeDraftModel(document: document))
    }
    private var localDraft: MerchantNPCKnowledgeDraft {
        var value = MerchantNPCKnowledgeDraft()
        value.faq = [.init(question: "Synthetic opening question", answer: "Synthetic local answer")]
        return value
    }
    func testStructuredKnowledgeIsSeparateFromLegacyNPCDraftAndNeverSent() async {
        let (document, reader, model) = await harness()
        let before = document.coordinator.draft
        await model.open(); XCTAssertTrue(model.coordinator.draft.isEmpty)
        model.edit(localDraft); await model.save()
        XCTAssertTrue(model.coordinator.savedThisEdit)
        XCTAssertEqual(document.coordinator.draft, before); XCTAssertFalse(document.coordinator.isDirty)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testCancelDiscardsUnsavedEditsAndReopenRestoresOnlyMemoryCopy() async {
        let (document, reader, model) = await harness()
        await model.open(); model.edit(localDraft); await model.save()
        var other = localDraft; other.faq[0].answer = "Unsaved"
        model.edit(other); model.cancel(); await model.open()
        XCTAssertEqual(model.coordinator.draft.faq.first?.answer, "Synthetic local answer")
        XCTAssertTrue(document.coordinator.isCurrent); XCTAssertEqual(reader.saveCount, 0)
    }
    func testParentReloadInvalidatesOldEditorEvenWithSameValuesAndAccount() async {
        let (document, reader, model) = await harness()
        await model.open(); model.edit(localDraft); await document.load(); await model.save()
        XCTAssertFalse(model.coordinator.canEdit); XCTAssertNil(model.coordinator.savedDraft)
        XCTAssertTrue(model.coordinator.draft.isEmpty); XCTAssertEqual(reader.saveCount, 0)
    }
    func testSignOutAndAccountChangeCannotSaveOldMemory() async {
        let (document, reader, model) = await harness()
        await model.open(); model.edit(localDraft); await model.save()
        reader.switchAccount(); await model.save()
        XCTAssertNil(model.coordinator.savedDraft); XCTAssertTrue(model.coordinator.draft.isEmpty)
        XCTAssertFalse(document.coordinator.isCurrent); XCTAssertEqual(reader.saveCount, 0)
    }
    func testLeavingPageOrBackgroundClearsPreviouslySavedMemory() async {
        let (document, reader, model) = await harness()
        await model.open(); model.edit(localDraft); await model.save(); model.invalidate()
        XCTAssertNil(model.coordinator.savedDraft); XCTAssertTrue(model.coordinator.draft.isEmpty)
        await model.open(); XCTAssertTrue(model.coordinator.draft.isEmpty)
        XCTAssertTrue(document.coordinator.isCurrent); XCTAssertEqual(reader.saveCount, 0)
    }
    func testParentReviewOrOtherDestinationCannotOpenDraftEditor() async {
        let (document, reader, model) = await harness()
        guard case .character(var value) = document.coordinator.draft else { return XCTFail() }
        value.greeting = "Changed"; document.edit(.character(value)); document.prepare()
        XCTAssertNotNil(document.coordinator.confirmation)
        await model.open(); XCTAssertFalse(model.coordinator.canEdit)
        let other = MerchantOperationsViewModel(reader: reader, destination: .profile)
        await other.load(); let otherModel = MerchantNPCKnowledgeDraftModel(document: other)
        await otherModel.open(); XCTAssertFalse(otherModel.coordinator.canEdit)
        XCTAssertEqual(reader.saveCount, 0)
    }
}
