import XCTest
@testable import Questify

@MainActor final class ClubProfileChoiceFlowTests: XCTestCase {
    private func context(_ a: ChoiceAccess, revision: UUID) throws -> ClubProfileChoiceContext {
        try XCTUnwrap(ClubProfileChoiceContext(target: .club(81), identity: a.identity, access: a, profile: a.profile, sourceRevision: revision))
    }
    func testCancelAndReopenUsesUnchangedRealForm() throws {
        let a = ChoiceAccess(), c = try context(a, revision: UUID()), m = ClubProfileChoiceController(), d = ClubOperationsDraft(profile: a.profile)
        m.open(kind: .type, source: d, context: c, isCurrent: { _ in true }); var staged = try XCTUnwrap(m.session).draft
        _ = staged.selectType("旅行组织"); m.close()
        m.open(kind: .type, source: d, context: c, isCurrent: { _ in true })
        XCTAssertEqual(m.session?.draft.type, "兴趣社群"); XCTAssertEqual(a.performs, 0)
    }
    func testRealFormApplyExistingReviewFakeSaveAndReadback() async throws {
        let a = ChoiceAccess(), c = try context(a, revision: UUID()), m = ClubProfileChoiceController(), original = a.profile, d = ClubOperationsDraft(profile: a.profile)
        m.open(kind: .type, source: d, context: c, isCurrent: { _ in true }); let session = try XCTUnwrap(m.session); var staged = session.draft; _ = staged.selectType("旅行组织")
        let applied = try XCTUnwrap(m.apply(staged, session: session, current: d, isCurrent: { _ in true }))
        let coordinator = ClubOperationsCoordinator(access: a)
        let review = try await coordinator.prepare(.update(applied, original: original), target: .club(81), expectedIdentity: try XCTUnwrap(a.identity), ownerID: UUID())
        XCTAssertEqual(a.performs, 0); await coordinator.confirm(review); XCTAssertEqual(a.performs, 1)
        guard case .received(let result) = coordinator.readback(target: .club(81)) else { return XCTFail("Expected actual fake readback") }
        XCTAssertEqual(result.profile?.club.clubType, "旅行组织"); XCTAssertEqual(result.profile?.memberReservedQuota, original.memberReservedQuota)
    }
    func testUnverifiedWriteStaysClosedAfterLocalApply() async throws {
        let a = ChoiceAccess(); a.writeAvailability = .unverified; let original = a.profile; var e = ClubProfileChoiceDraft(kind: .type, source: .init(profile: original)); _ = e.selectType("旅行组织")
        let coordinator = ClubOperationsCoordinator(access: a)
        let review = try await coordinator.prepare(.update(try e.applying(to: e.source), original: original), target: .club(81), expectedIdentity: try XCTUnwrap(a.identity), ownerID: UUID())
        await coordinator.confirm(review); XCTAssertEqual(coordinator.state(target: .club(81)), .notSent); XCTAssertEqual(a.performs, 0)
    }
    func testOldSheetCallbackCannotApplyAfterCancelOrReopen() throws {
        let a = ChoiceAccess(), c = try context(a, revision: UUID()), m = ClubProfileChoiceController(), d = ClubOperationsDraft(profile: a.profile)
        m.open(kind: .directions, source: d, context: c, isCurrent: { _ in true }); let old = try XCTUnwrap(m.session)
        m.close(); m.open(kind: .directions, source: d, context: c, isCurrent: { _ in true })
        XCTAssertNil(m.apply(old.draft, session: old, current: d, isCurrent: { _ in true })); XCTAssertNotEqual(m.session?.id, old.id)
    }
    func testIdentityRevisionAccessAndClubScopesRejectOldSelection() throws {
        let a = ChoiceAccess(), revision = UUID(), c = try context(a, revision: revision)
        XCTAssertFalse(c.matches(target: .club(82), identity: a.identity, access: a, profile: a.profile, sourceRevision: revision))
        XCTAssertFalse(c.matches(target: .club(81), identity: a.identity, access: a, profile: a.profile, sourceRevision: UUID()))
        XCTAssertFalse(c.matches(target: .club(81), identity: a.identity, access: ChoiceAccess(), profile: a.profile, sourceRevision: revision))
        a.identity = .init(accountID: 702, epoch: 2)
        XCTAssertFalse(c.matches(target: .club(81), identity: a.identity, access: a, profile: a.profile, sourceRevision: revision))
    }
    func testDeniedContextAndCreateNeverOpenEditSheet() throws {
        let a = ChoiceAccess(), m = ClubProfileChoiceController(); a.profile = ChoiceAccess.profile(owner: false, admin: false)
        XCTAssertNil(ClubProfileChoiceContext(target: .club(81), identity: a.identity, access: a, profile: a.profile, sourceRevision: UUID()))
        XCTAssertNil(ClubProfileChoiceContext(target: .create, identity: a.identity, access: a, profile: a.profile, sourceRevision: UUID()))
        m.open(kind: .type, source: .init(), context: nil, isCurrent: { _ in true }); XCTAssertNil(m.session)
    }
    func testCurrentHostAndParentDraftMustStillMatchAtApply() throws {
        let a = ChoiceAccess(), c = try context(a, revision: UUID()), m = ClubProfileChoiceController(), d = ClubOperationsDraft(profile: a.profile)
        m.open(kind: .type, source: d, context: c, isCurrent: { _ in true }); let session = try XCTUnwrap(m.session)
        XCTAssertNil(m.apply(session.draft, session: session, current: d, isCurrent: { _ in false }))
        var changed = d; changed.city = "New city"
        XCTAssertNil(m.apply(session.draft, session: session, current: changed, isCurrent: { _ in true }))
    }
    func testAdminSelectionFeedsDisplayOnlyOriginalWire() throws {
        let a = ChoiceAccess(); a.profile = ChoiceAccess.profile(owner: false, admin: true); _ = try context(a, revision: UUID())
        var e = ClubProfileChoiceDraft(kind: .type, source: .init(profile: a.profile)); _ = e.selectType("旅行组织")
        let fields = try ClubOperationsCommand.update(e.applying(to: e.source), original: a.profile).fields(snapshot: .init(target: .club(81), profile: a.profile), identity: try XCTUnwrap(a.identity))
        XCTAssertEqual(fields["clubType"] as? String, "旅行组织"); XCTAssertNil(fields["operationConfigUpdated"]); XCTAssertNil(fields["memberReservedQuota"])
    }
}

