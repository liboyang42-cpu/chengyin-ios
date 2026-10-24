import XCTest
import UIKit
@testable import Questify

@MainActor final class ProfileCasePictureSubsetModelTests: XCTestCase {
    private func harness() async throws -> (ProfileEditModel, SubsetService, SubsetSession) {
        let session = try SubsetSession(), service = SubsetService()
        let model = ProfileEditModel(coordinator: .init(service: service, currentSession: { session.value }))
        await model.resetAndLoad(); return (model, service, session)
    }
    private func open(_ model: ProfileEditModel) throws -> ProfileTextFieldEdit {
        model.beginTextEdit(.casePictures); return try XCTUnwrap(model.textEdit)
    }
    func testStageOneDuplicateByOriginalIndexPreservesOtherDraftFieldsWithoutWriting() async throws {
        let (model, service, _) = try await harness(); model.draft.caseIntroduction = "Local description"; model.draft.removesContactQR = true
        XCTAssertTrue(model.confirmCasePictureSubset(try open(model), retainedIndices: [0,2]))
        XCTAssertEqual(model.draft.casePictureSubset?.retainedIndices, [0,2])
        XCTAssertEqual(model.draft.casePictureSubset?.wireValue, "duplicate;last")
        XCTAssertEqual(model.draft.caseIntroduction, "Local description"); XCTAssertTrue(model.draft.removesContactQR)
        XCTAssertEqual(service.writes, 0); XCTAssertEqual(service.reads, 1)
    }
    func testCancelReopenPreservesStagedSubsetAndOldCallbackCannotApply() async throws {
        let (model, service, _) = try await harness()
        XCTAssertTrue(model.confirmCasePictureSubset(try open(model), retainedIndices: [1,2]))
        let before = model.draft, old = try open(model); model.cancelTextEdit(old)
        XCTAssertEqual(model.draft, before)
        let fresh = try open(model)
        XCTAssertEqual(fresh.draft.casePictureSubset?.retainedIndices, [1,2])
        XCTAssertFalse(model.confirmCasePictureSubset(old, retainedIndices: [0]))
        model.cancelTextEdit(old); XCTAssertEqual(model.textEdit?.id, fresh.id); XCTAssertEqual(service.writes, 0)
    }
    func testFullSelectionRestoresExactOriginalAndClearAllStillWorks() async throws {
        let (model, _, _) = try await harness()
        XCTAssertTrue(model.confirmCasePictureSubset(try open(model), retainedIndices: [1]))
        XCTAssertTrue(model.confirmCasePictureSubset(try open(model), retainedIndices: [0,1,2]))
        XCTAssertNil(model.draft.casePictureSubset); XCTAssertTrue(model.requestExit())
        let (other, _, _) = try await harness()
        XCTAssertTrue(other.confirmCasePictureSubset(try open(other), retainedIndices: []))
        XCTAssertTrue(other.draft.removesCasePictures); XCTAssertNil(other.draft.casePictureSubset)
        XCTAssertTrue(other.confirmCasePictureRemoval(try open(other), remove: false))
        XCTAssertFalse(other.draft.removesCasePictures)
    }
    func testReorderDuplicateOrArbitraryTextCannotBeStaged() async throws {
        let (model, source, _) = try await harness(); let edit = try open(model)
        for indices in [[2,0], [0,0], [-1], [3]] {
            XCTAssertFalse(model.confirmCasePictureSubset(edit, retainedIndices: indices))
            XCTAssertNil(model.draft.casePictureSubset)
        }
        XCTAssertFalse(model.confirmTextEdit(edit, text: "replacement")); XCTAssertEqual(source.writes, 0)
    }
    func testChangedOwnerAndDraftABACannotStageAgainstOldSnapshot() async throws {
        let (model, source, session) = try await harness(); let edit = try open(model)
        session.value = try .init(accountID: 902, epoch: 2, token: "synthetic-other", viewerRevision: 2)
        XCTAssertFalse(model.confirmCasePictureSubset(edit, retainedIndices: [0])); XCTAssertEqual(source.writes, 0)
        let (same, _, _) = try await harness(); let old = try open(same), before = same.draft
        same.draft.name = "Temporary"; same.draft = before
        XCTAssertFalse(same.confirmCasePictureSubset(old, retainedIndices: [0]))
    }
    func testReloadAndChangedSourceRetireOldSelectionBeforeAnyWrite() async throws {
        let (model, source, _) = try await harness(); let old = try open(model)
        model.cancelTextEdit(old); source.pictures = "new;images"; await model.load()
        XCTAssertFalse(model.confirmCasePictureSubset(old, retainedIndices: [0])); XCTAssertNil(model.draft.casePictureSubset)
        XCTAssertEqual(source.writes, 0)
    }
    func testExactPictureDriftAtReviewAndPrewriteCannotDeleteNewImages() async throws {
        let (model, source, _) = try await harness()
        XCTAssertTrue(model.confirmCasePictureSubset(try open(model), retainedIndices: [1,2]))
        source.pictures = "new;images"; await model.prepare()
        XCTAssertNil(model.confirmation); XCTAssertEqual(source.writes, 0)
        XCTAssertTrue(model.confirmCasePictureSubset(try open(model), retainedIndices: [1]))
        await model.prepare(); let review = try XCTUnwrap(model.confirmation)
        source.pictures = "newer;images"; await model.save(review)
        XCTAssertEqual(source.writes, 0); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.changed")
    }
    func testAcknowledgedSubsetRequiresExactReadbackAndThenReturnsOnlyOnce() async throws {
        let (model, source, _) = try await harness()
        XCTAssertTrue(model.confirmCasePictureSubset(try open(model), retainedIndices: [1,2]))
        await model.prepare(); let review = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(review.payload.casePics, "duplicate;last")
        let result = await model.save(review), receipt = try XCTUnwrap(result)
        XCTAssertEqual(source.writes, 1); XCTAssertEqual(model.coordinator.snapshot?.casePics, "duplicate;last")
        XCTAssertNil(model.draft.casePictureSubset); XCTAssertTrue(model.consumeSavedReturn(receipt)); XCTAssertFalse(model.consumeSavedReturn(receipt))
    }
    func testUnknownMatchingSubsetReadbackStaysLockedWithoutRepeatWriteOrReturn() async throws {
        let (model, source, _) = try await harness(); source.unknown = true
        XCTAssertTrue(model.confirmCasePictureSubset(try open(model), retainedIndices: [0,2]))
        await model.prepare(); let review = try XCTUnwrap(model.confirmation), receipt = await model.save(review)
        XCTAssertNil(receipt); XCTAssertTrue(model.coordinator.isLocked)
        await model.requestReload(); XCTAssertTrue(model.coordinator.isLocked)
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.readbackUnconfirmed"); XCTAssertEqual(source.writes, 1)
    }
    func testRejectedSaveAndFailedRefreshKeepSubsetProposal() async throws {
        let (model, source, _) = try await harness(); source.rejected = true
        XCTAssertTrue(model.confirmCasePictureSubset(try open(model), retainedIndices: [0,2]))
        await model.prepare(); let value = try XCTUnwrap(model.confirmation), receipt = await model.save(value)
        XCTAssertNil(receipt); XCTAssertEqual(model.draft.casePictureSubset?.retainedIndices, [0,2])
        source.failRead = true; await model.load()
        XCTAssertEqual(model.draft.casePictureSubset?.retainedIndices, [0,2]); XCTAssertEqual(source.writes, 1)
    }
}

