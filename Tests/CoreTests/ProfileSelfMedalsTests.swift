import XCTest
@testable import QuestifyCore

@MainActor final class ProfileSelfMedalsTests: XCTestCase {
    private final class PublicReader: SocialAccountReading {
        var identity=SocialAccountIdentity(accountID:81,epoch:1,role:"player");var presentationRevision:UInt64=1
        var isConfigured=true;let isOfflineExample=false
        func publicProfile(memberID:Int) async throws -> SocialPublicProfile { throw APIError.notConfigured }
        func informationList() async throws -> [SocialInformation] { [] }
        func information(id:Int) async throws -> SocialInformation { throw APIError.notConfigured }
        func invitationHistory(page:Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
    }
    private final class Reader: ProfileReading {
        var identity:ProfileReadIdentity? = .init(accountID:81,epoch:1);var isConfigured=true;var reads=0
        var wall=ProfileBadgeWall(identities:[],medals:[]);var error:Error?;var waits=false
        var pending:CheckedContinuation<ProfileBadgeWall,Error>?
        func profileBadges() async throws -> ProfileBadgeWall {
            reads += 1;if waits { return try await withCheckedThrowingContinuation { pending=$0 } }
            if let error { throw error };return wall
        }
        func profileOrders() async throws -> [ProfileOrder] { [] }
        func profileOrder(id:Int) async throws -> ProfileOrder { throw APIError.notConfigured }
        func profileParticipants() async throws -> [ProfileParticipant] { [] }
        func profileParticipant(id:Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
    }
    private let social=PublicReader(),reader=Reader(),model=ProfileSelfMedalsController()
    private func rows(_ name:String="City medal") throws -> [ProfileMedal] {
        try JSONDecoder().decode([ProfileMedal].self,from:JSONSerialization.data(withJSONObject:[["templateId":101,"medalName":name,"kind":"city"],["badgeCode":"walker","medalName":"Achievement","kind":"achievement"]]))
    }
    private func load(_ member:Int=81,current:Bool=true) async { await model.load(memberID:member,accountReader:social,profileReader:reader,isCurrent:{current}) }
    private func waitForPending() async { for _ in 0..<100 where reader.pending == nil { await Task.yield() };XCTAssertNotNil(reader.pending) }
    func testLoadsBothEarnedCityAndAchievementRows() async throws { reader.wall = .init(identities:[],medals:try rows());await load();XCTAssertEqual(model.medals?.count,2);XCTAssertNil(model.issue) }
    func testValidEmptyIsDifferentFromPartial() async { await load();XCTAssertEqual(model.medals,[]);reader.wall = .init(identities:[],medals:nil);await load();XCTAssertEqual(model.issue,.partial) }
    func testInitialPartialDoesNotClaimZeroMedals() async { reader.wall = .init(identities:[],medals:nil);await load();XCTAssertNil(model.medals);XCTAssertEqual(model.issue,.partial) }
    func testInitialFailureCanRetryRead() async { reader.error=APIError.httpStatus(503);await load();XCTAssertEqual(model.issue,.readFailed);reader.error=nil;await load();XCTAssertEqual(model.medals,[]);XCTAssertEqual(reader.reads,2) }
    func testFailedRefreshRetainsPriorRows() async throws { reader.wall = .init(identities:[],medals:try rows());await load();reader.error=APIError.httpStatus(503);await load();XCTAssertEqual(model.medals?.count,2);XCTAssertEqual(model.issue,.readFailed) }
    func testPartialRefreshRetainsPriorRows() async throws { reader.wall = .init(identities:[],medals:try rows());await load();reader.wall = .init(identities:[],medals:nil);await load();XCTAssertEqual(model.medals?.count,2);XCTAssertEqual(model.issue,.partial) }
    func testFreshEmptyReplacesOldRows() async throws { reader.wall = .init(identities:[],medals:try rows());await load();reader.wall = .init(identities:[],medals:[]);await load();XCTAssertEqual(model.medals,[]);XCTAssertNil(model.issue) }
    func testUnauthorizedRefreshClearsRows() async throws { reader.wall = .init(identities:[],medals:try rows());await load();reader.error=APIError.unauthorized;await load();XCTAssertNil(model.medals);XCTAssertEqual(model.issue,.signIn) }
    func testSourceUnauthorizedAlsoClearsRows() async throws { reader.wall = .init(identities:[],medals:try rows());await load();reader.error=ProfileReadFailure(code:401);await load();XCTAssertNil(model.medals);XCTAssertEqual(model.issue,.signIn) }
    func testGuestAndOtherProfileNeverReadPrivateWall() async { social.identity = .init(accountID:nil,epoch:1);await load();social.identity = .init(accountID:81,epoch:1);await load(92);XCTAssertEqual(reader.reads,0) }
    func testMismatchedPrivateOwnerCannotRead() async { reader.identity = .init(accountID:92,epoch:1);await load();XCTAssertEqual(reader.reads,0) }
    func testUnconfiguredOrRetiredParentCannotRead() async { await load(current:false);reader.isConfigured=false;await load();XCTAssertEqual(reader.reads,0) }
    func testRepeatedReadWhileLoadingIsSuppressed() async {
        reader.waits=true;let task=Task{await load()};await waitForPending();await load();XCTAssertEqual(reader.reads,1)
        reader.pending?.resume(returning:reader.wall);reader.pending=nil;await task.value
    }
    func testRetiredReadCannotPublishLateRows() async throws {
        reader.waits=true;let task=Task{await load()};await waitForPending();model.suspend()
        reader.pending?.resume(returning:.init(identities:[],medals:try rows()));reader.pending=nil;await task.value;XCTAssertNil(model.medals)
    }
    func testAccountChangeCannotPublishLateRows() async throws {
        reader.waits=true;let task=Task{await load()};await waitForPending();social.identity = .init(accountID:82,epoch:2)
        reader.pending?.resume(returning:.init(identities:[],medals:try rows()));reader.pending=nil;await task.value;XCTAssertNil(model.medals)
    }
    func testSocialRevisionABARetiresLateRead() async throws {
        reader.waits=true;let task=Task{await load()};await waitForPending();social.presentationRevision += 1
        reader.pending?.resume(returning:.init(identities:[],medals:try rows()));reader.pending=nil;await task.value;XCTAssertNil(model.medals)
    }
    func testReaderReplacementCannotShareContext() {
        let first=ProfileSelfMedalsContext.capture(memberID:81,accountReader:social,profileReader:reader,isCurrent:true)
        XCTAssertNotEqual(first,ProfileSelfMedalsContext.capture(memberID:81,accountReader:social,profileReader:Reader(),isCurrent:true))
    }
    func testSuspensionKeepsScopedRowsButRetireClearsThem() async throws {
        reader.wall = .init(identities:[],medals:try rows());await load();model.suspend();XCTAssertEqual(model.medals?.count,2);model.retire();XCTAssertNil(model.medals);XCTAssertNil(model.context)
    }
    func testScopedWallReaderRejectsQueuedReadAfterAccountRetirement() async throws {
        let context=try XCTUnwrap(ProfileSelfMedalsContext.capture(memberID:81,accountReader:social,profileReader:reader,isCurrent:true))
        let scoped=ProfileSelfMedalsScopedReader(context:context,accountReader:social,profileReader:reader,isCurrent:{true})
        social.presentationRevision += 1;XCTAssertNil(scoped.identity)
        do { _ = try await scoped.profileBadges();XCTFail("retired read") } catch { }
        XCTAssertEqual(reader.reads,0)
    }
    func testScopedWallReaderRejectsLateResult() async throws {
        let context=try XCTUnwrap(ProfileSelfMedalsContext.capture(memberID:81,accountReader:social,profileReader:reader,isCurrent:true))
        let scoped=ProfileSelfMedalsScopedReader(context:context,accountReader:social,profileReader:reader,isCurrent:{true});reader.waits=true
        let task=Task { try await scoped.profileBadges() };await waitForPending();social.presentationRevision += 1
        reader.pending?.resume(returning:reader.wall);reader.pending=nil
        do { _ = try await task.value;XCTFail("stale result") } catch { }
    }

}
