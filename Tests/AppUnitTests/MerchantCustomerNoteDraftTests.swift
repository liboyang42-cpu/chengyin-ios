import XCTest
@testable import Questify

@MainActor final class MerchantCustomerNoteDraftTests: XCTestCase {
    @MainActor private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "fixture://note-draft", accountID: 9001, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var isConfigured = true, isOfflineExample = true, canExecuteSyntheticMutation = false
        var permissions = ["merchant:crm:read", "merchant:crm:segment"]
        var reads = 0, writes = 0
        func access() async throws -> MerchantBusinessAccess { try grant() }
        func grant() throws -> MerchantBusinessAccess {
            try .init(["active": .bool(true), "merchant": .object(["id": .int(610)]),
                       "roleCode": .string("MERCHANT_MANAGER"), "permissions": .array(permissions.map(MerchantBusinessValue.string))])
        }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            reads += 1
            return try .init(access: grant(), document: .init(query: query, payload: MerchantBusinessSyntheticFixtures.payload(query)))
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            writes += 1; XCTFail("Local draft must never dispatch"); throw MerchantBusinessFailure.disabled
        }
    }
    @MainActor private final class Harness {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let owner: MerchantBusinessViewModel
        let drafts: MerchantCustomerNoteDraft
        let customer = try! MerchantCustomerID(61001)
        init() { owner = .init(reader: reader, journal: journal); drafts = .init(owner: owner) }
        func start() async { await owner.load(.customer(customer)); drafts.activate() }
        func open(_ correction: Int? = nil) throws -> MerchantBusinessEditorContext {
            try XCTUnwrap(drafts.open(customer: customer, corrects: correction))
        }
        func correction() throws -> Int {
            try XCTUnwrap(owner.coordinator.snapshot?.document.rows.first(where: {
                $0.kind == .timeline && ["NOTE", "NOTE_CORRECTION"].contains($0.fields.mbText("type") ?? "")
            })?.fields["noteId"]?.integer)
        }
    }
    func testCloseReopenPreservesExactRawTextWithoutIOOrIntent() async throws {
        let h = Harness(); await h.start(); let first = try h.open(), raw = "  e\u{0301} 👩🏽‍💻\r\n "
        h.drafts.update(editorID: first.id, content: raw, correctionCancelled: false)
        h.drafts.close(editorID: first.id)
        XCTAssertNil(h.drafts.value(for: first.id)); XCTAssertTrue(h.drafts.hasDraft(corrects: nil))
        let second = try h.open(); XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(h.drafts.value(for: second.id).map { Data($0.content.utf8) }, Data(raw.utf8))
        XCTAssertEqual(h.reader.reads, 1); XCTAssertEqual(h.reader.writes, 0); XCTAssertTrue(try h.journal.intents().isEmpty)
    }
    func testCorrectionAndNewNoteDraftsAreSeparate() async throws {
        let h = Harness(); await h.start(); let note = try h.correction(), first = try h.open(note)
        h.drafts.update(editorID: first.id, content: "correction", correctionCancelled: false)
        h.drafts.close(editorID: first.id)
        let second = try h.open(); XCTAssertEqual(h.drafts.value(for: second.id)?.content, "")
        h.drafts.update(editorID: second.id, content: "new", correctionCancelled: false)
        let again = try h.open(note); XCTAssertEqual(h.drafts.value(for: again.id)?.content, "correction")
        guard case .note(_, let target) = again.kind else { return XCTFail("Expected note") }
        XCTAssertEqual(target, note)
    }
    func testCancelledCorrectionModeAndEmptyTextSurviveReopen() async throws {
        let h = Harness(); await h.start(); let note = try h.correction(), first = try h.open(note)
        h.drafts.update(editorID: first.id, content: "", correctionCancelled: true); h.drafts.close(editorID: first.id)
        let reopened = try h.open(note)
        XCTAssertEqual(h.drafts.value(for: reopened.id)?.content, "")
        XCTAssertEqual(h.drafts.value(for: reopened.id)?.correctionCancelled, true)
    }
    func testClearTextDoesNotCancelCorrectionTarget() async throws {
        let h = Harness(); await h.start(); let first = try h.open(try h.correction())
        h.drafts.update(editorID: first.id, content: "text", correctionCancelled: false)
        h.drafts.update(editorID: first.id, content: "", correctionCancelled: false)
        XCTAssertEqual(h.drafts.value(for: first.id), MerchantCustomerNoteDraft.Draft(content: "", correctionCancelled: false))
    }
    func testOldEditorCannotOverwriteOrCloseNewLease() async throws {
        let h = Harness(); await h.start(); let first = try h.open(), second = try h.open()
        h.drafts.update(editorID: second.id, content: "current", correctionCancelled: false)
        h.drafts.update(editorID: first.id, content: "stale", correctionCancelled: true); h.drafts.close(editorID: first.id)
        XCTAssertEqual(h.drafts.value(for: second.id)?.content, "current")
        XCTAssertFalse(h.drafts.retireForReview(editorID: first.id))
    }
    func testStaleDiscardConfirmationCannotClearNewGeneration() async throws {
        let h = Harness(); await h.start(); _ = try h.open(); let old = h.drafts.generation
        h.drafts.discard(); let next = try h.open(); h.drafts.update(editorID: next.id, content: "new", correctionCancelled: false)
        h.drafts.discard(ifGeneration: old); XCTAssertEqual(h.drafts.value(for: next.id)?.content, "new")
        h.drafts.discard(); XCTAssertFalse(h.drafts.hasDrafts); XCTAssertNil(h.drafts.value(for: next.id))
    }
    func testAccountAuthorizationLogoutAndConfigurationDriftRejectOldEditor() async throws {
        for change in ["account", "authorization", "logout", "configuration"] {
            let h = Harness(); await h.start(); let first = try h.open()
            h.drafts.update(editorID: first.id, content: "private", correctionCancelled: false)
            switch change {
            case "account": h.reader.scope = .init(realm: "fixture://note-draft", accountID: 9002, epoch: 2)
            case "authorization": h.reader.authorizationGeneration = UUID()
            case "logout": h.reader.scope = nil
            default: h.reader.isConfigured = false
            }
            XCTAssertNil(h.drafts.value(for: first.id), change); XCTAssertEqual(h.drafts.synchronize(), first.id)
            XCTAssertFalse(h.drafts.hasDrafts); XCTAssertEqual(h.reader.writes, 0)
        }
    }
    func testDifferentCustomerAndAbsentCorrectionCannotOpen() async throws {
        let h = Harness(); await h.start()
        XCTAssertNil(h.drafts.open(customer: try .init(61002), corrects: nil))
        XCTAssertNil(h.drafts.open(customer: h.customer, corrects: -1))
        XCTAssertNil(h.drafts.open(customer: h.customer, corrects: 99999999))
    }
    func testReadOnlyGrantCannotAcquireLocalEditor() async throws {
        let h = Harness(); h.reader.permissions = ["merchant:crm:read"]; await h.start()
        XCTAssertNil(h.drafts.open(customer: h.customer, corrects: nil))
    }
    func testReviewHandoffDiscardsAllLocalDraftsAndOldCallbacks() async throws {
        let h = Harness(); await h.start(); let first = try h.open()
        h.drafts.update(editorID: first.id, content: "ready", correctionCancelled: false)
        XCTAssertTrue(h.drafts.retireForReview(editorID: first.id))
        XCTAssertFalse(h.drafts.retireForReview(editorID: first.id))
        h.drafts.update(editorID: first.id, content: "late", correctionCancelled: false)
        XCTAssertFalse(h.drafts.hasDrafts); XCTAssertEqual(h.reader.writes, 0)
    }
    func testPageInvalidationRetiresDraftBeforeReentry() async throws {
        let h = Harness(); await h.start(); let first = try h.open()
        h.drafts.update(editorID: first.id, content: "old", correctionCancelled: false)
        h.owner.invalidate(); XCTAssertEqual(h.drafts.synchronize(), first.id)
        await h.start(); let next = try h.open(); XCTAssertEqual(h.drafts.value(for: next.id)?.content, "")
    }
    func testBackgroundRetirementRefusesReopenUntilActive() async throws {
        let h = Harness(); await h.start(); let first = try h.open()
        h.drafts.update(editorID: first.id, content: "private", correctionCancelled: false)
        h.drafts.retire(); XCTAssertNil(h.drafts.open(customer: h.customer, corrects: nil))
        h.drafts.activate(); let next = try h.open(); XCTAssertEqual(h.drafts.value(for: next.id)?.content, "")
    }
    func testExistingConfirmationCannotBecomeEditableLocalDraft() async throws {
        let h = Harness(); await h.start(); let first = try h.open()
        h.drafts.update(editorID: first.id, content: "old", correctionCancelled: false)
        h.owner.prepare(.addNote(customer: h.customer, content: "review", correctsNoteID: nil))
        XCTAssertNotNil(h.owner.coordinator.confirmation)
        XCTAssertNil(h.drafts.open(customer: h.customer, corrects: nil))
        XCTAssertFalse(h.drafts.hasDrafts); XCTAssertEqual(h.reader.writes, 0)
    }
    func testUnknownJournalIntentDoesNotOfferLocalContinuation() async throws {
        let h = Harness()
        let scope = try XCTUnwrap(h.reader.scope)
        try h.journal.reserve(.init(scope: scope, merchantID: 610, target: "unknown-note", requestID: "fixture-unknown"))
        await h.start(); XCTAssertTrue(h.owner.coordinator.isLocked)
        XCTAssertNil(h.drafts.open(customer: h.customer, corrects: nil))
        XCTAssertEqual(try h.journal.intents().count, 1); XCTAssertEqual(h.reader.writes, 0)
    }

}
