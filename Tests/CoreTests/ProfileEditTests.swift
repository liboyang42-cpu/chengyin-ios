import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ProfileEditTests: XCTestCase {
    private func snapshot(_ changes: [String: Any] = [:]) throws -> ProfileEditSnapshot {
        var object: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Weekend walks", "avatar": " raw-avatar ", "wechat": " contact-qr ", "casePics": "one;;two;", "tagIds": "7,4"]
        object.merge(changes) { _, new in new }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testPayloadTrimsOnlyEditedFieldsAndPreservesReplacementValues() throws {
        let source = try snapshot()
        let payload = try ProfileEditPayload(draft: .init(name: " New Name\n", introduction: " New bio "), preserving: source)
        XCTAssertEqual(payload.name, "New Name"); XCTAssertEqual(payload.introduction, "New bio")
        XCTAssertEqual(payload.avatar, " raw-avatar "); XCTAssertEqual(payload.wechat, " contact-qr ")
        XCTAssertEqual(payload.casePics, "one;;two;"); XCTAssertEqual(payload.tagIds, "7,4")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: String])
        XCTAssertEqual(Set(json.keys), Set(["name", "introduction", "avatar", "wechat", "casePics", "tagIds"]))
        XCTAssertThrowsError(try ProfileEditPayload(draft: .init(name: " \n"), preserving: source))
    }
    func testMissingPreservationFailsClosed() throws {
        let json = Data(#"{"id":901,"nickname":"A","introduction":"","avatar":"","wechat":"","tagIds":""}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ProfileEditSnapshot.self, from: json))
    }
    @MainActor func testConfirmationIsImmutableAndReadbackVerifiesSuccess() async throws {
        let service = ProfileEditSyntheticService()
        let session = try ProfileEditSession(accountID: 901, epoch: 1, token: "fixture")
        let coordinator = ProfileEditCoordinator(service: service, currentSession: { session })
        await coordinator.load()
        var draft = ProfileEditDraft(name: "Confirmed Name", introduction: "Confirmed bio")
        await coordinator.prepare(draft)
        let confirmation = try XCTUnwrap(coordinator.confirmation)
        draft.name = "Later typing"
        await coordinator.save(confirmation)
        XCTAssertEqual(coordinator.snapshot?.nickname, "Confirmed Name")
        XCTAssertEqual(coordinator.messageKey, "profile.edit.saved")
        XCTAssertFalse(coordinator.isLocked)
        await coordinator.save(confirmation)
        XCTAssertEqual(coordinator.snapshot?.nickname, "Confirmed Name")
    }
    @MainActor func testUnknownOutcomeRemainsLockedAcrossNavigationAndSameAccountEpoch() async throws {
        var session: ProfileEditSession? = try .init(accountID: 901, epoch: 1, token: "fixture")
        let coordinator = ProfileEditCoordinator(service: ProfileEditSyntheticService(scenario: .unknown), currentSession: { session })
        await coordinator.load(); await coordinator.prepare(.init(name: "New"))
        let confirmation = try XCTUnwrap(coordinator.confirmation)
        await coordinator.save(confirmation)
        XCTAssertTrue(coordinator.isLocked)
        coordinator.leaveScreen(); await coordinator.load()
        XCTAssertTrue(coordinator.isLocked)
        session = nil; coordinator.synchronizeSession()
        session = try .init(accountID: 901, epoch: 2, token: "new-fixture")
        coordinator.synchronizeSession(); await coordinator.load()
        XCTAssertTrue(coordinator.isLocked)
        await coordinator.prepare(.init(name: "Another"))
        XCTAssertNil(coordinator.confirmation)
    }
    @MainActor func testRejectedWriteUnlocksButDoesNotClaimSaved() async throws {
        let session = try ProfileEditSession(accountID: 901, epoch: 1, token: "fixture")
        let coordinator = ProfileEditCoordinator(service: ProfileEditSyntheticService(scenario: .rejected), currentSession: { session })
        await coordinator.load(); await coordinator.prepare(.init(name: "New"))
        await coordinator.save(try XCTUnwrap(coordinator.confirmation))
        XCTAssertFalse(coordinator.isLocked)
        XCTAssertEqual(coordinator.messageKey, "profile.edit.rejected")
    }
    @MainActor func testOldConfirmationCannotWriteAfterTokenChange() async throws {
        var session: ProfileEditSession? = try .init(accountID: 901, epoch: 1, token: "fixture")
        let coordinator = ProfileEditCoordinator(service: ProfileEditSyntheticService(), currentSession: { session })
        await coordinator.load(); await coordinator.prepare(.init(name: "New"))
        let old = try XCTUnwrap(coordinator.confirmation)
        session = try .init(accountID: 901, epoch: 1, token: "replacement")
        await coordinator.save(old)
        XCTAssertNil(coordinator.snapshot); XCTAssertNil(coordinator.confirmation)
        await coordinator.load()
        XCTAssertEqual(coordinator.snapshot?.nickname, "Trail Friend")
    }
}
