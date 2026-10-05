import XCTest
@testable import Questify

@MainActor final class ProfileEditRefreshTests: XCTestCase {
    private func model(_ scenario: ProfileEditSyntheticService.Scenario) throws -> ProfileEditModel {
        let session = try ProfileEditSession(accountID: 901, epoch: 1, token: "synthetic-profile-refresh")
        return ProfileEditModel(coordinator: ProfileEditCoordinator(
            service: ProfileEditSyntheticService(scenario: scenario), currentSession: { session }))
    }

    func testFailedReloadKeepsUnsavedTextAndPreferencesThenCanSave() async throws {
        let model = try model(.refreshFailure)
        await model.resetAndLoad()
        let edited = ProfileEditDraft(name: "Kept name", introduction: "Kept signature", routePreferenceIDs: [7])
        model.draft = edited
        await model.load()
        XCTAssertEqual(model.draft, edited)
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.refreshFailed")
        XCTAssertFalse(model.busy)
        XCTAssertNil(model.confirmation)
        await model.prepare()
        let review = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(review.payload.name, edited.name)
        XCTAssertEqual(review.payload.introduction, edited.introduction)
        XCTAssertEqual(review.payload.tagIds, "7")
        await model.save(review)
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved")
        XCTAssertEqual(model.coordinator.snapshot?.tagIds, "7")
        XCTAssertFalse(model.coordinator.isLocked)
    }

    func testSuccessfulExplicitReloadStillRestoresServerValues() async throws {
        let model = try model(.success)
        await model.resetAndLoad()
        let original = model.draft
        model.draft = .init(name: "Local", introduction: "Local", routePreferenceIDs: [])
        await model.load()
        XCTAssertEqual(model.draft, original)
        XCTAssertFalse(model.busy)
    }

    func testSessionResetDoesNotKeepPreviousAccountsUnsavedDraft() async throws {
        var session: ProfileEditSession? = try .init(accountID: 901, epoch: 1, token: "synthetic-profile-refresh")
        let model = ProfileEditModel(coordinator: ProfileEditCoordinator(
            service: ProfileEditSyntheticService(), currentSession: { session }))
        await model.resetAndLoad()
        model.draft = .init(name: "Private unsaved name", introduction: "Private unsaved signature", routePreferenceIDs: [7])
        session = nil
        await model.resetAndLoad()
        XCTAssertEqual(model.draft, ProfileEditDraft())
        XCTAssertNil(model.coordinator.snapshot)
        XCTAssertNil(model.confirmation)
        XCTAssertFalse(model.busy)
    }
}

@MainActor final class ProfileEditRoleBoundaryTests: XCTestCase {
    private func session(_ revision: UInt64) throws -> ProfileEditSession {
        // Account, token and auth epoch deliberately stay identical across role changes.
        try .init(accountID: 901, epoch: 1, token: "synthetic-role-boundary", viewerRevision: revision)
    }

    func testRoleChangeThenFailedReloadClearsOldDraftAndReview() async throws {
        var current = try session(1)
        let service = ProfileRoleBoundaryService()
        let model = ProfileEditModel(coordinator: ProfileEditCoordinator(service: service, currentSession: { current }))
        await model.resetAndLoad()
        model.draft = .init(name: "Old role draft", introduction: "Private", routePreferenceIDs: [7])
        await model.prepare()
        XCTAssertNotNil(model.confirmation)
        current = try session(2)
        service.beforeRead = { _ in throw APIError.malformedResponse }
        await model.load()
        XCTAssertEqual(model.draft, ProfileEditDraft())
        XCTAssertNil(model.confirmation)
        XCTAssertNil(model.coordinator.confirmation)
        XCTAssertNil(model.coordinator.snapshot)
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.loadFailed")
        XCTAssertFalse(model.busy)
        XCTAssertEqual(service.saveCount, 0)
    }

