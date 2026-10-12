import XCTest
@testable import Questify

@MainActor final class ClubPostEditExitControlTests: XCTestCase {
    private final class Owner {}
    private let owner = Owner()
    private let original = ClubPostEditDraft(content: "original", images: ["a"])
    private let changed = ClubPostEditDraft(content: "changed", images: ["a"])
    private func session(account: Int = 7, epoch: UInt64 = 1, token: String = "synthetic") throws -> ClubCommunitySession {
        try .init(identity: .init(accountID: account, epoch: epoch), token: token)
    }
    private func scope(clubID: Int = 2, postID: Int = 4, postClubID: Int? = 2, version: Int = 1,
                       owner: AnyObject? = nil, session: ClubCommunitySession? = nil, original: ClubPostEditDraft? = nil) throws -> ClubPostEditExitModel.Scope {
        .init(clubID: clubID, postID: postID, postClubID: postClubID, version: version,
              owner: ObjectIdentifier(owner ?? self.owner), session: try session ?? self.session(), original: original ?? self.original)
    }
    private func ready(_ model: ClubPostEditExitModel, _ scope: ClubPostEditExitModel.Scope) throws -> ClubPostEditExitModel.Ticket {
        model.appear()
        XCTAssertEqual(model.request(scope: scope, draft: changed, currentSession: scope.session, canExit: true), .confirm)
        return try XCTUnwrap(model.pending)
    }
    private func discard(_ model: ClubPostEditExitModel, _ ticket: ClubPostEditExitModel.Ticket,
                         _ scope: ClubPostEditExitModel.Scope, draft: ClubPostEditDraft? = nil, canExit: Bool = true) -> Bool {
        model.discard(ticket, scope: scope, draft: draft ?? changed, currentSession: scope.session, canExit: canExit)
    }
    func testCleanCancelClosesOnceWithoutDialog() throws {
        let model = ClubPostEditExitModel(), s = try scope(); model.appear()
        XCTAssertEqual(model.request(scope: s, draft: original, currentSession: s.session, canExit: true), .close)
        XCTAssertFalse(model.dialog); XCTAssertNil(model.pending)
        XCTAssertEqual(model.request(scope: s, draft: original, currentSession: s.session, canExit: true), .blocked)
    }
    func testDirtyCancelAsksOnceAndKeepEditingPreservesDraft() throws {
        let model = ClubPostEditExitModel(), s = try scope(), ticket = try ready(model, s)
        XCTAssertEqual(model.request(scope: s, draft: changed, currentSession: s.session, canExit: true), .confirm)
        XCTAssertEqual(model.pending, ticket); model.keepEditing(ticket)
        XCTAssertFalse(model.dialog); XCTAssertNil(model.pending); XCTAssertEqual(changed.content, "changed")
    }
    func testDiscardConsumesTicketAndClosesOnlyOnce() throws {
        let model = ClubPostEditExitModel(), s = try scope(), ticket = try ready(model, s)
        XCTAssertTrue(discard(model, ticket, s)); XCTAssertFalse(discard(model, ticket, s))
    }
    func testPresentationDismissBeforeButtonStillAllowsExactAction() throws {
        let model = ClubPostEditExitModel(), s = try scope(), ticket = try ready(model, s)
        model.presentationChanged(false); XCTAssertTrue(discard(model, ticket, s))
    }
    func testNewRequestAfterDismissRetiresEarlierButton() throws {
        let model = ClubPostEditExitModel(), s = try scope(), ticket = try ready(model, s)
        model.presentationChanged(false); _ = model.request(scope: s, draft: changed, currentSession: s.session, canExit: true)
        XCTAssertNotEqual(model.pending, ticket); XCTAssertFalse(discard(model, ticket, s))
        model.keepEditing(ticket); XCTAssertTrue(model.dialog)
    }
    func testBusyOrUploadingRejectsRequestAndConfirmation() throws {
        let model = ClubPostEditExitModel(), s = try scope(), ticket = try ready(model, s)
        XCTAssertFalse(discard(model, ticket, s, canExit: false))
        XCTAssertEqual(model.request(scope: s, draft: original, currentSession: s.session, canExit: false), .blocked)
    }
    func testCurrentDraftAndObservedABACannotReuseTicket() throws {
        let model = ClubPostEditExitModel(), s = try scope(), ticket = try ready(model, s)
        XCTAssertFalse(discard(model, ticket, s, draft: .init(content: "newer", images: ["a"])))
        model.invalidate(); XCTAssertFalse(discard(model, ticket, s))
    }
    func testSceneDepartureAndReappearanceRetiresTicket() throws {
        let model = ClubPostEditExitModel(), s = try scope(), ticket = try ready(model, s)
        model.leave(); model.appear(); XCTAssertFalse(discard(model, ticket, s))
    }
    func testIdentityEpochAndCredentialChangesReject() throws {
        for replacement in [try session(account: 8), try session(epoch: 2), try session(token: "other")] {
            let model = ClubPostEditExitModel(), s = try scope(), ticket = try ready(model, s)
            XCTAssertFalse(model.discard(ticket, scope: s, draft: changed, currentSession: replacement, canExit: true))
        }
    }
    func testNewClubPostVersionOwnerOrSourceSnapshotRejects() throws {
        let replacementOwner = Owner()
        for replacement in [try scope(clubID: 3, postClubID: 3), try scope(postID: 5), try scope(version: 2),
                            try scope(owner: replacementOwner), try scope(original: .init(content: "refreshed", images: []))] {
            let model = ClubPostEditExitModel(), s = try scope(), ticket = try ready(model, s)
            XCTAssertFalse(discard(model, ticket, replacement))
        }
    }
    func testInvalidScopeAndSignedOutReject() throws {
        let guest = try ClubCommunitySession(identity: .init(accountID: nil, epoch: 1), token: nil)
        for s in [try scope(clubID: 0), try scope(postID: 0), try scope(postClubID: nil), try scope(postClubID: 9), try scope(session: guest)] {
            let model = ClubPostEditExitModel(); model.appear()
            XCTAssertEqual(model.request(scope: s, draft: changed, currentSession: s.session, canExit: true), .blocked)
        }
    }
    func testImageOnlyChangeRequiresConfirmation() throws {
        let model = ClubPostEditExitModel(), s = try scope(); model.appear()
        XCTAssertEqual(model.request(scope: s, draft: .init(content: "original", images: []), currentSession: s.session, canExit: true), .confirm)
    }
}
