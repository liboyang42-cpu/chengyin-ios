import XCTest
@testable import Questify

@MainActor private final class ProfileReviewSessionBox {
    var value: ProfileEditSession?
    init() throws { value = try .init(accountID: 901, epoch: 1, token: "synthetic-review-restore", viewerRevision: 1) }
}
@MainActor private final class ProfileReviewRestoreService: ProfileAvatarEditServing {
    let avatarSavingAvailable = true
    var reads = 0, saves = 0, savedCallbacks = 0
    var unknown = false, reject = false
    var beforeRead: (() async -> Void)?
    var fields: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Walks", "caseIntroducton": "Case",
        "avatar": "original-avatar", "wechat": "original-qr", "casePics": "one;two", "tagIds": "4,7"]
    func read(token: String) async throws -> ProfileEditSnapshot {
        reads += 1; await beforeRead?()
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        saves += 1
        if reject { throw ProfileEditWriteError.rejected(.init(code: 422, message: "Synthetic rejection")) }
        if unknown { throw ProfileEditWriteError.outcomeUnknown }
        fields["nickname"] = payload.name; fields["introduction"] = payload.introduction; fields["avatar"] = payload.avatar
        fields["wechat"] = payload.wechat; fields["casePics"] = payload.casePics; fields["tagIds"] = payload.tagIds
        if let value = payload.caseIntroduction { fields["caseIntroducton"] = value }
    }
    func saveAvatar(_ payload: ProfileEditPayload, token: String, isCurrent: @escaping @MainActor () -> Bool) async throws {
        guard isCurrent() else { throw ProfileEditWriteError.notSent }; try await save(payload, token: token)
    }
}
@MainActor private final class ProfileReviewAvatarTransport: ProfileAvatarDispatching {
    let isConfigured = true
    var forwards = 0
    func send(_ request: URLRequest, authorization: ProfileAvatarDispatchAuthorization) async throws -> (Data, Int) {
        try authorization.forward(request) { forwards += 1 }
        return (Data(#"{"code":200,"url":"https://avatar.invalid/staged.jpg"}"#.utf8), 200)
    }
}
@MainActor final class ProfileDraftReviewRestoreModelTests: XCTestCase {
    private func harness() async throws -> (ProfileEditModel, ProfileReviewRestoreService, ProfileReviewSessionBox) {
        let source = ProfileReviewRestoreService(), box = try ProfileReviewSessionBox()
        let coordinator = ProfileEditCoordinator(service: source, currentSession: { box.value }, onSaved: { source.savedCallbacks += 1 })
        let model = ProfileEditModel(coordinator: coordinator); await model.resetAndLoad(); return (model, source, box)
    }
    private func review(_ model: ProfileEditModel) async throws -> ProfileEditConfirmation {
        model.draft.name = "Local"; await model.prepare(); return try XCTUnwrap(model.confirmation)
    }
    func testComparisonUsesPreparedSnapshotAndPayloadWithoutExtraRequests() async throws {
        let (model, source, _) = try await harness(); let value = try await review(model)
        XCTAssertEqual(value.reviewSummary.changes.count, 1); XCTAssertEqual(value.reviewSummary.changes[0].before, .text("Trail Friend"))
        XCTAssertEqual(value.reviewSummary.changes[0].after, .text("Local")); XCTAssertEqual(source.reads, 2); XCTAssertEqual(source.saves, 0)
    }
    func testRestoreAtomicallyClearsEveryLocalProposalWithoutReadWriteOrSaveCallback() async throws {
        let (model, source, _) = try await harness(); model.draft.introduction = "Local bio"; model.draft.caseIntroduction = "Local case"
        model.draft.routePreferenceIDs = []; model.draft.removesContactQR = true; model.draft.removesCasePictures = true
        let value = try await review(model); XCTAssertEqual(value.reviewSummary.changes.count, 6); XCTAssertTrue(model.canRestoreReviewedDraft(value))
        let reads = source.reads; XCTAssertTrue(model.restoreReviewedDraft(value))
        XCTAssertEqual(model.draft, model.coordinator.snapshot?.draft); XCTAssertNil(model.confirmation); XCTAssertNil(model.coordinator.confirmation)
        XCTAssertEqual(source.reads, reads); XCTAssertEqual(source.saves, 0); XCTAssertEqual(source.savedCallbacks, 0)
        XCTAssertEqual(model.coordinator.messageKey, "profile.reviewRestore.restored"); XCTAssertFalse(model.blocksInteractiveExit)
        model.beginTextEdit(.name); XCTAssertNotNil(model.textEdit)
    }
    func testRestoreAdoptsLatestReviewedPreservedFieldsNotTheOlderLoadedSnapshot() async throws {
        let (model, source, _) = try await harness(); source.fields["wechat"] = "Fresh QR"; source.fields["casePics"] = "Fresh picture"
        let value = try await review(model); XCTAssertEqual(model.coordinator.snapshot?.wechat, "original-qr")
        XCTAssertTrue(model.restoreReviewedDraft(value)); XCTAssertEqual(model.coordinator.snapshot?.wechat, "Fresh QR")
        XCTAssertEqual(model.coordinator.snapshot?.casePics, "Fresh picture"); XCTAssertEqual(source.reads, 2)
    }
    func testRepeatedRestoreAndOldSaveAreRejectedWithoutRequests() async throws {
        let (model, source, _) = try await harness(); let value = try await review(model)
        XCTAssertTrue(model.restoreReviewedDraft(value)); XCTAssertFalse(model.restoreReviewedDraft(value))
        await model.coordinator.save(value); XCTAssertEqual(source.reads, 2); XCTAssertEqual(source.saves, 0)
    }
    func testCancelledReviewCannotDiscardDraftOrMasqueradeAsRestore() async throws {
        let (model, source, _) = try await harness(); let value = try await review(model), draft = model.draft
        model.coordinator.cancel(value); model.confirmation = nil
        XCTAssertFalse(model.restoreReviewedDraft(value)); XCTAssertEqual(model.draft, draft); XCTAssertEqual(source.reads, 2)
    }
    func testChangedDraftAndABAInvalidateRestorationEvenWhenValuesReturn() async throws {
        let (model, source, _) = try await harness(); let value = try await review(model), draft = model.draft
        model.draft.name = "Newer"; XCTAssertFalse(model.canRestoreReviewedDraft(value)); XCTAssertFalse(model.restoreReviewedDraft(value))
        model.draft = draft; XCTAssertFalse(model.restoreReviewedDraft(value)); XCTAssertEqual(model.draft.name, "Local"); XCTAssertEqual(source.saves, 0)
    }
    func testDraftChangedWhilePrepareWasAwaitingDoesNotReceiveRestoreCapability() async throws {
        let (model, source, _) = try await harness(); model.draft.name = "Reviewed"
        source.beforeRead = { if source.reads == 2 { model.draft.name = "Newer while reading" } }
        await model.prepare(); let value = try XCTUnwrap(model.confirmation)
        XCTAssertFalse(model.canRestoreReviewedDraft(value)); XCTAssertFalse(model.restoreReviewedDraft(value))
        XCTAssertEqual(model.draft.name, "Newer while reading"); XCTAssertEqual(source.saves, 0)
    }
    func testOwnerEpochViewerAndTokenChangesRejectRestoration() async throws {
        for next in [(902, UInt64(1), UInt64(1), "synthetic-review-restore"), (901, UInt64(2), UInt64(1), "synthetic-review-restore"),
                     (901, UInt64(1), UInt64(2), "synthetic-review-restore"), (901, UInt64(1), UInt64(1), "replacement-token")] {
            let (model, source, box) = try await harness(); let value = try await review(model)
            box.value = try .init(accountID: next.0, epoch: next.1, token: next.3, viewerRevision: next.2)
            XCTAssertFalse(model.restoreReviewedDraft(value)); XCTAssertEqual(source.reads, 2); XCTAssertEqual(source.saves, 0)
        }
    }
    func testRetiredLifetimeAndReactivationCannotReviveOldRestoreAction() async throws {
        let (model, _, _) = try await harness(); let value = try await review(model)
        model.retireAvatar(); model.activateAvatar(); XCTAssertFalse(model.restoreReviewedDraft(value)); XCTAssertEqual(model.draft.name, "Local")
    }
    func testFreshReviewSupersedesOldRestoreAction() async throws {
        let (model, source, _) = try await harness(); let old = try await review(model)
        model.coordinator.cancel(old); model.confirmation = nil; model.draft.name = "New review"; await model.prepare()
        let fresh = try XCTUnwrap(model.confirmation); XCTAssertFalse(model.restoreReviewedDraft(old)); XCTAssertTrue(model.canRestoreReviewedDraft(fresh))
        XCTAssertTrue(model.restoreReviewedDraft(fresh)); XCTAssertEqual(source.saves, 0)
    }
    func testAnotherCoordinatorCannotConsumeTheReview() async throws {
        let (model, _, box) = try await harness(); let value = try await review(model)
        let other = ProfileEditCoordinator(service: ProfileReviewRestoreService(), currentSession: { box.value }); await other.load()
        XCTAssertNil(other.discardReviewedDraft(value)); XCTAssertTrue(model.canRestoreReviewedDraft(value))
    }
    func testBusyReadRejectsRestoreAndOldReviewDoesNotReviveAfterReload() async throws {
        let (model, source, _) = try await harness(); let value = try await review(model)
        source.beforeRead = { XCTAssertFalse(model.restoreReviewedDraft(value)) }
        await model.coordinator.load(); XCTAssertFalse(model.restoreReviewedDraft(value)); XCTAssertEqual(source.saves, 0)
    }
    func testUnknownWriteCannotBeUnlockedOrRepeatedByRestore() async throws {
        let (model, source, _) = try await harness(); let value = try await review(model); source.unknown = true
        await model.save(value); XCTAssertTrue(model.coordinator.isLocked)
        XCTAssertFalse(model.restoreReviewedDraft(value)); XCTAssertNil(model.coordinator.discardReviewedDraft(value))
        XCTAssertTrue(model.coordinator.isLocked); XCTAssertEqual(source.saves, 1); XCTAssertEqual(source.savedCallbacks, 0)
    }
    func testRejectedSaveRequiresFreshReviewBeforeLocalRestoration() async throws {
        let (model, source, _) = try await harness(); let old = try await review(model); source.reject = true; await model.save(old)
        XCTAssertFalse(model.restoreReviewedDraft(old)); await model.prepare(); let fresh = try XCTUnwrap(model.confirmation)
        XCTAssertTrue(model.restoreReviewedDraft(fresh)); XCTAssertEqual(source.saves, 1)
    }
    func testRestoreThenEditAndSaveWorksWithoutCommittingExit() async throws {
        let (model, source, _) = try await harness(); let value = try await review(model); XCTAssertTrue(model.restoreReviewedDraft(value))
        model.beginTextEdit(.name); let edit = try XCTUnwrap(model.textEdit); XCTAssertTrue(model.confirmTextEdit(edit, text: "Saved later"))
        await model.prepare(); await model.save(try XCTUnwrap(model.confirmation))
        XCTAssertEqual(source.saves, 1); XCTAssertEqual(source.savedCallbacks, 1); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved")
        XCTAssertEqual(model.draft.name, "Saved later")
    }
    func testRestoreRetiresStagedAvatarWithoutUploadingAgainOrDeletingAsset() async throws {
        let (model, source, box) = try await harness(); let transport = ProfileReviewAvatarTransport()
        let url = try XCTUnwrap(URL(string: "https://profile.example/"))
        let approval = try ProfileAvatarApproval(baseURL: url, namespace: "review-fixture", accountID: 901, approvedOrigins: ["https://avatar.invalid"], nativePicker: true)
        let client = ProfileAvatarUploadClient(configuration: try APIConfiguration(baseURL: url), approval: approval, transport: transport,
            credentials: { box.value.flatMap { try? ProfileAvatarCredentials(session: $0, namespace: "review-fixture", token: "synthetic-review-restore") } }, currentApproval: { approval })
        let target = try XCTUnwrap(model.avatarTarget(source: client))
        let receipt = try await client.upload(.init(jpeg: Data([255, 216, 255, 1]), width: 2, height: 2), target: target,
            attemptID: UUID(), ownerCurrent: { model.ownsAvatarScope(target.scope) })
        model.stageAvatar(receipt.stage(current: { model.ownsAvatarScope(target.scope) }), preview: nil)
        await model.prepare(); let value = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(value.reviewSummary.changes.map(\.field), [.avatar]); XCTAssertEqual(value.reviewSummary.changes[0].after, .newAvatar)
        XCTAssertTrue(model.restoreReviewedDraft(value)); XCTAssertNil(model.draft.avatarReplacement); XCTAssertFalse(model.ownsAvatarScope(target.scope))
        XCTAssertEqual(transport.forwards, 1); XCTAssertEqual(source.saves, 0); XCTAssertEqual(source.reads, 2)
    }
}
