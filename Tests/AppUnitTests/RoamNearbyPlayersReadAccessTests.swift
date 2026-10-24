import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamNearbyPlayersReadAccessTests: XCTestCase {
    private let base=URL(string:"https://nearby-players.example/native")!
    private var area:RoamSearchArea { .init(coordinate:RoamCoordinate(latitude:30,longitude:120)!,label:"Selected area") }
    private var otherArea:RoamSearchArea { .init(coordinate:RoamCoordinate(latitude:31,longitude:121)!,label:"Other area") }
    private func root(_ wire:Wire,_ grants:Grants?=nil,manualOnly:Bool=false)throws->AppCompositionRoot {
        let suite="nearby-players-"+UUID().uuidString,vault=Vault()
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite));addTeardownBlock{defaults.removePersistentDomain(forName:suite)}
        let deployment=try ReviewedAppDeployment(market:.china,baseURL:base.absoluteString,
            approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],
            bundleIdentifier:"test.roam.players",realm:"synthetic")
        return .init(deployment:.reviewed(deployment),storage:.init(defaults:defaults,tokenStore:{_ in vault}),makeTransport:{wire},
            roamNearbyPlayersReadAccess:{grants?.select($0)},
            manualMapReadApproval:{context in manualOnly ? try? .init(context:context,expiresAt:Date().addingTimeInterval(60)) : nil})
    }
    private func login(_ session:AppSession)async {
        session.authChannels.cancel();await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456");XCTAssertNotNil(session.account)
    }
    private func request(_ radius:Int=3000)throws->URLRequest {
        try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent(RoamNearbyPlayersReadRoute.path),
            fields:["lat":"30.0","lng":"120.0","radius":String(radius)],token:"synthetic-players",boundary:"synthetic")
    }
    func testDefaultNilAndManualApprovalCannotDispatchPlayerRead() async throws {
        for manual in [false,true] {
            let wire=Wire(),session=try root(wire,manualOnly:manual).makeSession();await login(session);session.roamArea=area;wire.requests=[]
            let reader=session.roamNearbyPlayersReader
            XCTAssertNotNil(reader.identity);XCTAssertFalse(reader.isConfigured)
            do {_ = try await reader.roamPlayers(radiusM:3000);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
            XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testRealFactoryReadsExistingServiceWithOnlyManualCenterAndExactFields() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);session.roamArea=area;wire.requests=[]
        let rows=try await session.roamNearbyPlayersReader.roamPlayers(radiusM:3000)
        XCTAssertEqual(rows.map(\.id),[7]);XCTAssertEqual(rows.first?.approximateCoordinate?.latitude,30.123)
        XCTAssertEqual(wire.requests.count,1)
        let request=try XCTUnwrap(wire.requests.first)
        XCTAssertEqual(request.httpMethod,"POST");XCTAssertEqual(request.url?.lastPathComponent,"nearby-runners")
        XCTAssertNotNil(RoamNearbyPlayersReadRoute(request:request,baseURL:base,area:area))
        XCTAssertNil(session.roamNearbyPlayersReader.identity?.manualMapApprovalRevision)
        XCTAssertNotNil(session.roamNearbyPlayersReader.identity?.nearbyPlayersApprovalRevision)
    }
    func testMissingAreaAndOutOfServerRangeNeverDispatch() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        do {_ = try await session.roamNearbyPlayersReader.roamPlayers(radiusM:3000);XCTFail()}catch{XCTAssertEqual(error as? RoamReadFailure,.searchAreaRequired)}
        session.roamArea=area
        for value in [0,-1,3001,20000] {
            do {_ = try await session.roamNearbyPlayersReader.roamPlayers(radiusM:value);XCTFail()}catch{XCTAssertEqual(error as? APIError,.invalidRequest)}
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testEmptyMalformedFailureAndExplicitRetryRemainDistinct() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);session.roamArea=area
        let reader=session.roamNearbyPlayersReader
        wire.rows="[]";let empty=try await reader.roamPlayers(radiusM:1000);XCTAssertTrue(empty.isEmpty)
        wire.rows="null"
        do {_ = try await reader.roamPlayers(radiusM:1000);XCTFail()}catch{XCTAssertEqual(error as? APIError,.malformedResponse)}
        wire.rows="[]";wire.status=503
        do {_ = try await reader.roamPlayers(radiusM:1000);XCTFail()}catch{XCTAssertEqual(error as? APIError,.httpStatus(503))}
        wire.status=200;let retried=try await reader.roamPlayers(radiusM:1000);XCTAssertTrue(retried.isEmpty)
        XCTAssertEqual(wire.radii,[1000,1000,1000,1000])
    }
    func testNoPresenceFinishTilesOrOtherReaderMethodIsAvailable() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);session.roamArea=area;wire.requests=[]
        let reader=session.roamNearbyPlayersReader
        do {_ = try await reader.roamPlaces(radiusM:3000);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.roamRouteNodes(radiusM:3000);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.roamEvents(radiusM:3000);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.roamExploreDay();XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.roamNodeDetail(id:7);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.roamMerchantDetail(id:7);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testAreaChangeAndABARejectBothLateSuccessAnd401WithoutLogout() async throws {
        for aba in [false,true] {for status in [200,401] {
            let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);session.roamArea=area
            let reader=session.roamNearbyPlayersReader,before=reader.identity
            wire.hold=true;let held=expectation(description:"old area");wire.onHeld={held.fulfill()}
            let task=Task{try await reader.roamPlayers(radiusM:3000)};await fulfillment(of:[held],timeout:2)
            session.roamArea=otherArea;if aba {session.roamArea=area}
            XCTAssertNotEqual(before,reader.identity);wire.finish(status:status)
            do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
            XCTAssertEqual(session.account?.id,81)
        }}
    }
    func testCurrentApprovalReplacementRetiresIdentityAndExistingPlayerCardScope() async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session);session.roamArea=area
        let reader=session.roamNearbyPlayersReader,old=try XCTUnwrap(reader.identity)
        let access=try XCTUnwrap(grants.retained);grants.retained=try .init(context:access.context,approval:access.endpoints)
        XCTAssertNotEqual(reader.identity,old);XCTAssertNil(reader.identity?.manualMapApprovalRevision)
        let before=reader.identity;grants.retained?.revoke();XCTAssertFalse(reader.isConfigured);XCTAssertNotEqual(reader.identity,before)
    }
    func testCompositionRequiresCurrentAreaAndRetainsGrantThroughCopy() async throws {
        let wire=Wire(),transport=try root(wire,Grants()).transport()
        transport.current={.init(epoch:1,accountID:81,role:"player",token:"synthetic-players",viewerRevision:1)}
        do {_ = try await transport.send(request());XCTFail()}catch{}
        XCTAssertTrue(wire.requests.isEmpty)
        let selected=ManualMapAreaSelection();selected.select(area)
        let scoped=transport.scopedForManualMap(selected).replacingUnderlying(wire)
        _ = try await scoped.send(request())
        for path in ["api/roam/presence","api/roam/reveal","api/roam/finish","api/map/nearby"] {
            var r=try request();r.url=base.appendingPathComponent(path)
            do {_ = try await scoped.send(r);XCTFail(path)}catch{}
        }
        XCTAssertEqual(wire.requests.count,1)
    }
    func testTransportOwnerEpochTokenViewerRoleAndApprovalLateResponsesAreRetired() async throws {
        for change in ["owner","epoch","token","viewer","role","revoke","replace","remove"] {for status in [200,401] {
            let wire=Wire(),grants=Grants(),transport=try root(wire,grants).transport()
            var identity=CompositionHTTPTransport.SessionIdentity(epoch:1,accountID:81,role:"player",token:"synthetic-players",viewerRevision:1)
            transport.current={identity};let selection=ManualMapAreaSelection();selection.select(area)
            let scoped=transport.scopedForManualMap(selection);wire.hold=true
            let held=expectation(description:"held player read");wire.onHeld={held.fulfill()}
            let task=Task{try await scoped.send(request())};await fulfillment(of:[held],timeout:2)
            let access=try XCTUnwrap(grants.retained)
            switch change {
            case "owner":identity = .init(epoch:2,accountID:82,role:"player",token:"synthetic-players",viewerRevision:2)
            case "epoch":identity = .init(epoch:2,accountID:81,role:"player",token:"synthetic-players",viewerRevision:1)
            case "token":identity = .init(epoch:1,accountID:81,role:"player",token:"other",viewerRevision:1)
            case "viewer":identity = .init(epoch:1,accountID:81,role:"player",token:"synthetic-players",viewerRevision:2)
            case "role":identity = .init(epoch:1,accountID:81,role:"merchant",token:"synthetic-players",viewerRevision:1)
            case "revoke":access.revoke()
            case "replace":grants.retained=try .init(context:access.context,approval:access.endpoints)
            default:grants.enabled=false
            }
            wire.finish(status:status)
            do {_ = try await task.value;XCTFail(change)}catch{XCTAssertTrue(error is CancellationError)}
        }}
    }
    func testAccountSwitchRetiresOld401AndCurrent401ExpiresOnlyCurrentOwner() async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session);session.roamArea=area
        let reader=session.roamNearbyPlayersReader;wire.hold=true
        let held=expectation(description:"old owner");wire.onHeld={held.fulfill()}
        let task=Task{try await reader.roamPlayers(radiusM:3000)};await fulfillment(of:[held],timeout:2)
        await session.logout();wire.hold=false;wire.account=82;grants.retained=nil;await login(session);session.roamArea=area
        wire.finish(status:401)
        do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(session.account?.id,82);wire.status=401
        do {_ = try await reader.roamPlayers(radiusM:3000);XCTFail()}catch{}
        XCTAssertNil(session.account)
    }
    func testExplicitCancellationHasNoLateResultOrLogout() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);session.roamArea=area
        wire.hold=true;let held=expectation(description:"cancel");wire.onHeld={held.fulfill()}
        let task=Task{try await session.roamNearbyPlayersReader.roamPlayers(radiusM:3000)};await fulfillment(of:[held],timeout:2)
        task.cancel();wire.finish(status:401)
        do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(session.account?.id,81)
    }
    func testNormalBrowserAndPlayerCardKeepOriginalOtherLayerReader() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);session.roamArea=area
        let reader=session.roamNearbyPlayersReader
        let old=RoamBrowserView(reader:session.roamReader);XCTAssertNil(old.nearbyPlayersReader)
        let view=RoamBrowserView(reader:session.roamReader,nearbyPlayersReader:reader)
        XCTAssertTrue(view.reader === session.roamReader);XCTAssertTrue(view.nearbyPlayersReader === reader)
        let rows=try await reader.roamPlayers(radiusM:3000);let row=try XCTUnwrap(rows.first);wire.requests=[]
        let host=UIHostingController(rootView:NavigationStack { RoamItemDetailView(item:.player(row),reader:reader) })
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:844));window.rootViewController=host;window.makeKeyAndVisible()
        host.loadViewIfNeeded();host.view.layoutIfNeeded();for _ in 0..<20 {await Task.yield()}
        XCTAssertTrue(wire.requests.isEmpty);window.isHidden=true;window.rootViewController=nil
    }
    @MainActor private final class Grants {
        var enabled=true;var retained:RoamNearbyPlayersReadAccess?
        func select(_ context:RuntimeDependencyContext)->RoamNearbyPlayersReadAccess? {
            guard enabled else{return nil}
            if retained==nil,let approval=try? OperationEndpointApproval(baseURL:context.baseURL,namespace:context.session.namespace,accountID:context.session.accountID,paths:[RoamNearbyPlayersReadRoute.path]) {retained=try? .init(context:context,approval:approval)}
            return retained
        }
    }
    @MainActor private final class Vault:AppTokenStorage {
        var token:String?;func read()throws->String?{token};func write(_ value:String)throws{token=value};func clear()throws{token=nil}
    }
    @MainActor private final class Wire:HTTPTransport {
        var requests:[URLRequest]=[],radii:[Int]=[];var status=200,account=81,hold=false,onHeld:(()->Void)?
        var rows=#"[{"memberId":7,"nickname":"Runner","lat":30.123456,"lng":120.456789,"explorePct":7,"shops":2,"elapsedSec":20}]"#
        var pending:CheckedContinuation<(Data,Int),Error>?
        func finish(status:Int){let p=pending;pending=nil;p?.resume(returning:(Data(#"{"code":200,"data":[]}"#.utf8),status))}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request);let path=request.url!.lastPathComponent
            if path=="phone" {return(try JSONSerialization.data(withJSONObject:["code":200,"token":"synthetic-players","data":["id":account,"role":"player"]]),200)}
            if path=="userInfo" {return(try JSONSerialization.data(withJSONObject:["code":200,"appUser":["userId":account,"role":"player"]]),200)}
            guard path=="nearby-runners" else{return(Data(#"{"code":404}"#.utf8),404)}
            let body=String(data:request.httpBody!,encoding:.utf8)!
            radii.append(Int(body.components(separatedBy:"name=\"radius\"\r\n\r\n")[1].components(separatedBy:"\r\n")[0])!)
            if hold {return try await withCheckedThrowingContinuation {pending=$0;onHeld?()}}
            return(Data(("{\"code\":200,\"data\":"+rows+"}").utf8),status)
        }
    }
}