@MainActor private final class SubsetSession {
    var value: ProfileEditSession?
    init() throws { value = try .init(accountID: 901, epoch: 1, token: "synthetic-subset", viewerRevision: 1) }
}
@MainActor private final class SubsetService: ProfileEditServing {
    var pictures = "duplicate;duplicate;last", name = "Original", introduction = "Original intro"
    var unknown = false, rejected = false, failRead = false
    var writes = 0, reads = 0
    func read(token: String) async throws -> ProfileEditSnapshot {
        reads += 1; if failRead { throw APIError.httpStatus(503) }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject:
            ["id": 901, "nickname": name, "introduction": introduction, "avatar": "avatar", "wechat": "qr",
             "casePics": pictures, "caseIntroducton": "Case", "tagIds": "4,7"]))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        writes += 1
        if rejected { throw ProfileEditWriteError.rejected(.init(code: 422)) }
        pictures = payload.casePics; name = payload.name; introduction = payload.introduction
        if unknown { throw ProfileEditWriteError.outcomeUnknown }
    }
}

// Exercise the same Binding and owner-retirement entry points used by the real host.
extension ProfileCasePictureSubsetModelTests {
    func testBackgroundRetirementRejectsOldApplyAndHiddenReopenWithoutChangingDraft() async throws {
        let (model, service, _) = try await harness()
        model.draft.caseIntroduction = "Unsaved description"
        let old = try open(model), before = model.draft
        model.retireAvatar()
        XCTAssertNil(model.textEdit)
        XCTAssertFalse(model.canBeginTextEdit)
        XCTAssertFalse(model.confirmCasePictureSubset(old, retainedIndices: [0]))
        model.beginTextEdit(.casePictures)
        XCTAssertNil(model.textEdit)
        XCTAssertEqual(model.draft, before)
        model.activateAvatar()
        let fresh = try open(model)
        XCTAssertNotEqual(fresh.id, old.id)
        XCTAssertFalse(model.confirmCasePictureSubset(old, retainedIndices: [1]))
        model.cancelTextEdit(old)
        XCTAssertEqual(model.textEdit?.id, fresh.id)
        XCTAssertEqual(model.draft, before)
        XCTAssertEqual(service.writes, 0)
    }

