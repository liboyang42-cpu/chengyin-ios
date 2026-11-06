import SwiftUI
import XCTest
@testable import Questify

@MainActor final class MerchantReviewDraftReturnTests: XCTestCase {
    @MainActor private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "fixture://merchant", accountID: 9001, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var isConfigured = true, isOfflineExample = true, canExecuteSyntheticMutation = true
        var reads = 0, accessReads = 0, writes = 0
        var merchantID = 610, name = "Synthetic store", role = "MERCHANT_OWNER"
        var permissions: [String] = []
        var images = ["https://example.invalid/one.jpg", "https://example.invalid/two.jpg"]
        var content = "é", version = 0, reviewID = 63001
        var savedReply: String?
        var fail = false, multiplePages = false
        func access() async throws -> MerchantBusinessAccess {
            accessReads += 1; return try accessValue()
        }
        func accessValue() throws -> MerchantBusinessAccess {
            try .init(["active": .bool(true), "merchant": .object(["id": .int(merchantID), "name": .string(name)]),
                       "roleCode": .string(role), "permissions": .array(permissions.map(MerchantBusinessValue.string))])
        }
        func row(id: Int? = nil) throws -> MerchantBusinessRecord {
            try .init(kind: .review, fields: ["id": .int(id ?? reviewID), "version": .int(version), "rating": .int(4),
                "status": .string("VISIBLE"), "verifiedRedemption": .bool(true), "canReply": .bool(savedReply == nil), "canReport": .bool(true), "canEditReply": .bool(savedReply != nil), "merchantReply": savedReply.map(MerchantBusinessValue.string) ?? .null,
                "content": .string(content), "imageUrls": .array(images.map(MerchantBusinessValue.string))])
        }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            reads += 1
            if fail { throw URLError(.notConnectedToInternet) }
            let page = query.page
            let records = try multiplePages ? (page == 1 ? (1...20).map { try row(id: 63000 + $0) } : [row(id: 63021)]) : [row()]
            let payload: MerchantBusinessValue = .object(["mode": .string("manage"), "pageNum": .int(page), "pageSize": .int(20),
                "total": .int(multiplePages ? 21 : 1), "hasMore": .bool(multiplePages && page == 1),
                "items": .array(records.map { .object($0.fields) })])
            return .init(access: try accessValue(), document: try .init(query: query, payload: payload))
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            writes += 1; throw URLError(.timedOut)
        }
    }

    @MainActor private final class Harness {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let owner: MerchantBusinessViewModel
        let flow: MerchantReviewDraftReturn
        init() { owner = .init(reader: reader, journal: journal); flow = .init(owner: owner) }
        func start() async { await owner.load(.reviews(page: 1)); flow.activate() }
        func review(_ action: MerchantReviewReplyAction = .reply, _ content: String = "  Exact e\u{0301} 👩🏽‍💻\nText  ") throws -> MerchantBusinessConfirmation {
            owner.prepare(.review(id: try .init(reader.reviewID), version: reader.version, action: action, content: content))
            return try XCTUnwrap(owner.coordinator.confirmation)
        }
        func capture(_ review: MerchantBusinessConfirmation) throws -> MerchantReviewDraftReturn.Capture { try XCTUnwrap(flow.capture(review)) }
        func ticket(_ review: MerchantBusinessConfirmation) throws -> MerchantReviewDraftReturn.Return {
            XCTAssertTrue(flow.requestReturn(try capture(review)))
            return try XCTUnwrap(flow.didDismiss(reviewID: review.id))
        }
    }
    func testReplyUpdateAndReportReturnExactRawBytesAndOriginalTargetWithoutIO() async throws {
        for action in [MerchantReviewReplyAction.reply, .update, .report] {
            let h = Harness(); h.reader.savedReply = action == .update ? "Saved reply" : nil; await h.start(); let raw = "  e\u{0301} 👩🏽‍💻\r\nFix\u{00A0} "
            let review = try h.review(action, raw), ticket = try h.ticket(review)
            XCTAssertNil(h.owner.coordinator.confirmation)
            let context = try XCTUnwrap(h.flow.resume(ticket))
            guard case .review(let row, let restoredAction) = context.kind else { return XCTFail("Wrong editor") }
            XCTAssertEqual(row.id, "63001"); XCTAssertEqual(row.fields["version"]?.integer, 0); XCTAssertEqual(restoredAction, action)
            XCTAssertEqual(h.flow.initialContent(for: context.id).map { Data($0.utf8) }, Data(raw.utf8))
            XCTAssertEqual(h.reader.reads, 1); XCTAssertEqual(h.reader.accessReads, 0); XCTAssertEqual(h.reader.writes, 0)
            XCTAssertTrue(try h.journal.intents().isEmpty)
        }
    }
    func testNormalizedRequestIsNotUsedAsReturnedDraft() async throws {
        let h = Harness(); await h.start(); let raw = "  hello\n ", review = try h.review(.reply, raw)
        guard case .json(let fields) = review.request.body else { return XCTFail("Expected JSON") }
        XCTAssertEqual(fields["content"], .string("hello"))
        let context = try XCTUnwrap(h.flow.resume(try h.ticket(review)))
        XCTAssertEqual(h.flow.initialContent(for: context.id).map { Data($0.utf8) }, Data(raw.utf8))
    }
    func testDeleteReviewHasNoEditableDraft() async throws {
        let h = Harness(); h.reader.savedReply = "Saved reply"; await h.start(); XCTAssertNil(h.flow.capture(try h.review(.delete, "")))
    }
    func testUnrelatedMutationDoesNotGainReturnAction() async throws {
        let h = Harness(); await h.start()
        h.owner.prepare(.inviteOperator(role: "MERCHANT_MANAGER"))
        XCTAssertNil(h.owner.coordinator.confirmation) // Existing review projection cannot authorize an invitation.
        XCTAssertEqual(h.reader.writes, 0)
    }
    func testOrdinaryCancelDiscardsAndCannotReopen() async throws {
        let h = Harness(); await h.start(); let review = try h.review(), capture = try h.capture(review)
        h.flow.cancelReview(id: review.id)
        XCTAssertNil(h.owner.coordinator.confirmation); XCTAssertFalse(h.flow.requestReturn(capture))
        XCTAssertNil(h.flow.didDismiss(reviewID: review.id)); XCTAssertNil(h.flow.resumedEditorID)
    }
    func testOldCancelCannotCancelNewConfirmation() async throws {
        let h = Harness(); await h.start(); let old = try h.review(), fresh = try h.review(.report, "New report")
        h.flow.cancelReview(id: old.id); XCTAssertEqual(h.owner.coordinator.confirmation?.id, fresh.id)
    }
    func testOldCaptureCannotReturnNewConfirmationEvenWithSameRawText() async throws {
        let h = Harness(); await h.start(); let old = try h.review(), capture = try h.capture(old), fresh = try h.review()
        XCTAssertFalse(h.flow.requestReturn(capture)); XCTAssertEqual(h.owner.coordinator.confirmation?.id, fresh.id)
    }
    func testReturnConsumesExactConfirmationOnce() async throws {
        let h = Harness(); await h.start(); let review = try h.review(), capture = try h.capture(review)
        XCTAssertTrue(h.flow.requestReturn(capture)); XCTAssertFalse(h.flow.requestReturn(capture))
        let ticket = try XCTUnwrap(h.flow.didDismiss(reviewID: review.id)); XCTAssertNil(h.flow.didDismiss(reviewID: review.id))
        XCTAssertNotNil(h.flow.resume(ticket)); XCTAssertNil(h.flow.resume(ticket))
    }
    func testOldDismissalAndOldQueuedTicketCannotAffectNewerReturn() async throws {
        let h = Harness(); await h.start(); let old = try h.review(), oldTicket = try h.ticket(old)
        h.flow.discard(); let fresh = try h.review(.report, "Fresh reason"), freshTicket = try h.ticket(fresh)
        XCTAssertNil(h.flow.didDismiss(reviewID: old.id)); XCTAssertNil(h.flow.resume(oldTicket))
        XCTAssertEqual(h.flow.resume(freshTicket)?.id, freshTicket.context.id)
    }
    func testAnotherEditorBlocksAndConsumesQueuedReturn() async throws {
        let h = Harness(); await h.start(); let ticket = try h.ticket(h.review())
        XCTAssertNil(h.flow.resume(ticket, editorIsVacant: false)); XCTAssertNil(h.flow.resume(ticket))
        XCTAssertNil(h.flow.initialContent(for: ticket.context.id))
    }
    func testQueuedConfirmationClosesEditWindowBeforeTaskStarts() async throws {
        let h = Harness(); await h.start(); let review = try h.review(), capture = try h.capture(review)
        XCTAssertTrue(h.flow.beginConfirmation(id: review.id)); XCTAssertFalse(h.flow.requestReturn(capture))
        XCTAssertNil(h.flow.capture(review)); XCTAssertNil(h.flow.didDismiss(reviewID: review.id))
        XCTAssertEqual(h.reader.writes, 0)
    }
    func testOldConfirmTapDoesNotRetireNewReturn() async throws {
        let h = Harness(); await h.start(); let old = try h.review(), fresh = try h.review(.report, "New report")
        XCTAssertFalse(h.flow.beginConfirmation(id: old.id)); XCTAssertNotNil(h.flow.capture(fresh))
    }
    func testUnknownOutcomeDoesNotResurrectDraftOrRemoveJournal() async throws {
        let h = Harness(); await h.start(); let review = try h.review(), capture = try h.capture(review)
        XCTAssertTrue(h.flow.beginConfirmation(id: review.id)); await h.owner.confirm(review)
        XCTAssertTrue(h.owner.coordinator.isLocked); XCTAssertEqual(h.reader.writes, 1)
        let intents = try h.journal.intents(); XCTAssertEqual(intents.count, 1)
        XCTAssertFalse(h.flow.requestReturn(capture)); XCTAssertNil(h.flow.capture(review)); XCTAssertNil(h.flow.didDismiss(reviewID: review.id))
        h.flow.retire(); h.flow.activate(); XCTAssertEqual(try h.journal.intents(), intents)
    }
    func testBackgroundBeforeEditInvalidatesOldAndFreshCapturesOfSameReview() async throws {
        let h = Harness(); await h.start(); let review = try h.review(), capture = try h.capture(review)
        h.flow.retire(); h.flow.activate()
        XCTAssertFalse(h.flow.requestReturn(capture)); XCTAssertNil(h.flow.capture(review))
        XCTAssertNotNil(h.flow.capture(try h.review()))
    }
    func testBackgroundDuringDismissalCannotResumeAfterForeground() async throws {
        let h = Harness(); await h.start(); let review = try h.review(), ticket = try h.ticket(review)
        h.flow.retire(); h.flow.activate(); XCTAssertNil(h.flow.resume(ticket)); XCTAssertNil(h.flow.initialContent(for: ticket.context.id))
    }
    func testBackgroundClearsOnlyReturnedEditorIdentity() async throws {
        let h = Harness(); await h.start(); let ticket = try h.ticket(h.review())
        let context = try XCTUnwrap(h.flow.resume(ticket)); XCTAssertEqual(h.flow.retire(), context.id)
        XCTAssertNil(h.flow.initialContent(for: context.id)); XCTAssertNil(h.flow.retire())
    }
    func testAccountEpochAuthorizationAndConfigurationChangesRejectQueuedReturn() async throws {
        for change in 0..<4 {
            let h = Harness(); await h.start(); let ticket = try h.ticket(h.review())
            switch change { case 0: h.reader.scope = .init(realm: "fixture://merchant", accountID: 9002, epoch: 1)
            case 1: h.reader.scope = .init(realm: "fixture://merchant", accountID: 9001, epoch: 2)
            case 2: h.reader.authorizationGeneration = UUID()
            default: h.reader.isConfigured = false }
            XCTAssertNil(h.flow.resume(ticket)); XCTAssertNil(h.flow.initialContent(for: ticket.context.id))
        }
    }
    func testExactRealmBytesRejectCanonicalAlias() async throws {
        let h = Harness(); h.reader.scope = .init(realm: "fixture://é", accountID: 9001, epoch: 1); await h.start()
        let ticket = try h.ticket(h.review()); h.reader.scope = .init(realm: "fixture://e\u{0301}", accountID: 9001, epoch: 1)
        XCTAssertNil(h.flow.resume(ticket))
    }
    func testSameBytesReloadInvalidatesReturnedEditorByOwnerRevision() async throws {
        let h = Harness(); await h.start(); let ticket = try h.ticket(h.review()), context = try XCTUnwrap(h.flow.resume(ticket))
        await h.owner.load(.reviews(page: 1))
        XCTAssertNil(h.flow.initialContent(for: context.id)); XCTAssertEqual(h.flow.synchronize(), context.id)
    }
    func testExactPayloadBytesRejectCanonicallyEquivalentReplacementWithoutViewRevision() async throws {
        let h = Harness(); await h.start(); let ticket = try h.ticket(h.review())
        h.reader.content = "e\u{0301}"; await h.owner.coordinator.load(.reviews(page: 1))
        XCTAssertNil(h.flow.resume(ticket)); XCTAssertEqual(h.reader.writes, 0)
    }
    func testStoreRoleAndReviewVersionChangesRejectDirectReplacement() async throws {
        for change in 0..<3 {
            let h = Harness(); await h.start(); let ticket = try h.ticket(h.review())
            if change == 0 { h.reader.merchantID = 611 }
            if change == 1 { h.reader.role = "MERCHANT_MANAGER" }
            if change == 2 { h.reader.version = 1 }
            await h.owner.coordinator.load(.reviews(page: 1)); XCTAssertNil(h.flow.resume(ticket))
        }
    }
    func testReplacementOwnerCannotBorrowCapturedDraft() async throws {
        let old = Harness(), fresh = Harness(); fresh.reader.authorizationGeneration = old.reader.authorizationGeneration
        await old.start(); await fresh.start(); let review = try old.review(), capture = try old.capture(review)
        _ = try fresh.review(); XCTAssertFalse(fresh.flow.requestReturn(capture)); XCTAssertNotNil(fresh.owner.coordinator.confirmation)
    }
    func testOnlyMatchingReturnedEditorGetsInitialContent() async throws {
        let h = Harness(); await h.start(); let ticket = try h.ticket(h.review())
        XCTAssertNil(h.flow.initialContent(for: ticket.context.id)); _ = h.flow.resume(ticket)
        XCTAssertNil(h.flow.initialContent(for: UUID())); XCTAssertNotNil(h.flow.initialContent(for: ticket.context.id))
        h.flow.discard(); XCTAssertNil(h.flow.initialContent(for: ticket.context.id))
    }
    func testDormantControllerCannotCaptureOrConfirm() async throws {
        let h = Harness(); await h.owner.load(.reviews(page: 1)); let review = try h.review()
        XCTAssertNil(h.flow.capture(review)); XCTAssertFalse(h.flow.beginConfirmation(id: review.id)); XCTAssertEqual(h.reader.writes, 0)
    }
}

