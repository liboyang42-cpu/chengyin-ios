import XCTest
@testable import Questify

private actor BoundPhoneAppSource: ProfileEditServing {
    let snapshot: ProfileEditSnapshot
    private(set) var writes = 0
    init() throws {
        snapshot = try JSONDecoder().decode(ProfileEditSnapshot.self, from: Data(#"{"id":1,"nickname":"Synthetic owner","introduction":"","avatar":"","wechat":"","casePics":"","tagIds":"","phone":"13800138000"}"#.utf8))
    }
    func read(token: String) async throws -> ProfileEditSnapshot { snapshot }
    func save(_ payload: ProfileEditPayload, token: String) async throws { writes += 1 }
}
@MainActor final class ProfileBoundPhonePresentationTests: XCTestCase {
    func testNormalEditorLoadExposesOnlyMaskedCurrentPhoneWithoutDirtyDraftOrWrite() async throws {
        let source = try BoundPhoneAppSource(), session = try ProfileEditSession(accountID: 1, epoch: 1, token: "synthetic-phone")
        let coordinator = ProfileEditCoordinator(service: source, currentSession: { session }), model = ProfileEditModel(coordinator: coordinator)
        await model.resetAndLoad()
        XCTAssertEqual(coordinator.phoneDisplay, .masked("138****8000"))
        let snapshot = try XCTUnwrap(coordinator.snapshot)
        XCTAssertFalse(model.draft.hasChanges(comparedTo: snapshot)); XCTAssertNil(model.confirmation)
        let writes = await source.writes; XCTAssertEqual(writes, 0)
    }
    func testUnrelatedNameReviewDoesNotAcquireAPhoneSaveField() async throws {
        let source = try BoundPhoneAppSource(), session = try ProfileEditSession(accountID: 1, epoch: 1, token: "synthetic-phone")
        let coordinator = ProfileEditCoordinator(service: source, currentSession: { session }), model = ProfileEditModel(coordinator: coordinator)
        await model.resetAndLoad(); model.draft.name = "Changed synthetic name"
        await model.prepare()
        let review = try XCTUnwrap(model.confirmation)
        let data = try JSONEncoder().encode(review.payload)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["phone"]); XCTAssertNil(object["phoneDisplay"])
        coordinator.cancel(review)
        XCTAssertEqual(coordinator.phoneDisplay, .masked("138****8000"))
        let writes = await source.writes; XCTAssertEqual(writes, 0)
    }
    func testRetainedEditorDoesNotShowOldPhoneBeforeViewerRevisionReload() async throws {
        let source = try BoundPhoneAppSource()
        var current = try ProfileEditSession(accountID: 1, epoch: 1, token: "synthetic-phone", viewerRevision: 1)
        let coordinator = ProfileEditCoordinator(service: source, currentSession: { current }), model = ProfileEditModel(coordinator: coordinator)
        await model.resetAndLoad(); XCTAssertNotNil(coordinator.phoneDisplay)
        current = try .init(accountID: 1, epoch: 1, token: "synthetic-phone", viewerRevision: 2)
        XCTAssertNil(coordinator.phoneDisplay)
        await model.resetAndLoad(); XCTAssertEqual(coordinator.phoneDisplay, .masked("138****8000"))
    }
}
