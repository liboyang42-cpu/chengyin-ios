import XCTest
@testable import Questify

@MainActor final class ProfileSelfEditReturnTests: XCTestCase {
    private func harness() -> (ProfileSelfEditFixtureData,ProfileEditCoordinator,ProfileSelfEditAccess,ProfileSelfEditNavigation) {
        let data=ProfileSelfEditFixtureData()
        let actual=ProfileEditCoordinator(service:data,currentSession:{ data.editSession })
        return (data,actual,.init(coordinator:actual,sessionRevision:1),.init())
    }
    func testOrdinaryAccessUsesExactExistingCoordinator() {
        let (data,coordinator,access,_)=harness()
        let context=access.context(memberID:81,reader:data,isCurrent:true)
        XCTAssertEqual(context?.coordinator,ObjectIdentifier(coordinator));XCTAssertEqual(context?.memberID,81)
    }
    func testOwnPublicReadToEditorCancelAndFreshReadDoesNotWrite() async throws {
        let (data,coordinator,access,n)=harness();let original=try await data.publicProfile(memberID:81)
        let ticket=try XCTUnwrap(n.open(access.context(memberID:81,reader:data,isCurrent:true)))
        let editor=ProfileEditModel(coordinator:coordinator);await editor.resetAndLoad();XCTAssertTrue(editor.requestExit())
        XCTAssertTrue(n.finish(ticket.id,context:access.context(memberID:81,reader:data,isCurrent:true)))
        let returned=try await data.publicProfile(memberID:81)
        XCTAssertEqual(returned,original);XCTAssertEqual(data.publicReads,2);XCTAssertEqual(data.writes,0)
    }
    func testDiscardUsesExistingEditorReviewAndNeverPublishesDraft() async throws {
        let (data,coordinator,access,n)=harness();let ticket=try XCTUnwrap(n.open(access.context(memberID:81,reader:data,isCurrent:true)))
        let editor=ProfileEditModel(coordinator:coordinator);await editor.resetAndLoad();editor.draft.introduction="Unsent draft"
        XCTAssertFalse(editor.requestExit());XCTAssertTrue(editor.confirmExit(try XCTUnwrap(editor.exitConfirmation)))
        XCTAssertTrue(n.finish(ticket.id,context:access.context(memberID:81,reader:data,isCurrent:true)))
        let profile=try await data.publicProfile(memberID:81);XCTAssertEqual(profile.introduction,"Original public introduction");XCTAssertEqual(data.writes,0)
    }
    func testSavedEditorReturnsAuthoritativeFreshPublicProfile() async throws {
        let (data,coordinator,access,n)=harness();let ticket=try XCTUnwrap(n.open(access.context(memberID:81,reader:data,isCurrent:true)))
        let editor=ProfileEditModel(coordinator:coordinator);await editor.resetAndLoad();editor.draft.introduction="Saved synthetic introduction"
        await editor.prepare();await editor.save(try XCTUnwrap(editor.confirmation));XCTAssertEqual(data.writes,1)
        XCTAssertTrue(editor.requestExit());XCTAssertTrue(n.finish(ticket.id,context:access.context(memberID:81,reader:data,isCurrent:true)))
        let profile=try await data.publicProfile(memberID:81);XCTAssertEqual(profile.introduction,"Saved synthetic introduction")
    }
    func testFailedReturnReadCanRetryWithoutAnotherSave() async throws {
        let (data,_,access,n)=harness();let ticket=try XCTUnwrap(n.open(access.context(memberID:81,reader:data,isCurrent:true)))
        XCTAssertTrue(n.finish(ticket.id,context:access.context(memberID:81,reader:data,isCurrent:true)));data.failNextPublic=true
        do { _ = try await data.publicProfile(memberID:81);XCTFail("expected read error") } catch { }
        let reread=try await data.publicProfile(memberID:81);XCTAssertEqual(reread.introduction,data.introduction);XCTAssertEqual(data.writes,0)
    }
    func testAccountRetirementBlocksEditorAndReturnRefresh() throws {
        let (data,_,access,n)=harness();let ticket=try XCTUnwrap(n.open(access.context(memberID:81,reader:data,isCurrent:true))),refresh=n.refreshID
        data.retireAccount();XCTAssertNil(access.context(memberID:81,reader:data,isCurrent:true))
        XCTAssertFalse(n.finish(ticket.id,context:access.context(memberID:81,reader:data,isCurrent:true)));XCTAssertEqual(n.refreshID,refresh)
    }
    func testOtherProfileAndGuestNeverObtainSelfEditAccess() {
        let (data,_,access,_)=harness();XCTAssertNil(access.context(memberID:92,reader:data,isCurrent:true))
        data.identity = .init(accountID:nil,epoch:2);XCTAssertNil(access.context(memberID:81,reader:data,isCurrent:true))
    }
    func testReturningDoesNotReadOrSaveUntilPublicScreenRequestsRead() throws {
        let (data,_,access,n)=harness();let ticket=try XCTUnwrap(n.open(access.context(memberID:81,reader:data,isCurrent:true)))
        XCTAssertTrue(n.finish(ticket.id,context:access.context(memberID:81,reader:data,isCurrent:true)))
        XCTAssertEqual(data.publicReads,0);XCTAssertEqual(data.editorReads,0);XCTAssertEqual(data.writes,0)
    }
}
