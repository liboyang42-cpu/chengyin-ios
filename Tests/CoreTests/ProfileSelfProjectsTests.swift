import XCTest
@testable import QuestifyCore

@MainActor final class ProfileSelfProjectsTests: XCTestCase {
    private final class PublicReader: SocialAccountReading {
        var identity=SocialAccountIdentity(accountID:81,epoch:1,role:"player"), presentationRevision:UInt64=1
        var isConfigured=true; let isOfflineExample=false
        func publicProfile(memberID:Int) async throws -> SocialPublicProfile { throw APIError.notConfigured }
        func informationList() async throws -> [SocialInformation] { [] }
        func information(id:Int) async throws -> SocialInformation { throw APIError.notConfigured }
        func invitationHistory(page:Int) async throws -> SocialInviteHistory { throw APIError.notConfigured }
    }
    private final class Reader: CreatorContentReading {
        var scope=UUID(), isAuthenticated=true, isConfigured=true; let isOfflineExample=false
        var page=CreatorContentProjectPage(rows:[],total:0); var error:Error?; var reads=0;var waits=false
        var queries:[CreatorContentQuery]=[];var pending:CheckedContinuation<CreatorContentProjectPage,Error>?
        func projects(query:CreatorContentQuery) async throws -> CreatorContentProjectPage {
            reads += 1;queries.append(query)
            if waits { return try await withCheckedThrowingContinuation {pending=$0} }
            if let error {throw error}; return page
        }
        func center() async throws -> CreatorContentCenter { throw APIError.invalidRequest }
    }
    private let social=PublicReader(),source=Reader()
    private func context(member:Int=81,owner:SocialAccountIdentity?=nil,scope:UUID?=nil,current:Bool=true)->ProfileSelfProjectsContext? {
        .capture(memberID:member,accountReader:social,projectsReader:source,owner:owner ?? social.identity,ownerScope:scope ?? source.scope,isCurrent:current)
    }
    private func reader() throws -> ProfileSelfProjectsScopedReader {
        .init(context:try XCTUnwrap(context()),accountReader:social,projectsReader:source,isCurrent:{true})
    }
    private func row(_ id:Int=7,type:String="topic",start:String?=nil,end:String?=nil) throws -> CreatorContentProject {
        var data:[String:Any]=["id":id,"bizType":type,"title":"Project \(id)"]
        if let start {data["startTime"]=start};if let end {data["endTime"]=end}
        return try JSONDecoder().decode(CreatorContentProject.self,from:JSONSerialization.data(withJSONObject:data))
    }
    private func status(_ start:String?,_ end:String?,_ today:String="2026-10-11")->ProfileSelfProjectSchedule? {
        ProfileSelfProjectCalendar.status(start:start,end:end,today:today)
    }
    private func awaitPending() async {for _ in 0..<100 where source.pending == nil {await Task.yield()};XCTAssertNotNil(source.pending)}
    func testEndDayRemainsRunningUntilFollowingShanghaiDay() {XCTAssertEqual(status("2026-10-01","2026-10-11"),.running);XCTAssertEqual(status("2026-10-01","2026-10-10"),.ended)}
    func testFutureProjectAndUnknownStart() {XCTAssertEqual(status("2026-10-12",nil),.upcoming);XCTAssertNil(status(nil,"2020-01-01"))}
    func testMissingAndReversedEndBecomeSingleDay() {XCTAssertEqual(status("2026-10-11",nil),.running);XCTAssertEqual(status("2026-10-11","2020-01-01"),.running)}
    func testTimestampUsesDatePrefixWithoutTimezoneShift() {XCTAssertEqual(ProfileSelfProjectCalendar.day(" 2026-10-11T23:30:00Z "),"2026-10-11");XCTAssertNil(ProfileSelfProjectCalendar.day("unknown"))}
    func testShanghaiDayCrossesBeforeUTCDate() throws {let date=try XCTUnwrap(ISO8601DateFormatter().date(from:"2026-10-10T16:01:00Z"));XCTAssertEqual(ProfileSelfProjectCalendar.today(at:date),"2026-10-11")}
    func testTopicFilterBeforeCapAndTypedIDSeparation() throws {
        let activity=try row(type:"activity"),topic=try row(),ended=try row(8,start:"2020-01-01",end:"2020-01-01")
        let p=ProfileSelfProjectsPreview(page:.init(rows:[activity,ended,topic,topic],total:4),today:"2026-10-11")
        XCTAssertEqual(p.rows,[topic]);XCTAssertFalse(p.sourceTruncated)
    }
    func testPreviewMaximumEightAndTruncationIndependentOfLiveCount() throws {let rows=try (1...12).map{try row($0)};let p=ProfileSelfProjectsPreview(page:.init(rows:rows,total:201),today:"2026-10-11");XCTAssertEqual(p.rows.count,8);XCTAssertTrue(p.sourceTruncated)}
    func testOwnContextOnlyAndRetiredRouteDenied() {XCTAssertNil(context(member:92));XCTAssertNil(context(current:false));social.identity = .init(accountID:nil,epoch:2);XCTAssertNil(context())}
    func testExactOwnerAndCapturedReaderScopeRequired() {XCTAssertNil(context(owner:.init(accountID:81,epoch:2)));let scope=source.scope;source.scope=UUID();XCTAssertNil(context(scope:scope))}
    func testConfigurationAndAuthenticationRequired() {source.isConfigured=false;XCTAssertNil(context());source.isConfigured=true;source.isAuthenticated=false;XCTAssertNil(context())}
    func testControllerUsesAllQueryNotUnsupportedTopicFilter() async throws {let c=ProfileSelfProjectsController();await c.load(reader:try reader());XCTAssertEqual(source.queries,[.init()])}
    func testReadFailureRetainsRowsThenRetryReplaces() async throws {
        let r=try reader(),c=ProfileSelfProjectsController();source.page = .init(rows:[try row()],total:1);await c.load(reader:r)
        source.error=APIError.httpStatus(503);await c.load(reader:r);XCTAssertEqual(c.page?.rows.count,1);XCTAssertNotNil(c.issue)
        source.error=nil;source.page = .init(rows:[],total:0);await c.load(reader:r);XCTAssertTrue(c.page?.rows.isEmpty == true);XCTAssertNil(c.issue)
    }
    func testUnauthorizedClearsPreviouslyLoadedPrivateRows() async throws {let r=try reader(),c=ProfileSelfProjectsController();source.page = .init(rows:[try row()],total:1);await c.load(reader:r);source.error=APIError.unauthorized;await c.load(reader:r);XCTAssertNil(c.page);XCTAssertEqual(c.issue,.login)}
    func testRetiredQueuedReadDoesNotDispatch() async throws {let r=try reader();social.presentationRevision += 1;do {_ = try await r.projects(query:.init());XCTFail()}catch{};XCTAssertEqual(source.reads,0)}
    func testLateResponseCannotPublishAfterScopeChanges() async throws {let r=try reader(),c=ProfileSelfProjectsController();source.waits=true;let task=Task{await c.load(reader:r)};await awaitPending();source.scope=UUID();source.pending?.resume(returning:.init(rows:[],total:0));source.pending=nil;await task.value;XCTAssertNil(c.page)}
    func testLateUnauthorizedBecomesCancellation() async throws {let r=try reader();source.waits=true;let task=Task{try await r.projects(query:.init())};await awaitPending();social.presentationRevision += 1;source.pending?.resume(throwing:APIError.unauthorized);source.pending=nil;do {_ = try await task.value;XCTFail()}catch is CancellationError {}catch {XCTFail("must retire")}}
    func testDuplicateLoadsAreCoalesced() async throws {let r=try reader(),c=ProfileSelfProjectsController();source.waits=true;let task=Task{await c.load(reader:r)};await awaitPending();await c.load(reader:r);XCTAssertEqual(source.reads,1);source.pending?.resume(returning:.init(rows:[],total:0));source.pending=nil;await task.value}
    func testSuspendInvalidatesLateResponse() async throws {let r=try reader(),c=ProfileSelfProjectsController();source.waits=true;let task=Task{await c.load(reader:r)};await awaitPending();c.suspend();source.pending?.resume(returning:.init(rows:[],total:0));source.pending=nil;await task.value;XCTAssertNil(c.page);XCTAssertFalse(c.isLoading)}
    func testOnlyCurrentVisibleExactRowCanOpen() async throws {let r=try reader(),c=ProfileSelfProjectsController(),project=try row();source.page = .init(rows:[project],total:1);await c.load(reader:r);XCTAssertTrue(c.canOpen(project,reader:r,today:"2026-10-11"));XCTAssertFalse(c.canOpen(try row(88),reader:r,today:"2026-10-11"));source.error=APIError.httpStatus(500);await c.load(reader:r);XCTAssertFalse(c.canOpen(project,reader:r,today:"2026-10-11"))}
    func testCenterIncomeReadIsNeverForwarded() async throws {do {_ = try await reader().center();XCTFail()}catch {XCTAssertEqual(error as? APIError,.invalidRequest)}}
}