    func testActualAnchorDismantleRetiresOpenEditorAndOldBindingCannotReachReopenedEditor() async throws {
        let (model, service, _) = try await harness()
        let old = try open(model), oldBinding = model.textEditPresentation(for: model.textEdit), before = model.draft
        let anchor = ProfileAvatarOwnerAnchor(model: model)
        ProfileAvatarOwnerAnchor.dismantleUIViewController(UIViewController(), coordinator: anchor.makeCoordinator())
        XCTAssertNil(model.textEdit)
        XCTAssertNil(oldBinding.wrappedValue)
        XCTAssertFalse(model.confirmCasePictureSubset(old, retainedIndices: [0]))
        XCTAssertEqual(model.draft, before)
        model.activateAvatar()
        let fresh = try open(model), freshBinding = model.textEditPresentation(for: model.textEdit)
        XCTAssertNil(oldBinding.wrappedValue)
        oldBinding.wrappedValue = nil
        XCTAssertEqual(freshBinding.wrappedValue?.id, fresh.id)
        XCTAssertTrue(model.confirmCasePictureSubset(fresh, retainedIndices: [1,2]))
        XCTAssertEqual(model.draft.casePictureSubset?.retainedIndices, [1,2])
        XCTAssertEqual(service.writes, 0)
    }

    func testInitialNilAndCancelledBindingsCannotReadWriteOrCloseSuccessor() async throws {
        let (model, service, _) = try await harness()
        let initial = model.textEditPresentation(for: model.textEdit)
        XCTAssertNil(initial.wrappedValue)
        let old = try open(model), oldBinding = model.textEditPresentation(for: model.textEdit)
        XCTAssertEqual(oldBinding.wrappedValue?.id, old.id)
        XCTAssertNil(initial.wrappedValue)
        initial.wrappedValue = nil
        XCTAssertEqual(model.textEdit?.id, old.id)
        oldBinding.wrappedValue = nil
        XCTAssertNil(model.textEdit)
        let fresh = try open(model), freshBinding = model.textEditPresentation(for: model.textEdit)
        XCTAssertNotEqual(old.id, fresh.id)
        XCTAssertNil(initial.wrappedValue)
        XCTAssertNil(oldBinding.wrappedValue)
        initial.wrappedValue = fresh
        oldBinding.wrappedValue = fresh
        oldBinding.wrappedValue = nil
        initial.wrappedValue = nil
        XCTAssertEqual(freshBinding.wrappedValue?.id, fresh.id)
        XCTAssertFalse(model.confirmCasePictureSubset(old, retainedIndices: [0]))
        freshBinding.wrappedValue = nil
        XCTAssertNil(model.textEdit)
        XCTAssertNil(model.draft.casePictureSubset)
        XCTAssertEqual(service.writes, 0)
    }
}
