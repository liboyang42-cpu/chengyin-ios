import XCTest
@testable import Questify

@MainActor private final class ProfileReloadSessionBox {
    var value: ProfileEditSession?
    init(account: Int = 901, epoch: UInt64 = 1, viewer: UInt64 = 1) throws {
        value = try ProfileEditSession(accountID: account, epoch: epoch, token: "synthetic-profile-reload", viewerRevision: viewer)
    }
}
@MainActor private final class ProfileReloadService: ProfileEditServing {
    var readCount = 0
    var saveCount = 0
    var failsRead = false
    var unknownSave = false
    var beforeRead: (() async -> Void)?
    var fields: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Weekend walks",
                               "avatar": "original-avatar", "wechat": "original-wechat", "casePics": " a ; b ", "tagIds": "4,7"]
    func read(token: String) async throws -> ProfileEditSnapshot {
        readCount += 1; await beforeRead?()
        if failsRead { throw APIError.malformedResponse }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: fields))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        saveCount += 1
        if unknownSave { throw ProfileEditWriteError.outcomeUnknown }
        fields["nickname"] = payload.name; fields["introduction"] = payload.introduction; fields["tagIds"] = payload.tagIds
    }
}

@MainActor final class ProfileReloadDiscardTests: XCTestCase {
    private func harness() async throws -> (ProfileEditModel, ProfileReloadService, ProfileReloadSessionBox) {
        let service = ProfileReloadService(), box = try ProfileReloadSessionBox()
        let model = ProfileEditModel(coordinator: ProfileEditCoordinator(service: service, currentSession: { box.value }))
        await model.resetAndLoad(); return (model, service, box)
    }
    private var edited: ProfileEditDraft { .init(name: "  Edited e\u{301}  ", introduction: " Private\nraw text ", routePreferenceIDs: [7, 4]) }
    private func assertExact(_ actual: ProfileEditDraft, _ expected: ProfileEditDraft, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Array(actual.name.utf8), Array(expected.name.utf8), file: file, line: line)
        XCTAssertEqual(Array(actual.introduction.utf8), Array(expected.introduction.utf8), file: file, line: line)
        XCTAssertEqual(actual.routePreferenceIDs, expected.routePreferenceIDs, file: file, line: line)
    }
    func testDirtyReloadPresentsReviewWithoutReadingOrChangingAnyDraftBytes() async throws {
        let (model, service, _) = try await harness(); model.draft = edited
        await model.requestReload()
        XCTAssertNotNil(model.reloadConfirmation); assertExact(model.draft, edited)
        XCTAssertEqual(service.readCount, 1); XCTAssertEqual(service.saveCount, 0)
    }
    func testCancelPreservesAllBytesAndPreferencesWithoutReading() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.requestReload()
        let old = try XCTUnwrap(model.reloadConfirmation); model.cancelReload()
        assertExact(model.draft, edited); XCTAssertNil(model.reloadConfirmation)
        XCTAssertNil(model.confirmReload(old)); XCTAssertEqual(service.readCount, 1); XCTAssertEqual(service.saveCount, 0)
    }
    func testValidConfirmationConsumesOnceAndUsesExistingReadToRestoreServerDraft() async throws {
        let (model, service, _) = try await harness(); let initial = model.draft; model.draft = edited; await model.requestReload()
        let review = try XCTUnwrap(model.reloadConfirmation), operation = try XCTUnwrap(model.confirmReload(review))
        XCTAssertNil(model.reloadConfirmation); XCTAssertNil(model.confirmReload(review))
        await operation.value
        assertExact(model.draft, initial); XCTAssertEqual(service.readCount, 2); XCTAssertEqual(service.saveCount, 0)
    }
    func testFailedConfirmedReloadRetainsEveryTypedByteAndCanAskAgain() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.requestReload()
        let old = try XCTUnwrap(model.reloadConfirmation); service.failsRead = true
        let operation = try XCTUnwrap(model.confirmReload(old)); await operation.value
        assertExact(model.draft, edited); XCTAssertEqual(model.coordinator.messageKey, "profile.edit.refreshFailed")
        XCTAssertEqual(service.readCount, 2); XCTAssertFalse(model.busy)
        await model.requestReload(); XCTAssertNotEqual(model.reloadConfirmation?.id, old.id)
        XCTAssertEqual(service.readCount, 2); XCTAssertEqual(service.saveCount, 0)
    }
    func testCleanDraftReloadsDirectlyWithoutConfirmation() async throws {
        let (model, service, _) = try await harness(); await model.requestReload()
        XCTAssertNil(model.reloadConfirmation); XCTAssertEqual(service.readCount, 2); XCTAssertEqual(service.saveCount, 0)
    }
    func testExplicitPreferenceSelectionWithIdenticalWireValueIsNotDirty() async throws {
        let (model, service, _) = try await harness(); model.draft.routePreferenceIDs = [4, 7]
        await model.requestReload(); XCTAssertNil(model.reloadConfirmation); XCTAssertEqual(service.readCount, 2)
    }
    func testPreferenceOnlyClearAndReorderRequireConfirmation() async throws {
        for ids in [[], [7, 4]] {
            let (model, service, _) = try await harness(); model.draft.routePreferenceIDs = ids
            await model.requestReload(); XCTAssertNotNil(model.reloadConfirmation); XCTAssertEqual(service.readCount, 1)
        }
    }
    func testWhitespaceOnlyAndCanonicalUnicodeByteChangesAreDirty() async throws {
        let (model, service, _) = try await harness(); model.draft.name += " "
        await model.requestReload(); XCTAssertNotNil(model.reloadConfirmation); XCTAssertEqual(service.readCount, 1)
        model.cancelReload(); service.fields["nickname"] = "é"; await model.load()
        model.draft.name = "e\u{301}"; await model.requestReload()
        XCTAssertNotNil(model.reloadConfirmation); XCTAssertEqual(service.readCount, 2)
    }
    func testChangedDraftRetiresPendingDialogAndOldActionCannotRead() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.requestReload()
        let old = try XCTUnwrap(model.reloadConfirmation); model.draft.introduction += " changed"
        XCTAssertNil(model.reloadConfirmation); XCTAssertNil(model.confirmReload(old)); XCTAssertEqual(service.readCount, 1)
    }
    func testDraftABABetweenConfirmAndQueuedTaskDoesNotReload() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.requestReload()
        let operation = try XCTUnwrap(model.confirmReload(try XCTUnwrap(model.reloadConfirmation)))
        model.draft.name = "temporary"; model.draft = edited
        await operation.value; assertExact(model.draft, edited); XCTAssertEqual(service.readCount, 1)
    }
    func testNewReloadRequestRetiresPreviouslyConfirmedButNotStartedTask() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.requestReload()
        let operation = try XCTUnwrap(model.confirmReload(try XCTUnwrap(model.reloadConfirmation)))
        // requestReload has no suspension on its dirty-draft path; the next review
        // gets a new local revision before the already queued task can run.
        await model.requestReload(); let freshID = model.reloadConfirmation?.id
        await operation.value
        XCTAssertNotNil(freshID); XCTAssertEqual(model.reloadConfirmation?.id, freshID)
        assertExact(model.draft, edited); XCTAssertEqual(service.readCount, 1)
    }
    func testStaleDialogCannotConsumeOrCancelNewerConfirmation() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.requestReload()
        let old = try XCTUnwrap(model.reloadConfirmation); await model.requestReload(); let fresh = try XCTUnwrap(model.reloadConfirmation)
        XCTAssertNil(model.confirmReload(old)); XCTAssertEqual(model.reloadConfirmation?.id, fresh.id); XCTAssertEqual(service.readCount, 1)
    }
    func testAnotherOwnerCannotUseTheConfirmation() async throws {
        let (first, _, _) = try await harness(), (other, service, _) = try await harness()
        first.draft = edited; other.draft = edited; await first.requestReload(); await other.requestReload()
        let ownID = other.reloadConfirmation?.id
        XCTAssertNil(other.confirmReload(try XCTUnwrap(first.reloadConfirmation)))
        XCTAssertEqual(other.reloadConfirmation?.id, ownID); XCTAssertEqual(service.readCount, 1)
    }
    func testAccountAndViewerRevisionChangesRejectOldConfirmationBeforeRequest() async throws {
        for next in [(902, UInt64(2), UInt64(2)), (901, UInt64(1), UInt64(3))] {
            let (model, service, box) = try await harness(); model.draft = edited; await model.requestReload()
            let review = try XCTUnwrap(model.reloadConfirmation)
            box.value = try ProfileEditSession(accountID: next.0, epoch: next.1, token: "synthetic-profile-reload", viewerRevision: next.2)
            XCTAssertNil(model.confirmReload(review)); XCTAssertEqual(service.readCount, 1); XCTAssertEqual(service.saveCount, 0)
        }
    }
    func testSignOutRejectsQueuedConfirmationBeforeRead() async throws {
        let (model, service, box) = try await harness(); model.draft = edited; await model.requestReload()
        let operation = try XCTUnwrap(model.confirmReload(try XCTUnwrap(model.reloadConfirmation)))
        box.value = nil; await operation.value
        XCTAssertEqual(service.readCount, 1); XCTAssertEqual(service.saveCount, 0)
    }
    func testDepartureOrSceneRetirementRejectsPendingAndQueuedActions() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.requestReload()
        let old = try XCTUnwrap(model.reloadConfirmation); model.retireReload()
        XCTAssertNil(model.confirmReload(old)); assertExact(model.draft, edited)
        await model.requestReload(); let operation = try XCTUnwrap(model.confirmReload(try XCTUnwrap(model.reloadConfirmation)))
        model.retireReload(); await operation.value
        XCTAssertEqual(service.readCount, 1); XCTAssertEqual(service.saveCount, 0)
    }
    func testFreshBaselineChangeRejectsOldDialogEvenWithoutModelRevisionChange() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.requestReload()
        let review = try XCTUnwrap(model.reloadConfirmation); service.fields["casePics"] = "changed-original"
        _ = await model.coordinator.load()
        XCTAssertNil(model.confirmReload(review)); assertExact(model.draft, edited); XCTAssertEqual(service.readCount, 2)
    }
    func testSaveReviewRetiresReloadDialogAndKeepsExistingSavePath() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.requestReload()
        let reload = try XCTUnwrap(model.reloadConfirmation); await model.prepare()
        XCTAssertNil(model.reloadConfirmation); XCTAssertNil(model.confirmReload(reload)); XCTAssertNotNil(model.confirmation)
        XCTAssertEqual(service.readCount, 2); XCTAssertEqual(service.saveCount, 0)
    }
    func testRoleChangeDuringConfirmedReadCannotPublishPriorDraft() async throws {
        let (model, service, box) = try await harness(); model.draft = edited; await model.requestReload()
        service.beforeRead = { box.value = try? ProfileEditSession(accountID: 901, epoch: 1, token: "synthetic-profile-reload", viewerRevision: 2) }
        let operation = try XCTUnwrap(model.confirmReload(try XCTUnwrap(model.reloadConfirmation))); await operation.value
        assertExact(model.draft, .init()); XCTAssertNil(model.coordinator.snapshot); XCTAssertEqual(service.saveCount, 0)
    }
    func testUnknownWriteReconciliationStillReadsDirectlyAndNeverResends() async throws {
        let (model, service, _) = try await harness(); model.draft = edited; await model.prepare()
        service.unknownSave = true; await model.save(try XCTUnwrap(model.confirmation))
        XCTAssertTrue(model.coordinator.isLocked); let reads = service.readCount
        await model.requestReload()
        XCTAssertNil(model.reloadConfirmation); XCTAssertEqual(service.readCount, reads + 1)
        XCTAssertEqual(service.saveCount, 1); XCTAssertTrue(model.coordinator.isLocked)
    }
}