@MainActor final class MerchantAftercareDraftReturnTests: XCTestCase {
    private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "synthetic://aftercare-return", accountID: 9001, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var isConfigured = true, isOfflineExample = true, canExecuteSyntheticMutation = true
        var reads = 0, writes = 0
        var reason = "Original reason"
        var denied = false, succeeds = false
        func access() async throws -> MerchantBusinessAccess {
            var fields = try MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object!
            if denied { fields["permissions"] = .array([]) }
            return try .init(fields)
        }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            reads += 1
            var fields = try MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.refund).object!
            fields["reason"] = .string(reason)
            return try .init(access: await access(), document: .init(query: query, payload: .object(fields)))
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            writes += 1
            if succeeds, case .aftercare(let id, let decision, _, _) = mutation {
                return try .init(mutation: mutation, message: nil, data: .object([
                    "id": .int(62099), "refundId": .int(id.rawValue), "decision": .string(decision.rawValue),
                    "processing": .string("WAITING_PLATFORM_REVIEW"), "merchantOpinion": .string("PENDING"), "refunded": .bool(false)]))
            }
            throw URLError(.timedOut)
        }
    }
    @MainActor private final class Harness {
        let reader = Reader(), journal = MerchantBusinessMemoryIntentStore()
        let owner: MerchantBusinessViewModel
        let flow: MerchantAftercareDraftReturn
        init() { owner = .init(reader: reader, journal: journal); flow = .init(owner: owner) }
        func start() async throws { await owner.load(.refund(try .init(62001))); flow.appear(active: true) }
        func review(_ decision: MerchantAftercareDecision = .reject, content: String = "  Exact e\u{0301} explanation\n ", evidence: String? = "upload/merchant-aftercare-evidence/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png") throws -> MerchantBusinessConfirmation {
            owner.prepare(.aftercare(refund: try .init(62001), decision: decision, content: content, evidenceKey: evidence))
            return try XCTUnwrap(owner.coordinator.confirmation)
        }
        func returned(_ review: MerchantBusinessConfirmation) throws -> MerchantAftercareDraftReturn.Return {
            XCTAssertTrue(flow.requestReturn(try XCTUnwrap(flow.capture(review))))
            return try XCTUnwrap(flow.didDismiss(reviewID: review.id))
        }
    }
    func testEveryAllowedDecisionReturnsExactLocalFieldsWithoutReadsWritesOrReservation() async throws {
        for decision in MerchantAftercareDecision.allCases {
            let h = Harness(); try await h.start()
            let text = "  e\u{0301} 👩🏽‍💻\n local  ", evidence = "upload/merchant-aftercare-evidence/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.png"
            let review = try h.review(decision, content: text, evidence: evidence), reads = h.reader.reads
            let ticket = try h.returned(review), editor = try XCTUnwrap(h.flow.resume(ticket, editorIsVacant: true))
            let draft = try XCTUnwrap(h.flow.initialDraft(for: editor.id))
            XCTAssertEqual(draft.decision, decision)
            XCTAssertEqual(Data(draft.content.utf8), Data(text.utf8)); XCTAssertEqual(Data(draft.evidence.utf8), Data(evidence.utf8))
            guard case .aftercare(let row) = editor.kind else { return XCTFail("Wrong editor kind") }
            XCTAssertEqual(row.id, "62001"); XCTAssertNil(h.owner.coordinator.confirmation)
            XCTAssertEqual(h.reader.reads, reads); XCTAssertEqual(h.reader.writes, 0); XCTAssertTrue(try h.journal.intents().isEmpty)
        }
    }
    func testCancelDiscardsReviewWithoutCreatingReturnTicket() async throws {
        let h = Harness(); try await h.start(); let review = try h.review(), capture = try XCTUnwrap(h.flow.capture(review))
        h.flow.cancelReview(id: review.id)
        XCTAssertNil(h.owner.coordinator.confirmation); XCTAssertFalse(h.flow.requestReturn(capture))
        XCTAssertNil(h.flow.didDismiss(reviewID: review.id)); XCTAssertNil(h.flow.resumedEditorID)
        XCTAssertEqual(h.reader.writes, 0)
    }
    func testOldReviewCaptureAndCancelCannotTouchReplacementReview() async throws {
        let h = Harness(); try await h.start(); let old = try h.review(), capture = try XCTUnwrap(h.flow.capture(old))
        let replacement = try h.review(.agree, content: "Different opinion")
        XCTAssertFalse(h.flow.requestReturn(capture)); h.flow.cancelReview(id: old.id)
        XCTAssertEqual(h.owner.coordinator.confirmation?.id, replacement.id)
    }
    func testReturnAndDismissAndResumeAreEachOnceOnly() async throws {
        let h = Harness(); try await h.start(); let review = try h.review(), capture = try XCTUnwrap(h.flow.capture(review))
        XCTAssertTrue(h.flow.requestReturn(capture)); XCTAssertFalse(h.flow.requestReturn(capture))
        let ticket = try XCTUnwrap(h.flow.didDismiss(reviewID: review.id))
        XCTAssertNil(h.flow.didDismiss(reviewID: review.id))
        XCTAssertNotNil(h.flow.resume(ticket, editorIsVacant: true)); XCTAssertNil(h.flow.resume(ticket, editorIsVacant: true))
    }
    func testOldQueuedReturnCannotReplaceNewerEditor() async throws {
        let h = Harness(); try await h.start(); let old = try h.returned(h.review())
        h.flow.discard(); let fresh = try h.returned(h.review(.agree, content: "Fresh opinion"))
        XCTAssertNil(h.flow.resume(old, editorIsVacant: true))
        XCTAssertEqual(h.flow.resume(fresh, editorIsVacant: true)?.id, fresh.context.id)
    }
    func testOccupiedEditorRejectsAndConsumesTheReturnTicket() async throws {
        let h = Harness(); try await h.start(); let ticket = try h.returned(h.review())
        XCTAssertNil(h.flow.resume(ticket, editorIsVacant: false)); XCTAssertNil(h.flow.resume(ticket, editorIsVacant: true))
    }
    func testScopeAndAuthorizationChangesRejectReturnBeforeHostObservers() async throws {
        for auth in [false, true] {
            let h = Harness(); try await h.start(); let review = try h.review(), capture = try XCTUnwrap(h.flow.capture(review))
            if auth { h.reader.authorizationGeneration = UUID() } else { h.reader.scope = nil }
            XCTAssertFalse(h.flow.requestReturn(capture)); XCTAssertNil(h.flow.capture(review)); XCTAssertEqual(h.reader.writes, 0)
        }
    }
    func testBackgroundAndHiddenSceneReactivationCannotReviveOldReview() async throws {
        let h = Harness(); try await h.start(); let review = try h.review(), capture = try XCTUnwrap(h.flow.capture(review))
        h.flow.disappear(); h.flow.sceneChanged(active: false); h.flow.sceneChanged(active: true)
        XCTAssertFalse(h.flow.requestReturn(capture)); XCTAssertNil(h.flow.capture(review))
        h.flow.appear(active: true); XCTAssertNil(h.flow.capture(review))
        let fresh = try h.review(); XCTAssertNotNil(h.flow.capture(fresh))
    }
    func testDispatchBoundaryRetiresReturnBeforeAnyQueuedSend() async throws {
        let h = Harness(); try await h.start(); let review = try h.review(), capture = try XCTUnwrap(h.flow.capture(review))
        XCTAssertTrue(h.flow.beginConfirmation(id: review.id))
        XCTAssertFalse(h.flow.requestReturn(capture)); XCTAssertNil(h.flow.capture(review)); XCTAssertEqual(h.reader.writes, 0)
    }
    func testUnknownOutcomeCannotReturnOrReleaseExistingReservation() async throws {
        let h = Harness(); try await h.start(); let review = try h.review(), capture = try XCTUnwrap(h.flow.capture(review))
        XCTAssertTrue(h.flow.beginConfirmation(id: review.id)); await h.owner.confirm(review)
        XCTAssertEqual(h.reader.writes, 1); XCTAssertTrue(h.owner.coordinator.isLocked)
        let intents = try h.journal.intents(); XCTAssertEqual(intents.count, 1)
        XCTAssertFalse(h.flow.requestReturn(capture)); XCTAssertNil(h.flow.capture(review))
        XCTAssertEqual(try h.journal.intents(), intents); XCTAssertEqual(h.reader.writes, 1)
        // Existing same-review retry remains the coordinator's decision; local Edit stays unavailable.
        if h.owner.coordinator.confirmation?.id == review.id {
            XCTAssertTrue(h.flow.beginConfirmation(id: review.id)); XCTAssertNil(h.flow.capture(review))
        }
    }
    func testSnapshotRefreshAndReadPermissionLossInvalidateReturn() async throws {
        let h = Harness(); try await h.start(); let review = try h.review(), ticket = try h.returned(review)
        h.reader.denied = true; await h.owner.load(.refund(try .init(62001)))
        XCTAssertNil(h.flow.resume(ticket, editorIsVacant: true)); XCTAssertNil(h.flow.initialDraft(for: ticket.context.id))
    }
    func testReturnedEmptyEvidenceStaysEmptyWithoutAddingAttachment() async throws {
        let h = Harness(); try await h.start(); let ticket = try h.returned(h.review(.agree, evidence: nil))
        let editor = try XCTUnwrap(h.flow.resume(ticket, editorIsVacant: true))
        XCTAssertEqual(h.flow.initialDraft(for: editor.id)?.evidence, "")
        XCTAssertEqual(h.reader.writes, 0)
    }
}


