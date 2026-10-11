import XCTest
@testable import QuestifyCore

@MainActor final class ProfileSelfGrowthTests:XCTestCase {
    private final class PublicReader:SocialAccountReading {
        var identity=SocialAccountIdentity(accountID:81,epoch:1,role:"player"),presentationRevision:UInt64=1
        var isConfigured=true;let isOfflineExample=false
        func publicProfile(memberID:Int) async throws->SocialPublicProfile { throw APIError.notConfigured }
        func informationList() async throws->[SocialInformation] { [] }
        func information(id:Int) async throws->SocialInformation { throw APIError.notConfigured }
        func invitationHistory(page:Int) async throws->SocialInviteHistory { throw APIError.notConfigured }
    }
    private final class Reader:GrowthCenterReading {
        var scope=UUID();var isAuthenticated=true;var isConfigured=true;let isOfflineExample=false
        var reads=0,boardReads=0;var waits=false;var error:Error?
        var pending:CheckedContinuation<GrowthCenterOverview,Error>?
        var queries:[GrowthBoardQuery]=[]
        var empty:GrowthCenterOverview { .init(center:.failure(.failed),progress:.failure(.failed),completed:.failure(.failed),rank:.failure(.failed)) }
        func overview() async throws->GrowthCenterOverview {
            reads += 1;if waits { return try await withCheckedThrowingContinuation { pending=$0 } };if let error {throw error};return empty
        }
        func leaderboard(query:GrowthBoardQuery) async throws->GrowthLeaderboard {
            boardReads += 1;queries.append(query)
            return try JSONDecoder().decode(GrowthLeaderboard.self,from:Data("{\"metric\":\"\(query.metric.rawValue)\",\"period\":\"\(query.period.rawValue)\",\"list\":[],\"me\":{}}".utf8))
        }
    }
    private let social=PublicReader(),reader=Reader()
    private func context(_ member:Int=81,owner:SocialAccountIdentity?=nil,scope:UUID?=nil,current:Bool=true)->ProfileSelfGrowthContext? {
        .capture(memberID:member,accountReader:social,growthReader:reader,owner:owner ?? social.identity,ownerScope:scope ?? reader.scope,isCurrent:current)
    }
    private func scoped() throws->ProfileSelfGrowthScopedReader { .init(context:try XCTUnwrap(context()),accountReader:social,growthReader:reader,isCurrent:{true}) }
    private func summary(center:String=#"{"growth":{"levelNo":3,"expValue":2450},"points":700,"badges":[],"missions":[]}"#,
                         progress:String=#"{"level":4,"totalCheckins":12,"totalMileage":13.45,"streakDays":2}"#) throws->ProfileSelfGrowthSummary {
        .init(.init(center:.content(try JSONDecoder().decode(GrowthCenterRecord.self,from:Data(center.utf8))),progress:.content(try JSONDecoder().decode(GrowthPlayProgress.self,from:Data(progress.utf8))),completed:.failure(.failed),rank:.failure(.failed)))
    }
    private func waitPending() async { for _ in 0..<100 where reader.pending == nil {await Task.yield()};XCTAssertNotNil(reader.pending) }
    func testSixMetricsUseExactSourceValues() throws { let s=try summary();XCTAssertEqual(s.level,4);XCTAssertEqual(s.experience,2450);XCTAssertEqual(s.points,700);XCTAssertEqual(s.checkins,12);XCTAssertEqual(s.mileage,13.45);XCTAssertEqual(s.streakDays,2) }
    func testKnownZeroIsPreservedInsteadOfUnknown() throws {
        let s=try summary(center:#"{"growth":{"levelNo":0,"expValue":0},"points":0,"badges":[],"missions":[]}"#,progress:#"{"level":0,"totalCheckins":0,"totalMileage":0,"streakDays":0}"#)
        XCTAssertEqual(s.level,1);XCTAssertEqual(s.points,0);XCTAssertEqual(s.mileage,0);XCTAssertEqual(s.checkins,0)
    }
    func testMissingMetricsRemainUnknown() throws { let s=try summary(center:#"{"growth":{},"badges":[],"missions":[]}"#,progress:#"{"totalMileage":null}"#);XCTAssertNil(s.level);XCTAssertNil(s.points);XCTAssertNil(s.mileage);XCTAssertNil(s.checkins) }
    func testNegativeValuesAreNotPresentedAsZero() throws { let s=try summary(center:#"{"growth":{"expValue":-1},"points":-2,"badges":[],"missions":[]}"#,progress:#"{"totalCheckins":-1,"totalMileage":-3,"streakDays":-2}"#);XCTAssertNil(s.points);XCTAssertNil(s.experience);XCTAssertNil(s.mileage);XCTAssertNil(s.streakDays) }
    func testMissingPlayLevelFallsBackToCenterLevel() throws { XCTAssertEqual(try summary(progress:#"{"totalMileage":0}"#).level,3) }
    func testFailedSectionsRemainFailuresNotEmptyRecords() { let s=ProfileSelfGrowthSummary(reader.empty);XCTAssertEqual(s.centerIssue,.failed);XCTAssertEqual(s.progressIssue,.failed);XCTAssertNil(s.points);XCTAssertNil(s.checkins) }
    func testOtherMemberGuestAndRetiredParentHaveNoContext() { XCTAssertNil(context(92));social.identity = .init(accountID:nil,epoch:2);XCTAssertNil(context());XCTAssertNil(context(current:false)) }
    func testHostOwnerMustExactlyMatchPublicViewer() { XCTAssertNil(context(owner:.init(accountID:81,epoch:2,role:"player")));XCTAssertNil(context(owner:.init(accountID:82,epoch:1))) }
    func testCapturedGrowthScopeCannotBeReusedAfterChange() { let old=reader.scope;reader.scope=UUID();XCTAssertNil(context(scope:old)) }
    func testUnconfiguredOrUnauthenticatedReaderHasNoContext() { reader.isConfigured=false;XCTAssertNil(context());reader.isConfigured=true;reader.isAuthenticated=false;XCTAssertNil(context()) }
    func testOverviewUsesExistingReaderOnce() async throws { _ = try await scoped().overview();XCTAssertEqual(reader.reads,1) }
    func testLeaderboardForwardsExactExistingQuery() async throws { let q=GrowthBoardQuery(metric:.exp,period:.week);_ = try await scoped().leaderboard(query:q);XCTAssertEqual(reader.queries,[q]) }
    func testQueuedOverviewAfterRetirementMakesNoRead() async throws { let s=try scoped();social.presentationRevision += 1;do {_ = try await s.overview();XCTFail()}catch{};XCTAssertEqual(reader.reads,0) }
    func testQueuedLeaderboardAfterRetirementMakesNoRead() async throws { let s=try scoped();reader.scope=UUID();do {_ = try await s.leaderboard(query:.init());XCTFail()}catch{};XCTAssertEqual(reader.boardReads,0) }
    func testLateOverviewCannotPublishToNewViewer() async throws {
        let s=try scoped();reader.waits=true;let task=Task{try await s.overview()};await waitPending();social.presentationRevision += 1
        reader.pending?.resume(returning:reader.empty);reader.pending=nil;do {_ = try await task.value;XCTFail()}catch is CancellationError {}catch {XCTFail("must retire")}
    }
    func testLateErrorIsRetiredRatherThanLeaked() async throws {
        let s=try scoped();reader.waits=true;let task=Task{try await s.overview()};await waitPending();social.presentationRevision += 1
        reader.pending?.resume(throwing:APIError.unauthorized);reader.pending=nil;do {_ = try await task.value;XCTFail()}catch is CancellationError {}catch {XCTFail("must retire")}
    }
    func testCurrentFailureRemainsRetryable() async throws { let s=try scoped();reader.error=APIError.httpStatus(503);do {_ = try await s.overview();XCTFail()}catch{};reader.error=nil;_ = try await s.overview();XCTAssertEqual(reader.reads,2) }
    func testScopeAndConfigurationRetireDestinationAccess() throws { let s=try scoped();XCTAssertTrue(s.isAuthenticated);reader.isConfigured=false;XCTAssertFalse(s.isAuthenticated);XCTAssertFalse(s.isConfigured) }
}
