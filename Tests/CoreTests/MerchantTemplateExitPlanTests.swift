import Foundation
import XCTest
@testable import QuestifyCore

final class MerchantTemplateExitPlanTests: XCTestCase {
    private func template() throws -> MerchantNodeTemplate {
        try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(MerchantOperationsFixtureData.templateJSON.utf8))
    }
    private func plan() -> MerchantTemplateExitPlan {
        var value = MerchantTemplateExitPlan()
        value.offlineAlternative = "Ask the host for the printed clue."
        value.failureExit = "Stop the activity and leave through the public entrance."
        return value
    }
    func testBothContingenciesRequireExplicitNonblankInstructions() {
        var value = MerchantTemplateExitPlan()
        XCTAssertEqual(value.blocker, "merchant.exitPlan.offlineRequired")
        value.offlineAlternative = " \n \t"; XCTAssertEqual(value.blocker, "merchant.exitPlan.offlineRequired")
        value.offlineAlternative = plan().offlineAlternative
        XCTAssertEqual(value.blocker, "merchant.exitPlan.exitRequired")
        value.failureExit = " \n"; XCTAssertEqual(value.blocker, "merchant.exitPlan.exitRequired")
        value.failureExit = plan().failureExit; XCTAssertNil(value.blocker)
    }
    func testTextBoundUsesUTF16AndNeverSilentlyTruncatesInstructions() {
        var value = plan()
        value.offlineAlternative = String(repeating: "a", count: 600); XCTAssertNil(value.blocker)
        value.offlineAlternative += "a"; XCTAssertEqual(value.blocker, "merchant.exitPlan.textLimit")
        XCTAssertEqual(value.offlineAlternative.count, 601)
        value = plan(); value.failureExit = String(repeating: "🧭", count: 300); XCTAssertNil(value.blocker)
        value.failureExit += "🧭"; XCTAssertEqual(value.blocker, "merchant.exitPlan.textLimit")
        XCTAssertEqual(value.failureExit.utf16.count, 602)
    }
    func testNewAndDecodedTemplatesNeverInventExitPlanOrAcceptServerInjection() throws {
        var created = MerchantNodeTemplate(); created.title = "New template"; created.method = .photo
        XCTAssertNil(created.exitPlan); XCTAssertNil(created.blocker)
        created.exitPlan = plan(); XCTAssertNil(created.blocker)
        XCTAssertTrue(MerchantOperationsDraft.template(created).localOnlyReview)
        let existing = try template(); XCTAssertNil(existing.exitPlan)
        let injected = try JSONDecoder().decode(MerchantNodeTemplate.self, from: Data(#"{"title":"Example","validationMethod":2,"exitPlan":{"offlineAlternative":"AI promises offline access","failureExit":"AI promises a refund"}}"#.utf8))
        XCTAssertNil(injected.exitPlan)
    }
    func testExitPlanIsIndependentAndEitherLocalGroupBlocksTransport() throws {
        var value = try template()
        let original = try JSONSerialization.data(withJSONObject: value.fields, options: .sortedKeys)
        value.exitPlan = plan(); XCTAssertNil(value.participationPlan); XCTAssertNil(value.blocker)
        XCTAssertTrue(MerchantOperationsDraft.template(value).localOnlyReview)
        XCTAssertEqual(try JSONSerialization.data(withJSONObject: value.fields, options: .sortedKeys), original)
        XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews()) {
            XCTAssertEqual($0 as? MerchantOperationsFailure, .liveWritesDisabled)
        }
        var participation = MerchantTemplateParticipationPlan()
        participation.durationMinutes = "15"; participation.maximumParticipants = "6"; participation.staffing = .selfGuided
        value.participationPlan = participation; value.exitPlan = nil
        XCTAssertTrue(MerchantOperationsDraft.template(value).localOnlyReview)
        XCTAssertThrowsError(try MerchantOperationsDraft.template(value).previews())
        value.participationPlan = nil
        XCTAssertFalse(MerchantOperationsDraft.template(value).localOnlyReview)
        XCTAssertNoThrow(try MerchantOperationsDraft.template(value).previews())
    }
    func testAIResultCannotFillOrReplaceExitInstructions() throws {
        var value = try template(); value.exitPlan = plan()
        let result = try MerchantTemplateAssistResult(.object([
            "questionName": .string("Generated question"), "offlineAlternative": .string("Keep playing offline"),
            "failureExit": .string("Automatic refund"), "exitPlan": .object(["approved": .bool(true)])
        ]))
        let merged = result.merge(into: value, captured: value, edits: .init(), capturedEdits: .init())
        XCTAssertEqual(merged.exitPlan, value.exitPlan)
        XCTAssertTrue(result.unsupportedKeys.contains("offlineAlternative"))
        XCTAssertTrue(result.unsupportedKeys.contains("failureExit"))
        XCTAssertTrue(result.unsupportedKeys.contains("exitPlan"))
    }
    @MainActor func testReviewRetainsImmutableInstructionsAndEditInvalidatesIt() async throws {
        let reader = MerchantOperationsFixtureReader()
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var value = try template(); value.exitPlan = .init()
        coordinator.edit(.template(value)); XCTAssertTrue(coordinator.isDirty); XCTAssertFalse(coordinator.canReview)
        coordinator.prepare(); XCTAssertNil(coordinator.confirmation)
        value.exitPlan = plan(); coordinator.edit(.template(value)); coordinator.prepare()
        let review = try XCTUnwrap(coordinator.confirmation)
        coordinator.cancelConfirmation(); XCTAssertEqual(coordinator.draft, .template(value))
        coordinator.prepare(); XCTAssertNotNil(coordinator.confirmation)
        value.exitPlan?.failureExit = "Pause and ask the host for the marked public exit."
        coordinator.edit(.template(value)); XCTAssertNil(coordinator.confirmation)
        if case .template(let frozen) = review.draft { XCTAssertEqual(frozen.exitPlan, plan()) }
        else { XCTFail("Expected frozen merchant template") }
        await coordinator.confirm(review); XCTAssertEqual(reader.saveCount, 0)
    }
    @MainActor func testLocalExitReviewCannotReadOrSendAndDiscardRemovesIt() async throws {
        let reader = MerchantOperationsFixtureReader()
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(71))
        await coordinator.load(); var value = try template(); value.exitPlan = plan()
        coordinator.edit(.template(value)); coordinator.prepare(); let review = try XCTUnwrap(coordinator.confirmation)
        let readCount = reader.accessCount
        await coordinator.confirm(review); await coordinator.confirm(review)
        XCTAssertEqual(reader.accessCount, readCount); XCTAssertEqual(reader.saveCount, 0)
        XCTAssertFalse(coordinator.exampleSaved); XCTAssertFalse(coordinator.isLocked)
        XCTAssertEqual(coordinator.issue, .key("merchant.participation.localOnly"))
        coordinator.discardChanges(); XCTAssertEqual(coordinator.draft, .template(try template()))
        coordinator.edit(.template(value)); await coordinator.load()
        XCTAssertEqual(coordinator.draft, .template(try template()))
        coordinator.edit(.template(value)); reader.switchAccount(); coordinator.prepare()
        XCTAssertFalse(coordinator.canReview); coordinator.leaveScreen(); XCTAssertNil(coordinator.draft)
    }
}
