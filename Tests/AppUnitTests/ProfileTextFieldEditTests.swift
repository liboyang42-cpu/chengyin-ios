import XCTest
@testable import Questify

@MainActor private final class ProfileFieldSessionBox {
    var value: ProfileEditSession?
    init() throws { value = try .init(accountID: 901, epoch: 1, token: "synthetic-profile-field", viewerRevision: 1) }
}
@MainActor private final class ProfileFieldService: ProfileAvatarEditServing {
    var avatarSavingAvailable = true
    var reads = 0, saves = 0
    var unknownSave = false
    var beforeRead: (() async -> Void)?
    var fields: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Weekend walks",
        "avatar": "avatar", "wechat": " wechat ", "casePics": " a ; b ", "tagIds": "4,7"]
    func read(token: String) async throws -> ProfileEditSnapshot {
        reads += 1; await beforeRead?()
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        saves += 1
        if unknownSave { throw ProfileEditWriteError.outcomeUnknown }
        fields["nickname"] = payload.name; fields["introduction"] = payload.introduction; fields["tagIds"] = payload.tagIds
    }
    func saveAvatar(_ payload: ProfileEditPayload, token: String, isCurrent: @escaping @MainActor () -> Bool) async throws {
        guard isCurrent() else { throw ProfileEditWriteError.notSent }
        try await save(payload, token: token)
    }
}
@MainActor private final class ProfileFieldAvatarTransport: ProfileAvatarDispatching {
    let isConfigured = true
    var forwards = 0
    func send(_ request: URLRequest, authorization: ProfileAvatarDispatchAuthorization) async throws -> (Data, Int) {
        try authorization.forward(request) { forwards += 1 }
        return (Data(#"{"code":200,"url":"https://avatar.invalid/staged.jpg"}"#.utf8), 200)
    }
}

@MainActor final class ProfileTextFieldEditTests: XCTestCase {
    private func harness() async throws -> (ProfileEditModel, ProfileFieldService, ProfileFieldSessionBox) {
        let service = ProfileFieldService(), box = try ProfileFieldSessionBox()
        let model = ProfileEditModel(coordinator: .init(service: service, currentSession: { box.value }))
        await model.resetAndLoad(); return (model, service, box)
    }
    private var edited: ProfileEditDraft { .init(name: "  Local e\u{301}  ", introduction: " Private\nraw text ", routePreferenceIDs: [7, 4]) }
    private func assertExact(_ actual: ProfileEditDraft, _ expected: ProfileEditDraft, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(actual.name.utf8), Array(expected.name.utf8), file: file, line: line)
        XCTAssertEqual(Array(actual.introduction.utf8), Array(expected.introduction.utf8), file: file, line: line)
        XCTAssertEqual(actual.routePreferenceIDs, expected.routePreferenceIDs, file: file, line: line)
        XCTAssertEqual(actual.avatarReplacement, expected.avatarReplacement, file: file, line: line)
    }
    func testOpenCopiesExactCurrentDraftAndDoesNotReadOrWrite() async throws {
        for field in [ProfileTextField.name, .introduction] {
            let (model, service, _) = try await harness(); model.draft = edited
            model.beginTextEdit(field); let edit = try XCTUnwrap(model.textEdit)
            XCTAssertEqual(Array(edit.originalText.utf8), Array(field.value(in: edited).utf8))
            assertExact(model.draft, edited); XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.saves, 0)
        }
    }
    func testCancelRetainsWholeDraftAndReopenStartsFresh() async throws {
        for field in [ProfileTextField.name, .introduction] {
            let (model, service, _) = try await harness(); model.draft = edited
            model.beginTextEdit(field); let first = try XCTUnwrap(model.textEdit)
            model.cancelTextEdit(first); assertExact(model.draft, edited); XCTAssertNil(model.textEdit)
            XCTAssertFalse(model.confirmTextEdit(first, text: "cancelled scratch"))
            model.beginTextEdit(field); let reopened = try XCTUnwrap(model.textEdit)
            XCTAssertNotEqual(reopened.id, first.id)
            XCTAssertEqual(Array(reopened.originalText.utf8), Array(field.value(in: edited).utf8))
            XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.saves, 0)
        }
    }
    func testNicknameConfirmChangesOnlyNameAndPreservesExactBytes() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; model.beginTextEdit(.name)
        let edit = try XCTUnwrap(model.textEdit), raw = " \te\u{301} 昵称 \n"
        XCTAssertTrue(model.confirmTextEdit(edit, text: raw)); var expected = edited; expected.name = raw
        assertExact(model.draft, expected); XCTAssertNil(model.textEdit)
        XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.saves, 0)
    }
    func testIntroductionConfirmChangesOnlyIntroductionAndCanStageEmpty() async throws {
        for raw in ["  e\u{301}\n简介 \n ", ""] {
            let (model, service, _) = try await harness(); model.draft = edited; model.beginTextEdit(.introduction)
            XCTAssertTrue(model.confirmTextEdit(try XCTUnwrap(model.textEdit), text: raw))
            var expected = edited; expected.introduction = raw; assertExact(model.draft, expected)
            XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.saves, 0)
        }
    }
    func testEmptyNicknameStagesLocallyButCannotBecomeValidSave() async throws {
        let (model, service, _) = try await harness(); model.beginTextEdit(.name)
        XCTAssertTrue(model.confirmTextEdit(try XCTUnwrap(model.textEdit), text: "  "))
        XCTAssertEqual(model.draft.name, "  "); XCTAssertFalse(model.draft.isValid)
        await model.prepare(); XCTAssertNil(model.confirmation); XCTAssertEqual(service.saves, 0)
    }
    func testRepeatedConfirmationAndLateCancelCannotChangeSuccessor() async throws {
        let (model, _, _) = try await harness(); model.beginTextEdit(.name)
        let old = try XCTUnwrap(model.textEdit); XCTAssertTrue(model.confirmTextEdit(old, text: "New name"))
        model.beginTextEdit(.introduction); let fresh = try XCTUnwrap(model.textEdit)
        model.cancelTextEdit(old); XCTAssertEqual(model.textEdit?.id, fresh.id)
        XCTAssertFalse(model.confirmTextEdit(old, text: "stale")); XCTAssertEqual(model.textEdit?.id, fresh.id)
        XCTAssertTrue(model.confirmTextEdit(fresh, text: "New bio")); XCTAssertEqual(model.draft.name, "New name")
    }
    func testRepeatedOpenDoesNotReplaceScratchSession() async throws {
        let (model, _, _) = try await harness(); model.beginTextEdit(.name); let edit = try XCTUnwrap(model.textEdit)
        model.beginTextEdit(.introduction); XCTAssertEqual(model.textEdit?.id, edit.id)
        XCTAssertEqual(model.textEdit?.field, .name)
    }
    func testAnotherModelCannotConfirmOrCancelThisModelsEditor() async throws {
        let (first, _, _) = try await harness(), (other, _, _) = try await harness()
        first.beginTextEdit(.name); other.beginTextEdit(.name)
        let foreign = try XCTUnwrap(first.textEdit), own = try XCTUnwrap(other.textEdit)
        other.cancelTextEdit(foreign); XCTAssertFalse(other.confirmTextEdit(foreign, text: "foreign"))
        XCTAssertEqual(other.textEdit?.id, own.id); XCTAssertEqual(other.draft.name, "Trail Friend")
    }
    func testDraftABAAndUnrelatedFieldChangeRetireOldScratch() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; model.beginTextEdit(.name)
        let old = try XCTUnwrap(model.textEdit); model.draft.introduction = "temporary"; model.draft = edited
        XCTAssertNil(model.textEdit); XCTAssertFalse(model.confirmTextEdit(old, text: "stale")); assertExact(model.draft, edited)
        XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.saves, 0)
    }
    func testAccountEpochAndViewerChangesRejectOldScratch() async throws {
        for next in [(902, UInt64(1), UInt64(1)), (901, UInt64(2), UInt64(1)), (901, UInt64(1), UInt64(2))] {
            let (model, service, box) = try await harness(); model.beginTextEdit(.name); let old = try XCTUnwrap(model.textEdit)
            box.value = try .init(accountID: next.0, epoch: next.1, token: "synthetic-profile-field", viewerRevision: next.2)
            XCTAssertFalse(model.confirmTextEdit(old, text: "stale")); XCTAssertNil(model.textEdit)
            XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.saves, 0)
        }
    }
    func testSignOutRejectsScratchAndResetClearsIt() async throws {
        let (model, service, box) = try await harness(); model.beginTextEdit(.introduction)
        let old = try XCTUnwrap(model.textEdit); box.value = nil
        XCTAssertFalse(model.confirmTextEdit(old, text: "private")); await model.resetAndLoad()
        assertExact(model.draft, .init()); XCTAssertNil(model.textEdit); XCTAssertFalse(model.canBeginTextEdit)
        XCTAssertEqual(service.reads, 1)
    }
    func testResetReloadsAndCannotReceiveOldFieldAction() async throws {
        let (model, service, _) = try await harness(); model.beginTextEdit(.name); let old = try XCTUnwrap(model.textEdit)
        await model.resetAndLoad(); XCTAssertNil(model.textEdit)
        XCTAssertFalse(model.confirmTextEdit(old, text: "stale")); XCTAssertEqual(service.reads, 2)
    }
    func testCancelledResetKeepsScratch() async throws {
        let (model, service, _) = try await harness(); model.beginTextEdit(.name); let edit = try XCTUnwrap(model.textEdit)
        let task = Task { @MainActor in await model.resetAndLoad() }; task.cancel(); await task.value
        XCTAssertEqual(model.textEdit?.id, edit.id); XCTAssertEqual(service.reads, 1)
        XCTAssertTrue(model.confirmTextEdit(edit, text: "retained"))
    }
    func testSnapshotDriftIncludingCanonicalUnicodeDifferenceRejectsScratch() async throws {
        let (model, service, _) = try await harness(); service.fields["wechat"] = "é"; await model.load()
        model.beginTextEdit(.name); let old = try XCTUnwrap(model.textEdit)
        service.fields["wechat"] = "e\u{301}"; _ = await model.coordinator.load()
        XCTAssertFalse(model.confirmTextEdit(old, text: "stale")); XCTAssertEqual(model.draft.name, "Trail Friend")
        XCTAssertEqual(service.saves, 0)
    }
    func testBackgroundRetiresReviewsButKeepsFieldSessionAndExactScratch() async throws {
        let (model, service, _) = try await harness(); model.beginTextEdit(.introduction)
        let edit = try XCTUnwrap(model.textEdit), scratch = " background\n e\u{301} "
        model.retireReload(); model.retireAvatar(); model.activateAvatar()
        XCTAssertEqual(model.textEdit?.id, edit.id); XCTAssertTrue(model.confirmTextEdit(edit, text: scratch))
        XCTAssertEqual(Array(model.draft.introduction.utf8), Array(scratch.utf8))
        XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.saves, 0)
    }
    func testOpenFieldBlocksCompetingExitReadReloadAndSaveReview() async throws {
        let (model, service, _) = try await harness(); model.beginTextEdit(.name); let edit = try XCTUnwrap(model.textEdit)
        XCTAssertTrue(model.blocksInteractiveExit); XCTAssertFalse(model.requestExit()); XCTAssertNil(model.exitConfirmation)
        await model.load(); await model.requestReload(); await model.prepare()
        XCTAssertNil(model.confirmation); XCTAssertNil(model.reloadConfirmation); XCTAssertEqual(model.textEdit?.id, edit.id)
        XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.saves, 0)
    }
    func testOpenFieldBlocksQueuedSaveAction() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.prepare()
        let save = try XCTUnwrap(model.confirmation); model.coordinator.cancel(save); model.confirmation = nil
        model.beginTextEdit(.name); let edit = try XCTUnwrap(model.textEdit), reads = service.reads
        await model.save(save); XCTAssertEqual(model.textEdit?.id, edit.id)
        XCTAssertEqual(service.reads, reads); XCTAssertEqual(service.saves, 0)
    }
    func testExitReloadSaveReviewsAndAvatarPresentationBlockOpen() async throws {
        let (model, _, _) = try await harness(); model.draft = edited
        _ = model.requestExit(); model.beginTextEdit(.name); XCTAssertNil(model.textEdit); model.cancelExit()
        await model.requestReload(); model.beginTextEdit(.name); XCTAssertNil(model.textEdit); model.cancelReload()
        await model.prepare(); model.beginTextEdit(.name); XCTAssertNil(model.textEdit)
        let review = try XCTUnwrap(model.confirmation); model.coordinator.cancel(review); model.confirmation = nil
        model.avatarPresentationActive = true; model.beginTextEdit(.name); XCTAssertNil(model.textEdit)
    }
    func testBusyReadBlocksOpen() async throws {
        let (model, service, _) = try await harness()
        service.beforeRead = { model.beginTextEdit(.name); XCTAssertNil(model.textEdit) }
        await model.load(); XCTAssertEqual(service.reads, 2)
    }
    func testUnknownWriteLockCannotBeClearedOrBypassedByLocalEditor() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.prepare(); service.unknownSave = true
        await model.save(try XCTUnwrap(model.confirmation)); XCTAssertTrue(model.coordinator.isLocked)
        let reads = service.reads; model.beginTextEdit(.name); XCTAssertNil(model.textEdit)
        XCTAssertTrue(model.coordinator.isLocked); XCTAssertEqual(service.reads, reads); XCTAssertEqual(service.saves, 1)
    }
    func testCommittedExitStaysTerminalAndNewModelCanReopen() async throws {
        let (model, service, _) = try await harness(); XCTAssertTrue(model.requestExit())
        model.beginTextEdit(.name); await model.resetAndLoad(); XCTAssertNil(model.textEdit); XCTAssertEqual(service.reads, 1)
        let reopened = ProfileEditModel(coordinator: model.coordinator); await reopened.resetAndLoad()
        reopened.beginTextEdit(.name); XCTAssertNotNil(reopened.textEdit); XCTAssertNil(model.textEdit)
    }
    func testConfirmedFieldStillRequiresWholePageReviewAndSave() async throws {
        let (model, service, _) = try await harness(); model.beginTextEdit(.name)
        XCTAssertTrue(model.confirmTextEdit(try XCTUnwrap(model.textEdit), text: "  Local e\u{301}  "))
        XCTAssertEqual(service.saves, 0); XCTAssertFalse(model.requestExit()); XCTAssertNotNil(model.exitConfirmation)
        model.cancelExit(); await model.prepare(); let save = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(Array(save.payload.name.utf8), Array("Local e\u{301}".utf8)); XCTAssertEqual(service.saves, 0)
        await model.save(save); XCTAssertEqual(service.saves, 1); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved")
    }
    func testStagedAvatarAndPreferencesSurviveFieldCancelAndApply() async throws {
        let (model, service, box) = try await harness(); model.draft.routePreferenceIDs = [7, 4]
        let transport = ProfileFieldAvatarTransport(), url = try XCTUnwrap(URL(string: "https://profile.example/"))
        let approval = try ProfileAvatarApproval(baseURL: url, namespace: "field-fixture", accountID: 901,
            approvedOrigins: ["https://avatar.invalid"], nativePicker: true)
        let source = ProfileAvatarUploadClient(configuration: try APIConfiguration(baseURL: url), approval: approval, transport: transport,
            credentials: { box.value.flatMap { try? ProfileAvatarCredentials(session: $0, namespace: "field-fixture", token: "synthetic-profile-field") } },
            currentApproval: { approval })
        let target = try XCTUnwrap(model.avatarTarget(source: source))
        let receipt = try await source.upload(.init(jpeg: Data([255, 216, 255, 1]), width: 2, height: 2), target: target,
            attemptID: UUID(), ownerCurrent: { model.ownsAvatarScope(target.scope) })
        let replacement = receipt.stage(current: { model.ownsAvatarScope(target.scope) }); model.stageAvatar(replacement, preview: nil)
        let before = model.draft; model.beginTextEdit(.name); model.cancelTextEdit(try XCTUnwrap(model.textEdit)); assertExact(model.draft, before)
        model.beginTextEdit(.introduction); XCTAssertTrue(model.confirmTextEdit(try XCTUnwrap(model.textEdit), text: "new bio"))
        XCTAssertEqual(model.draft.avatarReplacement, replacement); XCTAssertEqual(model.draft.routePreferenceIDs, [7, 4])
        XCTAssertTrue(model.ownsAvatarScope(target.scope)); XCTAssertEqual(transport.forwards, 1)
        XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.saves, 0)
    }
}