@MainActor private final class ChoiceAccess: ClubOperationsAccess {
    var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
    var isConfigured = true
    var writeAvailability = ClubOperationsWriteAvailability.syntheticOnly
    var profile = ChoiceAccess.profile()
    var performs = 0
    static func profile(owner: Bool = true, admin: Bool = false) -> ClubOperationsProfile {
        try! JSONDecoder().decode(ClubOperationsProfile.self, from: Data("{\"id\":81,\"name\":\"Club\",\"city\":\"City\",\"clubType\":\"兴趣社群\",\"activityPrefs\":\"轻社交\",\"isOwner\":\(owner),\"viewerIsAdmin\":\(admin),\"prioritySignupEnabled\":1,\"memberReservedQuota\":4}".utf8))
    }
    func snapshot(target: ClubOperationsTarget) async throws -> ClubOperationsSnapshot { .init(target: target, profile: profile) }
    func perform(_ command: ClubOperationsCommand, target: ClubOperationsTarget, expectedIdentity: ClubReadIdentity) async throws -> ClubOperationsReceipt {
        XCTAssertEqual(identity, expectedIdentity); XCTAssertEqual(target, .club(81))
        let fields = try command.fields(snapshot: .init(target: target, profile: profile), identity: expectedIdentity)
        var object = fields; object["id"] = 81; object["isOwner"] = profile.club.isOwner; object["viewerIsAdmin"] = profile.club.viewerIsAdmin
        profile = try JSONDecoder().decode(ClubOperationsProfile.self, from: JSONSerialization.data(withJSONObject: object))
        performs += 1; return .init(clubID: 81, message: "Fake saved")
    }
}
