import Foundation
import XCTest
@testable import Questify

@MainActor private final class ReviewC6AppWire: ProfileCurrentReviewDispatching {
    var requests: [URLRequest] = []
    var status=200, failed=false
    var after: (() -> Void)?
    func send(_ request: URLRequest, authorization: ProfileCurrentReviewAuthorization) async throws -> (Data,Int) {
        try authorization.forward(request) { requests.append(request) };after?()
        if failed { throw ProfileCurrentReviewFailure.unavailable }
        return (Data(#"{"code":200,"data":{"available":true,"currentVersion":9,"avatar":{"versionNo":7,"state":"REJECTED","live":false}}}"#.utf8),status)
    }
}
@MainActor private final class ReviewC6AppVault: AppTokenStorage {
    var value: String?="synthetic-review-app-token"
    func read() throws -> String? { value }
    func write(_ value:String) throws { self.value=value }
    func clear() throws { value=nil }
}
@MainActor private final class ReviewC6LoginWire: HTTPTransport {
    var requests:[URLRequest]=[], role="player"
    func send(_ request:URLRequest) async throws -> (Data,Int) {
        requests.append(request)
        return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8),200)
    }
}
@MainActor private final class ReviewC6HostFixture {
    let wire=ReviewC6LoginWire(),vault=ReviewC6AppVault(),review=ReviewC6AppWire()
    let root:AppCompositionRoot
    let suite="review-c6-"+UUID().uuidString
    let defaults:UserDefaults
    init() throws {
        defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        let deployment=try ReviewedAppDeployment(market:.china,baseURL:"https://review-host.example.test/native",approvedBaseURLs:[.china:["https://review-host.example.test/native"]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.review."+UUID().uuidString.lowercased(),realm:"synthetic")
        let wire=wire,vault=vault
        root = .init(deployment:.reviewed(deployment),storage:.init(defaults:defaults,tokenStore:{_ in vault}),makeTransport:{wire})
    }
    func boot() async -> AppSession { let s=root.makeSession();await s.bootstrap();wire.requests=[];return s }
    func approve(_ s:AppSession,viewer:UInt64?=nil) throws -> ProfileCurrentReviewReadApproval {
        let a=try ProfileCurrentReviewReadApproval(context:XCTUnwrap(s.profileCurrentReviewIdentity.context),viewerRevision:viewer ?? s.profileCurrentReviewIdentity.viewerRevision,expiresAt:Date().addingTimeInterval(600))
        try root.profileCurrentReviewSelection.replace(with:a);return a
    }
    func snapshot() throws -> ProfileEditSnapshot {
        try JSONDecoder().decode(ProfileEditSnapshot.self,from:Data(#"{"id":7,"nickname":"Synthetic","introduction":"","avatar":"saved","wechat":"","casePics":"","tagIds":""}"#.utf8))
    }
    func key(_ r:ProfileCurrentReviewReader,_ s:ProfileEditSnapshot) -> ProfileCurrentReviewReadKey? { r.key(snapshot:s,editorID:UUID(),lifetimeID:UUID(),draftRevision:0,readRevision:1) }
    func cleanup() { root.profileCurrentReviewSelection.revoke();defaults.removePersistentDomain(forName:suite) }
}
@MainActor private final class ReviewC6EditorIdentity {
    var session:ProfileEditSession?
    let context:RuntimeDependencyContext
    var approval:ProfileCurrentReviewReadApproval?
    init() throws {
        context = .init(market:.china,baseURL:URL(string:"https://review-editor.example.test")!,role:"player",session:try .init(accountID:41,epoch:1,namespace:"review-editor",token:"synthetic-editor-token",role:"player"))
        session=try .init(accountID:41,epoch:1,token:"synthetic-editor-token",viewerRevision:1)
        approval=try .init(context:context,viewerRevision:1,expiresAt:Date().addingTimeInterval(600))
    }
}
@MainActor private final class ReviewC6EditorService:ProfileEditServing {
    var reads=0,writes=0,unknown=false
    var fields:[String:Any]=["id":41,"nickname":"Synthetic","introduction":"Saved","avatar":"saved","wechat":"","casePics":"","tagIds":""]
    func read(token:String) async throws -> ProfileEditSnapshot { reads+=1;return try JSONDecoder().decode(ProfileEditSnapshot.self,from:JSONSerialization.data(withJSONObject:fields)) }
    func save(_ payload:ProfileEditPayload,token:String) async throws {
        writes+=1;if unknown { throw ProfileEditWriteError.outcomeUnknown };fields["nickname"]=payload.name;fields["introduction"]=payload.introduction
    }
}
@MainActor private struct ReviewC6EditorHarness {
    let model:ProfileEditModel,service:ReviewC6EditorService,identity:ReviewC6EditorIdentity,wire:ReviewC6AppWire,reader:ProfileCurrentReviewReader,owner:ProfileCurrentReviewNoticeOwner
    func key() -> ProfileCurrentReviewReadKey? { ProfileCurrentReviewNoticeContext.key(model:model,reader:reader,active:owner.active) }
    func load() async throws {
        let key=try XCTUnwrap(key()),snapshot=try XCTUnwrap(model.coordinator.currentAvatarReadSnapshot)
        await owner.load(reader:reader,snapshot:snapshot,key:key,currentKey:{self.key()})
    }
}
@MainActor final class ProfileReviewC6HostTests:XCTestCase {
    private func host() throws -> ReviewC6HostFixture { let f=try ReviewC6HostFixture();addTeardownBlock{@MainActor in f.cleanup()};return f }
    private func editor() async throws -> ReviewC6EditorHarness {
        let identity=try ReviewC6EditorIdentity(),service=ReviewC6EditorService(),wire=ReviewC6AppWire(),owner=ProfileCurrentReviewNoticeOwner()
        let model=ProfileEditModel(coordinator:.init(service:service,currentSession:{identity.session}))
        let reader=ProfileCurrentReviewReader(baseURL:identity.context.baseURL,namespace:identity.context.session.namespace,currentSession:{identity.session},currentApproval:{identity.approval},currentContext:{identity.context},transport:wire)
        owner.setVisible(true,sceneActive:true);await model.resetAndLoad()
        return .init(model:model,service:service,identity:identity,wire:wire,reader:reader,owner:owner)
    }
    func testNormalCompositionDefaultsToNoReviewSourceOrRequest() async throws {
        let f=try host(),s=await f.boot();XCTAssertNil(s.profileCurrentReviewReader);XCTAssertNil(s.makeProfileCurrentReviewReader(transport:f.review))
        XCTAssertNil(s.profileCurrentReviewIdentity.approvalRevision);XCTAssertTrue(f.wire.requests.isEmpty);XCTAssertTrue(f.review.requests.isEmpty)
    }
    func testNormalHostUsesScopedGETWithoutGenericHTTPFallback() async throws {
        let f=try host(),s=await f.boot();_=try f.approve(s)
        let r=try XCTUnwrap(s.makeProfileCurrentReviewReader(transport:f.review)),snapshot=try f.snapshot(),key=try XCTUnwrap(f.key(r,snapshot))
        _=try await r.read(snapshot:snapshot,key:key,isCurrent:{true})
        XCTAssertEqual(f.review.requests.first?.httpMethod,"GET");XCTAssertEqual(f.review.requests.first?.url?.path,"/native/api/user/profile/review");XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testRetainedNormalReaderIsStableUntilSelectionChanges() async throws {
        let f=try host(),s=await f.boot();_=try f.approve(s)
        let first=try XCTUnwrap(s.profileCurrentReviewReader);XCTAssertTrue(first === s.profileCurrentReviewReader)
        f.root.profileCurrentReviewSelection.revoke();XCTAssertNil(s.profileCurrentReviewReader);XCTAssertNil(f.key(first,try f.snapshot()))
        _=try f.approve(s);XCTAssertFalse(first === s.profileCurrentReviewReader)
    }
    func testSourceRevocationAndReinstallationNeverReviveOldReader() async throws {
        let f=try host(),s=await f.boot(),old=try f.approve(s),r=try XCTUnwrap(s.makeProfileCurrentReviewReader(transport:f.review)),snapshot=try f.snapshot()
        f.root.profileCurrentReviewSelection.revoke();XCTAssertNil(f.key(r,snapshot));XCTAssertThrowsError(try f.root.profileCurrentReviewSelection.replace(with:old))
        _=try f.approve(s);XCTAssertNil(f.key(r,snapshot));XCTAssertNotNil(s.makeProfileCurrentReviewReader(transport:f.review))
    }
    func testWrongViewerRevisionCannotOpenHostFactory() async throws {
        let f=try host(),s=await f.boot();_=try f.approve(s,viewer:s.profileCurrentReviewIdentity.viewerRevision &+ 1)
        XCTAssertNil(s.makeProfileCurrentReviewReader(transport:f.review));XCTAssertTrue(f.review.requests.isEmpty)
    }
    func testRoleRefreshMakesOldReadIdentityAndKeysInvalid() async throws {
        let f=try host(),s=await f.boot();_=try f.approve(s)
        let old=s.profileCurrentReviewIdentity,r=try XCTUnwrap(s.makeProfileCurrentReviewReader(transport:f.review)),snapshot=try f.snapshot()
        f.wire.role="merchant";await s.refreshOwnAccount()
        XCTAssertNotEqual(s.profileCurrentReviewIdentity,old);XCTAssertNil(f.key(r,snapshot));XCTAssertNil(s.makeProfileCurrentReviewReader(transport:f.review))
    }
    func testCurrentDenialDoesNotLogOutOrClearStoredToken() async throws {
        let f=try host(),s=await f.boot();_=try f.approve(s)
        let r=try XCTUnwrap(s.makeProfileCurrentReviewReader(transport:f.review)),snapshot=try f.snapshot(),key=try XCTUnwrap(f.key(r,snapshot));f.review.status=403
        do {_=try await r.read(snapshot:snapshot,key:key,isCurrent:{true});XCTFail()}catch{}
        XCTAssertNil(s.makeProfileCurrentReviewReader(transport:f.review));XCTAssertEqual(s.account?.id,7);XCTAssertEqual(f.vault.value,"synthetic-review-app-token")
    }
    func testLateDenialDoesNotRevokeReplacementLease() async throws {
        let f=try host(),s=await f.boot(),old=try f.approve(s)
        let r=try XCTUnwrap(s.makeProfileCurrentReviewReader(transport:f.review)),snapshot=try f.snapshot(),key=try XCTUnwrap(f.key(r,snapshot))
        var replacement:ProfileCurrentReviewReadApproval?;f.review.status=401;f.review.after={replacement=try? f.approve(s)}
        do {_=try await r.read(snapshot:snapshot,key:key,isCurrent:{true});XCTFail()}catch{}
        XCTAssertFalse(old.revoked);XCTAssertFalse(replacement?.revoked ?? true);XCTAssertEqual(s.account?.id,7)
    }
    func testReadLeavesDraftSavedProjectionAndWriterUntouched() async throws {
        let h=try await editor(),draft=h.model.draft,reads=h.service.reads;try await h.load()
        XCTAssertNotNil(h.owner.fact(for:h.key()));XCTAssertEqual(h.model.draft,draft);XCTAssertEqual(h.service.reads,reads);XCTAssertEqual(h.service.writes,0)
    }
    func testPickerDraftABAAndExplicitReloadClearOldNotice() async throws {
        let h=try await editor();try await h.load();let old=try XCTUnwrap(h.key())
        h.model.avatarPresentationActive=true;XCTAssertNil(h.key());XCTAssertNil(h.owner.fact(for:h.key()));h.model.avatarPresentationActive=false
        let draft=h.model.draft;h.model.draft.introduction="Local edit";h.model.draft=draft
        XCTAssertNotEqual(h.key(),old);XCTAssertNil(h.owner.fact(for:h.key()));try await h.load()
        let before=h.key();await h.model.requestReload();XCTAssertNotEqual(h.key(),before);XCTAssertNil(h.owner.fact(for:h.key()));XCTAssertEqual(h.service.writes,0)
    }
    func testHiddenForegroundCannotReactivateOwnerAndReentryReadsFresh() async throws {
        let h=try await editor();try await h.load();h.owner.setVisible(false,sceneActive:true)
        h.owner.setSceneActive(false);h.owner.setSceneActive(true);XCTAssertFalse(h.owner.active);XCTAssertNil(h.key())
        h.owner.setVisible(true,sceneActive:true);XCTAssertNil(h.owner.fact(for:h.key()));try await h.load();XCTAssertNotNil(h.owner.fact(for:h.key()))
    }
    func testBackgroundAndRevokedGrantHideFactImmediately() async throws {
        let h=try await editor();try await h.load();h.owner.setSceneActive(false);XCTAssertNil(h.key())
        h.model.suspendForBackground();h.model.activateAvatar();h.owner.setSceneActive(true);XCTAssertNil(h.owner.fact(for:h.key()))
        try await h.load();h.identity.approval?.revoke();XCTAssertNil(h.key());XCTAssertNil(h.owner.fact(for:h.key()));XCTAssertEqual(h.service.writes,0)
    }
    func testSnapshotGetterCannotReuseLoadedAccountAcrossSessionChange() async throws {
        let h=try await editor();XCTAssertNotNil(h.model.coordinator.currentAvatarReadSnapshot)
        h.identity.session=try .init(accountID:42,epoch:2,token:"synthetic-new-account",viewerRevision:2)
        XCTAssertNil(h.model.coordinator.currentAvatarReadSnapshot);XCTAssertNil(h.key());XCTAssertEqual(h.service.writes,0)
    }
    func testFailureClearsNoticeWithoutDiscardingLocalDraft() async throws {
        let h=try await editor();try await h.load();let draft=h.model.draft;h.wire.failed=true;try await h.load()
        XCTAssertNil(h.owner.fact(for:h.key()));XCTAssertEqual(h.model.draft,draft);XCTAssertEqual(h.service.writes,0)
    }
    func testReviewCannotResolveUnknownSaveOrResendOriginalWrite() async throws {
        let h=try await editor();h.model.draft.introduction="Changed";await h.model.prepare();let c=try XCTUnwrap(h.model.confirmation);h.service.unknown=true
        let saved=await h.model.save(c);XCTAssertNil(saved);XCTAssertTrue(h.model.coordinator.isLocked)
        let draft=h.model.draft,reads=h.service.reads,message=h.model.coordinator.messageKey;try await h.load()
        XCTAssertTrue(h.model.coordinator.isLocked);XCTAssertEqual(h.model.draft,draft);XCTAssertEqual(h.service.reads,reads);XCTAssertEqual(h.service.writes,1);XCTAssertEqual(h.model.coordinator.messageKey,message)
    }
    func testOriginalSaveConfirmationAndOneUseReturnAreIndependentOfReview() async throws {
        let h=try await editor();try await h.load();h.model.draft.introduction="Changed";await h.model.prepare();XCTAssertNil(h.key())
        let c=try XCTUnwrap(h.model.confirmation),result=await h.model.save(c),receipt=try XCTUnwrap(result)
        XCTAssertTrue(h.model.consumeSavedReturn(receipt));XCTAssertFalse(h.model.consumeSavedReturn(receipt));XCTAssertEqual(h.service.writes,1);XCTAssertEqual(h.wire.requests.count,1)
    }

    func testReadLeaseDurationIsCapturedBeforeWallClockRollback() {
        let start = Date(timeIntervalSince1970: 1_800_000_000), expires = start.addingTimeInterval(300)
        let delay = ProfileCurrentReviewSourceSelection.expirationDelay(expiresAt: expires, observedAt: start)
        let clock = ContinuousClock(), admitted = clock.now
        let deadline = admitted.advanced(by: .nanoseconds(delay))
        XCTAssertEqual(delay, 300_000_000_000)
        XCTAssertGreaterThan(ProfileCurrentReviewSourceSelection.expirationDelay(expiresAt: expires, observedAt: start.addingTimeInterval(-3600)), delay)
        XCTAssertEqual(admitted.duration(to: deadline), .seconds(300))
    }
    func testReadLeaseDurationRejectsExpiredNonfiniteAndBoundsOverflow() {
        let start = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(ProfileCurrentReviewSourceSelection.expirationDelay(expiresAt: start, observedAt: start), 0)
        XCTAssertEqual(ProfileCurrentReviewSourceSelection.expirationDelay(expiresAt: start.addingTimeInterval(-1), observedAt: start), 0)
        XCTAssertEqual(ProfileCurrentReviewSourceSelection.expirationDelay(expiresAt: Date(timeIntervalSince1970: .infinity), observedAt: start), 0)
        XCTAssertEqual(ProfileCurrentReviewSourceSelection.expirationDelay(expiresAt: start.addingTimeInterval(0.125), observedAt: start), 125_000_000)
        let bounded = ProfileCurrentReviewSourceSelection.expirationDelay(expiresAt: .distantFuture, observedAt: start)
        XCTAssertGreaterThan(bounded, 0); XCTAssertLessThan(bounded, Int64.max)
    }
    func testDeadlineRetiresReaderWithoutChangingAccountAndFreshLeaseRecovers() async throws {
        let f=try host(),s=await f.boot()
        let old=try ProfileCurrentReviewReadApproval(context:XCTUnwrap(s.profileCurrentReviewIdentity.context),viewerRevision:s.profileCurrentReviewIdentity.viewerRevision,expiresAt:Date().addingTimeInterval(0.5))
        try f.root.profileCurrentReviewSelection.replace(with:old)
        let reader=try XCTUnwrap(s.makeProfileCurrentReviewReader(transport:f.review)),revision=f.root.profileCurrentReviewSelection.revision
        let clock=ContinuousClock(),limit=clock.now.advanced(by:.seconds(3))
        while f.root.profileCurrentReviewSelection.revision == revision && clock.now < limit {
            try await Task.sleep(nanoseconds:20_000_000)
        }
        XCTAssertNotEqual(f.root.profileCurrentReviewSelection.revision,revision)
        XCTAssertNil(s.makeProfileCurrentReviewReader(transport:f.review)); XCTAssertNil(f.key(reader,try f.snapshot()))
        XCTAssertEqual(s.account?.id,7); XCTAssertEqual(f.vault.value,"synthetic-review-app-token")
        XCTAssertThrowsError(try f.root.profileCurrentReviewSelection.replace(with:old))
        let fresh=try ProfileCurrentReviewReadApproval(context:old.context,viewerRevision:old.viewerRevision,expiresAt:Date().addingTimeInterval(30))
        try f.root.profileCurrentReviewSelection.replace(with:fresh)
        XCTAssertNotNil(s.makeProfileCurrentReviewReader(transport:f.review)); XCTAssertNil(f.key(reader,try f.snapshot()))
    }
    func testOldExpiryTaskCannotRetireReplacementLease() async throws {
        let f=try host(),s=await f.boot()
        let old=try ProfileCurrentReviewReadApproval(context:XCTUnwrap(s.profileCurrentReviewIdentity.context),viewerRevision:s.profileCurrentReviewIdentity.viewerRevision,expiresAt:Date().addingTimeInterval(0.5))
        try f.root.profileCurrentReviewSelection.replace(with:old)
        let reader=try XCTUnwrap(s.makeProfileCurrentReviewReader(transport:f.review))
        let fresh=try ProfileCurrentReviewReadApproval(context:old.context,viewerRevision:old.viewerRevision,expiresAt:Date().addingTimeInterval(30))
        try f.root.profileCurrentReviewSelection.replace(with:fresh)
        let revision=f.root.profileCurrentReviewSelection.revision
        try await Task.sleep(nanoseconds:600_000_000)
        XCTAssertEqual(f.root.profileCurrentReviewSelection.revision,revision)
        XCTAssertTrue(f.root.profileCurrentReviewSelection.approval(for:fresh.context) === fresh)
        XCTAssertNotNil(s.makeProfileCurrentReviewReader(transport:f.review)); XCTAssertNil(f.key(reader,try f.snapshot()))
    }
}
