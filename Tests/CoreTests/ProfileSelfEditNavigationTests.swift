import XCTest
@testable import QuestifyCore

@MainActor final class ProfileSelfEditNavigationTests: XCTestCase {
    private let reader = NSObject(), editor = NSObject()
    private func context(member: Int = 81, viewer: Int? = 81, epoch: UInt64 = 1, revision: UInt64 = 1,
                         editorID: Int? = 81, editorEpoch: UInt64 = 1, editorRevision: UInt64? = 1,
                         readerConfigured: Bool = true, editorConfigured: Bool = true, current: Bool = true,
                         readerObject: AnyObject? = nil, editorObject: AnyObject? = nil) -> ProfileSelfEditContext? {
        .init(memberID: member, reader: readerObject ?? reader, viewer: .init(accountID:viewer,epoch:epoch,role:"player"),
            readerRevision:revision,readerConfigured:readerConfigured,coordinator:editorObject ?? editor,
            editorIdentity:editorID.map { .init(accountID:$0,epoch:editorEpoch) },editorRevision:editorRevision,
            editorConfigured:editorConfigured,isCurrent:current)
    }
    func testOwnProfileCanOpen() throws { let n=ProfileSelfEditNavigation();XCTAssertNotNil(n.open(context())) }
    func testGuestCannotOpen() { XCTAssertNil(ProfileSelfEditNavigation().open(context(viewer:nil))) }
    func testOtherMemberCannotOpen() { XCTAssertNil(context(member:92)) }
    func testMismatchedEditorAccountCannotOpen() { XCTAssertNil(context(editorID:92)) }
    func testMissingEditorSessionCannotOpen() { XCTAssertNil(context(editorID:nil)) }
    func testUnavailableReaderOrEditorCannotOpen() { XCTAssertNil(context(readerConfigured:false));XCTAssertNil(context(editorConfigured:false)) }
    func testNonpositiveMemberCannotOpen() { XCTAssertNil(context(member:0,viewer:0,editorID:0)) }
    func testRetiredParentCannotOpen() { XCTAssertNil(context(current:false)) }
    func testRepeatedOpenCannotReplaceActiveTicket() throws {
        let n=ProfileSelfEditNavigation(),first=try XCTUnwrap(n.open(context()));XCTAssertNil(n.open(context()));XCTAssertEqual(n.ticket,first)
    }
    func testSameContextReturnRequestsExactlyOneFreshRead() throws {
        let n=ProfileSelfEditNavigation(),before=n.refreshID,t=try XCTUnwrap(n.open(context()))
        XCTAssertTrue(n.finish(t.id,context:context()));XCTAssertNotEqual(n.refreshID,before);let after=n.refreshID
        XCTAssertFalse(n.finish(t.id,context:context()));XCTAssertEqual(n.refreshID,after);XCTAssertNil(n.ticket)
    }
    func testWrongTicketCannotFinishCurrentEditor() throws {
        let n=ProfileSelfEditNavigation(),t=try XCTUnwrap(n.open(context())),before=n.refreshID
        XCTAssertFalse(n.finish(UUID(),context:context()));XCTAssertEqual(n.ticket,t);XCTAssertEqual(n.refreshID,before)
    }
    func testStaleReturnDoesNotRefreshNewAccount() throws {
        let n=ProfileSelfEditNavigation(),t=try XCTUnwrap(n.open(context())),before=n.refreshID
        XCTAssertFalse(n.finish(t.id,context:context(member:82,viewer:82,editorID:82)));XCTAssertEqual(n.refreshID,before);XCTAssertNil(n.ticket)
    }
    func testViewerEpochOrRevisionRetiresOldTicket() throws {
        let n=ProfileSelfEditNavigation(),t=try XCTUnwrap(n.open(context()))
        XCTAssertFalse(n.isCurrent(t,context:context(epoch:2)));XCTAssertFalse(n.isCurrent(t,context:context(revision:2)))
    }
    func testEditorEpochAndRevisionRetireOldTicket() throws {
        let n=ProfileSelfEditNavigation(),t=try XCTUnwrap(n.open(context()))
        XCTAssertFalse(n.isCurrent(t,context:context(editorEpoch:2)));XCTAssertFalse(n.isCurrent(t,context:context(editorRevision:2)))
    }
    func testReaderOrCoordinatorReplacementRetiresTicket() throws {
        let n=ProfileSelfEditNavigation(),t=try XCTUnwrap(n.open(context()))
        XCTAssertFalse(n.isCurrent(t,context:context(readerObject:NSObject())));XCTAssertFalse(n.isCurrent(t,context:context(editorObject:NSObject())))
    }
    func testOldDismissCannotRetireReopenedEditor() throws {
        let n=ProfileSelfEditNavigation(),old=try XCTUnwrap(n.open(context()));_ = n.finish(old.id,context:context())
        let current=try XCTUnwrap(n.open(context())),before=n.refreshID
        XCTAssertFalse(n.finish(old.id,context:context()));XCTAssertEqual(n.ticket,current);XCTAssertEqual(n.refreshID,before)
    }
    func testNilContextCannotPublishReturnRefresh() throws {
        let n=ProfileSelfEditNavigation(),t=try XCTUnwrap(n.open(context())),before=n.refreshID
        XCTAssertFalse(n.finish(t.id,context:nil));XCTAssertEqual(n.refreshID,before)
    }
}