    func testRoleChangeDuringReviewReadCannotPublishOldDraftOrConfirmation() async throws {
        var current = try session(1)
        let replacement = try session(2)
        let service = ProfileRoleBoundaryService()
        let model = ProfileEditModel(coordinator: ProfileEditCoordinator(service: service, currentSession: { current }))
        await model.resetAndLoad()
        model.draft = .init(name: "Old role draft", introduction: "Private", routePreferenceIDs: [7])
        service.beforeRead = { count in
            if count == 2 { await Task.yield(); current = replacement }
        }
        await model.prepare()
        XCTAssertEqual(model.draft, ProfileEditDraft())
        XCTAssertNil(model.confirmation)
        XCTAssertNil(model.coordinator.confirmation)
        XCTAssertNil(model.coordinator.snapshot)
        XCTAssertFalse(model.busy)
        XCTAssertEqual(service.saveCount, 0)
    }

    func testRoleABADuringConfirmationReadPreventsWrite() async throws {
        var current = try session(1)
        let intermediate = try session(2), returnedRole = try session(3)
        let service = ProfileRoleBoundaryService()
        let model = ProfileEditModel(coordinator: ProfileEditCoordinator(service: service, currentSession: { current }))
        await model.resetAndLoad()
        model.draft = .init(name: "Reviewed old role", introduction: "Private")
        await model.prepare()
        let oldReview = try XCTUnwrap(model.confirmation)
        service.beforeRead = { count in
            if count == 3 {
                current = intermediate
                await Task.yield()
                current = returnedRole
            }
        }
        await model.save(oldReview)
        XCTAssertEqual(service.saveCount, 0)
        XCTAssertEqual(model.draft, ProfileEditDraft())
        XCTAssertNil(model.confirmation)
        XCTAssertNil(model.coordinator.snapshot)
        XCTAssertFalse(model.busy)
        XCTAssertFalse(model.coordinator.isLocked)
        // The old review remains unusable even after returning to the original role.
        await model.save(oldReview)
        XCTAssertEqual(service.saveCount, 0)
    }

    func testRoleChangeDuringDispatchedSaveKeepsLockUntilFreshAcknowledgedReadback() async throws {
        var current = try session(1)
        let replacement = try session(2)
        let service = ProfileRoleBoundaryService()
        var savedCallbacks = 0
        let model = ProfileEditModel(coordinator: ProfileEditCoordinator(service: service,
            currentSession: { current }, onSaved: { savedCallbacks += 1 }))
        await model.resetAndLoad()
        model.draft = .init(name: "Confirmed before switch", introduction: "Confirmed signature")
        await model.prepare()
        let review = try XCTUnwrap(model.confirmation)
        service.beforeSave = { await Task.yield(); current = replacement }
        await model.save(review)
        XCTAssertEqual(service.saveCount, 1)
        XCTAssertEqual(savedCallbacks, 0)
        XCTAssertEqual(model.draft, ProfileEditDraft())
        XCTAssertNil(model.confirmation)
        XCTAssertNil(model.coordinator.snapshot)
        XCTAssertFalse(model.busy)
        XCTAssertTrue(model.coordinator.isLocked)
        await model.load()
        XCTAssertEqual(service.saveCount, 1)
        XCTAssertEqual(savedCallbacks, 1)
        XCTAssertFalse(model.coordinator.isLocked)
        XCTAssertEqual(model.coordinator.messageKey, "profile.edit.saved")
        XCTAssertEqual(model.draft.name, "Confirmed before switch")
    }
}

/// Synthetic service whose hook runs before the delayed response is delivered. No network.
@MainActor private final class ProfileRoleBoundaryService: ProfileEditServing {
    var beforeRead: ((Int) async throws -> Void)?
    var beforeSave: (() async throws -> Void)?
    private(set) var readCount = 0
    private(set) var saveCount = 0
    private var name = "Trail Friend"
    private var introduction = "Weekend walks"
    private var tagIds = "4,7"
    func read(token: String) async throws -> ProfileEditSnapshot {
        readCount += 1
        try await beforeRead?(readCount)
        let object: [String: Any] = ["id": 901, "nickname": name, "introduction": introduction,
            "avatar": "", "wechat": "", "casePics": "", "tagIds": tagIds]
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        saveCount += 1
        try await beforeSave?()
        name = payload.name; introduction = payload.introduction; tagIds = payload.tagIds
    }
}
