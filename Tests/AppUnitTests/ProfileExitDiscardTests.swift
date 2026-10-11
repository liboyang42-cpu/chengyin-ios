import XCTest
@testable import Questify

@MainActor private final class ProfileExitSessionBox {
    var value: ProfileEditSession?
    init() throws {
        value = try .init(accountID: 901, epoch: 1, token: "synthetic-profile-exit", viewerRevision: 1)
    }
}
@MainActor private final class ProfileExitService: ProfileAvatarEditServing {
    var avatarSavingAvailable = true
    var readCount = 0
    var saveCount = 0
    var failsRead = false
    var unknownSave = false
    var beforeRead: (() async -> Void)?
    var fields: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Weekend walks",
        "avatar": "original-avatar", "wechat": "original-wechat", "casePics": " a ; b ", "tagIds": "4,7"]
    func read(token: String) async throws -> ProfileEditSnapshot {
        readCount += 1
        await beforeRead?()
        if failsRead { throw APIError.malformedResponse }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        saveCount += 1
        if unknownSave { throw ProfileEditWriteError.outcomeUnknown }
        fields["nickname"] = payload.name; fields["introduction"] = payload.introduction; fields["tagIds"] = payload.tagIds
    }
    func saveAvatar(_ payload: ProfileEditPayload, token: String, isCurrent: @escaping @MainActor () -> Bool) async throws {
        guard isCurrent() else { throw ProfileEditWriteError.notSent }
        try await save(payload, token: token)
    }
}
@MainActor private final class ProfileExitAvatarTransport: ProfileAvatarDispatching {
    let isConfigured = true
    var forwards = 0
    func send(_ request: URLRequest, authorization: ProfileAvatarDispatchAuthorization) async throws -> (Data, Int) {
        try authorization.forward(request) { forwards += 1 }
        return (Data(#"{"code":200,"url":"https://avatar.invalid/staged.jpg"}"#.utf8), 200)
    }
}

@MainActor final class ProfileExitDiscardTests: XCTestCase {
    private func harness() async throws -> (ProfileEditModel, ProfileExitService, ProfileExitSessionBox) {
        let service = ProfileExitService(), box = try ProfileExitSessionBox()
        let model = ProfileEditModel(coordinator: ProfileEditCoordinator(service: service, currentSession: { box.value }))
        await model.resetAndLoad()
        return (model, service, box)
    }
    private var edited: ProfileEditDraft { .init(name: "  Local e\u{301}  ", introduction: " Private\nraw text ", routePreferenceIDs: [7, 4]) }
    private func assertExact(_ actual: ProfileEditDraft, _ expected: ProfileEditDraft, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(actual.name.utf8), Array(expected.name.utf8), file: file, line: line)
        XCTAssertEqual(Array(actual.introduction.utf8), Array(expected.introduction.utf8), file: file, line: line)
        XCTAssertEqual(actual.routePreferenceIDs, expected.routePreferenceIDs, file: file, line: line)
        XCTAssertEqual(actual.avatarReplacement, expected.avatarReplacement, file: file, line: line)
    }
    func testCleanExitAllowsDismissalOnceWithoutReadOrWrite() async throws {
        let (model, service, _) = try await harness()
        XCTAssertTrue(model.requestExit()); XCTAssertNil(model.exitConfirmation)
        XCTAssertFalse(model.requestExit()); XCTAssertFalse(model.blocksInteractiveExit)
        XCTAssertEqual(service.readCount, 1); XCTAssertEqual(service.saveCount, 0)
    }
    func testDirtyExitPresentsReviewAndPreservesEveryByteWithoutTransport() async throws {
        let (model, service, _) = try await harness(); model.draft = edited
        XCTAssertTrue(model.blocksInteractiveExit); XCTAssertFalse(model.requestExit())
        XCTAssertNotNil(model.exitConfirmation); assertExact(model.draft, edited)
        XCTAssertEqual(service.readCount, 1); XCTAssertEqual(service.saveCount, 0)
    }
    func testCancelPreservesAllDraftBytesAndRejectsOldAction() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; _ = model.requestExit()
        let review = try XCTUnwrap(model.exitConfirmation); model.cancelExit()
        XCTAssertNil(model.exitConfirmation); assertExact(model.draft, edited)
        XCTAssertFalse(model.confirmExit(review)); XCTAssertEqual(service.readCount, 1); XCTAssertEqual(service.saveCount, 0)
    }
    func testConfirmConsumesOnceDiscardsLocalDraftAndRetiresAvatarOwner() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; _ = model.requestExit()
        let review = try XCTUnwrap(model.exitConfirmation), lifetime = model.avatarLifetimeID
        XCTAssertTrue(model.confirmExit(review)); XCTAssertFalse(model.confirmExit(review)); XCTAssertFalse(model.requestExit())
        XCTAssertNil(model.exitConfirmation); assertExact(model.draft, .init()); XCTAssertNotEqual(model.avatarLifetimeID, lifetime)
        XCTAssertEqual(service.readCount, 1); XCTAssertEqual(service.saveCount, 0)
    }
    func testWhitespaceAndCanonicalUnicodeByteDifferencesRequireReview() async throws {
        let (model, service, _) = try await harness(); model.draft.name += " "
        XCTAssertFalse(model.requestExit()); XCTAssertNotNil(model.exitConfirmation)
        service.fields["nickname"] = "é"; await model.load(); model.draft.name = "e\u{301}"
        XCTAssertFalse(model.requestExit()); XCTAssertNotNil(model.exitConfirmation)
        XCTAssertEqual(service.readCount, 2); XCTAssertEqual(service.saveCount, 0)
    }
    func testPreferenceOnlyClearAndReorderRequireReview() async throws {
        for ids in [[], [7, 4]] {
            let (model, _, _) = try await harness(); model.draft.routePreferenceIDs = ids
            XCTAssertFalse(model.requestExit()); XCTAssertNotNil(model.exitConfirmation)
        }
    }
    func testSameExplicitPreferenceWireValueCanExitDirectly() async throws {
        let (model, service, _) = try await harness(); model.draft.routePreferenceIDs = [4, 7]
        XCTAssertTrue(model.requestExit()); XCTAssertNil(model.exitConfirmation); XCTAssertEqual(service.readCount, 1)
    }
    func testChangedDraftAndDraftABARetireOldReview() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; _ = model.requestExit()
        let review = try XCTUnwrap(model.exitConfirmation)
        model.draft.name = "Temporary"; model.draft = edited
        XCTAssertNil(model.exitConfirmation); XCTAssertFalse(model.confirmExit(review)); assertExact(model.draft, edited)
        XCTAssertEqual(service.readCount, 1)
    }
    func testStaleDialogCannotConsumeOrCancelANewerReview() async throws {
        let (model, _, _) = try await harness(); model.draft = edited; _ = model.requestExit()
        let old = try XCTUnwrap(model.exitConfirmation); _ = model.requestExit(); let fresh = try XCTUnwrap(model.exitConfirmation)
        XCTAssertFalse(model.confirmExit(old)); XCTAssertEqual(model.exitConfirmation?.id, fresh.id)
        XCTAssertTrue(model.confirmExit(fresh))
    }
    func testAnotherEditorCannotUseTheReview() async throws {
        let (first, _, _) = try await harness(), (other, service, _) = try await harness()
        first.draft = edited; other.draft = edited; _ = first.requestExit(); _ = other.requestExit()
        let own = other.exitConfirmation?.id
        XCTAssertFalse(other.confirmExit(try XCTUnwrap(first.exitConfirmation)))
        XCTAssertEqual(other.exitConfirmation?.id, own); XCTAssertEqual(service.readCount, 1)
    }
    func testAccountEpochAndViewerChangesRejectOldReview() async throws {
        for next in [(902, UInt64(2), UInt64(2)), (901, UInt64(2), UInt64(1)), (901, UInt64(1), UInt64(3))] {
            let (model, service, box) = try await harness(); model.draft = edited; _ = model.requestExit()
            let review = try XCTUnwrap(model.exitConfirmation)
            box.value = try .init(accountID: next.0, epoch: next.1, token: "synthetic-profile-exit", viewerRevision: next.2)
            XCTAssertFalse(model.confirmExit(review)); XCTAssertEqual(service.readCount, 1); XCTAssertEqual(service.saveCount, 0)
        }
    }
    func testSignOutRejectsReviewThenAllowsCleanSignInScreenExit() async throws {
        let (model, service, box) = try await harness(); model.draft = edited; _ = model.requestExit()
        let review = try XCTUnwrap(model.exitConfirmation); box.value = nil
        XCTAssertFalse(model.confirmExit(review)); XCTAssertTrue(model.requestExit()); assertExact(model.draft, .init())
        XCTAssertEqual(service.readCount, 1); XCTAssertEqual(service.saveCount, 0)
    }
    func testSnapshotChangeRejectsReviewEvenWithoutModelRevisionChange() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; _ = model.requestExit()
        let review = try XCTUnwrap(model.exitConfirmation); service.fields["casePics"] = "changed original"
        _ = await model.coordinator.load()
        XCTAssertFalse(model.confirmExit(review)); assertExact(model.draft, edited); XCTAssertEqual(service.readCount, 2)
    }
    func testDepartureAndBackgroundRetirementRejectReview() async throws {
        let (model, _, _) = try await harness(); model.draft = edited; _ = model.requestExit()
        let first = try XCTUnwrap(model.exitConfirmation); model.retireReload()
        XCTAssertFalse(model.confirmExit(first)); _ = model.requestExit()
        let second = try XCTUnwrap(model.exitConfirmation); model.retireAvatar(); model.activateAvatar()
        XCTAssertFalse(model.confirmExit(second)); assertExact(model.draft, edited)
    }
    func testPendingReloadReviewAndAvatarPresentationBlockCompetingExit() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.requestReload()
        XCTAssertFalse(model.requestExit()); XCTAssertNil(model.exitConfirmation); XCTAssertNotNil(model.reloadConfirmation)
        model.cancelReload(); model.avatarPresentationActive = true
        XCTAssertFalse(model.requestExit()); XCTAssertNil(model.exitConfirmation)
        model.avatarPresentationActive = false; XCTAssertFalse(model.requestExit()); XCTAssertNotNil(model.exitConfirmation)
        XCTAssertEqual(service.readCount, 1)
    }
    func testReloadRetiresExitReviewAndStillPreservesDirtyDraft() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; _ = model.requestExit()
        let review = try XCTUnwrap(model.exitConfirmation); await model.requestReload()
        XCTAssertFalse(model.confirmExit(review)); XCTAssertNotNil(model.reloadConfirmation); assertExact(model.draft, edited)
        XCTAssertEqual(service.readCount, 1)
    }
    func testBusyReadCannotDismissOrReplaceDraft() async throws {
        let (model, service, _) = try await harness(); model.draft = edited
        service.beforeRead = {
            XCTAssertTrue(model.blocksInteractiveExit); XCTAssertFalse(model.requestExit()); XCTAssertNil(model.exitConfirmation)
        }
        service.failsRead = true; await model.load(); assertExact(model.draft, edited)
        XCTAssertFalse(model.requestExit()); XCTAssertNotNil(model.exitConfirmation); XCTAssertEqual(service.saveCount, 0)
    }
    func testSaveReviewRetiresExitAndBlocksNavigationUntilReviewCloses() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; _ = model.requestExit()
        let old = try XCTUnwrap(model.exitConfirmation); await model.prepare()
        XCTAssertFalse(model.confirmExit(old)); XCTAssertFalse(model.requestExit()); XCTAssertNotNil(model.confirmation)
        XCTAssertEqual(service.saveCount, 0)
    }
    func testUnknownSaveCanLeaveWithoutReleasingLockOrRetrying() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.prepare(); service.unknownSave = true
        await model.save(try XCTUnwrap(model.confirmation)); XCTAssertTrue(model.coordinator.isLocked)
        let reads = service.readCount; XCTAssertFalse(model.requestExit()); let review = try XCTUnwrap(model.exitConfirmation)
        model.cancelExit(); XCTAssertTrue(model.coordinator.isLocked); XCTAssertFalse(model.confirmExit(review))
        _ = model.requestExit(); XCTAssertTrue(model.confirmExit(try XCTUnwrap(model.exitConfirmation)))
        XCTAssertTrue(model.coordinator.isLocked); XCTAssertEqual(service.readCount, reads); XCTAssertEqual(service.saveCount, 1)
    }
    func testChangedUnknownWriteLockInvalidatesPriorExitReview() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; _ = model.requestExit()
        let exit = try XCTUnwrap(model.exitConfirmation)
        await model.coordinator.prepare(model.draft)
        let save = try XCTUnwrap(model.coordinator.confirmation); service.unknownSave = true
        await model.coordinator.save(save)
        XCTAssertTrue(model.coordinator.isLocked); let reads = service.readCount
        XCTAssertFalse(model.confirmExit(exit)); assertExact(model.draft, edited)
        XCTAssertTrue(model.coordinator.isLocked); XCTAssertEqual(service.readCount, reads); XCTAssertEqual(service.saveCount, 1)
    }
    func testCommittedExitRejectsQueuedLoadReloadPrepareAndSave() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.prepare()
        let save = try XCTUnwrap(model.confirmation); model.coordinator.cancel(save); model.confirmation = nil
        _ = model.requestExit(); XCTAssertTrue(model.confirmExit(try XCTUnwrap(model.exitConfirmation)))
        let reads = service.readCount
        await model.load(); await model.requestReload(); await model.prepare(); await model.save(save)
        XCTAssertEqual(service.readCount, reads); XCTAssertEqual(service.saveCount, 0); assertExact(model.draft, .init())
    }
    func testQueuedResetAfterCommittedExitCannotReopenOrRead() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; _ = model.requestExit()
        let review = try XCTUnwrap(model.exitConfirmation)
        // This MainActor task cannot enter reset before the synchronous exit below.
        let queued = Task { @MainActor in await model.resetAndLoad() }
        XCTAssertTrue(model.confirmExit(review)); let reads = service.readCount
        let lifetime = model.avatarLifetimeID
        await queued.value
        XCTAssertEqual(service.readCount, reads); XCTAssertEqual(service.saveCount, 0)
        XCTAssertFalse(model.canRequestExit); XCTAssertFalse(model.requestExit())
        XCTAssertEqual(model.avatarLifetimeID, lifetime); assertExact(model.draft, .init())
    }
    func testCancelledResetPreservesActiveDraftAndExitReview() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; _ = model.requestExit()
        let review = try XCTUnwrap(model.exitConfirmation), lifetime = model.avatarLifetimeID
        let queued = Task { @MainActor in await model.resetAndLoad() }
        queued.cancel(); await queued.value
        XCTAssertEqual(service.readCount, 1); XCTAssertEqual(service.saveCount, 0)
        assertExact(model.draft, edited); XCTAssertEqual(model.exitConfirmation?.id, review.id)
        XCTAssertEqual(model.avatarLifetimeID, lifetime); XCTAssertTrue(model.confirmExit(review))
    }
    func testReopenedEditorUsesANewModelAndKeepsUnknownWriteLock() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.prepare()
        service.unknownSave = true; await model.save(try XCTUnwrap(model.confirmation))
        _ = model.requestExit(); XCTAssertTrue(model.confirmExit(try XCTUnwrap(model.exitConfirmation)))
        let reads = service.readCount
        let reopened = ProfileEditModel(coordinator: model.coordinator)
        await reopened.resetAndLoad()
        XCTAssertEqual(service.readCount, reads + 1); XCTAssertEqual(service.saveCount, 1)
        XCTAssertTrue(reopened.coordinator.isLocked); XCTAssertTrue(model.coordinator.isLocked)
        XCTAssertFalse(model.canRequestExit); XCTAssertTrue(reopened.canRequestExit)
        XCTAssertTrue(reopened.requestExit())
    }
    func testOldResetCannotClearReopenedEditorsSaveReview() async throws {
        let (model, service, _) = try await harness(); XCTAssertTrue(model.requestExit())
        let reopened = ProfileEditModel(coordinator: model.coordinator)
        await reopened.resetAndLoad(); reopened.draft = edited; await reopened.prepare()
        let review = try XCTUnwrap(reopened.confirmation), reads = service.readCount
        await model.resetAndLoad()
        XCTAssertEqual(service.readCount, reads); XCTAssertEqual(service.saveCount, 0)
        XCTAssertEqual(reopened.coordinator.confirmation?.id, review.id)
        XCTAssertEqual(reopened.confirmation?.id, review.id); assertExact(reopened.draft, edited)
        XCTAssertFalse(model.canRequestExit); assertExact(model.draft, .init())
    }
    func testFailedInitialLoadAndUnconfiguredScreenCanExit() async throws {
        let box = try ProfileExitSessionBox(), service = ProfileExitService(); service.failsRead = true
        let failed = ProfileEditModel(coordinator: .init(service: service, currentSession: { box.value }))
        await failed.resetAndLoad(); XCTAssertTrue(failed.requestExit()); XCTAssertEqual(service.readCount, 1)
        let disabled = ProfileEditModel(coordinator: .init(service: nil, currentSession: { box.value }))
        await disabled.resetAndLoad(); XCTAssertTrue(disabled.requestExit())
    }
    func testStagedAvatarOnlyNeedsReviewAndCancelKeepsReceipt() async throws {
        let (model, service, box) = try await harness()
        let transport = ProfileExitAvatarTransport(), url = try XCTUnwrap(URL(string: "https://profile.invalid/"))
        let approval = try ProfileAvatarApproval(baseURL: url, namespace: "exit-fixture", accountID: 901,
            approvedOrigins: ["https://avatar.invalid"], nativePicker: true)
        let source = ProfileAvatarUploadClient(configuration: try APIConfiguration(baseURL: url), approval: approval, transport: transport,
            credentials: { box.value.flatMap { try? ProfileAvatarCredentials(session: $0, namespace: "exit-fixture", token: "synthetic-profile-exit") } },
            currentApproval: { approval })
        let target = try XCTUnwrap(model.avatarTarget(source: source))
        let receipt = try await source.upload(.init(jpeg: Data([255, 216, 255, 1]), width: 2, height: 2), target: target,
            attemptID: UUID(), ownerCurrent: { model.ownsAvatarScope(target.scope) })
        let replacement = receipt.stage(current: { model.ownsAvatarScope(target.scope) })
        model.stageAvatar(replacement, preview: nil)
        XCTAssertFalse(model.requestExit()); XCTAssertNotNil(model.exitConfirmation); model.cancelExit()
        XCTAssertEqual(model.draft.avatarReplacement, replacement); XCTAssertTrue(model.ownsAvatarScope(target.scope))
        _ = model.requestExit(); XCTAssertTrue(model.confirmExit(try XCTUnwrap(model.exitConfirmation)))
        XCTAssertNil(model.draft.avatarReplacement); XCTAssertFalse(model.ownsAvatarScope(target.scope))
        XCTAssertEqual(transport.forwards, 1); XCTAssertEqual(service.readCount, 1); XCTAssertEqual(service.saveCount, 0)
    }
}
