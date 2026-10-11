import XCTest
@testable import Questify

@MainActor private final class ProfileQRSessionBox {
    var value: ProfileEditSession?
    init() throws { value = try .init(accountID: 901, epoch: 1, token: "synthetic-profile-qr", viewerRevision: 1) }
}
@MainActor private final class ProfileQRService: ProfileEditServing {
    var reads = 0, saves = 0
    var unknown = false, rejected = false, failRead = false
    var readbackQR: String?
    var captured: ProfileEditPayload?
    var fields: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Walks",
        "avatar": " original-avatar ", "wechat": " https://qr.invalid/e\u{301}.png ", "casePics": " one ;two ", "caseIntroducton": "Case", "tagIds": "4,7"]
    func read(token: String) async throws -> ProfileEditSnapshot {
        reads += 1
        if failRead { throw APIError.malformedResponse }
        var data = fields; if saves > 0, let readbackQR { data["wechat"] = readbackQR }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: data))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        saves += 1; captured = payload
        if rejected { throw ProfileEditWriteError.rejected(.init(code: 422, message: "Synthetic rejection")) }
        if unknown { throw ProfileEditWriteError.outcomeUnknown }
        fields["nickname"] = payload.name; fields["introduction"] = payload.introduction
        fields["wechat"] = payload.wechat; fields["tagIds"] = payload.tagIds
        if let text = payload.caseIntroduction { fields["caseIntroducton"] = text }
    }
}
@MainActor final class ProfileContactQRRemovalModelTests: XCTestCase {
    private func harness() async throws -> (ProfileEditModel, ProfileQRService, ProfileQRSessionBox) {
        let source = ProfileQRService(), session = try ProfileQRSessionBox()
        let model = ProfileEditModel(coordinator: .init(service: source, currentSession: { session.value }))
        await model.resetAndLoad(); return (model, source, session)
    }
    private func open(_ model: ProfileEditModel) throws -> ProfileTextFieldEdit {
        model.beginTextEdit(.contactQR); return try XCTUnwrap(model.textEdit)
    }
    func testOpenAndCancelDoNotChangePageDraftOrDispatch() async throws {
        let (model, source, _) = try await harness(); model.draft.caseIntroduction = "Local case"; model.draft.routePreferenceIDs = [7, 4]
        let before = model.draft, edit = try open(model); model.cancelTextEdit(edit)
        XCTAssertEqual(model.draft, before); XCTAssertFalse(model.confirmContactQR(edit, remove: true))
        XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0)
    }
    func testConfirmRemovalOnlyStagesFlagAndRetainsEveryOtherField() async throws {
        let (model, source, _) = try await harness(); model.draft.caseIntroduction = "Local case"; model.draft.routePreferenceIDs = [7, 4]
        let old = model.draft; XCTAssertTrue(model.confirmContactQR(try open(model), remove: true))
        XCTAssertTrue(model.draft.removesContactQR); XCTAssertEqual(model.draft.name, old.name)
        XCTAssertEqual(model.draft.introduction, old.introduction); XCTAssertEqual(model.draft.caseIntroduction, old.caseIntroduction)
        XCTAssertEqual(model.draft.routePreferenceIDs, old.routePreferenceIDs); XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0)
    }
    func testReopenCancelRetainsRemovalAndRestoreClearsOnlyProposal() async throws {
        let (model, _, _) = try await harness(); XCTAssertTrue(model.confirmContactQR(try open(model), remove: true))
        let cancelled = try open(model); XCTAssertTrue(cancelled.draft.removesContactQR); model.cancelTextEdit(cancelled)
        XCTAssertTrue(model.draft.removesContactQR)
        XCTAssertTrue(model.confirmContactQR(try open(model), remove: false)); XCTAssertFalse(model.draft.removesContactQR)
        XCTAssertTrue(model.requestExit())
    }
    func testArbitraryQRCodeReplacementIsRejectedAndOriginalNeverShownAsInput() async throws {
        let (model, source, _) = try await harness(); let edit = try open(model)
        XCTAssertEqual(edit.originalText, "")
        XCTAssertFalse(model.confirmTextEdit(edit, text: "https://unapproved.invalid/new.png"))
        XCTAssertFalse(model.draft.removesContactQR); XCTAssertEqual(source.saves, 0)
    }
    func testBooleanConfirmationCannotEditAnotherField() async throws {
        let (model, _, _) = try await harness(); model.beginTextEdit(.name); let edit = try XCTUnwrap(model.textEdit)
        XCTAssertFalse(model.confirmContactQR(edit, remove: true)); XCTAssertEqual(model.textEdit?.id, edit.id)
        XCTAssertEqual(model.draft.name, "Trail Friend")
    }
    func testOldApplyAndCancelCannotTouchNewerFieldSession() async throws {
        let (model, _, _) = try await harness(); let old = try open(model)
        XCTAssertTrue(model.confirmContactQR(old, remove: true)); let fresh = try open(model)
        model.cancelTextEdit(old); XCTAssertEqual(model.textEdit?.id, fresh.id)
        XCTAssertFalse(model.confirmContactQR(old, remove: false)); XCTAssertEqual(model.textEdit?.id, fresh.id)
        XCTAssertTrue(model.draft.removesContactQR)
    }
    func testDraftABAAndUnicodeQRSourceDriftRejectOldAction() async throws {
        let (model, source, _) = try await harness(); let first = try open(model), before = model.draft
        model.draft.name = "Temporary"; model.draft = before; XCTAssertFalse(model.confirmContactQR(first, remove: true))
        source.fields["wechat"] = "é"; await model.load(); let second = try open(model)
        source.fields["wechat"] = "e\u{301}"; _ = await model.coordinator.load()
        XCTAssertFalse(model.confirmContactQR(second, remove: true)); XCTAssertEqual(source.saves, 0)
    }
    func testOwnerEpochAndViewerChangeRejectsRemovalWithoutRequest() async throws {
        for next in [(902, UInt64(1), UInt64(1)), (901, UInt64(2), UInt64(1)), (901, UInt64(1), UInt64(2))] {
            let (model, source, session) = try await harness(); let edit = try open(model)
            session.value = try .init(accountID: next.0, epoch: next.1, token: "synthetic-profile-qr", viewerRevision: next.2)
            XCTAssertFalse(model.confirmContactQR(edit, remove: true)); XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0)
        }
    }
    func testRemovalIsDirtyForWholePageExitAndReload() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmContactQR(try open(model), remove: true))
        XCTAssertFalse(model.requestExit()); XCTAssertNotNil(model.exitConfirmation); model.cancelExit()
        await model.requestReload(); XCTAssertNotNil(model.reloadConfirmation); model.cancelReload()
        XCTAssertTrue(model.draft.removesContactQR); XCTAssertEqual(source.reads, 1)
    }
    func testOtherFieldChangesRetainPendingRemoval() async throws {
        let (model, _, _) = try await harness(); XCTAssertTrue(model.confirmContactQR(try open(model), remove: true))
        model.beginTextEdit(.name); XCTAssertTrue(model.confirmTextEdit(try XCTUnwrap(model.textEdit), text: "Updated"))
        model.beginTextEdit(.caseIntroduction); XCTAssertTrue(model.confirmTextEdit(try XCTUnwrap(model.textEdit), text: "Updated case"))
        XCTAssertTrue(model.draft.removesContactQR)
    }
    func testReviewIdentifiesRemovalAndSaveVerifiesEmptyReadback() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmContactQR(try open(model), remove: true)); await model.prepare()
        let review = try XCTUnwrap(model.confirmation); XCTAssertTrue(review.payload.removesContactQR)
        XCTAssertEqual(review.payload.wechat, ""); XCTAssertEqual(source.saves, 0)
        await model.save(review); XCTAssertEqual(source.saves, 1); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved")
        XCTAssertEqual(model.coordinator.snapshot?.wechat, ""); XCTAssertFalse(model.draft.removesContactQR)
        XCTAssertTrue(try open(model).snapshot.wechat.isEmpty)
    }
    func testNewQRCodeBeforeReviewOrBeforeSavePreventsDeletion() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmContactQR(try open(model), remove: true))
        source.fields["wechat"] = "Remote QR"; await model.prepare(); XCTAssertNil(model.confirmation); XCTAssertEqual(source.saves, 0)
        XCTAssertTrue(model.confirmContactQR(try open(model), remove: true)); await model.prepare(); let review = try XCTUnwrap(model.confirmation)
        source.fields["wechat"] = "Newer QR"; await model.save(review); XCTAssertEqual(source.saves, 0)
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.changed")
    }
    func testUnicodeOnlyQRCodeDriftAfterReviewCannotBeDeleted() async throws {
        let (model, source, _) = try await harness(); source.fields["wechat"] = "é"; await model.load()
        XCTAssertTrue(model.confirmContactQR(try open(model), remove: true)); await model.prepare(); let review = try XCTUnwrap(model.confirmation)
        source.fields["wechat"] = "e\u{301}"; await model.save(review); XCTAssertEqual(source.saves, 0)
    }
    func testKnownAckWithOldQRCodeReadbackStaysLockedUntilEmptyReadback() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmContactQR(try open(model), remove: true)); await model.prepare()
        source.readbackQR = "Still present"; await model.save(try XCTUnwrap(model.confirmation))
        XCTAssertTrue(model.coordinator.isLocked); XCTAssertTrue(model.draft.removesContactQR)
        source.readbackQR = nil; await model.requestReload()
        XCTAssertFalse(model.coordinator.isLocked); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved"); XCTAssertEqual(source.saves, 1)
    }
    func testUnknownRemovalNeverUnlocksOrRepeatsPostOnEmptyReadback() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmContactQR(try open(model), remove: true)); await model.prepare()
        source.unknown = true; await model.save(try XCTUnwrap(model.confirmation)); source.fields["wechat"] = ""
        await model.requestReload(); XCTAssertTrue(model.coordinator.isLocked); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.readbackUnconfirmed")
        model.beginTextEdit(.contactQR); XCTAssertNil(model.textEdit); XCTAssertEqual(source.saves, 1)
    }
    func testRejectedRemovalAndFailedRefreshKeepTheProposal() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmContactQR(try open(model), remove: true)); await model.prepare()
        source.rejected = true; await model.save(try XCTUnwrap(model.confirmation)); XCTAssertTrue(model.draft.removesContactQR)
        source.failRead = true; await model.requestReload(); let reload = try XCTUnwrap(model.confirmReload(try XCTUnwrap(model.reloadConfirmation)))
        await reload.value; XCTAssertTrue(model.draft.removesContactQR); XCTAssertEqual(source.saves, 1)
    }
    func testSuccessfulRemovalCannotRestoreOldQRWithAStaleAction() async throws {
        let (model, source, _) = try await harness(); let old = try open(model)
        XCTAssertTrue(model.confirmContactQR(old, remove: true)); await model.prepare(); await model.save(try XCTUnwrap(model.confirmation))
        XCTAssertFalse(model.confirmContactQR(old, remove: false)); XCTAssertEqual(model.coordinator.snapshot?.wechat, "")
        XCTAssertTrue(model.confirmContactQR(try open(model), remove: false)); XCTAssertFalse(model.draft.removesContactQR)
        XCTAssertEqual(source.saves, 1)
    }
}