@MainActor extension MerchantAftercareDraftReturnTests {
    func testActualHostEditorBindingRejectsOldGetterAndNilSetterAfterReplacement() {
        let first = MerchantBusinessEditorContext(kind: .invite), second = MerchantBusinessEditorContext(kind: .invite)
        var current: MerchantBusinessEditorContext? = first
        let source = Binding<MerchantBusinessEditorContext?>(get: { current }, set: { current = $0 })
        let old = MerchantAftercareDraftReturn.editorBinding(source, presentedID: first.id)
        XCTAssertEqual(old.wrappedValue?.id, first.id)
        current = second
        XCTAssertNil(old.wrappedValue); old.wrappedValue = nil
        XCTAssertEqual(current?.id, second.id)
        let fresh = MerchantAftercareDraftReturn.editorBinding(source, presentedID: second.id)
        fresh.wrappedValue = nil; XCTAssertNil(current)
    }
    func testActualHostDismissalOwnershipRejectsOldOwnerAndPermitsCurrentNilEditor() {
        let old = UUID(), fresh = UUID()
        XCTAssertFalse(MerchantAftercareDraftReturn.ownsDismissal(presentedID: old, currentEditorID: nil, pendingEditorID: fresh))
        XCTAssertFalse(MerchantAftercareDraftReturn.ownsDismissal(presentedID: fresh, currentEditorID: fresh, pendingEditorID: fresh))
        XCTAssertFalse(MerchantAftercareDraftReturn.ownsDismissal(presentedID: nil, currentEditorID: nil, pendingEditorID: nil))
        XCTAssertTrue(MerchantAftercareDraftReturn.ownsDismissal(presentedID: fresh, currentEditorID: nil, pendingEditorID: fresh))
    }
}


@MainActor extension MerchantAftercareDraftReturnTests {
    func testAcknowledgedReceiptCannotReopenOldDraftOrSendAgain() async throws {
        let h = Harness(); try await h.start(); h.reader.succeeds = true
        let review = try h.review(), captured = try XCTUnwrap(h.flow.capture(review))
        XCTAssertTrue(h.flow.beginConfirmation(id: review.id)); await h.owner.confirm(review)
        let receipt = try XCTUnwrap(h.owner.coordinator.receipt)
        XCTAssertFalse(h.flow.requestReturn(captured)); XCTAssertNil(h.flow.capture(review))
        XCTAssertFalse(h.flow.beginConfirmation(id: review.id))
        XCTAssertEqual(h.owner.coordinator.receipt, receipt); XCTAssertEqual(h.reader.writes, 1)
        XCTAssertTrue(try h.journal.intents().isEmpty)
    }
}
