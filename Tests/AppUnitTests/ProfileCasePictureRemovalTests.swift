import XCTest
@testable import Questify

@MainActor private final class ProfileCaseRemovalSessionBox {
    var value: ProfileEditSession?
    init() throws { value = try .init(accountID: 901, epoch: 1, token: "synthetic-case-removal", viewerRevision: 1) }
}
@MainActor private final class ProfileCaseRemovalService: ProfileEditServing {
    var reads = 0, saves = 0
    var unknown = false, rejected = false, failRead = false
    var readbackPictures: String?
    var captured: ProfileEditPayload?
    var fields: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Walks",
        "avatar": " original-avatar ", "wechat": " original-qr ", "casePics": " one ;two; one ", "caseIntroducton": "Case", "tagIds": "4,7"]
    func read(token: String) async throws -> ProfileEditSnapshot {
        reads += 1; if failRead { throw APIError.malformedResponse }
        var data = fields; if saves > 0, let readbackPictures { data["casePics"] = readbackPictures }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: data))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        saves += 1; captured = payload
        if rejected { throw ProfileEditWriteError.rejected(.init(code: 422, message: "Synthetic rejection")) }
        if unknown { throw ProfileEditWriteError.outcomeUnknown }
        fields["nickname"] = payload.name; fields["introduction"] = payload.introduction
        fields["wechat"] = payload.wechat; fields["tagIds"] = payload.tagIds; fields["casePics"] = payload.casePics
        if let text = payload.caseIntroduction { fields["caseIntroducton"] = text }
    }
}
@MainActor final class ProfileCasePictureRemovalModelTests: XCTestCase {
    private func harness() async throws -> (ProfileEditModel, ProfileCaseRemovalService, ProfileCaseRemovalSessionBox) {
        let source = ProfileCaseRemovalService(), session = try ProfileCaseRemovalSessionBox()
        let model = ProfileEditModel(coordinator: .init(service: source, currentSession: { session.value }))
        await model.resetAndLoad(); return (model, source, session)
    }
    private func open(_ model: ProfileEditModel) throws -> ProfileTextFieldEdit {
        model.beginTextEdit(.casePictures); return try XCTUnwrap(model.textEdit)
    }
    func testOpenAndCancelKeepPageDraftAndDoNotReadOrWrite() async throws {
        let (model, source, _) = try await harness(); model.draft.caseIntroduction = "Local case"
        let before = model.draft, edit = try open(model); model.cancelTextEdit(edit)
        XCTAssertEqual(model.draft, before); XCTAssertFalse(model.confirmCasePictureRemoval(edit, remove: true))
        XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0)
    }
    func testClearOnlyStagesFlagAndPreservesAllOtherLocalFields() async throws {
        let (model, source, _) = try await harness(); model.draft.caseIntroduction = "Local case"; model.draft.removesContactQR = true; model.draft.routePreferenceIDs = [7]
        XCTAssertTrue(model.confirmCasePictureRemoval(try open(model), remove: true)); XCTAssertTrue(model.draft.removesCasePictures)
        XCTAssertEqual(model.draft.caseIntroduction, "Local case"); XCTAssertTrue(model.draft.removesContactQR)
        XCTAssertEqual(model.draft.routePreferenceIDs, [7]); XCTAssertEqual(model.draft.name, "Trail Friend"); XCTAssertEqual(source.saves, 0)
    }
    func testReopenCancelRetainsStagedRemovalAndKeepAllReversesProposal() async throws {
        let (model, _, _) = try await harness(); XCTAssertTrue(model.confirmCasePictureRemoval(try open(model), remove: true))
        let edit = try open(model); XCTAssertTrue(edit.draft.removesCasePictures); model.cancelTextEdit(edit)
        XCTAssertTrue(model.draft.removesCasePictures); XCTAssertTrue(model.confirmCasePictureRemoval(try open(model), remove: false))
        XCTAssertFalse(model.draft.removesCasePictures); XCTAssertTrue(model.requestExit())
    }
    func testArbitraryReplacementAndPartialImageStringCannotBeStaged() async throws {
        for proposed in ["replacement", "one", "one;two"] {
            let (model, source, _) = try await harness(); let edit = try open(model); XCTAssertEqual(edit.originalText, "")
            XCTAssertFalse(model.confirmTextEdit(edit, text: proposed)); XCTAssertFalse(model.draft.removesCasePictures); XCTAssertEqual(source.saves, 0)
        }
    }
    func testConfirmationCannotBeAppliedToAnotherField() async throws {
        let (model, _, _) = try await harness(); model.beginTextEdit(.caseIntroduction); let edit = try XCTUnwrap(model.textEdit)
        XCTAssertFalse(model.confirmCasePictureRemoval(edit, remove: true)); XCTAssertEqual(model.textEdit?.id, edit.id)
        XCTAssertNil(model.draft.caseIntroduction)
    }
    func testOldApplyCancelAndDraftABACannotAffectNewEditor() async throws {
        let (model, _, _) = try await harness(); let old = try open(model), before = model.draft
        model.draft.name = "Temporary"; model.draft = before; XCTAssertFalse(model.confirmCasePictureRemoval(old, remove: true))
        let fresh = try open(model); model.cancelTextEdit(old); XCTAssertEqual(model.textEdit?.id, fresh.id)
        XCTAssertFalse(model.confirmCasePictureRemoval(old, remove: false)); XCTAssertEqual(model.textEdit?.id, fresh.id)
    }
    func testOwnerEpochAndViewerChangeInvalidateClearWithoutRequest() async throws {
        for next in [(902, UInt64(1), UInt64(1)), (901, UInt64(2), UInt64(1)), (901, UInt64(1), UInt64(2))] {
            let (model, source, session) = try await harness(); let edit = try open(model)
            session.value = try .init(accountID: next.0, epoch: next.1, token: "synthetic-case-removal", viewerRevision: next.2)
            XCTAssertFalse(model.confirmCasePictureRemoval(edit, remove: true)); XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0)
        }
    }
    func testExactSourceDriftRejectsOldLocalEditor() async throws {
        let (model, source, _) = try await harness(); source.fields["casePics"] = "é"; await model.load(); let edit = try open(model)
        source.fields["casePics"] = "e\u{301}"; _ = await model.coordinator.load()
        XCTAssertFalse(model.confirmCasePictureRemoval(edit, remove: true)); XCTAssertEqual(source.saves, 0)
    }
    func testClearIsDirtyForWholePageExitAndReload() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmCasePictureRemoval(try open(model), remove: true))
        XCTAssertFalse(model.requestExit()); XCTAssertNotNil(model.exitConfirmation); model.cancelExit()
        await model.requestReload(); XCTAssertNotNil(model.reloadConfirmation); model.cancelReload()
        XCTAssertTrue(model.draft.removesCasePictures); XCTAssertEqual(source.reads, 1)
    }
    func testDescriptionEditRetainsImageRemovalAndReopenCapturesPendingState() async throws {
        let (model, _, _) = try await harness(); XCTAssertTrue(model.confirmCasePictureRemoval(try open(model), remove: true))
        model.beginTextEdit(.caseIntroduction); let edit = try XCTUnwrap(model.textEdit); XCTAssertTrue(edit.draft.removesCasePictures)
        XCTAssertTrue(model.confirmTextEdit(edit, text: "Updated description")); XCTAssertTrue(model.draft.removesCasePictures)
    }
    func testReviewAndKnownSaveRequireEmptyImageReadback() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmCasePictureRemoval(try open(model), remove: true)); await model.prepare()
        let review = try XCTUnwrap(model.confirmation); XCTAssertTrue(review.payload.removesCasePictures); XCTAssertEqual(review.payload.casePics, "")
        XCTAssertEqual(source.saves, 0); await model.save(review); XCTAssertEqual(source.saves, 1)
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved"); XCTAssertEqual(model.coordinator.snapshot?.casePics, "")
        XCTAssertFalse(model.draft.removesCasePictures)
    }
    func testChangedImagesBeforeReviewOrSaveCannotBeCleared() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmCasePictureRemoval(try open(model), remove: true))
        source.fields["casePics"] = "Remote"; await model.prepare(); XCTAssertNil(model.confirmation); XCTAssertEqual(source.saves, 0)
        XCTAssertTrue(model.confirmCasePictureRemoval(try open(model), remove: true)); await model.prepare(); let review = try XCTUnwrap(model.confirmation)
        source.fields["casePics"] = "Newer"; await model.save(review); XCTAssertEqual(source.saves, 0)
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.changed")
    }
    func testUnicodeOnlyPrewriteImageDriftPreventsDeletion() async throws {
        let (model, source, _) = try await harness(); source.fields["casePics"] = "é"; await model.load()
        XCTAssertTrue(model.confirmCasePictureRemoval(try open(model), remove: true)); await model.prepare(); let review = try XCTUnwrap(model.confirmation)
        source.fields["casePics"] = "e\u{301}"; await model.save(review); XCTAssertEqual(source.saves, 0)
    }
    func testAcknowledgedSaveStaysLockedForNonemptyReadbackThenReconciles() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmCasePictureRemoval(try open(model), remove: true)); await model.prepare()
        source.readbackPictures = "Still present"; await model.save(try XCTUnwrap(model.confirmation)); XCTAssertTrue(model.coordinator.isLocked)
        source.readbackPictures = nil; await model.requestReload(); XCTAssertFalse(model.coordinator.isLocked); XCTAssertEqual(source.saves, 1)
    }
    func testUnknownClearRemainsLockedEvenWithEmptyReadbackAndNeverRepeatsPost() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmCasePictureRemoval(try open(model), remove: true)); await model.prepare()
        source.unknown = true; await model.save(try XCTUnwrap(model.confirmation)); source.fields["casePics"] = ""; await model.requestReload()
        XCTAssertTrue(model.coordinator.isLocked); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.readbackUnconfirmed")
        model.beginTextEdit(.casePictures); XCTAssertNil(model.textEdit); XCTAssertEqual(source.saves, 1)
    }
    func testRejectedWriteAndFailedRefreshKeepRemovalProposal() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmCasePictureRemoval(try open(model), remove: true)); await model.prepare()
        source.rejected = true; await model.save(try XCTUnwrap(model.confirmation)); XCTAssertTrue(model.draft.removesCasePictures)
        source.failRead = true; await model.requestReload(); let task = try XCTUnwrap(model.confirmReload(try XCTUnwrap(model.reloadConfirmation)))
        await task.value; XCTAssertTrue(model.draft.removesCasePictures); XCTAssertEqual(source.saves, 1)
    }
    func testSavedImagesCannotBeRestoredThroughStaleEditorAction() async throws {
        let (model, source, _) = try await harness(); let old = try open(model)
        XCTAssertTrue(model.confirmCasePictureRemoval(old, remove: true)); await model.prepare(); await model.save(try XCTUnwrap(model.confirmation))
        XCTAssertFalse(model.confirmCasePictureRemoval(old, remove: false)); XCTAssertEqual(model.coordinator.snapshot?.casePics, "")
        XCTAssertTrue(model.confirmCasePictureRemoval(try open(model), remove: false)); XCTAssertFalse(model.draft.removesCasePictures); XCTAssertEqual(source.saves, 1)
    }
}
