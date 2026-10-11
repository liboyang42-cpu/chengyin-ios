import XCTest
@testable import Questify

@MainActor private final class ProfileCaseSessionBox {
    var value: ProfileEditSession?
    init() throws { value = try .init(accountID: 901, epoch: 1, token: "synthetic-profile-case", viewerRevision: 1) }
}
@MainActor private final class ProfileCaseService: ProfileEditServing {
    var reads = 0, saves = 0
    var unknown = false, rejected = false, failRead = false
    var readbackOverride: String?
    var captured: ProfileEditPayload?
    var fields: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Weekend walks",
        "avatar": " original-avatar ", "wechat": " original-wechat ", "casePics": " one ;two; one ",
        "tagIds": "4,7", "caseIntroducton": "  City e\u{301}\nStories "]
    func read(token: String) async throws -> ProfileEditSnapshot {
        reads += 1
        if failRead { throw APIError.malformedResponse }
        var result = fields
        if saves > 0, let readbackOverride { result["caseIntroducton"] = readbackOverride }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: result))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        saves += 1; captured = payload
        if rejected { throw ProfileEditWriteError.rejected(.init(code: 422, message: "Synthetic rejection")) }
        if unknown { throw ProfileEditWriteError.outcomeUnknown }
        fields["nickname"] = payload.name; fields["introduction"] = payload.introduction; fields["tagIds"] = payload.tagIds
        if let text = payload.caseIntroduction { fields["caseIntroducton"] = text }
    }
}
@MainActor final class ProfileCasePortfolioModelTests: XCTestCase {
    private func harness() async throws -> (ProfileEditModel, ProfileCaseService, ProfileCaseSessionBox) {
        let source = ProfileCaseService(), session = try ProfileCaseSessionBox()
        let model = ProfileEditModel(coordinator: .init(service: source, currentSession: { session.value }))
        await model.resetAndLoad(); return (model, source, session)
    }
    private func open(_ model: ProfileEditModel) throws -> ProfileTextFieldEdit {
        model.beginTextEdit(.caseIntroduction); return try XCTUnwrap(model.textEdit)
    }
    func testOpenCopiesExactServerDescriptionAndCancelDoesNotTouchAnyDraft() async throws {
        let (model, source, _) = try await harness(); model.draft.name = "Other name"; model.draft.routePreferenceIDs = [7, 4]
        let before = model.draft, edit = try open(model)
        XCTAssertEqual(Array(edit.originalText.utf8), Array("  City e\u{301}\nStories ".utf8))
        model.cancelTextEdit(edit); XCTAssertEqual(model.draft, before)
        XCTAssertFalse(model.confirmTextEdit(edit, text: "cancelled")); XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0)
    }
    func testConfirmStagesOnlyCaseBytesAndReopenUsesStagedValue() async throws {
        let (model, source, _) = try await harness(); model.draft.routePreferenceIDs = [7, 4]
        let raw = " \te\u{301}\n作品 "; XCTAssertTrue(model.confirmTextEdit(try open(model), text: raw))
        XCTAssertEqual(Array(try XCTUnwrap(model.draft.caseIntroduction).utf8), Array(raw.utf8))
        XCTAssertEqual(model.draft.name, "Trail Friend"); XCTAssertEqual(model.draft.introduction, "Weekend walks")
        XCTAssertEqual(model.draft.routePreferenceIDs, [7, 4]); XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0)
        let reopened = try open(model); XCTAssertEqual(Array(reopened.originalText.utf8), Array(raw.utf8))
    }
    func testConfirmingOriginalDescriptionRestoresUntouchedOmission() async throws {
        let (model, source, _) = try await harness(); let first = try open(model), original = first.originalText
        XCTAssertTrue(model.confirmTextEdit(first, text: "Local case"))
        XCTAssertTrue(model.confirmTextEdit(try open(model), text: original)); XCTAssertNil(model.draft.caseIntroduction)
        XCTAssertFalse(model.draft.hasChanges(comparedTo: try XCTUnwrap(model.coordinator.snapshot)))
        XCTAssertTrue(model.requestExit()); XCTAssertEqual(source.saves, 0)
    }
    func testCaseOnlyDirtyDraftRequiresExitAndReloadReview() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmTextEdit(try open(model), text: "Changed"))
        XCTAssertTrue(model.blocksInteractiveExit); XCTAssertFalse(model.requestExit()); XCTAssertNotNil(model.exitConfirmation)
        model.cancelExit(); await model.requestReload(); XCTAssertNotNil(model.reloadConfirmation)
        model.cancelReload(); XCTAssertEqual(model.draft.caseIntroduction, "Changed"); XCTAssertEqual(source.reads, 1)
    }
    func testCaseDraftSurvivesEditingOtherTextAndPreferenceFields() async throws {
        let (model, _, _) = try await harness(); XCTAssertTrue(model.confirmTextEdit(try open(model), text: "Case text"))
        model.beginTextEdit(.name); XCTAssertTrue(model.confirmTextEdit(try XCTUnwrap(model.textEdit), text: "New name"))
        model.beginTextEdit(.introduction); XCTAssertTrue(model.confirmTextEdit(try XCTUnwrap(model.textEdit), text: "New bio"))
        model.draft.routePreferenceIDs = []
        XCTAssertEqual(model.draft.caseIntroduction, "Case text")
    }
    func testMissingDescriptionStillAllowsImageInspectionButCannotStageText() async throws {
        let (model, source, _) = try await harness(); source.fields.removeValue(forKey: "caseIntroducton"); await model.load()
        let edit = try open(model); XCTAssertNil(edit.snapshot.caseIntroduction)
        XCTAssertEqual(ProfileCasePortfolio(casePics: edit.snapshot.casePics).images, [" one ", "two", " one "])
        XCTAssertFalse(model.confirmTextEdit(edit, text: "invented baseline")); XCTAssertNil(model.draft.caseIntroduction)
        XCTAssertEqual(source.saves, 0)
    }
    func testLocalEditAndSnapshotUnicodeDriftCannotConsumeNewerState() async throws {
        let (model, source, _) = try await harness(); source.fields["caseIntroducton"] = "é"; await model.load()
        let edit = try open(model); source.fields["caseIntroducton"] = "e\u{301}"; _ = await model.coordinator.load()
        XCTAssertFalse(model.confirmTextEdit(edit, text: "stale")); XCTAssertEqual(source.saves, 0)
    }
    func testAccountAndViewerChangeRejectCaseActionWithoutWriting() async throws {
        for changed in [(902, UInt64(1), UInt64(1)), (901, UInt64(2), UInt64(1)), (901, UInt64(1), UInt64(2))] {
            let (model, source, session) = try await harness(); let edit = try open(model)
            session.value = try .init(accountID: changed.0, epoch: changed.1, token: "synthetic-profile-case", viewerRevision: changed.2)
            XCTAssertFalse(model.confirmTextEdit(edit, text: "stale")); XCTAssertEqual(source.reads, 1); XCTAssertEqual(source.saves, 0)
        }
    }
    func testBackgroundRetainsCaseScratchAndCancelReopenUsesOriginal() async throws {
        let (model, source, _) = try await harness(); let first = try open(model)
        model.retireReload(); model.retireAvatar(); model.activateAvatar()
        XCTAssertEqual(model.textEdit?.id, first.id); model.cancelTextEdit(first)
        let reopened = try open(model); XCTAssertEqual(reopened.originalText, first.originalText); XCTAssertEqual(source.reads, 1)
    }
    func testPreparedCaseReviewUsesExactBytesAndPreservesAllMedia() async throws {
        let (model, source, _) = try await harness(); let raw = "  e\u{301}\nCase "
        XCTAssertTrue(model.confirmTextEdit(try open(model), text: raw)); await model.prepare()
        let review = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(Array(try XCTUnwrap(review.payload.caseIntroduction).utf8), Array(raw.utf8))
        XCTAssertEqual(review.payload.casePics, " one ;two; one "); XCTAssertEqual(review.payload.avatar, " original-avatar ")
        XCTAssertEqual(review.payload.wechat, " original-wechat "); XCTAssertEqual(source.reads, 2); XCTAssertEqual(source.saves, 0)
    }
    func testCaseOnlySaveIsReadBackAndReopensSavedDescription() async throws {
        let (model, source, _) = try await harness(); let text = "  Saved e\u{301}\n"
        XCTAssertTrue(model.confirmTextEdit(try open(model), text: text)); await model.prepare()
        await model.save(try XCTUnwrap(model.confirmation)); XCTAssertEqual(source.saves, 1)
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved"); XCTAssertFalse(model.coordinator.isLocked)
        XCTAssertNil(model.draft.caseIntroduction)
        XCTAssertEqual(Array(try open(model).originalText.utf8), Array(text.utf8))
    }
    func testCaseClearSerializesEmptyAndVerifiesReadback() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmTextEdit(try open(model), text: ""))
        await model.prepare(); await model.save(try XCTUnwrap(model.confirmation))
        XCTAssertEqual(source.captured?.caseIntroduction, ""); XCTAssertEqual(model.coordinator.snapshot?.caseIntroduction, "")
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved")
    }
    func testConcurrentDescriptionChangeBeforeReviewDoesNotWrite() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmTextEdit(try open(model), text: "Local"))
        source.fields["caseIntroducton"] = "Remote"; await model.prepare()
        XCTAssertNil(model.confirmation); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.changed"); XCTAssertEqual(source.saves, 0)
    }
    func testDescriptionChangesAfterReviewRejectSaveIncludingUnicodeOnlyChange() async throws {
        let (model, source, _) = try await harness(); source.fields["caseIntroducton"] = "é"; await model.load()
        XCTAssertTrue(model.confirmTextEdit(try open(model), text: "Local")); await model.prepare(); let review = try XCTUnwrap(model.confirmation)
        source.fields["caseIntroducton"] = "e\u{301}"; await model.save(review)
        XCTAssertEqual(source.saves, 0); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.changed")
    }
    func testMismatchedReadbackKeepsLockUntilAcknowledgedExactReadback() async throws {
        let (model, source, _) = try await harness(); let raw = "e\u{301}"
        XCTAssertTrue(model.confirmTextEdit(try open(model), text: raw)); await model.prepare(); source.readbackOverride = "é"
        await model.save(try XCTUnwrap(model.confirmation)); XCTAssertTrue(model.coordinator.isLocked)
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.unknown"); XCTAssertEqual(model.draft.caseIntroduction, raw)
        source.readbackOverride = nil; await model.requestReload()
        XCTAssertFalse(model.coordinator.isLocked); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved")
        XCTAssertEqual(source.saves, 1)
    }
    func testUnknownWriteNeverUnlocksEvenWhenCaseReadbackMatches() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmTextEdit(try open(model), text: "Unknown"))
        await model.prepare(); source.unknown = true; await model.save(try XCTUnwrap(model.confirmation))
        source.fields["caseIntroducton"] = "Unknown"; await model.requestReload()
        XCTAssertTrue(model.coordinator.isLocked); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.readbackUnconfirmed")
        model.beginTextEdit(.caseIntroduction); XCTAssertNil(model.textEdit); XCTAssertEqual(source.saves, 1)
    }
    func testRejectedSaveAndFailedRefreshKeepCaseDraft() async throws {
        let (model, source, _) = try await harness(); XCTAssertTrue(model.confirmTextEdit(try open(model), text: "Retained"))
        await model.prepare(); source.rejected = true; await model.save(try XCTUnwrap(model.confirmation))
        XCTAssertEqual(model.draft.caseIntroduction, "Retained"); XCTAssertFalse(model.coordinator.isLocked)
        source.failRead = true; await model.requestReload(); let review = try XCTUnwrap(model.reloadConfirmation)
        let reload = try XCTUnwrap(model.confirmReload(review)); await reload.value
        XCTAssertEqual(model.draft.caseIntroduction, "Retained"); XCTAssertEqual(source.saves, 1)
    }
}
