import Foundation
import XCTest
@testable import Questify
@MainActor private final class NickHostVault:AppTokenStorage {
    var token:String?="synthetic-nick-host"
    func read() throws -> String?{token};func write(_ value:String) throws {token=value};func clear() throws {token=nil}
}
@MainActor private final class NickHostLogin:HTTPTransport {
    var requests:[URLRequest]=[],role="player"
    func send(_ r:URLRequest) async throws -> (Data,Int){requests.append(r);return(Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8),200)}
}
@MainActor private final class NickHostRead:ProfileNicknameDispatching {
    var requests:[URLRequest]=[],status=200,after:(()->Void)?
    func send(_ r:URLRequest,authorization:ProfileNicknameReadAuthorization) async throws -> (Data,Int){try authorization.forward(r){requests.append(r)};after?();return(Data(#"{"code":200,"data":{"nickname":"城市玩家","available":true}}"#.utf8),status)}
}
@MainActor private final class NickHostFixture {
    let root:AppCompositionRoot,defaults:UserDefaults,suite="nick-host-"+UUID().uuidString
    let vault=NickHostVault(),wire=NickHostLogin(),read=NickHostRead()
    init() throws {
        defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        let d=try ReviewedAppDeployment(market:.china,baseURL:"https://nick-host.example.test/native",approvedBaseURLs:[.china:["https://nick-host.example.test/native"]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.nick."+UUID().uuidString.lowercased(),realm:"synthetic")
        let wire=wire,vault=vault;root = .init(deployment:.reviewed(d),storage:.init(defaults:defaults,tokenStore:{_ in vault}),makeTransport:{wire})
    }
    func boot() async -> AppSession{let s=root.makeSession();await s.bootstrap();wire.requests=[];return s}
    func grant(_ s:AppSession,viewer:UInt64?=nil) throws -> ProfileNicknameReadApproval{
        let a=try ProfileNicknameReadApproval(context:XCTUnwrap(s.profileNicknameIdentity.context),viewerRevision:viewer ?? s.profileNicknameIdentity.viewerRevision,expiresAt:Date().addingTimeInterval(600));try root.profileNicknameSelection.replace(with:a);return a
    }
    func cleanup(){root.profileNicknameSelection.revoke();defaults.removePersistentDomain(forName:suite)}
}
@MainActor private final class NickHostFlowReader:ProfileNicknameAvailabilityReading {
    var identity:ProfileReadIdentity? = .init(accountID:7,epoch:1),viewerRevision:UInt64?=3,sourceRevision:UUID?=UUID(),isConfigured=true
    var calls=0
    func check(_ value:String) async throws -> ProfileNicknameCheck {calls+=1;return .taken}
    func suggest(_ base:String,cursor:Int?) async throws -> ProfileNicknameSuggestion{let next=(cursor ?? 0)+1;return .init(nickname:base+"#000"+String(next),cursor:next)}
}
@MainActor private final class NickHostProfileService:ProfileEditServing {
    var writes=0
    func read(token:String) async throws -> ProfileEditSnapshot{try JSONDecoder().decode(ProfileEditSnapshot.self,from:Data(#"{"id":7,"nickname":"原名字","introduction":"Saved","avatar":"saved","wechat":"","casePics":"","tagIds":""}"#.utf8))}
    func save(_ payload:ProfileEditPayload,token:String) async throws{writes+=1;throw ProfileEditWriteError.outcomeUnknown}
}
@MainActor final class NicknameC6HostTests:XCTestCase {
    private func host() throws -> NickHostFixture{let f=try NickHostFixture();addTeardownBlock{@MainActor in f.cleanup()};return f}
    func testUnconfiguredRootNeverReturnsNicknameReaderOrDispatches() async throws{
        let f=try host(),s=await f.boot();XCTAssertNil(s.profileNicknameReader);XCTAssertNil(s.makeProfileNicknameReader(transport:f.read));XCTAssertTrue(f.wire.requests.isEmpty);XCTAssertTrue(f.read.requests.isEmpty)
    }
    func testExplicitReadLeaseUsesNativePOSTWithoutGenericHostTransport() async throws{
        let f=try host(),s=await f.boot();_=try f.grant(s);let r=try XCTUnwrap(s.makeProfileNicknameReader(transport:f.read)),result=try await r.check("城市玩家")
        XCTAssertEqual(result,.available);XCTAssertEqual(f.read.requests.first?.url?.path,"/native/api/user/nickname/check");XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testReaderCacheRetiresOnWithdrawalAndRejectsReusedIssuance() async throws{
        let f=try host(),s=await f.boot(),old=try f.grant(s),r=try XCTUnwrap(s.profileNicknameReader);XCTAssertTrue(r === s.profileNicknameReader)
        f.root.profileNicknameSelection.revoke();XCTAssertNil(s.profileNicknameReader);XCTAssertFalse(r.isConfigured);XCTAssertThrowsError(try f.root.profileNicknameSelection.replace(with:old))
        _=try f.grant(s);XCTAssertFalse(r === s.profileNicknameReader)
    }
    func testWrongViewerOrRoleRefreshCannotReuseSource() async throws{
        let f=try host(),s=await f.boot();_=try f.grant(s,viewer:s.profileNicknameIdentity.viewerRevision &+ 1);XCTAssertNil(s.makeProfileNicknameReader(transport:f.read))
        _=try f.grant(s);let r=try XCTUnwrap(s.makeProfileNicknameReader(transport:f.read));f.wire.role="merchant";await s.refreshOwnAccount();XCTAssertFalse(r.isConfigured);XCTAssertNil(s.makeProfileNicknameReader(transport:f.read))
    }
    func testCurrentUnauthorizedNeverLogsOutOrClearsToken() async throws{
        let f=try host(),s=await f.boot();_=try f.grant(s);let r=try XCTUnwrap(s.makeProfileNicknameReader(transport:f.read));f.read.status=403
        do{_=try await r.check("城市玩家");XCTFail()}catch{}
        XCTAssertNil(s.makeProfileNicknameReader(transport:f.read));XCTAssertEqual(s.account?.id,7);XCTAssertEqual(f.vault.token,"synthetic-nick-host")
    }
    func testLateUnauthorizedCannotRevokeReplacementReadLease() async throws{
        let f=try host(),s=await f.boot(),old=try f.grant(s),r=try XCTUnwrap(s.makeProfileNicknameReader(transport:f.read));var replacement:ProfileNicknameReadApproval?
        f.read.status=401;f.read.after={replacement=try? f.grant(s)}
        do{_=try await r.check("城市玩家");XCTFail()}catch{}
        XCTAssertFalse(old.revoked);XCTAssertFalse(replacement?.revoked ?? true);XCTAssertEqual(s.account?.id,7)
    }
    func testHiddenOwnerCannotReadUntilActualReappearance() async{
        let r=NickHostFlowReader(),m=ProfileNicknameAvailabilityModel(flow:.init(reader:r));m.appear();m.leave();await m.load("城市玩家",original:"原名字");XCTAssertEqual(r.calls,0);XCTAssertFalse(m.visible)
        m.appear();await m.load("城市玩家",original:"原名字");XCTAssertEqual(r.calls,1)
    }
    func testDifferentExpectedEditorIdentityCannotExposeCandidates() async{
        let r=NickHostFlowReader(),m=ProfileNicknameAvailabilityModel(flow:.init(reader:r,expectedIdentity:.init(accountID:8,epoch:1),expectedViewerRevision:3));m.appear();await m.load("城市玩家",original:"原名字")
        XCTAssertEqual(r.calls,0);XCTAssertTrue(m.flow.candidates.isEmpty);XCTAssertNil(m.flow.actionID)
    }
    func testSuggestionOnlyChangesTemporaryTextUntilOriginalConfirm() async throws{
        let service=NickHostProfileService(),session=try ProfileEditSession(accountID:7,epoch:1,token:"synthetic-editor",viewerRevision:3),model=ProfileEditModel(coordinator:.init(service:service,currentSession:{session}))
        await model.resetAndLoad();model.beginTextEdit(.name);let edit=try XCTUnwrap(model.textEdit),draft=model.draft,r=NickHostFlowReader(),flow=ProfileNicknameAvailabilityFlow(reader:r)
        flow.activate();flow.setInput("城市玩家");await flow.check(debounce:false);let action=try XCTUnwrap(flow.actionID),temporary=try XCTUnwrap(flow.select("城市玩家#0001",action:action))
        XCTAssertEqual(model.draft,draft);XCTAssertEqual(service.writes,0)
        XCTAssertTrue(model.confirmTextEdit(edit,text:temporary));XCTAssertEqual(model.draft.name,temporary);XCTAssertEqual(service.writes,0)
    }
    func testReadOrCandidateCannotResolveOriginalUnknownOrPersistData() async throws{
        let service=NickHostProfileService(),session=try ProfileEditSession(accountID:7,epoch:1,token:"synthetic-editor",viewerRevision:3),model=ProfileEditModel(coordinator:.init(service:service,currentSession:{session}))
        await model.resetAndLoad();model.draft.introduction="Changed";await model.prepare();let confirmation=try XCTUnwrap(model.confirmation);_=await model.save(confirmation);XCTAssertTrue(model.coordinator.isLocked)
        let draft=model.draft,r=NickHostFlowReader(),flow=ProfileNicknameAvailabilityFlow(reader:r);flow.activate();flow.setInput("城市玩家");await flow.check(debounce:false)
        XCTAssertTrue(model.coordinator.isLocked);XCTAssertEqual(model.draft,draft);XCTAssertEqual(service.writes,1)
    }

    func testReadLeaseDurationIsCapturedBeforeWallClockRollback() {
        let start = Date(timeIntervalSince1970: 1_800_000_000), expires = start.addingTimeInterval(300)
        let delay = ProfileNicknameSourceSelection.expirationDelay(expiresAt: expires, observedAt: start)
        let clock = ContinuousClock(), admitted = clock.now
        let deadline = admitted.advanced(by: .nanoseconds(delay))
        XCTAssertEqual(delay, 300_000_000_000)
        XCTAssertGreaterThan(ProfileNicknameSourceSelection.expirationDelay(expiresAt: expires, observedAt: start.addingTimeInterval(-3600)), delay)
        XCTAssertEqual(admitted.duration(to: deadline), .seconds(300))
    }
    func testReadLeaseDurationRejectsExpiredNonfiniteAndBoundsOverflow() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ProfileNicknameSourceSelection.expirationDelay(expiresAt: start, observedAt: start), 0)
        XCTAssertEqual(ProfileNicknameSourceSelection.expirationDelay(expiresAt: start.addingTimeInterval(-1), observedAt: start), 0)
        XCTAssertEqual(ProfileNicknameSourceSelection.expirationDelay(expiresAt: Date(timeIntervalSince1970: .infinity), observedAt: start), 0)
        XCTAssertEqual(ProfileNicknameSourceSelection.expirationDelay(expiresAt: start.addingTimeInterval(0.125), observedAt: start), 125_000_000)
        let bounded = ProfileNicknameSourceSelection.expirationDelay(expiresAt: .distantFuture, observedAt: start)
        XCTAssertGreaterThan(bounded, 0); XCTAssertLessThan(bounded, Int64.max)
    }
    func testDeadlineRetiresReaderWithoutChangingAccountAndFreshLeaseRecovers() async throws {
        let f=try host(),s=await f.boot()
        let old=try ProfileNicknameReadApproval(context:XCTUnwrap(s.profileNicknameIdentity.context),viewerRevision:s.profileNicknameIdentity.viewerRevision,expiresAt:Date().addingTimeInterval(0.5))
        try f.root.profileNicknameSelection.replace(with:old)
        let reader=try XCTUnwrap(s.makeProfileNicknameReader(transport:f.read)),revision=f.root.profileNicknameSelection.revision
        let clock=ContinuousClock(),limit=clock.now.advanced(by:.seconds(3))
        while f.root.profileNicknameSelection.revision == revision && clock.now < limit {
            try await Task.sleep(nanoseconds:20_000_000)
        }
        XCTAssertNotEqual(f.root.profileNicknameSelection.revision,revision)
        XCTAssertNil(s.makeProfileNicknameReader(transport:f.read)); XCTAssertFalse(reader.isConfigured)
        XCTAssertEqual(s.account?.id,7); XCTAssertEqual(f.vault.token,"synthetic-nick-host")
        XCTAssertThrowsError(try f.root.profileNicknameSelection.replace(with:old))
        let fresh=try ProfileNicknameReadApproval(context:old.context,viewerRevision:old.viewerRevision,expiresAt:Date().addingTimeInterval(30))
        try f.root.profileNicknameSelection.replace(with:fresh)
        XCTAssertNotNil(s.makeProfileNicknameReader(transport:f.read)); XCTAssertFalse(reader.isConfigured)
    }
    func testOldExpiryTaskCannotRetireReplacementLease() async throws {
        let f=try host(),s=await f.boot()
        let old=try ProfileNicknameReadApproval(context:XCTUnwrap(s.profileNicknameIdentity.context),viewerRevision:s.profileNicknameIdentity.viewerRevision,expiresAt:Date().addingTimeInterval(0.5))
        try f.root.profileNicknameSelection.replace(with:old)
        let reader=try XCTUnwrap(s.makeProfileNicknameReader(transport:f.read))
        let fresh=try ProfileNicknameReadApproval(context:old.context,viewerRevision:old.viewerRevision,expiresAt:Date().addingTimeInterval(30))
        try f.root.profileNicknameSelection.replace(with:fresh)
        let revision=f.root.profileNicknameSelection.revision
        try await Task.sleep(nanoseconds:600_000_000)
        XCTAssertEqual(f.root.profileNicknameSelection.revision,revision)
        XCTAssertTrue(f.root.profileNicknameSelection.approval(for:fresh.context) === fresh)
        XCTAssertNotNil(s.makeProfileNicknameReader(transport:f.read)); XCTAssertFalse(reader.isConfigured)
    }
}
