import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class MerchantNPCKnowledgeDismissalTests: XCTestCase {
    private struct Fixture {
        let document: MerchantOperationsViewModel
        let reader: MerchantOperationsFixtureReader
        let model: MerchantNPCKnowledgeDraftModel
    }
    private func fixture() async -> Fixture {
        let reader = MerchantOperationsFixtureReader()
        let document = MerchantOperationsViewModel(reader: reader, destination: .character); await document.load()
        let model = MerchantNPCKnowledgeDraftModel(document: document); await model.open()
        return .init(document: document, reader: reader, model: model)
    }
    private var draft: MerchantNPCKnowledgeDraft {
        var value = MerchantNPCKnowledgeDraft(); value.faq = [.init(question: "Synthetic question", answer: "Caf\u{00E9}")]; return value
    }
    func testCleanDraftClosesWithoutReviewOrRead() async {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        var guardrail = MerchantNPCKnowledgeDismissal(); let reads = f.reader.accessCount
        XCTAssertEqual(guardrail.prepare(f.model, isActive: true), .close); XCTAssertNil(guardrail.review)
        XCTAssertFalse(MerchantNPCKnowledgeDismissal.blocksInteractiveDismissal(f.model))
        XCTAssertEqual(f.reader.accessCount, reads); XCTAssertEqual(f.reader.saveCount, 0)
    }
    func testDirtyPrepareProtectsDraftWithoutReadingSavingOrCopyingTextIntoReview() async throws {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        f.model.edit(draft); let original = f.model.coordinator.draft; let revision = f.model.revision; let reads = f.reader.accessCount
        var guardrail = MerchantNPCKnowledgeDismissal()
        XCTAssertEqual(guardrail.prepare(f.model, isActive: true), .confirm)
        let review = try XCTUnwrap(guardrail.review)
        XCTAssertEqual(Set(Mirror(reflecting: review).children.compactMap(\.label)),
                       Set(["id", "owner", "scope", "revision", "draftFingerprint", "savedFingerprint"]))
        XCTAssertEqual(MerchantNPCKnowledgeDismissal.fingerprint(original).count, 32)
        XCTAssertTrue(MerchantNPCKnowledgeDismissal.blocksInteractiveDismissal(f.model))
        XCTAssertEqual(f.model.coordinator.draft, original); XCTAssertEqual(f.model.revision, revision)
        XCTAssertEqual(f.reader.accessCount, reads); XCTAssertEqual(f.reader.saveCount, 0)
    }
    func testKeepEditingRetainsDraftAndRevokesTheOldConfirmation() async throws {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        f.model.edit(draft); let original = f.model.coordinator.draft
        var guardrail = MerchantNPCKnowledgeDismissal(); _ = guardrail.prepare(f.model, isActive: true)
        let review = try XCTUnwrap(guardrail.review); guardrail.keepEditing()
        XCTAssertFalse(guardrail.discard(review, model: f.model, isActive: true))
        XCTAssertEqual(f.model.coordinator.draft, original); XCTAssertTrue(f.model.coordinator.canEdit)
    }
    func testExplicitDiscardConsumesOneExactIntentWithoutExternalWrite() async throws {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        f.model.edit(draft); let reads = f.reader.accessCount
        var guardrail = MerchantNPCKnowledgeDismissal(); _ = guardrail.prepare(f.model, isActive: true)
        let review = try XCTUnwrap(guardrail.review)
        XCTAssertTrue(guardrail.discard(review, model: f.model, isActive: true))
        XCTAssertFalse(guardrail.discard(review, model: f.model, isActive: true))
        XCTAssertEqual(f.model.coordinator.phase, .closed); XCTAssertTrue(f.model.coordinator.draft.isEmpty)
        XCTAssertEqual(f.reader.accessCount, reads); XCTAssertEqual(f.reader.saveCount, 0)
    }
    func testLaterEditInvalidatesOldReview() async throws {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        f.model.edit(draft); var guardrail = MerchantNPCKnowledgeDismissal(); _ = guardrail.prepare(f.model, isActive: true)
        let review = try XCTUnwrap(guardrail.review); var changed = f.model.coordinator.draft
        changed.faq[0].answer = "New unsaved answer"; f.model.edit(changed)
        XCTAssertFalse(guardrail.discard(review, model: f.model, isActive: true))
        XCTAssertEqual(f.model.coordinator.draft.faq[0].answer, "New unsaved answer")
    }
    func testEditAndRestoreStillInvalidatesPriorRevision() async throws {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        f.model.edit(draft); let original = f.model.coordinator.draft
        var guardrail = MerchantNPCKnowledgeDismissal(); _ = guardrail.prepare(f.model, isActive: true)
        let review = try XCTUnwrap(guardrail.review); var changed = original; changed.faq[0].answer = "Temporary"
        f.model.edit(changed); f.model.edit(original)
        XCTAssertFalse(guardrail.discard(review, model: f.model, isActive: true)); XCTAssertTrue(f.model.coordinator.canEdit)
    }
    func testRawCanonicalChangeWithoutModelRevisionCannotUseOldReview() async throws {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        f.model.edit(draft); let revision = f.model.revision
        var guardrail = MerchantNPCKnowledgeDismissal(); _ = guardrail.prepare(f.model, isActive: true)
        let review = try XCTUnwrap(guardrail.review); var changed = f.model.coordinator.draft
        changed.faq[0].answer = "Cafe\u{0301}"; f.model.coordinator.edit(changed)
        XCTAssertEqual(f.model.revision, revision)
        XCTAssertFalse(guardrail.discard(review, model: f.model, isActive: true))
        XCTAssertTrue(f.model.coordinator.draft.faq[0].answer.utf8.elementsEqual("Cafe\u{0301}".utf8))
    }
    func testNewLocalSaveInvalidatesReviewEvenWithoutModelRevision() async throws {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        f.model.edit(draft); let revision = f.model.revision
        var guardrail = MerchantNPCKnowledgeDismissal(); _ = guardrail.prepare(f.model, isActive: true)
        let review = try XCTUnwrap(guardrail.review); await f.model.coordinator.saveLocally()
        XCTAssertEqual(f.model.revision, revision); XCTAssertNotNil(f.model.coordinator.savedDraft)
        XCTAssertFalse(guardrail.discard(review, model: f.model, isActive: true)); XCTAssertTrue(f.model.coordinator.canEdit)
    }
    func testReviewCannotDiscardAnotherModelUnderSameDocument() async throws {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        f.model.edit(draft); var guardrail = MerchantNPCKnowledgeDismissal(); _ = guardrail.prepare(f.model, isActive: true)
        let review = try XCTUnwrap(guardrail.review)
        let other = MerchantNPCKnowledgeDraftModel(document: f.document); await other.open(); other.edit(f.model.coordinator.draft)
        XCTAssertFalse(guardrail.discard(review, model: other, isActive: true))
        XCTAssertFalse(other.coordinator.draft.isEmpty); XCTAssertFalse(f.model.coordinator.draft.isEmpty)
    }
    func testScopeLossNeverBlocksPrivacyClosureOrAllowsOldDiscard() async throws {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        f.model.edit(draft); var guardrail = MerchantNPCKnowledgeDismissal(); _ = guardrail.prepare(f.model, isActive: true)
        let review = try XCTUnwrap(guardrail.review); f.reader.switchAccount()
        XCTAssertFalse(MerchantNPCKnowledgeDismissal.blocksInteractiveDismissal(f.model))
        XCTAssertFalse(guardrail.discard(review, model: f.model, isActive: true))
        XCTAssertEqual(guardrail.prepare(f.model, isActive: true), .close)
        f.model.invalidate(); XCTAssertTrue(f.model.coordinator.draft.isEmpty); XCTAssertNil(f.model.coordinator.savedDraft)
    }
    func testBackgroundBlocksForegroundReviewAndKeepsImmediatePrivacyInvalidation() async throws {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        f.model.edit(draft); var guardrail = MerchantNPCKnowledgeDismissal(); _ = guardrail.prepare(f.model, isActive: true)
        let review = try XCTUnwrap(guardrail.review)
        XCTAssertFalse(guardrail.discard(review, model: f.model, isActive: false))
        XCTAssertEqual(guardrail.prepare(f.model, isActive: false), .blocked); XCTAssertNil(guardrail.review)
        f.model.invalidate(); XCTAssertTrue(f.model.coordinator.draft.isEmpty); XCTAssertNil(f.model.coordinator.savedDraft)
    }
    func testDiscardRetainsOnlyExistingSavedCopyForNormalReopen() async throws {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        f.model.edit(draft); await f.model.save(); let saved = try XCTUnwrap(f.model.coordinator.savedDraft)
        var changed = saved; changed.faq[0].answer = "Unsaved answer"; f.model.edit(changed)
        var guardrail = MerchantNPCKnowledgeDismissal(); _ = guardrail.prepare(f.model, isActive: true)
        XCTAssertTrue(guardrail.discard(try XCTUnwrap(guardrail.review), model: f.model, isActive: true))
        XCTAssertEqual(f.model.coordinator.savedDraft, saved)
        await f.model.open(); XCTAssertEqual(f.model.coordinator.draft, saved)
        XCTAssertFalse(MerchantNPCKnowledgeDismissal.requiresConfirmation(f.model)); XCTAssertEqual(f.reader.saveCount, 0)
    }
    func testCanonicallyEquivalentDirtyBytesStillNeedDismissalConfirmation() async throws {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        f.model.edit(draft); await f.model.save(); var changed = f.model.coordinator.draft
        changed.faq[0].answer = "Cafe\u{0301}"; f.model.edit(changed)
        XCTAssertFalse(f.model.coordinator.isDirty) // Existing Core save comparison is unchanged.
        XCTAssertTrue(MerchantNPCKnowledgeDismissal.requiresConfirmation(f.model))
        var guardrail = MerchantNPCKnowledgeDismissal(); XCTAssertEqual(guardrail.prepare(f.model, isActive: true), .confirm)
    }
    func testInvalidUnfinishedFieldsAreProtectedWithoutSaveValidation() async {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        var invalid = MerchantNPCKnowledgeDraft(); invalid.products = [.init(name: "", priceMinor: "not a price", currency: "?")]
        f.model.edit(invalid); XCTAssertFalse(invalid.validationIssues.isEmpty)
        var guardrail = MerchantNPCKnowledgeDismissal(); XCTAssertEqual(guardrail.prepare(f.model, isActive: true), .confirm)
        XCTAssertTrue(MerchantNPCKnowledgeDismissal.blocksInteractiveDismissal(f.model)); XCTAssertEqual(f.reader.saveCount, 0)
    }
    func testFingerprintsPreserveFieldFramingRowIdentityAndOrder() {
        var first = MerchantNPCKnowledgeDraft(); first.faq = [.init(question: "a", answer: "bc"), .init(question: "Second", answer: "Answer")]
        var split = first; split.faq[0].question = "ab"; split.faq[0].answer = "c"
        var reordered = first; reordered.faq.reverse()
        var newIdentity = first; newIdentity.faq[0] = .init(question: "a", answer: "bc")
        for value in [split, reordered, newIdentity] {
            XCTAssertNotEqual(MerchantNPCKnowledgeDismissal.fingerprint(first), MerchantNPCKnowledgeDismissal.fingerprint(value))
        }
    }
    func testNewCloseIntentInvalidatesTheOlderDialog() async throws {
        let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
        f.model.edit(draft); var guardrail = MerchantNPCKnowledgeDismissal(); _ = guardrail.prepare(f.model, isActive: true)
        let older = try XCTUnwrap(guardrail.review); _ = guardrail.prepare(f.model, isActive: true)
        XCTAssertNotEqual(older.id, guardrail.review?.id)
        XCTAssertFalse(guardrail.discard(older, model: f.model, isActive: true)); XCTAssertTrue(f.model.coordinator.canEdit)
    }
    func testBusyLocalSaveBlocksVoluntaryCloseButNeverRevocation() async throws {
        let reader = GateReader(); let document = MerchantOperationsViewModel(reader: reader, destination: .character); await document.load()
        defer { withExtendedLifetime(document) {} }
        let model = MerchantNPCKnowledgeDraftModel(document: document); await model.open(); model.edit(draft)
        let started = expectation(description: "Local authorization check started"); reader.onHold = { started.fulfill() }; reader.hold = true
        let save = Task { await model.save() }; await fulfillment(of: [started], timeout: 1)
        var guardrail = MerchantNPCKnowledgeDismissal()
        XCTAssertEqual(model.coordinator.phase, .saving); XCTAssertEqual(guardrail.prepare(model, isActive: true), .blocked)
        XCTAssertTrue(MerchantNPCKnowledgeDismissal.blocksInteractiveDismissal(model))
        reader.fixture.switchAccount()
        XCTAssertFalse(MerchantNPCKnowledgeDismissal.blocksInteractiveDismissal(model))
        XCTAssertEqual(guardrail.prepare(model, isActive: true), .close)
        model.invalidate(); reader.release(); await save.value
        XCTAssertTrue(model.coordinator.draft.isEmpty); XCTAssertNil(model.coordinator.savedDraft)
    }
    func testBilingualLargeTextSheetConstructionKeepsLegacyDraftAndNeverWrites() async {
        for locale in ["en", "zh-Hans"] {
            let f = await fixture(); defer { withExtendedLifetime(f.document) {} }
            let legacy = f.document.coordinator.draft; f.model.edit(draft)
            let host = UIHostingController(rootView: NavigationStack { MerchantNPCKnowledgeDraftView(model: f.model) }
                .environment(\.locale, Locale(identifier: locale)).dynamicTypeSize(.accessibility5))
            host.loadViewIfNeeded(); host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 568); host.view.layoutIfNeeded()
            XCTAssertEqual(f.document.coordinator.draft, legacy); XCTAssertEqual(f.reader.saveCount, 0)
        }
    }
    @MainActor private final class GateReader: MerchantOperationsReading {
        let fixture = MerchantOperationsFixtureReader(); var hold = false; var onHold: (() -> Void)?
        private var continuation: CheckedContinuation<Void, Never>?
        var scope: UUID { fixture.scope }; var isAuthenticated: Bool { fixture.isAuthenticated }
        var isConfigured: Bool { true }; var isOfflineExample: Bool { true }
        func access() async throws -> MerchantOperationsAccess {
            if hold { await withCheckedContinuation { continuation = $0; onHold?() } }
            return try await fixture.access()
        }
        func document(_ destination: MerchantOperationsDestination) async throws -> MerchantOperationsDocument { try await fixture.document(destination) }
        func saveExample(_ draft: MerchantOperationsDraft) async throws { try await fixture.saveExample(draft) }
        func release() { hold = false; let value = continuation; continuation = nil; value?.resume() }
    }
}
