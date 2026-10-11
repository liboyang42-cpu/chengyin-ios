import Foundation
import XCTest
@testable import QuestifyCore

final class MerchantTemplateParticipationPlanTests: XCTestCase {
    private func plan() -> MerchantTemplateParticipationPlan {
        var value = MerchantTemplateParticipationPlan()
        value.durationMinutes = "15"; value.maximumParticipants = "6"; value.staffing = .staffRequired
        return value
    }
    private func template() throws -> MerchantNodeTemplate {
        try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(MerchantOperationsFixtureData.templateJSON.utf8))
    }
    func testBlankPlanRequiresEveryFieldAndDoesNotAssumeNoEmployee() {
        var value = MerchantTemplateParticipationPlan()
        XCTAssertEqual(value.blocker, "merchant.participation.durationInvalid")
        value.durationMinutes = "15"
        XCTAssertEqual(value.blocker, "merchant.participation.capacityInvalid")
        value.maximumParticipants = "6"
        XCTAssertEqual(value.blocker, "merchant.participation.staffingRequired")
        value.staffing = .selfGuided; XCTAssertNil(value.blocker)
        value.staffing = .staffRequired; XCTAssertNil(value.blocker)
    }
    func testCountsRejectFractionsSignsZeroOverflowAndNonASCIIInput() {
        for invalid in ["", " ", "0", "-1", "+1", "1.5", "1e2", "1 0", "１２", "∞", String(repeating: "9", count: 30)] {
            XCTAssertNil(MerchantTemplateParticipationPlan.positiveInteger(invalid), invalid)
            var value = plan(); value.durationMinutes = invalid
            XCTAssertEqual(value.blocker, "merchant.participation.durationInvalid", invalid)
            value = plan(); value.maximumParticipants = invalid
            XCTAssertEqual(value.blocker, "merchant.participation.capacityInvalid", invalid)
        }
        XCTAssertEqual(MerchantTemplateParticipationPlan.positiveInteger(" \n15 \t"), 15)
        XCTAssertEqual(MerchantTemplateParticipationPlan.positiveInteger("01"), 1)
        XCTAssertEqual(MerchantTemplateParticipationPlan.positiveInteger(String(Int.max)), Int.max)
    }
    func testLegacyServerDecodeDoesNotInventParticipationFacts() throws {
        let value = try template()
        XCTAssertNil(value.participationPlan); XCTAssertNil(value.blocker)
        let forged = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(#"{"title":"Example","validationMethod":2,"participationPlan":{"durationMinutes":"15","maximumParticipants":"6","staffing":"selfGuided"}}"#.utf8))
        XCTAssertNil(forged.participationPlan)
        var created = MerchantNodeTemplate(); created.title = "New merchant plan"; created.method = .photo
        created.participationPlan = .init()
        XCTAssertEqual(created.blocker, "merchant.participation.durationInvalid")
        created.participationPlan = plan(); XCTAssertNil(created.blocker)
        XCTAssertTrue(MerchantOperationsDraft.template(created).localOnlyReview)
    }
    func testLocalPlanNeverChangesLegacyPayloadAndCannotMakeRequestPreview() throws {
        var value = try template()
        let before = try JSONSerialization.data(withJSONObject: value.fields, options: .sortedKeys)
        XCTAssertFalse(MerchantOperationsDraft.template(value).localOnlyReview)
        XCTAssertNoThrow(try MerchantOperationsDraft.template(value).previews())
        value.participationPlan = plan()
        XCTAssertNil(value.blocker)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: value.fields, options: .sortedKeys), before)
        XCTAssertEqual(value.couponID, 19)
        XCTAssertTrue(MerchantOperationsDraft.template(value).localOnlyReview)
        XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews()) {
            XCTAssertEqual($0 as? MerchantOperationsFailure, .liveWritesDisabled)
        }
        value.participationPlan = nil
        XCTAssertNoThrow(try MerchantOperationsDraft.template(value).previews())
    }
    func testAISuggestionMergeRetainsMerchantPlanAndCannotProvideOne() throws {
        var value = try template(); value.participationPlan = plan()
        let result = try MerchantTemplateAssistResult(.object([
            "questionName": .string("New question"), "durationMinutes": .string("1"),
            "maximumParticipants": .string("999"), "staffing": .string("selfGuided")
        ]))
        let merged = result.merge(into: value, captured: value, edits: .init(), capturedEdits: .init())
        XCTAssertEqual(merged.participationPlan, value.participationPlan)
        XCTAssertTrue(result.unsupportedKeys.contains("durationMinutes"))
        XCTAssertTrue(result.unsupportedKeys.contains("maximumParticipants"))
        XCTAssertTrue(result.unsupportedKeys.contains("staffing"))
    }
    @MainActor func testLocalPlanRequiresValidationThenFreezesAndCancelsOnEdit() async throws {
        let reader = MerchantOperationsFixtureReader()
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load()
        var value = try template(); value.participationPlan = .init()
        coordinator.edit(.template(value)); XCTAssertTrue(coordinator.isDirty); XCTAssertFalse(coordinator.canReview)
        coordinator.prepare(); XCTAssertNil(coordinator.confirmation)
        value.participationPlan = plan(); coordinator.edit(.template(value)); XCTAssertTrue(coordinator.canReview)
        coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        XCTAssertEqual(review.draft, .template(value))
        coordinator.cancelConfirmation(); XCTAssertEqual(coordinator.draft, .template(value)); XCTAssertTrue(coordinator.isDirty)
        coordinator.prepare(); XCTAssertNotNil(coordinator.confirmation)
        value.participationPlan?.durationMinutes = "20"; coordinator.edit(.template(value))
        XCTAssertNil(coordinator.confirmation)
        if case .template(let snapshot) = review.draft { XCTAssertEqual(snapshot.participationPlan?.durationMinutes, "15") }
        else { XCTFail("Expected template snapshot") }
        await coordinator.confirm(review); XCTAssertEqual(reader.saveCount, 0)
    }
    @MainActor func testLocalReviewCannotDispatchEvenWhenReaderCanSave() async throws {
        let reader = MerchantOperationsFixtureReader()
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); XCTAssertTrue(reader.canSave)
        var value = try template(); value.participationPlan = plan(); coordinator.edit(.template(value))
        coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        let accessReads = reader.accessCount
        await coordinator.confirm(review); await coordinator.confirm(review)
        XCTAssertEqual(reader.saveCount, 0); XCTAssertEqual(reader.accessCount, accessReads)
        XCTAssertEqual(coordinator.issue, .key("merchant.participation.localOnly"))
        XCTAssertFalse(coordinator.isLocked); XCTAssertFalse(coordinator.exampleSaved)
        XCTAssertEqual(coordinator.draft, .template(value)); XCTAssertTrue(coordinator.isDirty)
    }
    @MainActor func testDiscardReloadAndSessionReplacementRemoveLocalPlan() async throws {
        let reader = MerchantOperationsFixtureReader()
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load()
        var value = try template(); value.participationPlan = plan()
        coordinator.edit(.template(value)); coordinator.discardChanges()
        XCTAssertEqual(coordinator.draft, .template(try template())); XCTAssertFalse(coordinator.isDirty)
        coordinator.edit(.template(value)); await coordinator.load()
        XCTAssertEqual(coordinator.draft, .template(try template())); XCTAssertFalse(coordinator.isDirty)
        coordinator.edit(.template(value)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        reader.switchAccount(); await coordinator.confirm(review)
        XCTAssertEqual(reader.saveCount, 0); XCTAssertFalse(coordinator.canReview)
        coordinator.leaveScreen(); XCTAssertNil(coordinator.draft); XCTAssertNil(coordinator.confirmation)
    }
}
