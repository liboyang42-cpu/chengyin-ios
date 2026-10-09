import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class MerchantAftercareEvidenceFlowTests: XCTestCase {
    private final class DraftBox {
        var value = MerchantAftercareEvidenceDraft(decision: .reject, content: "Original explanation", evidence: "old key")
        var editorCurrent = true
        var attachedKeys: [String] = []
    }
    private final class EvidenceReader: MerchantEngagementReading {
        var scope: MerchantBusinessScope?
        var authorizationGeneration: UUID? = UUID()
        let isConfigured = true
        var isSyntheticEnabled = true
        var device = true, executable = true
        var proofCount = 0, executeCount = 0
        var snapshot: MerchantBusinessSnapshot
        var uploadError: Error?
        var wrongRefund = false, wrongSelection = false
        var pauseProof = false
        var continuation: CheckedContinuation<Void, Never>?
        var pauseExecute = false
        var executeContinuation: CheckedContinuation<Void, Never>?
        var pauseBeforeForward = false
        var forwardContinuation: CheckedContinuation<Void, Never>?
        init(scope: MerchantBusinessScope?, snapshot: MerchantBusinessSnapshot) { self.scope = scope; self.snapshot = snapshot }
        func canExecute(_ command: MerchantEngagementCommand, merchantID: Int) -> Bool { executable }
        func permitsDevice(_ action: MerchantEngagementDeviceGrant.Action, merchantID: Int) -> Bool { device && merchantID == snapshot.access.merchantID }
        func access() async throws -> MerchantEngagementAccess {
            try .init(XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.access).object))
        }
        func read(_ query: MerchantEngagementQuery) async throws -> MerchantEngagementPayload { throw MerchantBusinessFailure.invalid }
        func proof(_ command: MerchantEngagementCommand) async throws -> MerchantEngagementProof {
            proofCount += 1
            if pauseProof { await withCheckedContinuation { continuation = $0 } }
            return .init(access: try await access(), refund: snapshot.document)
        }
        func execute(_ command: MerchantEngagementCommand, requestID: String, proof: MerchantEngagementProof, scope: MerchantBusinessScope) async throws -> MerchantEngagementReceipt {
            executeCount += 1
            if pauseExecute { await withCheckedContinuation { executeContinuation = $0 } }
            if let uploadError { throw uploadError }
            guard case .uploadEvidence(let refund, let selected, _, _) = command else { throw MerchantBusinessFailure.invalid }
            return .evidenceUploaded(refundID: wrongRefund ? try .init(62002) : refund,
                selectionID: wrongSelection ? UUID() : selected.id,
                try .init(objectKey: "upload/merchant-aftercare-evidence/" + String(repeating: "a", count: 32) + ".png"))
        }
        func execute(_ review: MerchantEngagementReview, authorization: MerchantEngagementDispatchAuthorization,
                     check: () throws -> Void) async throws -> MerchantEngagementReceipt {
            try authorization.consume(review); try check()
            if pauseBeforeForward { await withCheckedContinuation { forwardContinuation = $0 } }
            // Deliberately validate only the minted authorization after this suspension,
            // matching the real production transport's final beforeForward boundary.
            try authorization.validate(review)
            return try await execute(review.command, requestID: review.requestID, proof: review.proof, scope: review.scope)
        }
    }
    private struct Harness {
        let flow: MerchantAftercareEvidenceFlow
        let document: MerchantBusinessViewModel
        let business: MerchantBusinessFixtureReader
        let reader: EvidenceReader
        let draft: DraftBox
        let journal: MerchantBusinessMemoryIntentStore
    }
    private func harness() async throws -> Harness {
        let business = MerchantBusinessFixtureReader(scenario: .ready), journal = MerchantBusinessMemoryIntentStore()
        let document = MerchantBusinessViewModel(reader: business, journal: journal)
        await document.load(.refund(try .init(62001)))
        let snapshot = try XCTUnwrap(document.coordinator.snapshot), draft = DraftBox()
        let reader = EvidenceReader(scope: business.scope, snapshot: snapshot)
        let owner = try XCTUnwrap(MerchantAftercareEvidenceOwner(editorID: UUID(), document: document, editorIsCurrent: { draft.editorCurrent }))
        let flow = try XCTUnwrap(MerchantAftercareEvidenceFlow(owner: owner,
            dependencies: .init(reader: reader, journal: journal, recovery: MerchantExportMemoryRecoveryStore()),
            original: draft.value, currentDraft: { draft.value }, applyKey: { key in
                draft.attachedKeys.append(key)
                draft.value = .init(decision: draft.value.decision, content: draft.value.content, evidence: key)
            }))
        return .init(flow: flow, document: document, business: business, reader: reader, draft: draft, journal: journal)
    }
    private func selection() throws -> MerchantEvidenceSelection {
        try .init(bytes: Data([137, 80, 78, 71, 13, 10, 26, 10]), filename: "evidence.png", mimeType: "image/png")
    }
    private func upload(_ h: Harness) async throws {
        let preparation = try XCTUnwrap(h.flow.select(try selection())); await preparation.value
        let review = try XCTUnwrap(h.flow.review)
        let task = try XCTUnwrap(h.flow.confirm(review)); await task.value
    }
    func testOpeningIsLocalAndSelectionDoesNotUploadOrChangeDraft() async throws {
        let h = try await harness(), original = h.draft.value
        XCTAssertEqual(h.reader.proofCount, 0); XCTAssertEqual(h.reader.executeCount, 0)
        let task = try XCTUnwrap(h.flow.select(try selection())); await task.value
        XCTAssertNotNil(h.flow.review); XCTAssertEqual(h.reader.proofCount, 1); XCTAssertEqual(h.reader.executeCount, 0)
        XCTAssertEqual(h.draft.value, original); XCTAssertFalse(h.flow.canAttach)
    }
    func testUploadRequiresItsReviewThenExplicitSingleUseAttachChangesOnlyKey() async throws {
        let h = try await harness(), original = h.draft.value
        try await upload(h)
        XCTAssertEqual(h.reader.executeCount, 1); XCTAssertEqual(h.draft.value, original)
        XCTAssertTrue(h.flow.canAttach); XCTAssertTrue(h.flow.attach()); XCTAssertFalse(h.flow.attach())
        XCTAssertEqual(h.draft.attachedKeys.count, 1); XCTAssertEqual(h.draft.value.content, original.content)
        XCTAssertEqual(h.draft.value.decision, original.decision); XCTAssertNotEqual(h.draft.value.evidence, original.evidence)
        XCTAssertNil(h.flow.coordinator.receipt); XCTAssertNil(h.flow.selection); XCTAssertTrue(try h.journal.intents().isEmpty)
    }
    func testMissingDeviceGatePreventsSelectionAndReads() async throws {
        let h = try await harness(); h.reader.device = false
        XCTAssertFalse(h.flow.canSelect); XCTAssertNil(h.flow.select(try selection()))
        XCTAssertEqual(h.reader.proofCount, 0); XCTAssertEqual(h.reader.executeCount, 0); XCTAssertEqual(h.draft.value.evidence, "old key")
    }
    func testDisabledUploadCannotConsumeReviewOrAlterDraft() async throws {
        let h = try await harness(); let task = try XCTUnwrap(h.flow.select(try selection())); await task.value
        let review = try XCTUnwrap(h.flow.review); h.reader.executable = false
        XCTAssertNil(h.flow.confirm(review)); XCTAssertNotNil(h.flow.review); XCTAssertEqual(h.reader.executeCount, 0)
        XCTAssertFalse(h.flow.attach()); XCTAssertEqual(h.draft.value.evidence, "old key")
    }
    func testProductionStillRequiresDurableJournal() async throws {
        let h = try await harness(); h.reader.isSyntheticEnabled = false
        let task = try XCTUnwrap(h.flow.select(try selection())); await task.value
        let confirm = try XCTUnwrap(h.flow.confirm(try XCTUnwrap(h.flow.review))); await confirm.value
        XCTAssertEqual(h.flow.coordinator.failure, .disabled); XCTAssertEqual(h.reader.executeCount, 0)
        XCTAssertFalse(h.flow.canAttach); XCTAssertEqual(h.draft.value.evidence, "old key")
    }
    func testCancelUploadReviewAndClearSelectionAreLocal() async throws {
        let h = try await harness(); let task = try XCTUnwrap(h.flow.select(try selection())); await task.value
        h.flow.cancelReview(); XCTAssertNil(h.flow.review); XCTAssertNotNil(h.flow.selection)
        h.flow.clearSelection(); XCTAssertNil(h.flow.selection); XCTAssertEqual(h.reader.executeCount, 0)
        XCTAssertEqual(h.draft.value.evidence, "old key"); XCTAssertTrue(try h.journal.intents().isEmpty)
    }
    func testCancelAfterUploadDoesNotAttachOrDeleteRemoteImage() async throws {
        let h = try await harness(); try await upload(h); h.flow.retire()
        XCTAssertNil(h.flow.selection); XCTAssertNil(h.flow.coordinator.receipt); XCTAssertFalse(h.flow.canAttach)
        XCTAssertEqual(h.reader.executeCount, 1); XCTAssertEqual(h.draft.value.evidence, "old key"); XCTAssertTrue(h.draft.attachedKeys.isEmpty)
    }
    func testDuplicateSelectAndConfirmAreBlockedBeforeTaskStarts() async throws {
        let h = try await harness(); let first = try XCTUnwrap(h.flow.select(try selection()))
        XCTAssertNil(h.flow.select(try selection())); await first.value
        let review = try XCTUnwrap(h.flow.review), confirm = try XCTUnwrap(h.flow.confirm(try XCTUnwrap(h.flow.review)))
        XCTAssertNil(h.flow.confirm(review)); await confirm.value
        XCTAssertEqual(h.reader.executeCount, 1)
    }
    func testUnknownUploadKeepsOriginalKeyAndJournalBlocksReopen() async throws {
        let h = try await harness(); h.reader.uploadError = URLError(.timedOut); try await upload(h)
        XCTAssertTrue(h.flow.coordinator.locked); XCTAssertEqual(h.flow.coordinator.failure, .unknown)
        XCTAssertFalse(h.flow.canAttach); XCTAssertFalse(h.flow.attach()); XCTAssertNil(h.flow.prepareUpload())
        XCTAssertEqual(h.draft.value.evidence, "old key"); XCTAssertEqual(try h.journal.intents().count, 1)
        let owner = try XCTUnwrap(MerchantAftercareEvidenceOwner(editorID: UUID(), document: h.document, editorIsCurrent: { true }))
        let next = try XCTUnwrap(MerchantAftercareEvidenceFlow(owner: owner,
            dependencies: .init(reader: h.reader, journal: h.journal, recovery: MerchantExportMemoryRecoveryStore()),
            original: h.draft.value, currentDraft: { h.draft.value }, applyKey: { _ in XCTFail("Must not attach unknown upload") }))
        let retry = try XCTUnwrap(next.select(try selection())); await retry.value
        XCTAssertEqual(next.coordinator.failure, .pending); XCTAssertNil(next.review); XCTAssertEqual(h.reader.executeCount, 1)
    }
    func testWrongRefundReceiptCannotAttachOrConsume() async throws {
        let h = try await harness(); h.reader.wrongRefund = true; try await upload(h)
        XCTAssertFalse(h.flow.canAttach); XCTAssertFalse(h.flow.attach()); XCTAssertNotNil(h.flow.coordinator.receipt)
        XCTAssertEqual(h.draft.value.evidence, "old key")
    }
    func testWrongSelectionReceiptCannotAttachOrConsume() async throws {
        let h = try await harness(); h.reader.wrongSelection = true; try await upload(h)
        XCTAssertFalse(h.flow.canAttach); XCTAssertFalse(h.flow.attach()); XCTAssertNotNil(h.flow.coordinator.receipt)
        XCTAssertEqual(h.draft.value.evidence, "old key")
    }
    func testChangedRefundProofCannotReachUpload() async throws {
        let h = try await harness(); let task = try XCTUnwrap(h.flow.select(try selection())); await task.value
        let review = try XCTUnwrap(h.flow.review)
        var fields = try XCTUnwrap(MerchantBusinessSyntheticFixtures.decode(MerchantBusinessSyntheticFixtures.refund).object)
        fields["reason"] = .string("Changed source")
        h.reader.snapshot = .init(access: h.reader.snapshot.access,
            document: try .init(query: h.reader.snapshot.document.query, payload: .object(fields)))
        let confirm = try XCTUnwrap(h.flow.confirm(review)); await confirm.value
        XCTAssertEqual(h.flow.coordinator.failure, .conflict); XCTAssertEqual(h.reader.executeCount, 0)
        XCTAssertEqual(h.draft.value.evidence, "old key")
    }
    func testInitiallyMismatchedRefundProofIsNotPresentedAsReview() async throws {
        let h = try await harness()
        let query = MerchantBusinessQuery.customer(try .init(61001))
        h.reader.snapshot = .init(access: h.reader.snapshot.access, document: try .init(query: query, payload: MerchantBusinessSyntheticFixtures.payload(query)))
        let task = try XCTUnwrap(h.flow.select(try selection())); await task.value
        XCTAssertNil(h.flow.review); XCTAssertEqual(h.flow.issue, "merchant.business.stale"); XCTAssertEqual(h.reader.executeCount, 0)
    }
    func testDifferentEditorOrParentReviewRetiresOwnership() async throws {
        let h = try await harness(); try await upload(h); h.draft.editorCurrent = false
        XCTAssertFalse(h.flow.canAttach); XCTAssertFalse(h.flow.attach()); XCTAssertEqual(h.draft.value.evidence, "old key")
        let other = try await harness(); other.document.prepare(.aftercare(refund: try .init(62001), decision: .agree, content: "", evidenceKey: nil))
        XCTAssertFalse(other.flow.isCurrent); XCTAssertNil(other.flow.select(try selection()))
    }
    func testSameDataReloadChangesPageRevisionAndCannotReceiveOldEvidence() async throws {
        let h = try await harness(); try await upload(h)
        await h.document.load(.refund(try .init(62001)))
        XCTAssertFalse(h.flow.canAttach); XCTAssertFalse(h.flow.attach()); XCTAssertEqual(h.draft.value.evidence, "old key")
    }
    func testAccountEpochRealmAndAuthorizationChangesRejectAttachment() async throws {
        for mode in 0..<4 {
            let h = try await harness(); try await upload(h)
            let old = try XCTUnwrap(h.reader.scope)
            switch mode {
            case 0: h.reader.scope = .init(realm: old.realm, accountID: old.accountID + 1, epoch: old.epoch)
            case 1: h.reader.scope = .init(realm: old.realm, accountID: old.accountID, epoch: old.epoch + 1)
            case 2: h.reader.scope = .init(realm: "different", accountID: old.accountID, epoch: old.epoch)
            default: h.reader.authorizationGeneration = UUID()
            }
            XCTAssertFalse(h.flow.attach()); XCTAssertTrue(h.draft.attachedKeys.isEmpty); XCTAssertEqual(h.draft.value.evidence, "old key")
        }
    }
    func testChangedRawExplanationDecisionAndEvidenceCannotBeOverwritten() async throws {
        for mode in 0..<3 {
            let h = try await harness(); try await upload(h)
            h.draft.value = .init(decision: mode == 0 ? .agree : .reject,
                content: mode == 1 ? "New explanation" : "Original explanation", evidence: mode == 2 ? "newer key" : "old key")
            let current = h.draft.value; XCTAssertFalse(h.flow.attach()); XCTAssertEqual(h.draft.value, current)
        }
        let a = MerchantAftercareEvidenceDraft(decision: .agree, content: "Caf\u{00E9}", evidence: " raw ")
        XCTAssertNotEqual(a, .init(decision: .agree, content: "Cafe\u{0301}", evidence: " raw "))
        XCTAssertNotEqual(a, .init(decision: .agree, content: "Caf\u{00E9}", evidence: "raw"))
    }
    func testLateProofAfterRetirementCannotReopenOrUpload() async throws {
        let h = try await harness(); h.reader.pauseProof = true
        let task = try XCTUnwrap(h.flow.select(try selection()))
        for _ in 0..<100 where h.reader.continuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(h.reader.continuation)
        h.flow.retire(); continuation.resume(); await task.value
        XCTAssertNil(h.flow.review); XCTAssertNil(h.flow.selection); XCTAssertFalse(h.flow.isCurrent)
        XCTAssertEqual(h.reader.executeCount, 0); XCTAssertEqual(h.draft.value.evidence, "old key")
    }
    func testOwnerRevisionChangeDuringUploadKeepsUnknownReservationAndOriginalDraft() async throws {
        let h = try await harness(); let selectionTask = try XCTUnwrap(h.flow.select(try selection())); await selectionTask.value
        h.reader.pauseExecute = true
        let upload = try XCTUnwrap(h.flow.confirm(try XCTUnwrap(h.flow.review)))
        for _ in 0..<100 where h.reader.executeContinuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(h.reader.executeContinuation)
        XCTAssertEqual(try h.journal.intents().count, 1)
        h.document.invalidate(); h.flow.retire(); continuation.resume(); await upload.value
        XCTAssertEqual(try h.journal.intents().count, 1); XCTAssertEqual(h.reader.executeCount, 1)
        XCTAssertNil(h.flow.coordinator.receipt); XCTAssertFalse(h.flow.attach()); XCTAssertEqual(h.draft.value.evidence, "old key")
    }
    func testLatePickerCallbackAfterBackgroundRetirementCannotPrepareUpload() async throws {
        let h = try await harness(), chosen = try selection()
        XCTAssertTrue(h.flow.canSelect)
        // Merely opening the picker does not select or prepare; the scene observer retires on background.
        XCTAssertEqual(h.reader.proofCount, 0); h.flow.retire()
        XCTAssertNil(h.flow.select(chosen)); XCTAssertEqual(h.reader.proofCount, 0); XCTAssertEqual(h.reader.executeCount, 0)
        XCTAssertEqual(h.draft.value.evidence, "old key")
    }
    func testOwnerChangesDuringConfirmationProofBlockDispatchWithoutViewRetirement() async throws {
        for mode in 0..<3 {
            let h = try await harness(); let selected = try XCTUnwrap(h.flow.select(try selection())); await selected.value
            h.reader.pauseProof = true
            let upload = try XCTUnwrap(h.flow.confirm(try XCTUnwrap(h.flow.review)))
            for _ in 0..<100 where h.reader.continuation == nil { await Task.yield() }
            let continuation = try XCTUnwrap(h.reader.continuation)
            switch mode {
            case 0: h.document.invalidate()
            case 1: h.draft.editorCurrent = false
            default: h.draft.value = .init(decision: .reject, content: "New explanation", evidence: "newer key")
            }
            let current = h.draft.value
            // No flow.retire() or SwiftUI observer is invoked before the proof resumes.
            XCTAssertNil(h.flow.coordinator.reader.scope)
            continuation.resume(); await upload.value
            XCTAssertEqual(h.reader.executeCount, 0); XCTAssertTrue(try h.journal.intents().isEmpty)
            XCTAssertFalse(h.flow.attach()); XCTAssertEqual(h.draft.value, current)
        }
    }
    func testOwnerLossAtFinalAuthorizationBarrierBlocksForwardWithoutViewRetirement() async throws {
        let h = try await harness(); let selected = try XCTUnwrap(h.flow.select(try selection())); await selected.value
        h.reader.pauseBeforeForward = true
        let upload = try XCTUnwrap(h.flow.confirm(try XCTUnwrap(h.flow.review)))
        for _ in 0..<100 where h.reader.forwardContinuation == nil { await Task.yield() }
        let continuation = try XCTUnwrap(h.reader.forwardContinuation)
        XCTAssertEqual(try h.journal.intents().count, 1)
        h.draft.value = .init(decision: .reject, content: "Changed during final barrier", evidence: "newer key")
        XCTAssertNil(h.flow.coordinator.reader.scope)
        continuation.resume(); await upload.value
        XCTAssertEqual(h.reader.executeCount, 0); XCTAssertFalse(h.flow.attach())
        XCTAssertEqual(h.draft.value.evidence, "newer key")
        // The existing conservative post-reservation rule remains authoritative.
        XCTAssertEqual(try h.journal.intents().count, 1)
    }
    func testRetirementIsPermanentAndNoPickerOrUploadOpensDuringBilingualConstruction() async throws {
        let h = try await harness()
        for locale in ["en", "zh-Hans"] {
            let host = UIHostingController(rootView: MerchantAftercareEvidenceSheet(model: h.flow)
                .environment(\.locale, Locale(identifier: locale)).dynamicTypeSize(.accessibility5))
            host.loadViewIfNeeded()
        }
        XCTAssertEqual(h.reader.proofCount, 0); XCTAssertEqual(h.reader.executeCount, 0)
        h.flow.retire(); h.flow.retire(); XCTAssertNil(h.flow.select(try selection())); XCTAssertFalse(h.flow.attach())
        XCTAssertEqual(h.draft.value.evidence, "old key")
    }
}
