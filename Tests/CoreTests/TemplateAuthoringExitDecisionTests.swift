import XCTest
@testable import QuestifyCore

final class TemplateAuthoringExitDecisionTests: XCTestCase {
    private func ready(_ draft: TemplateAuthoringDraft) throws -> TemplateAuthoringRestore {
        .ready(.init(session: try .init(accountID: 999, namespace: "exit", epoch: 1, authorizationRevision: "member"), identity: .init(), draft: draft))
    }
    private func state(_ draft: TemplateAuthoringDraft, _ checkpoint: TemplateAuthoringRestore) -> TemplateAuthoringExitDecision.Status { TemplateAuthoringExitDecision(draft: draft, checkpoint: checkpoint).status }
    func testExactEmptyDefaultWithoutRecordIsClean() { XCTAssertEqual(state(.init(), .missing), .clean) }
    func testAnyUnsavedDraftContentRequiresReviewEvenWithoutTitle() {
        var draft = TemplateAuthoringDraft(); draft.questionName = "Question"; XCTAssertEqual(state(draft, .missing), .unsaved)
        draft = .init(); draft.advanced.value["future"] = .bool(true); XCTAssertEqual(state(draft, .missing), .unsaved)
    }
    func testExactStoredDraftIsCleanIncludingUnknownFields() throws {
        var draft = TemplateAuthoringDraft(title: "Saved"); draft.advanced.value["future"] = .object(["x": .string("keep")]); XCTAssertEqual(state(draft, try ready(draft)), .clean)
    }
    func testChangesAfterLocalSaveNeedReview() throws {
        let saved = TemplateAuthoringDraft(title: "Saved"); var changed = saved; changed.title = "Changed"; XCTAssertEqual(state(changed, try ready(saved)), .unsaved)
    }
    func testCanonicallyEquivalentUnicodeStillUsesExactStoredBytes() throws {
        let saved = TemplateAuthoringDraft(title: "\u{00E9}"); var changed = saved; changed.title = "e\u{0301}"; XCTAssertEqual(state(changed, try ready(saved)), .unsaved)
    }
    func testMissingAndEmptyOptionalFieldsAreDistinct() throws {
        let saved = TemplateAuthoringDraft(); var changed = saved; changed.questionName = ""; XCTAssertEqual(state(changed, try ready(saved)), .unsaved)
    }
    func testArrayOrderIsPartOfCheckpoint() throws {
        var saved = TemplateAuthoringDraft(); saved.advanced.value["future"] = .array([.string("a"), .string("b")]); var changed = saved; changed.advanced.value["future"] = .array([.string("b"), .string("a")]); XCTAssertEqual(state(changed, try ready(saved)), .unsaved)
    }
    func testEnvelopeMetadataDoesNotCreateFalseDraftChanges() throws {
        let draft = TemplateAuthoringDraft(title: "Saved"); XCTAssertEqual(state(draft, try ready(draft)), state(draft, try ready(draft)))
    }
    func testNonfiniteCurrentDraftIsNeverClean() throws {
        var bad = TemplateAuthoringDraft(); bad.advanced.value["future"] = .number(.nan); XCTAssertNil(TemplateAuthoringExitDecision.snapshot(bad)); XCTAssertEqual(state(bad, .missing), .unverified); XCTAssertEqual(state(bad, try ready(.init())), .unverified)
    }
    func testNonfiniteCheckpointIsUnverified() throws {
        var bad = TemplateAuthoringDraft(); bad.advanced.value["future"] = .number(.infinity); XCTAssertEqual(state(.init(), try ready(bad)), .unverified)
    }
    func testUnreadableIncompatibleAndForeignOwnerRecordsRequireReview() {
        for checkpoint in [TemplateAuthoringRestore.unavailable, .incompatible, .ownerMismatch] { XCTAssertEqual(state(.init(), checkpoint), .unverified) }
    }
    func testInspectingDoesNotNormalizeOrMutateAnyDraftField() throws {
        var draft = TemplateAuthoringDraft(title: "  raw  "); draft.preferenceJson = " { \"future\": true } "; let before = TemplateAuthoringExitDecision.snapshot(draft)
        _ = state(draft, try ready(draft)); XCTAssertEqual(TemplateAuthoringExitDecision.snapshot(draft), before)
    }
}
