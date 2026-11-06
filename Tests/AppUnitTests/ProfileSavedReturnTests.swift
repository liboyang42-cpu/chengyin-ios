import XCTest
@testable import Questify

@MainActor final class ProfileSavedReturnModelTests: XCTestCase {
    private func make(_ scenario: ProfileEditSyntheticService.Scenario = .success) throws -> ProfileEditModel {
        let session = try ProfileEditSession(accountID: 901, epoch: 1, token: "synthetic-model-return", viewerRevision: 1)
        return .init(coordinator: .init(service: ProfileEditSyntheticService(scenario: scenario), currentSession: { session }))
    }
    private func review(_ model: ProfileEditModel, name: String = "Saved name") async throws -> ProfileEditConfirmation {
        await model.resetAndLoad()
        model.draft = .init(name: name, introduction: "Saved introduction")
        await model.prepare()
        return try XCTUnwrap(model.confirmation)
    }
    func testCurrentSavedDraftConsumesOnceAndRootCallbackCanRemainInPlace() async throws {
        let model = try make(), value = try await review(model)
        let result = await model.save(value), receipt = try XCTUnwrap(result)
        var callbacks = 0
        if model.consumeSavedReturn(receipt) { callbacks += 1 }
        if model.consumeSavedReturn(receipt) { callbacks += 1 }
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved")
        XCTAssertEqual(model.draft.name, "Saved name")
        // A root observer may intentionally remain to inspect the existing status.
        await model.load(); XCTAssertEqual(model.draft.name, "Saved name")
    }
    func testChangedDraftThenRestoredBytesCannotReviveSavedReturn() async throws {
        let model = try make(), value = try await review(model)
        let result = await model.save(value), receipt = try XCTUnwrap(result), saved = model.draft
        model.draft.name = "New local edit"; model.draft = saved
        XCTAssertFalse(model.consumeSavedReturn(receipt))
    }
    func testExplicitRefreshDoesNotReturnEvenIfOldStatusWasSaved() async throws {
        let model = try make(), value = try await review(model)
        let result = await model.save(value), receipt = try XCTUnwrap(result)
        await model.requestReload()
        XCTAssertFalse(model.consumeSavedReturn(receipt)); XCTAssertFalse(model.coordinator.isLocked)
    }
    func testBackgroundOrDepartureRetiresReturnWithoutChangingCommittedSnapshot() async throws {
        let model = try make(), value = try await review(model)
        let result = await model.save(value), receipt = try XCTUnwrap(result)
        model.retireAvatar(); model.activateAvatar()
        XCTAssertFalse(model.consumeSavedReturn(receipt))
        XCTAssertEqual(model.coordinator.snapshot?.nickname, "Saved name")
    }
    func testUnknownAndRejectedWritesNeverProduceReturn() async throws {
        for scenario in [ProfileEditSyntheticService.Scenario.unknown, .rejected] {
            let model = try make(scenario), value = try await review(model)
            let receipt = await model.save(value)
            XCTAssertNil(receipt)
            XCTAssertEqual(model.coordinator.isLocked, scenario == .unknown)
        }
    }
    func testCancelledReviewCannotReturnOrWrite() async throws {
        let model = try make(), value = try await review(model)
        model.coordinator.cancel(value); model.confirmation = nil
        let receipt = await model.save(value)
        XCTAssertNil(receipt); XCTAssertEqual(model.coordinator.snapshot?.nickname, "Trail Friend")
    }
    func testOldReceiptCannotConsumeNewSaveOrCauseASecondReturn() async throws {
        let model = try make(), value = try await review(model)
        let firstResult = await model.save(value), first = try XCTUnwrap(firstResult)
        model.draft.name = "Second save"; await model.prepare()
        let secondReview = try XCTUnwrap(model.confirmation), secondResult = await model.save(secondReview)
        let second = try XCTUnwrap(secondResult)
        XCTAssertFalse(model.consumeSavedReturn(first))
        XCTAssertTrue(model.consumeSavedReturn(second)); XCTAssertFalse(model.consumeSavedReturn(second))
    }
    func testLateReplyAfterLocalLifecycleRetirementCannotReturn() async throws {
        let session = try ProfileEditSession(accountID: 901, epoch: 1, token: "synthetic-late-return")
        let service = SavedReturnModelService()
        let model = ProfileEditModel(coordinator: .init(service: service, currentSession: { session }))
        let value = try await review(model)
        service.afterWrite = { model.retireAvatar() }
        let receipt = await model.save(value)
        XCTAssertNil(receipt); XCTAssertEqual(service.writes, 1)
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved")
    }
    func testLateReplyAfterDraftCorrectionCannotReturn() async throws {
        let session = try ProfileEditSession(accountID: 901, epoch: 1, token: "synthetic-draft-return")
        let service = SavedReturnModelService()
        let model = ProfileEditModel(coordinator: .init(service: service, currentSession: { session }))
        let value = try await review(model)
        service.afterWrite = { model.draft.name = "Later correction" }
        let receipt = await model.save(value)
        XCTAssertNil(receipt); XCTAssertEqual(service.writes, 1)
    }
    func testOwnerChangesDuringSaveCannotReturnOrPublishOldDraft() async throws {
        var current = try ProfileEditSession(accountID: 901, epoch: 1, token: "synthetic-owner-return", viewerRevision: 1)
        let next = try ProfileEditSession(accountID: 902, epoch: 2, token: "synthetic-new-owner", viewerRevision: 2)
        let service = SavedReturnModelService()
        let model = ProfileEditModel(coordinator: .init(service: service, currentSession: { current }))
        let value = try await review(model)
        service.afterWrite = { current = next }
        let receipt = await model.save(value)
        XCTAssertNil(receipt); XCTAssertEqual(model.draft, ProfileEditDraft())
        XCTAssertNil(model.coordinator.snapshot); XCTAssertEqual(service.writes, 1)
    }
    func testDraftChangedAfterReviewBeforeSaveCannotReturnFromOldConfirmation() async throws {
        let model = try make(), value = try await review(model)
        model.draft.name = "Newer unreviewed correction"
        let receipt = await model.save(value)
        XCTAssertNil(receipt)
        // The pre-existing write path still saves only the immutable reviewed payload.
        XCTAssertEqual(model.coordinator.snapshot?.nickname, "Saved name")
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved")
    }
    func testPresentationBookkeepingDoesNotRetireCurrentSuccessfulSave() async throws {
        let session = try ProfileEditSession(accountID: 901, epoch: 1, token: "synthetic-sheet-bookkeeping")
        let service = SavedReturnModelService()
        let model = ProfileEditModel(coordinator: .init(service: service, currentSession: { session }))
        let value = try await review(model)
        // The existing sheet's confirmation-id change clears only reload dialogs.
        service.afterWrite = { model.retireReload() }
        let result = await model.save(value), receipt = try XCTUnwrap(result)
        XCTAssertTrue(model.consumeSavedReturn(receipt)); XCTAssertEqual(service.writes, 1)
    }
}

@MainActor private final class SavedReturnModelService: ProfileEditServing {
    var afterWrite: (() -> Void)?
    private(set) var writes = 0
    private var name = "Original", introduction = "Original introduction"
    func read(token: String) async throws -> ProfileEditSnapshot {
        try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject:
            ["id": 901, "nickname": name, "introduction": introduction, "avatar": "", "wechat": "", "casePics": "", "tagIds": ""]))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        writes += 1; name = payload.name; introduction = payload.introduction
        afterWrite?()
    }
}
