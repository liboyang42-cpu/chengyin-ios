import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamAlbumMetadataReadAccessTests: XCTestCase {
    private let base=URL(string:"https://album.example/native")!
    private func root(_ wire: Wire, _ grants: Grants? = nil) throws -> AppCompositionRoot {
        let suite="roam-album-read-"+UUID().uuidString, vault=Vault()
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite));addTeardownBlock { defaults.removePersistentDomain(forName:suite) }
        let deployment=try ReviewedAppDeployment(market:.china,baseURL:base.absoluteString,
            approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],
            bundleIdentifier:"test.roam.album",realm:"synthetic")
        return .init(deployment:.reviewed(deployment),storage:.init(defaults:defaults,tokenStore:{_ in vault}),
            makeTransport:{wire},roamAlbumMetadataReadAccess:{grants?.select($0)})
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel();await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456")
        XCTAssertNotNil(session.account)
    }
    private func request(_ page:Int=1) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent(RoamAlbumMetadataReadRoute.path),
            fields:["pageNum":String(page),"pageSize":"20"],token:"synthetic-album",boundary:"synthetic")
    }
    func testDefaultNilReaderAndPagerStayUnavailableWithoutDispatch() async throws {
        let wire=Wire(),session=try root(wire).makeSession();await login(session);wire.requests=[]
        let reader=session.roamAlbumMetadataReader,pager=RoamAlbumPager(reader:reader)
        XCTAssertNotNil(reader.identity);XCTAssertFalse(reader.isConfigured)
        await pager.loadNext();XCTAssertEqual(pager.error as? APIError,.notConfigured)
        XCTAssertFalse(pager.loaded);XCTAssertTrue(pager.stamps.isEmpty);XCTAssertTrue(wire.requests.isEmpty)
    }
    func testOriginalPagerLoadsTwoPagesAndRefreshesFromPageOne() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        let pager=RoamAlbumPager(reader:session.roamAlbumMetadataReader)
        await pager.loadNext();XCTAssertTrue(pager.loaded);XCTAssertTrue(pager.hasMore);XCTAssertEqual(pager.stamps.map(\.id),[1])
        await pager.loadNext();XCTAssertFalse(pager.hasMore);XCTAssertEqual(pager.stamps.map(\.id),[1,2])
        await pager.loadNext();XCTAssertEqual(wire.pages,[1,2])
        pager.reset();await pager.loadNext();XCTAssertEqual(wire.pages,[1,2,1]);XCTAssertEqual(pager.stamps.map(\.id),[1])
    }
    func testFailedNextPageRetriesSameCursorWithoutLosingExistingStamps() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session)
        let pager=RoamAlbumPager(reader:session.roamAlbumMetadataReader)
        await pager.loadNext();wire.status=503;await pager.loadNext()
        XCTAssertNotNil(pager.error);XCTAssertEqual(pager.stamps.map(\.id),[1])
        wire.status=200;await pager.loadNext();XCTAssertNil(pager.error);XCTAssertEqual(wire.pages,[1,2,2])
        XCTAssertEqual(pager.stamps.map(\.id),[1,2])
    }
    func testMalformedPageNeverBecomesEmptyOrAdvancesCursor() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session)
        wire.bodyOverride=#"{"code":200,"data":{"total":2,"pageNum":1,"pageSize":20}}"#
        let pager=RoamAlbumPager(reader:session.roamAlbumMetadataReader);await pager.loadNext()
        XCTAssertEqual(pager.error as? APIError,.malformedResponse);XCTAssertFalse(pager.loaded)
        wire.bodyOverride=nil;await pager.loadNext();XCTAssertEqual(wire.pages,[1,1])
    }
    func testOnlyAlbumMetadataReadIsAvailableAndOldCallersKeepTheirReader() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        let reader=session.roamAlbumMetadataReader
        XCTAssertThrowsError(try reader.history())
        do {_ = try await reader.tilePage(afterID:0,limit:1000);XCTFail()}catch {XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.shopBadge();XCTFail()}catch {XCTAssertEqual(error as? APIError,.notConfigured)}
        XCTAssertTrue(wire.requests.isEmpty)
        let original=RoamExperienceHubView(reader:session.roamExperienceReader)
        XCTAssertNil(original.albumMetadataReader)
        let injected=RoamExperienceHubView(reader:session.roamExperienceReader,albumMetadataReader:reader)
        XCTAssertTrue(injected.albumMetadataReader === reader);XCTAssertTrue(injected.reader === session.roamExperienceReader)
    }
    func testScopeChangesWhenApprovalIsRevokedReplacedOrViewerChanges() async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session)
        let reader=session.roamAlbumMetadataReader,first=reader.scope
        XCTAssertTrue(reader.isConfigured);grants.retained?.revoke()
        XCTAssertFalse(reader.isConfigured);XCTAssertNotEqual(reader.scope,first)
        grants.retained=nil;XCTAssertTrue(reader.isConfigured);XCTAssertNotEqual(reader.scope,first)
        let before=reader.scope;await session.logout();XCTAssertNotEqual(reader.scope,before);XCTAssertNil(reader.identity)
    }
    func testTransportClonesKeepIndependentApprovalAndRejectWrongRoutesTokenOrQuery() async throws {
        let wire=Wire(),transport=try root(wire,Grants()).transport()
        transport.current={.init(epoch:1,accountID:81,role:"player",token:"synthetic-album",viewerRevision:1)}
        let clone=transport.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
        _ = try await clone.send(try request())
        for path in ["api/roam/reveal","api/roam/stamp/create","api/roam/stamp/received","api/roam/stamp/exchange"] {
            var r=try request();r.url=base.appendingPathComponent(path)
            do {_ = try await clone.send(r);XCTFail(path)}catch {}
        }
        var r=try request();r.setValue("other-token",forHTTPHeaderField:"Authorization")
        do {_ = try await clone.send(r);XCTFail()}catch {}
        r=try request();r.url=URL(string:r.url!.absoluteString+"?memberId=81")
        do {_ = try await clone.send(r);XCTFail()}catch {}
        XCTAssertEqual(wire.requests.count,1)
    }
    func testNoApprovalCannotBorrowManualScopeOrDispatch() async throws {
        let wire=Wire(),transport=try root(wire).transport()
        transport.current={.init(epoch:1,accountID:81,role:"player",token:"synthetic-album",viewerRevision:1)}
        do {_ = try await transport.scopedForManualMap(ManualMapAreaSelection()).send(try request());XCTFail()}catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testChangedIdentityOrIssuanceRejectsBothLatePageAnd401() async throws {
        for change in ["owner","epoch","token","viewer","role","revoke","replace","remove"] {
            for status in [200,401] {
                let wire=Wire(),grants=Grants(),transport=try root(wire,grants).transport()
                var identity=CompositionHTTPTransport.SessionIdentity(epoch:1,accountID:81,role:"player",token:"synthetic-album",viewerRevision:1)
                transport.current={identity};wire.hold=true
                let held=expectation(description:"album read held");wire.onHeld={held.fulfill()}
                let task=Task {try await transport.send(try request())};await fulfillment(of:[held],timeout:2)
                let access=try XCTUnwrap(grants.retained)
                switch change {
                case "owner":identity = .init(epoch:2,accountID:82,role:"player",token:"synthetic-album",viewerRevision:2)
                case "epoch":identity = .init(epoch:2,accountID:81,role:"player",token:"synthetic-album",viewerRevision:1)
                case "token":identity = .init(epoch:1,accountID:81,role:"player",token:"other",viewerRevision:1)
                case "viewer":identity = .init(epoch:1,accountID:81,role:"player",token:"synthetic-album",viewerRevision:2)
                case "role":identity = .init(epoch:1,accountID:81,role:"merchant",token:"synthetic-album",viewerRevision:1)
                case "revoke":access.revoke()
                case "replace":grants.retained=try .init(context:access.context,approval:access.endpoints)
                default:grants.enabled=false
                }
                wire.finish(status:status)
                do {_ = try await task.value;XCTFail(change)}catch {XCTAssertTrue(error is CancellationError)}
            }
        }
    }
    func testLate401CannotExpireSuccessorButCurrent401DoesExpire() async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session)
        let reader=session.roamAlbumMetadataReader;wire.hold=true
        let held=expectation(description:"old album account");wire.onHeld={held.fulfill()}
        let task=Task {try await reader.album(page:1,pageSize:20)};await fulfillment(of:[held],timeout:2)
        await session.logout();wire.hold=false;wire.account=82;grants.retained=nil;await login(session)
        wire.finish(status:401)
        do {_ = try await task.value;XCTFail()}catch {XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(session.account?.id,82)
        wire.status=401
        do {_ = try await reader.album(page:1,pageSize:20);XCTFail()}catch {}
        XCTAssertNil(session.account)
    }
    func testTypedAlbumAndDetailNeverConstructCaptureOrPermitRemoteImages() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session)
        let reader=session.roamAlbumMetadataReader,identity=try XCTUnwrap(reader.identity)
        let scope=RoamStampAlbumReadOnlyScope(reader:reader,identity:identity,isCurrent:{true})
        let page=try await reader.album(page:1,pageSize:20),stamp=try XCTUnwrap(page.list.first)
        var captures=0
        let view=RoamStampAlbumView(reader:reader,stampDestination:{captures += 1;return AnyView(Text("No capture"))},readOnlyScope:scope)
        XCTAssertFalse(view.allowsCapture);XCTAssertFalse(view.allowsRemoteImages);XCTAssertFalse(scope.allowsRemoteImages)
        let capture=UIHostingController(rootView:view.captureDestination);capture.loadViewIfNeeded();capture.view.layoutIfNeeded()
        XCTAssertEqual(captures,0)
        XCTAssertFalse(RoamStampAlbumView(reader:reader).allowsCapture)
        XCTAssertFalse(RoamStampAlbumView(reader:reader).allowsRemoteImages)
        let detail=RoamStampDetailView(stamp:stamp,offline:false,readOnlyScope:scope,allowsRemoteImages:false)
        let host=UIHostingController(rootView:detail);wire.requests=[];host.loadViewIfNeeded();host.view.layoutIfNeeded()
        XCTAssertTrue(detail.canShowStamp);XCTAssertTrue(wire.requests.isEmpty)
        let legacy=RoamStampAlbumView(reader:session.roamExperienceReader)
        XCTAssertTrue(legacy.allowsCapture);XCTAssertTrue(legacy.allowsRemoteImages)
    }
    func testFrozenReadOnlyScopeExpiresOnApprovalReplacementAndDoesNotClearFreshScope() async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session)
        let reader=session.roamAlbumMetadataReader,identity=try XCTUnwrap(reader.identity)
        let old=RoamStampAlbumReadOnlyScope(reader:reader,identity:identity,isCurrent:{true})
        XCTAssertTrue(old.isCurrent);let access=try XCTUnwrap(grants.retained)
        grants.retained=try .init(context:access.context,approval:access.endpoints)
        XCTAssertFalse(old.isCurrent)
        let fresh=RoamStampAlbumReadOnlyScope(reader:reader,identity:identity,isCurrent:{true})
        let oldNative=RoamAlbumMetadataLifetime.Controller(scope:old)
        RoamAlbumMetadataLifetime.dismantleUIViewController(oldNative,coordinator:())
        XCTAssertTrue(fresh.isCurrent);XCTAssertNotEqual(old.id,fresh.id)
        wire.requests=[];do {_ = try await old.album(page:1,pageSize:20);XCTFail()}catch{}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testRetirementAndAccountChangeRejectHeldMetadataAndRemoveDetail() async throws {
        for changeAccount in [false,true] {
            let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session)
            let reader=session.roamAlbumMetadataReader,identity=try XCTUnwrap(reader.identity)
            let scope=RoamStampAlbumReadOnlyScope(reader:reader,identity:identity,isCurrent:{true})
            wire.hold=true;let held=expectation(description:"album presentation");wire.onHeld={held.fulfill()}
            let task=Task {try await scope.album(page:1,pageSize:20)};await fulfillment(of:[held],timeout:2)
            if changeAccount {await session.logout()}else{scope.retire()}
            wire.finish(status:200);do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
            XCTAssertFalse(scope.isCurrent)
        }
    }
    func testNormalWholePageHostWithNoApprovalDoesNotDispatch() async throws {
        let wire=Wire(),session=try root(wire).makeSession();await login(session);wire.requests=[]
        let host=UIHostingController(rootView:NavigationStack {RoamAlbumMetadataDestination(reader:session.roamAlbumMetadataReader)}.environment(\.scenePhase,.active))
        let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=host;window.makeKeyAndVisible()
        defer {window.isHidden=true;window.rootViewController=nil}
        host.loadViewIfNeeded();host.view.layoutIfNeeded();for _ in 0..<30 {await Task.yield()}
        XCTAssertFalse(session.roamAlbumMetadataReader.isConfigured);XCTAssertTrue(wire.requests.isEmpty)
    }
    func testNormalNavigationChildCoverKeepsScopeButRootRemovalRetiresIt() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session)
        let reader=session.roamAlbumMetadataReader,identity=try XCTUnwrap(reader.identity)
        let scope=RoamStampAlbumReadOnlyScope(reader:reader,identity:identity,isCurrent:{true}),probe=AlbumProbe()
        let host=UIHostingController(rootView:AnyView(AlbumNavigationHost(reader:reader,scope:scope,probe:probe)))
        let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=host;window.makeKeyAndVisible()
        defer {window.isHidden=true;window.rootViewController=nil}
        host.loadViewIfNeeded();host.view.layoutIfNeeded()
        for _ in 0..<100 where probe.appearances==0 {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertGreaterThan(probe.appearances,0);XCTAssertTrue(scope.isCurrent)
        probe.covered=true
        for _ in 0..<100 where probe.childAppearances==0 {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertGreaterThan(probe.childAppearances,0);XCTAssertGreaterThan(probe.disappearances,0);XCTAssertTrue(scope.isCurrent)
        probe.covered=false
        for _ in 0..<100 where probe.appearances<2 {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertGreaterThanOrEqual(probe.appearances,2);XCTAssertTrue(scope.isCurrent)
        host.rootView=AnyView(Text("Root left"));host.view.layoutIfNeeded()
        for _ in 0..<100 where scope.isCurrent {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertFalse(scope.isCurrent)
    }
    @MainActor private final class AlbumProbe:ObservableObject {
        @Published var covered=false
        var appearances=0,disappearances=0,childAppearances=0
    }
    @MainActor private struct AlbumNavigationHost:View {
        let reader:RoamAlbumMetadataReader
        let scope:RoamStampAlbumReadOnlyScope
        @ObservedObject var probe:AlbumProbe
        var body:some View {
            NavigationStack {
                RoamAlbumMetadataDestination(reader:reader,scope:scope)
                    .onAppear{probe.appearances += 1}.onDisappear{probe.disappearances += 1}
                    .navigationDestination(isPresented:$probe.covered) {
                        Text("Stamp metadata").onAppear{probe.childAppearances += 1}
                    }
            }.environment(\.scenePhase,.active)
        }
    }
    private func walk(_ reader:RoamAlbumMetadataReader) async throws -> (RoamLiveSessionController,AlbumWalkService,AlbumWalkLocation,AlbumWalkStorage) {
        let date=Date(timeIntervalSince1970:1_790_932_200),identity=try XCTUnwrap(reader.identity)
        let service=AlbumWalkService(identity:identity),location=try AlbumWalkLocation(date:date),storage=AlbumWalkStorage()
        let owner=RoamLiveSessionController(service:service,location:location,journal:.init(storage:storage),now:{date})
        owner.prepare();await owner.start(purposeAccepted:true);XCTAssertEqual(owner.phase,.active)
        return(owner,service,location,storage)
    }
    func testNormalPausedAlbumUsesDedicatedReaderAndReturnsWithoutNewLiveWork() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session)
        let reader=session.roamAlbumMetadataReader
        let (owner,service,location,storage)=try await walk(reader)
        let view=RoamLiveSessionView(controller:owner,localHistoryReader:session.roamExperienceReader,albumMetadataReader:reader)
        XCTAssertTrue(view.albumMetadataReader === reader);XCTAssertTrue(view.localHistoryReader === session.roamExperienceReader)
        let presentation=RoamPausedBrowsePresentation();presentation.appear()
        let context=try XCTUnwrap(RoamPausedBrowseContext.capture(kind:.album,owner:owner,reader:reader))
        let calls=service.calls,fixes=location.calls,bytes=storage.bytes
        presentation.open(context,entryID:presentation.entryID,owner:owner,reader:reader)
        let target=try XCTUnwrap(presentation.target),scope=try XCTUnwrap(target.albumScope)
        XCTAssertEqual(owner.phase,.paused);XCTAssertNil(target.historyReader);XCTAssertFalse(scope.allowsRemoteImages)
        _ = try await scope.album(page:1,pageSize:20)
        presentation.parentDisappeared(departing:false,coveredByPresentation:true)
        XCTAssertTrue(scope.isCurrent);presentation.close(id:target.id)
        XCTAssertFalse(scope.isCurrent);XCTAssertEqual(owner.phase,.paused)
        XCTAssertEqual(service.calls,calls);XCTAssertEqual(location.calls,fixes);XCTAssertEqual(storage.bytes,bytes)
        XCTAssertThrowsError(try scope.history())
    }
    func testPausedAlbumApprovalReissueInvalidatesOldContextAndDismissal() async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session)
        let reader=session.roamAlbumMetadataReader
        let (owner,_,_,_)=try await walk(reader)
        let presentation=RoamPausedBrowsePresentation();presentation.appear()
        let context=try XCTUnwrap(RoamPausedBrowseContext.capture(kind:.album,owner:owner,reader:reader))
        presentation.open(context,entryID:presentation.entryID,owner:owner,reader:reader)
        let old=try XCTUnwrap(presentation.target),oldBinding=presentation.binding(for:old,owner:owner,reader:reader)
        let access=try XCTUnwrap(grants.retained);grants.retained=try .init(context:access.context,approval:access.endpoints)
        XCTAssertNil(oldBinding.wrappedValue);presentation.retireIfStale(owner:owner,reader:reader);XCTAssertNil(presentation.target)
        presentation.appear();let nextContext=try XCTUnwrap(RoamPausedBrowseContext.capture(kind:.album,owner:owner,reader:reader))
        XCTAssertNotEqual(context,nextContext);presentation.open(nextContext,entryID:presentation.entryID,owner:owner,reader:reader)
        let next=try XCTUnwrap(presentation.target);oldBinding.wrappedValue=nil
        XCTAssertEqual(presentation.target?.id,next.id);XCTAssertFalse(old.albumScope!.isCurrent)
        presentation.parentDisappeared(departing:true,coveredByPresentation:true)
        XCTAssertNil(presentation.target);XCTAssertFalse(next.albumScope!.isCurrent);XCTAssertEqual(owner.phase,.paused)
    }
    @MainActor private final class Grants {
        var enabled=true;var retained:RoamAlbumMetadataReadAccess?
        func select(_ context:RuntimeDependencyContext)->RoamAlbumMetadataReadAccess? {
            guard enabled else{return nil}
            if retained==nil,let approval=try? OperationEndpointApproval(baseURL:context.baseURL,
                namespace:context.session.namespace,accountID:context.session.accountID,paths:[RoamAlbumMetadataReadRoute.path]) {
                retained=try? .init(context:context,approval:approval)
            }
            return retained
        }
    }
    @MainActor private final class Vault:AppTokenStorage {
        var token:String?;func read()throws->String?{token};func write(_ value:String)throws{token=value};func clear()throws{token=nil}
    }
    @MainActor private final class Wire:HTTPTransport {
        var requests:[URLRequest]=[],pages:[Int]=[]
        var status=200,account=81;var bodyOverride:String?,hold=false,onHeld:(()->Void)?
        var pending:CheckedContinuation<(Data,Int),Error>?
        func finish(status:Int){let value=pending;pending=nil;value?.resume(returning:(Data(#"{"code":200,"data":{"list":[],"total":0,"pageNum":1,"pageSize":20}}"#.utf8),status))}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request);let path=request.url!.lastPathComponent
            if path=="phone" {return(try JSONSerialization.data(withJSONObject:["code":200,"token":"synthetic-album","data":["id":account,"role":"player"]]),200)}
            if path=="userInfo" {return(try JSONSerialization.data(withJSONObject:["code":200,"appUser":["userId":account,"role":"player"]]),200)}
            guard path=="list" else{return(Data(#"{"code":404}"#.utf8),404)}
            let body=String(data:request.httpBody!,encoding:.utf8)!
            let page=Int(body.components(separatedBy:"name=\"pageNum\"\r\n\r\n")[1].components(separatedBy:"\r\n")[0])!
            let size=Int(body.components(separatedBy:"name=\"pageSize\"\r\n\r\n")[1].components(separatedBy:"\r\n")[0])!
            pages.append(page)
            if hold {return try await withCheckedThrowingContinuation {pending=$0;onHeld?()}}
            if let bodyOverride{return(Data(bodyOverride.utf8),status)}
            let row:[String:Any] = ["id":page,"picUrl":"https://unapproved.invalid/private.jpg","caption":"Saved caption","checkState":1]
            return(try JSONSerialization.data(withJSONObject:["code":200,"data":["list":[row],"total":21,"pageNum":page,"pageSize":size]]),status)
        }
    }
}

@MainActor private final class AlbumWalkStorage: RoamHistoryDataStoring {
    var bytes: [String: Data] = [:]
    var writes = 0
    func read(key: String) throws -> Data? { bytes[key] }
    func write(_ data: Data, key: String) throws { writes += 1; bytes[key] = data }
}
@MainActor private final class AlbumWalkLocation: RoamDeviceLocationProviding {
    let value: RoamDeviceFix
    var calls = 0
    init(date: Date) throws {
        value = try RoamDeviceFix(coordinate: XCTUnwrap(RoamCoordinate(latitude: 31.2, longitude: 121.4)),
                                  accuracyMeters: 10, measuredAt: date, datum: .gcj02)
    }
    func currentFix() async throws -> RoamDeviceFix { calls += 1; return value }
    func stop() {}
}
@MainActor private final class AlbumWalkService: RoamLiveServing {
    let captured: RoamExperienceIdentity
    var identity: RoamExperienceIdentity?
    var enabled = true
    var isAvailable: Bool { enabled && identity == captured }
    var presenceAvailable: Bool { false }
    var calls = 0
    init(identity: RoamExperienceIdentity) { captured = identity; self.identity = identity }
    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }
    func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt {
        calls += 1
        return try decode(RoamLiveRevealReceipt.self, #"{"sessionId":12,"newlyRevealed":0}"#)
    }
    func fact(key: String) async throws -> RoamSessionFact {
        calls += 1
        return try decode(RoamSessionFact.self, "{\"state\":\"ACTIVE\",\"sessionId\":12,\"clientSessionKey\":\"\(key)\"}")
    }
    func places(fix: RoamDeviceFix) async throws -> [RoamPlace] { calls += 1; return [] }
    func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode] { calls += 1; return [] }
    func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt {
        calls += 1; throw APIError.notConfigured
    }
    func shopVisit(sessionID: Int, sourceType: Int, sourceID: Int, fix: RoamDeviceFix) async throws -> RoamLiveShopReceipt {
        calls += 1; throw APIError.notConfigured
    }
    func presence(sessionID: Int, fix: RoamDeviceFix, explorationPercent: Int) async throws {
        calls += 1; throw APIError.notConfigured
    }
    func finish(sessionID: Int, poiIDs: [Int], distanceMeters: Int) async throws {
        calls += 1; throw APIError.notConfigured
    }
}
