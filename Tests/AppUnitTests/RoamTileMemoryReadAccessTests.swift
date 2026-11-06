import XCTest
import SwiftUI
@testable import Questify

@MainActor final class RoamTileMemoryReadAccessTests: XCTestCase {
    private let base=URL(string:"https://tiles.example/native")!
    private func root(_ wire: Wire, _ grants: Grants? = nil) throws -> AppCompositionRoot {
        let suite="roam-tile-read-"+UUID().uuidString, vault=Vault()
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite));addTeardownBlock { defaults.removePersistentDomain(forName:suite) }
        let deployment=try ReviewedAppDeployment(market:.china,baseURL:base.absoluteString,
            approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],
            bundleIdentifier:"test.roam.tiles",realm:"synthetic")
        return .init(deployment:.reviewed(deployment),storage:.init(defaults:defaults,tokenStore:{_ in vault}),
            makeTransport:{wire},roamTileMemoryReadAccess:{grants?.select($0)})
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel();await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456")
        XCTAssertNotNil(session.account)
    }
    private func request(_ cursor: Int = 0) -> URLRequest {
        var request=URLRequest(url:URL(string:base.absoluteString+"/api/roam/tiles/page?afterId=\(cursor)&limit=1000")!)
        request.httpMethod="GET";request.setValue("application/json",forHTTPHeaderField:"Accept")
        request.setValue("synthetic-tiles",forHTTPHeaderField:"Authorization");return request
    }
    func testDefaultNilReaderAndPagerStayUnavailableWithoutDispatch() async throws {
        let wire=Wire(),session=try root(wire).makeSession();await login(session);wire.requests=[]
        let reader=session.roamTileMemoryReader,pager=RoamTileMemoryPager(reader:reader)
        XCTAssertNotNil(reader.identity);XCTAssertFalse(reader.isConfigured)
        await pager.loadNext();XCTAssertEqual(pager.error as? APIError,.notConfigured)
        XCTAssertFalse(pager.loaded);XCTAssertTrue(pager.tiles.isEmpty);XCTAssertTrue(wire.requests.isEmpty)
    }
    func testOriginalPagerLoadsTwoPagesDeduplicatesAndRefreshesFromZero() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        let pager=RoamTileMemoryPager(reader:session.roamTileMemoryReader)
        await pager.loadNext();XCTAssertTrue(pager.loaded);XCTAssertTrue(pager.hasMore);XCTAssertEqual(pager.tiles,["wx4g0ec"])
        await pager.loadNext();XCTAssertFalse(pager.hasMore);XCTAssertEqual(pager.tiles,["wx4g0ec","wx4g0ed"])
        await pager.loadNext();XCTAssertEqual(wire.cursors,[0,5])
        pager.reset();await pager.loadNext();XCTAssertEqual(wire.cursors,[0,5,0]);XCTAssertEqual(pager.tiles,["wx4g0ec"])
    }
    func testFailedNextPageRetriesSameCursorWithoutLosingExistingTiles() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session)
        let pager=RoamTileMemoryPager(reader:session.roamTileMemoryReader)
        await pager.loadNext();wire.status=503;await pager.loadNext()
        XCTAssertNotNil(pager.error);XCTAssertEqual(pager.tiles,["wx4g0ec"])
        wire.status=200;await pager.loadNext();XCTAssertNil(pager.error);XCTAssertEqual(wire.cursors,[0,5,5])
        XCTAssertEqual(pager.tiles,["wx4g0ec","wx4g0ed"])
    }
    func testMalformedPageNeverBecomesEmptyOrAdvancesCursor() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session)
        wire.bodyOverride=#"{"code":200,"data":{"nextAfterId":0,"hasMore":false}}"#
        let pager=RoamTileMemoryPager(reader:session.roamTileMemoryReader);await pager.loadNext()
        XCTAssertEqual(pager.error as? APIError,.malformedResponse);XCTAssertFalse(pager.loaded)
        wire.bodyOverride=nil;await pager.loadNext();XCTAssertEqual(wire.cursors,[0,0])
    }
    func testOnlyTileReadIsAvailableAndOldCallersKeepTheirReader() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        let reader=session.roamTileMemoryReader
        XCTAssertThrowsError(try reader.history())
        do {_ = try await reader.album(page:1,pageSize:20);XCTFail()}catch {XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.shopBadge();XCTFail()}catch {XCTAssertEqual(error as? APIError,.notConfigured)}
        XCTAssertTrue(wire.requests.isEmpty)
        let original=RoamExperienceHubView(reader:session.roamExperienceReader)
        XCTAssertNil(original.tileMemoryReader)
        let injected=RoamExperienceHubView(reader:session.roamExperienceReader,tileMemoryReader:reader)
        XCTAssertTrue(injected.tileMemoryReader === reader);XCTAssertTrue(injected.reader === session.roamExperienceReader)
    }
    func testScopeChangesWhenApprovalIsRevokedReplacedOrViewerChanges() async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session)
        let reader=session.roamTileMemoryReader,first=reader.scope
        XCTAssertTrue(reader.isConfigured);grants.retained?.revoke()
        XCTAssertFalse(reader.isConfigured);XCTAssertNotEqual(reader.scope,first)
        grants.retained=nil;XCTAssertTrue(reader.isConfigured);XCTAssertNotEqual(reader.scope,first)
        let before=reader.scope;await session.logout();XCTAssertNotEqual(reader.scope,before);XCTAssertNil(reader.identity)
    }
    func testTransportClonesKeepIndependentApprovalAndRejectWrongRoutesTokenOrQuery() async throws {
        let wire=Wire(),transport=try root(wire,Grants()).transport()
        transport.current={.init(epoch:1,accountID:81,role:"player",token:"synthetic-tiles",viewerRevision:1)}
        let clone=transport.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
        _ = try await clone.send(request())
        for path in ["api/roam/reveal","api/roam/tiles","api/roam/session","api/roam/stamp/list"] {
            var r=request();r.url=base.appendingPathComponent(path)
            do {_ = try await clone.send(r);XCTFail(path)}catch {}
        }
        var r=request();r.setValue("other-token",forHTTPHeaderField:"Authorization")
        do {_ = try await clone.send(r);XCTFail()}catch {}
        r=request();r.url=URL(string:r.url!.absoluteString+"&memberId=81")
        do {_ = try await clone.send(r);XCTFail()}catch {}
        XCTAssertEqual(wire.requests.count,1)
    }
    func testNoApprovalCannotBorrowManualScopeOrDispatch() async throws {
        let wire=Wire(),transport=try root(wire).transport()
        transport.current={.init(epoch:1,accountID:81,role:"player",token:"synthetic-tiles",viewerRevision:1)}
        do {_ = try await transport.scopedForManualMap(ManualMapAreaSelection()).send(request());XCTFail()}catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testChangedIdentityOrIssuanceRejectsBothLatePageAnd401() async throws {
        for change in ["owner","epoch","token","viewer","role","revoke","replace","remove"] {
            for status in [200,401] {
                let wire=Wire(),grants=Grants(),transport=try root(wire,grants).transport()
                var identity=CompositionHTTPTransport.SessionIdentity(epoch:1,accountID:81,role:"player",token:"synthetic-tiles",viewerRevision:1)
                transport.current={identity};wire.hold=true
                let held=expectation(description:"tile read held");wire.onHeld={held.fulfill()}
                let task=Task {try await transport.send(request())};await fulfillment(of:[held],timeout:2)
                let access=try XCTUnwrap(grants.retained)
                switch change {
                case "owner":identity = .init(epoch:2,accountID:82,role:"player",token:"synthetic-tiles",viewerRevision:2)
                case "epoch":identity = .init(epoch:2,accountID:81,role:"player",token:"synthetic-tiles",viewerRevision:1)
                case "token":identity = .init(epoch:1,accountID:81,role:"player",token:"other",viewerRevision:1)
                case "viewer":identity = .init(epoch:1,accountID:81,role:"player",token:"synthetic-tiles",viewerRevision:2)
                case "role":identity = .init(epoch:1,accountID:81,role:"merchant",token:"synthetic-tiles",viewerRevision:1)
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
        let reader=session.roamTileMemoryReader;wire.hold=true
        let held=expectation(description:"old tile account");wire.onHeld={held.fulfill()}
        let task=Task {try await reader.tilePage(afterID:0,limit:1000)};await fulfillment(of:[held],timeout:2)
        await session.logout();wire.hold=false;wire.account=82;grants.retained=nil;await login(session)
        wire.finish(status:401)
        do {_ = try await task.value;XCTFail()}catch {XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(session.account?.id,82)
        wire.status=401
        do {_ = try await reader.tilePage(afterID:0,limit:1000);XCTFail()}catch {}
        XCTAssertNil(session.account)
    }
    @MainActor private final class Grants {
        var enabled=true;var retained:RoamTileMemoryReadAccess?
        func select(_ context:RuntimeDependencyContext)->RoamTileMemoryReadAccess? {
            guard enabled else{return nil}
            if retained==nil,let approval=try? OperationEndpointApproval(baseURL:context.baseURL,
                namespace:context.session.namespace,accountID:context.session.accountID,paths:[RoamTileMemoryReadRoute.path]) {
                retained=try? .init(context:context,approval:approval)
            }
            return retained
        }
    }
    @MainActor private final class Vault:AppTokenStorage {
        var token:String?;func read()throws->String?{token};func write(_ value:String)throws{token=value};func clear()throws{token=nil}
    }
    @MainActor private final class Wire:HTTPTransport {
        var requests:[URLRequest]=[],cursors:[Int]=[]
        var status=200,account=81;var bodyOverride:String?,hold=false,onHeld:(()->Void)?
        var pending:CheckedContinuation<(Data,Int),Error>?
        func finish(status:Int){let value=pending;pending=nil;value?.resume(returning:(Data(#"{"code":200,"data":{"tiles":[],"nextAfterId":0,"hasMore":false}}"#.utf8),status))}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request);let path=request.url!.lastPathComponent
            if path=="phone" {return(try JSONSerialization.data(withJSONObject:["code":200,"token":"synthetic-tiles","data":["id":account,"role":"player"]]),200)}
            if path=="userInfo" {return(try JSONSerialization.data(withJSONObject:["code":200,"appUser":["userId":account,"role":"player"]]),200)}
            guard path=="page" else{return(Data(#"{"code":404}"#.utf8),404)}
            let cursor=Int(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.first(where:{$0.name=="afterId"})!.value!)!
            cursors.append(cursor)
            if hold {return try await withCheckedThrowingContinuation {pending=$0;onHeld?()}}
            if let bodyOverride{return(Data(bodyOverride.utf8),status)}
            let tiles=cursor==0 ? ["wx4g0ec"]:["wx4g0ec","wx4g0ed"]
            return(try JSONSerialization.data(withJSONObject:["code":200,"data":["tiles":tiles,"nextAfterId":cursor==0 ? 5:7,"hasMore":cursor==0]]),status)
        }
    }
}
