import XCTest
@testable import Questify

@MainActor private final class SuggestionEditAppClient: MerchantTemplateAssistServing {
    var session: PublishingSession? = .init(namespace: "synthetic", accountID: 901, epoch: UUID(), role: "merchant", region: .china)
    var canGenerate = true
    func generate(_ input: MerchantTemplateAssistInput) async throws -> MerchantTemplateAssistResult {
        try .init(.object(["title": .string("Generated title"), "questionName": .string("Generated question")]))
    }
    func cancel() {}
}
@MainActor final class MerchantTemplateSuggestionEditAppTests: XCTestCase {
    private func setup() async throws -> (MerchantOperationsViewModel, MerchantOperationsFixtureReader, MerchantTemplateAssistFlow, MerchantTemplateSuggestionEditModel) {
        let reader = MerchantOperationsFixtureReader()
        let actual = MerchantOperationsViewModel(reader: reader, destination: .template(nil)); await actual.load()
        let flow = MerchantTemplateAssistFlow(coordinator: actual.coordinator, client: SuggestionEditAppClient())
        flow.shopName = "Synthetic shop"; flow.prompt = "Synthetic activity"; await flow.generate()
        let review = try XCTUnwrap(flow.visibleReview), suggestion = try XCTUnwrap(flow.visibleReview?.suggestions.first(where: { $0.field == .title }))
        let edit = try XCTUnwrap(flow.prepareSuggestionEdit(review.action(for: suggestion)))
        return (actual, reader, flow, .init(flow: flow, edit: edit))
    }
    func testCancellingDoesNotChangeCandidateOrActualDraft() async throws {
        let (document, reader, flow, model) = try await setup(); let before = document.coordinator.draft
        model.update("Unsaved human wording"); model.cancel()
        XCTAssertNil(model.edit); XCTAssertFalse(model.save())
        XCTAssertEqual(document.coordinator.draft, before)
        XCTAssertEqual(flow.visibleReview?.suggestions.first(where: { $0.field == .title })?.proposed, "Generated title")
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testSaveChangesOnlySuggestionAndRetainsGeneratedTextForComparison() async throws {
        let (document, reader, flow, model) = try await setup(); let before = document.coordinator.draft
        XCTAssertFalse(model.canSave); model.update("Human wording"); XCTAssertTrue(model.canSave); XCTAssertTrue(model.save())
        XCTAssertNil(model.edit); XCTAssertFalse(model.save()); XCTAssertEqual(document.coordinator.draft, before)
        let suggestion = try XCTUnwrap(flow.visibleReview?.suggestions.first(where: { $0.field == .title }))
        XCTAssertEqual(suggestion.generated, "Generated title"); XCTAssertEqual(suggestion.proposed, "Human wording"); XCTAssertTrue(suggestion.isEdited)
        XCTAssertEqual(reader.saveCount, 0)
    }
    func testParentReloadMakesOldEditorUnableToCommit() async throws {
        let (document, reader, _, model) = try await setup()
        model.update("Old edit"); await document.load()
        XCTAssertFalse(model.isCurrent); XCTAssertFalse(model.canSave); XCTAssertFalse(model.save()); XCTAssertEqual(reader.saveCount, 0)
    }
    func testNoOpAndInvalidTextCannotBeSaved() async throws {
        let (document, reader, _, model) = try await setup(); let before = document.coordinator.draft
        model.update(" Generated title\n"); XCTAssertFalse(model.canSave); XCTAssertFalse(model.save())
        model.update("  "); XCTAssertEqual(model.edit?.issue, .empty); XCTAssertFalse(model.canSave)
        model.update("Text\u{0000}"); XCTAssertEqual(model.edit?.issue, .controls); XCTAssertFalse(model.save())
        XCTAssertEqual(document.coordinator.draft, before); XCTAssertEqual(reader.saveCount, 0)
    }
}
