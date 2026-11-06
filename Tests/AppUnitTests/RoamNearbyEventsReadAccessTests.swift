import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamNearbyEventsReadAccessTests: XCTestCase {
    private let base=URL(string:"https://nearby-events.example/native")!
    private var area:RoamSearchArea { .init(coordinate:RoamCoordinate(latitude:30,longitude:120)!,label:"Selected area") }
    private var otherArea:RoamSearchArea { .init(coordinate:RoamCoordinate(latitude:31,longitude:121)!,label:"Other area") }
    private func root(_ wire:Wire,_ grants:Grants?=nil,manualOnly:Bool=false,playersOnly:Bool=false)throws->AppCompositionRoot {
        let suite="nearby-events-"+UUID().uuidString,vault=Vault()
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite));addTeardownBlock{defaults.removePersistentDomain(forName:suite)}
        let deployment=try ReviewedAppDeployment(market:.china,baseURL:base.absoluteString,
            approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],
            bundleIdentifier:"test.roam.events",realm:"synthetic")
        return .init(deployment:.reviewed(deployment),storage:.init(defaults:defaults,tokenStore:{_ in vault}),makeTransport:{wire},
            roamNearbyEventsReadAccess:{grants?.select($0)},
            roamNearbyPlayersReadAccess:{context in playersOnly ? try? .init(context:context,approval:.init(baseURL:context.baseURL,namespace:context.session.namespace,accountID:context.session.accountID,paths:[RoamNearbyPlayersReadRoute.path])) : nil},
            manualMapReadApproval:{context in manualOnly ? try? .init(context:context,expiresAt:Date().addingTimeInterval(60)) : nil})
    }
    private func login(_ session:AppSession)async {
        session.authChannels.cancel();await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456");XCTAssertNotNil(session.account)
    }
    private func request(_ radius:Int=3000)throws->URLRequest {
        var parts=URLComponents(url:base.appendingPathComponent(RoamNearbyEventsReadRoute.path),resolvingAgainstBaseURL:false)!
        parts.queryItems=[URLQueryItem(name:"lat",value:"30.0"),URLQueryItem(name:"lng",value:"120.0"),URLQueryItem(name:"radius",value:String(radius))]
        var r=URLRequest(url:parts.url!);r.httpMethod="GET";r.setValue("application/json",forHTTPHeaderField:"Accept");r.setValue("synthetic-events",forHTTPHeaderField:"Authorization");return r
    }
    func testDefaultNilManualAndPlayersApprovalCannotDispatchEvents() async throws {
        for (manual,players) in [(false,false),(true,false),(false,true)] {
            let wire=Wire(),session=try root(wire,manualOnly:manual,playersOnly:players).makeSession();await login(session);session.roamArea=area;wire.requests=[]
            let reader=session.roamNearbyEventsReader
            XCTAssertNotNil(reader.identity);XCTAssertFalse(reader.isConfigured)
            do {_ = try await reader.roamEvents(radiusM:3000);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
            XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testRealFactoryReadsExistingServiceWithOnlyManualCenterAndExactFields() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);session.roamArea=area;wire.requests=[]
        let rows=try await session.roamNearbyEventsReader.roamEvents(radiusM:3000)
        XCTAssertEqual(rows.items.map(\.id),["activity-7","topic-7"]);XCTAssertEqual(rows.radius,3000)
        XCTAssertEqual(wire.requests.count,1)
        let request=try XCTUnwrap(wire.requests.first)
        XCTAssertEqual(request.httpMethod,"GET");XCTAssertEqual(request.url?.path,"/native/api/roam/hangout/nearby");XCTAssertNil(request.httpBody)
        XCTAssertNotNil(RoamNearbyEventsReadRoute(request:request,baseURL:base,area:area))
        XCTAssertNil(session.roamNearbyEventsReader.identity?.manualMapApprovalRevision)
        XCTAssertNotNil(session.roamNearbyEventsReader.identity?.nearbyEventsApprovalRevision)
    }
    func testMissingAreaAndOutOfServerRangeNeverDispatch() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        do {_ = try await session.roamNearbyEventsReader.roamEvents(radiusM:3000);XCTFail()}catch{XCTAssertEqual(error as? RoamReadFailure,.searchAreaRequired)}
        session.roamArea=area
        for value in [0,-1,20001,Int.max] {
            do {_ = try await session.roamNearbyEventsReader.roamEvents(radiusM:value);XCTFail()}catch{XCTAssertEqual(error as? APIError,.invalidRequest)}
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testEmptyMalformedFailureAndExplicitRetryRemainDistinct() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);session.roamArea=area
        let reader=session.roamNearbyEventsReader
        wire.rows="[]";let empty=try await reader.roamEvents(radiusM:1000);XCTAssertTrue(empty.items.isEmpty)
        wire.rows="null"
        do {_ = try await reader.roamEvents(radiusM:1000);XCTFail()}catch{XCTAssertEqual(error as? APIError,.malformedResponse)}
        wire.rows="[]";wire.status=503
        do {_ = try await reader.roamEvents(radiusM:1000);XCTFail()}catch{XCTAssertEqual(error as? APIError,.httpStatus(503))}
        wire.status=200;let retried=try await reader.roamEvents(radiusM:1000);XCTAssertTrue(retried.items.isEmpty)
        XCTAssertEqual(wire.radii,[1000,1000,1000,1000])
    }
    func testNoPresenceFinishTilesOrOtherReaderMethodIsAvailable() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);session.roamArea=area;wire.requests=[]
        let reader=session.roamNearbyEventsReader
        do {_ = try await reader.roamPlaces(radiusM:3000);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.roamRouteNodes(radiusM:3000);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.roamPlayers(radiusM:3000);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.roamExploreDay();XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.roamNodeDetail(id:7);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.roamMerchantDetail(id:7);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testAreaChangeAndABARejectBothLateSuccessAnd401WithoutLogout() async throws {
        for aba in [false,true] {for status in [200,401] {
            let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);session.roamArea=area
            let reader=session.roamNearbyEventsReader,before=reader.identity
            wire.hold=true;let held=expectation(description:"old area");wire.onHeld={held.fulfill()}
            let task=Task{try await reader.roamEvents(radiusM:3000)};await fulfillment(of:[held],timeout:2)
            session.roamArea=otherArea;if aba {session.roamArea=area}
            XCTAssertNotEqual(before,reader.identity);wire.finish(status:status)
            do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
            XCTAssertEqual(session.account?.id,81)
        }}
    }
    func testCurrentApprovalReplacementRetiresIdentityAndExistingEventCardScope() async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session);session.roamArea=area
        let reader=session.roamNearbyEventsReader,old=try XCTUnwrap(reader.identity)
        let access=try XCTUnwrap(grants.retained);grants.retained=try .init(context:access.context,approval:access.endpoints)
        XCTAssertNotEqual(reader.identity,old);XCTAssertNil(reader.identity?.manualMapApprovalRevision)
        let before=reader.identity;grants.retained?.revoke();XCTAssertFalse(reader.isConfigured);XCTAssertNotEqual(reader.identity,before)
    }
    func testCompositionRequiresCurrentAreaAndRetainsGrantThroughCopy() async throws {
        let wire=Wire(),transport=try root(wire,Grants()).transport()
        transport.current={.init(epoch:1,accountID:81,role:"player",token:"synthetic-events",viewerRevision:1)}
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
            var identity=CompositionHTTPTransport.SessionIdentity(epoch:1,accountID:81,role:"player",token:"synthetic-events",viewerRevision:1)
            transport.current={identity};let selection=ManualMapAreaSelection();selection.select(area)
            let scoped=transport.scopedForManualMap(selection);wire.hold=true
            let held=expectation(description:"held event read");wire.onHeld={held.fulfill()}
            let task=Task{try await scoped.send(request())};await fulfillment(of:[held],timeout:2)
            let access=try XCTUnwrap(grants.retained)
            switch change {
            case "owner":identity = .init(epoch:2,accountID:82,role:"player",token:"synthetic-events",viewerRevision:2)
            case "epoch":identity = .init(epoch:2,accountID:81,role:"player",token:"synthetic-events",viewerRevision:1)
            case "token":identity = .init(epoch:1,accountID:81,role:"player",token:"other",viewerRevision:1)
            case "viewer":identity = .init(epoch:1,accountID:81,role:"player",token:"synthetic-events",viewerRevision:2)
            case "role":identity = .init(epoch:1,accountID:81,role:"merchant",token:"synthetic-events",viewerRevision:1)
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
        let reader=session.roamNearbyEventsReader;wire.hold=true
        let held=expectation(description:"old owner");wire.onHeld={held.fulfill()}
        let task=Task{try await reader.roamEvents(radiusM:3000)};await fulfillment(of:[held],timeout:2)
        await session.logout();wire.hold=false;wire.account=82;grants.retained=nil;await login(session);session.roamArea=area
        wire.finish(status:401)
        do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(session.account?.id,82);wire.status=401
        do {_ = try await reader.roamEvents(radiusM:3000);XCTFail()}catch{}
        XCTAssertNil(session.account)
    }
    func testExplicitCancellationHasNoLateResultOrLogout() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);session.roamArea=area
        wire.hold=true;let held=expectation(description:"cancel");wire.onHeld={held.fulfill()}
        let task=Task{try await session.roamNearbyEventsReader.roamEvents(radiusM:3000)};await fulfillment(of:[held],timeout:2)
        task.cancel();wire.finish(status:401)
        do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(session.account?.id,81)
    }
    func testNormalBrowserEventCardKeepsTypedCurrentTargetsWithoutNewRead() async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);session.roamArea=area
        let reader=session.roamNearbyEventsReader
        let old=RoamBrowserView(reader:session.roamReader);XCTAssertNil(old.nearbyEventsReader)
        let view=RoamBrowserView(reader:session.roamReader,nearbyEventsReader:reader)
        XCTAssertTrue(view.reader === session.roamReader);XCTAssertTrue(view.nearbyEventsReader === reader)
        let rows=try await reader.roamEvents(radiusM:3000);XCTAssertEqual(rows.items.count,2)
        let scope=try XCTUnwrap(RoamEventNavigationScope(readerID:ObjectIdentifier(reader),identity:reader.identity,area:reader.searchArea,presentationID:UUID(),isConfigured:reader.isConfigured))
        for row in rows.items {
            let target=RoamEventDestination(event:row)
            XCTAssertNotNil(target)
            if row.kind=="activity" {XCTAssertEqual(target,.activity(7))}else{XCTAssertEqual(target,.topic(7))}
        }
        wire.requests=[]
        let host=UIHostingController(rootView:NavigationStack { RoamItemDetailView(item:.event(rows.items[0]),reader:reader,eventDestination:{_ in AnyView(Text("Destination"))}) })
        let window=UIWindow(frame:CGRect(x:0,y:0,width:390,height:844));window.rootViewController=host;window.makeKeyAndVisible()
        host.loadViewIfNeeded();host.view.layoutIfNeeded();for _ in 0..<20 {await Task.yield()}
        XCTAssertTrue(wire.requests.isEmpty);XCTAssertEqual(scope.identity,reader.identity)
        window.isHidden=true;window.rootViewController=nil
    }
    func testCurrentEventTapCannotUseAnOldApprovalOrAreaScope() async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session);session.roamArea=area
        let reader=session.roamNearbyEventsReader,rows=try await reader.roamEvents(radiusM:3000)
        let row=try XCTUnwrap(rows.items.first),presentation=UUID()
        func scope()->RoamEventNavigationScope? { .init(readerID:ObjectIdentifier(reader),identity:reader.identity,area:reader.searchArea,presentationID:presentation,isConfigured:reader.isConfigured) }
        let rendered=try XCTUnwrap(scope()),selected=try XCTUnwrap(RoamEventNavigationSelection(event:row,currentEvent:row,rendered:rendered,current:rendered))
        XCTAssertTrue(selected.mayRemainOpen(in:scope()))
        session.roamArea=otherArea;session.roamArea=area
        XCTAssertFalse(selected.mayRemainOpen(in:scope()))
        XCTAssertNil(RoamEventNavigationSelection(event:row,currentEvent:row,rendered:rendered,current:scope()))
        let fresh=try XCTUnwrap(scope());grants.retained?.revoke()
        XCTAssertNil(scope());XCTAssertNil(RoamEventNavigationSelection(event:row,currentEvent:row,rendered:fresh,current:scope()))
    }
    @MainActor private final class Grants {
        var enabled=true;var retained:RoamNearbyEventsReadAccess?
        func select(_ context:RuntimeDependencyContext)->RoamNearbyEventsReadAccess? {
            guard enabled else{return nil}
            if retained==nil,let approval=try? OperationEndpointApproval(baseURL:context.baseURL,namespace:context.session.namespace,accountID:context.session.accountID,paths:[RoamNearbyEventsReadRoute.path]) {retained=try? .init(context:context,approval:approval)}
            return retained
        }
    }
    @MainActor private final class Vault:AppTokenStorage {
        var token:String?;func read()throws->String?{token};func write(_ value:String)throws{token=value};func clear()throws{token=nil}
    }
    @MainActor private final class Wire:HTTPTransport {
        var requests:[URLRequest]=[],radii:[Int]=[];var status=200,account=81,hold=false,onHeld:(()->Void)?
        var rows=#"[{"id":7,"kind":"activity","name":"Activity","latitude":30.0,"longitude":120.0},{"id":7,"kind":"topic","name":"Topic","latitude":30.0,"longitude":120.0}]"#
        var pending:CheckedContinuation<(Data,Int),Error>?
        func finish(status:Int){let p=pending;pending=nil;p?.resume(returning:(Data(#"{"code":200,"data":{"items":[],"radius":3000}}"#.utf8),status))}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request);let path=request.url!.lastPathComponent
            if path=="phone" {return(try JSONSerialization.data(withJSONObject:["code":200,"token":"synthetic-events","data":["id":account,"role":"player"]]),200)}
            if path=="userInfo" {return(try JSONSerialization.data(withJSONObject:["code":200,"appUser":["userId":account,"role":"player"]]),200)}
            guard path=="nearby" else{return(Data(#"{"code":404}"#.utf8),404)}
            let radius=Int(URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!.first{$0.name=="radius"}!.value!)!
            radii.append(radius)
            if hold {return try await withCheckedThrowingContinuation {pending=$0;onHeld?()}}
            return(Data(("{\"code\":200,\"data\":{\"items\":"+rows+",\"radius\":"+String(radius)+"}}").utf8),status)
        }
    }
}