extension ProfileTextFieldEditTests {
    func testBackgroundPreservesSameTextPresentationUntilExplicitCancel() async throws {
        for field in [ProfileTextField.name, .introduction] {
            let (model, service, _) = try await harness()
            let original = model.draft; model.beginTextEdit(field)
            let edit = try XCTUnwrap(model.textEdit), binding = model.textEditPresentation(for: model.textEdit)
            model.suspendForBackground()
            XCTAssertEqual(model.textEdit?.id, edit.id); XCTAssertEqual(binding.wrappedValue?.id, edit.id)
            assertExact(model.draft, original); XCTAssertFalse(model.canBeginTextEdit)
            model.activateAvatar()
            XCTAssertEqual(binding.wrappedValue?.id, edit.id)
            model.cancelTextEdit(edit); model.beginTextEdit(field)
            let reopened = try XCTUnwrap(model.textEdit)
            XCTAssertNotEqual(reopened.id, edit.id); XCTAssertEqual(reopened.originalText, edit.originalText)
            XCTAssertEqual(service.reads, 1); XCTAssertEqual(service.saves, 0)
        }
    }
    func testBackgroundLateApplyCannotStageOrSave() async throws {
        let (model, service, _) = try await harness(); let original = model.draft
        model.beginTextEdit(.name); let edit = try XCTUnwrap(model.textEdit)
        model.suspendForBackground()
        XCTAssertFalse(model.confirmTextEdit(edit, text: "Late scratch"))
        assertExact(model.draft, original); XCTAssertNil(model.textEdit); XCTAssertEqual(service.saves, 0)
    }
    func testTrueOwnerRetirementAfterBackgroundStillClearsTextAndRejectsOldApply() async throws {
        let (model, service, _) = try await harness(); let original = model.draft
        model.beginTextEdit(.name); let edit = try XCTUnwrap(model.textEdit)
        model.suspendForBackground(); model.retireAvatar(); model.activateAvatar()
        XCTAssertNil(model.textEdit); XCTAssertFalse(model.confirmTextEdit(edit, text: "Retired"))
        assertExact(model.draft, original); XCTAssertEqual(service.saves, 0)
    }
    func testBackgroundAfterOwnerChangeAndNonTextEditorsRemainStrictlyRetired() async throws {
        for field in [ProfileTextField.contactQR, .casePictures, .preferences] {
            let (model, service, _) = try await harness(); model.beginTextEdit(field)
            let edit = try XCTUnwrap(model.textEdit); model.suspendForBackground(); model.activateAvatar()
            XCTAssertNil(model.textEdit); XCTAssertFalse(model.confirmTextEdit(edit, text: ""))
            XCTAssertEqual(service.saves, 0)
        }
        let (model, service, box) = try await harness(); model.beginTextEdit(.name)
        let edit = try XCTUnwrap(model.textEdit)
        box.value = try .init(accountID: 902, epoch: 2, token: "synthetic-other", viewerRevision: 2)
        model.suspendForBackground(); model.activateAvatar()
        XCTAssertNil(model.textEdit); XCTAssertFalse(model.confirmTextEdit(edit, text: "Other owner"))
        XCTAssertEqual(service.saves, 0)
    }
    func testResumedCurrentTextApplyStillConsumesOnceWithoutWriting() async throws {
        let (model, service, _) = try await harness(); model.beginTextEdit(.introduction)
        let edit = try XCTUnwrap(model.textEdit); model.suspendForBackground(); model.activateAvatar()
        XCTAssertTrue(model.confirmTextEdit(edit, text: "Current scratch"))
        XCTAssertFalse(model.confirmTextEdit(edit, text: "Repeated"))
        XCTAssertEqual(model.draft.introduction, "Current scratch"); XCTAssertEqual(service.saves, 0)
    }
}
