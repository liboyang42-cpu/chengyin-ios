import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamPassportServerHistoryHostTests: XCTestCase {
    private let base=URL(string:"https://passport-host.example/native")!
    private func root(_ wire:Wire,_ grants:Grants?=nil)throws->AppCompositionRoot {
        let suite="passport-read-"+UUID().uuidString,vault=Vault()
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite));addTeardownBlock {defaults.removePersistentDomain(forName:suite)}
        let deployment=try ReviewedAppDeployment(market:.china,baseURL:base.absoluteString,approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.passport.history",realm:"synthetic")
        return .init(deployment:.reviewed(deployment),storage:.init(defaults:defaults,tokenStore:{_ in vault}),makeTransport:{wire},roamPassportHistoryReadAccess:{grants?.select($0)})
    }
    private func login(_ session:AppSession)async {session.authChannels.cancel();await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456");XCTAssertNotNil(session.account)}
    func testRealSessionDefaultNilDeniesAllThreeReadsAndKeepsLocalHistoryAvailable()async throws {
        let wire=Wire(),session=try root(wire).makeSession();await login(session);wire.requests=[]
        XCTAssertNotNil(session.roamPassportHistoryReader.identity);XCTAssertFalse(session.roamPassportHistoryReader.isConfigured)
        do {_ = try await session.roamPassportHistoryReader.page(before:nil);XCTFail()}catch {XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await session.roamPassportHistoryReader.record(sessionID:"9");XCTFail()}catch {XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await session.roamPassportHistoryReader.summary();XCTFail()}catch {XCTAssertEqual(error as? APIError,.notConfigured)}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testOriginalCompositionRoutesAllThreeReadsOnlyWithIndependentGrant()async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        let reader=session.roamPassportHistoryReader
        let summary=try await reader.summary(),page=try await reader.page(before:nil),record=try await reader.record(sessionID:"9")
        XCTAssertEqual(summary.trips,20);XCTAssertEqual(page.items.first?.sessionID,"9");XCTAssertEqual(record.sessionID,"9")
        XCTAssertEqual(wire.requests.map {$0.url!.lastPathComponent},["summary","history","record"])
    }
    func testTransportCloneRetainsOnlyExactPassportGrantAndRejectsOtherRoutes()async throws {
        let wire=Wire(),transport=try root(wire,Grants()).transport()
        transport.current={.init(epoch:1,accountID:81,role:"player",token:"synthetic-passport",viewerRevision:1)}
        let clone=transport.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
        let request=try RoamPassportHistoryReadRoute.history(before:nil).request(baseURL:base,token:"synthetic-passport")
        _ = try await clone.send(request)
        for path in ["api/roam/finish","api/roam/session","api/roam/stamp/list","api/exploration-anniversary","api/roam/passport/history?limit=30&owner=81","api/roam/passport/record?sessionId=09"] {
            var r=request;r.url=URL(string:base.absoluteString+"/"+path)
            do {_ = try await clone.send(r);XCTFail(path)}catch {}
        }
        var r=request;r.setValue("other",forHTTPHeaderField:"Authorization")
        do {_ = try await clone.send(r);XCTFail()}catch {}
        r=request;r.httpMethod="POST"
        do {_ = try await clone.send(r);XCTFail()}catch {}
        XCTAssertEqual(wire.requests.count,1)
    }
    func testDefaultNilCannotBorrowManualMapOrPassportToolsGrant()async throws {
        let wire=Wire(),transport=try root(wire).transport()
        transport.current={.init(epoch:1,accountID:81,role:"player",token:"synthetic-passport",viewerRevision:1)}
        transport.roamPassportToolsReadAccess = { context in
            try? .init(context: context, approval: .init(baseURL: context.baseURL, namespace: context.session.namespace,
                accountID: context.session.accountID, paths: Set(RoamPassportToolsService.paths)))
        }
        let request=try RoamPassportHistoryReadRoute.summary.request(baseURL:base,token:"synthetic-passport")
        do {_ = try await transport.scopedForManualMap(ManualMapAreaSelection()).send(request);XCTFail()}catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testLateOldOwner401CannotExpireSuccessorWhileCurrent401Does()async throws {
        let wire=Wire(),grants=Grants(),session=try root(wire,grants).makeSession();await login(session)
        wire.hold=true
        let task=Task {try await session.roamPassportHistoryReader.page(before:nil)}
        for _ in 0..<200 where wire.pending == nil {await Task.yield()}
        _ = try XCTUnwrap(wire.pending);await session.logout();wire.hold=false;wire.account=82;grants.retained=nil;await login(session)
        wire.finish(status:401)
        do {_ = try await task.value;XCTFail()}catch {XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(session.account?.id,82)
        wire.status=401
        do {_ = try await session.roamPassportHistoryReader.page(before:nil);XCTFail()}catch {}
        XCTAssertNil(session.account)
    }
    func testOriginalLocalHistoryEntryOpensServerListSummaryAndExactRecordWithoutWrites()async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        let local=Local(identity:session.roamPassportHistoryReader.identity)
        let host=UIHostingController(rootView:NavigationStack {RoamHistoryView(reader:local)}
            .environment(\.roamPassportHistoryReader,session.roamPassportHistoryReader).environment(\.scenePhase,.active))
        let scene=try HostedNavigationSceneWindow();defer {scene.retire()}
        scene.window.rootViewController=host;scene.window.makeKeyAndVisible();host.loadViewIfNeeded()
        try await eventually {self.find("roam.serverHistory.open",in:scene.window) != nil}
        XCTAssertTrue(wire.requests.isEmpty,"Rendering the original local page grants no remote read")
        try await tap("roam.serverHistory.open",in:scene.window)
        try await eventually {wire.requests.filter {$0.url?.lastPathComponent == "history"}.count == 1}
        XCTAssertTrue(wire.requests.contains {$0.url?.lastPathComponent == "summary"})
        try await tap("roam.serverHistory.record",in:scene.window)
        try await eventually {wire.requests.contains {$0.url?.lastPathComponent == "record"}}
        XCTAssertEqual(wire.requests.last?.url?.query,"sessionId=9")
        XCTAssertTrue(wire.requests.allSatisfy {$0.httpMethod == "GET" && $0.httpBody == nil})
    }
    func testHostedDefaultNilShowsDisabledRemoteEntryWithoutNetwork()async throws {
        let wire=Wire(),session=try root(wire).makeSession();await login(session);wire.requests=[]
        let local=Local(identity:session.roamPassportHistoryReader.identity)
        let host=UIHostingController(rootView:NavigationStack {RoamHistoryView(reader:local)}
            .environment(\.roamPassportHistoryReader,session.roamPassportHistoryReader).environment(\.scenePhase,.active))
        let scene=try HostedNavigationSceneWindow();defer {scene.retire()}
        scene.window.rootViewController=host;scene.window.makeKeyAndVisible();host.loadViewIfNeeded()
        try await eventually {self.find("roam.serverHistory.open",in:scene.window) != nil}
        XCTAssertFalse(session.roamPassportHistoryReader.isConfigured);XCTAssertTrue(wire.requests.isEmpty)
    }
    func testBackgroundDiscardsPresentationAndForegroundRequiresExplicitFreshRead()async throws {
        let wire=Wire(),session=try root(wire,Grants()).makeSession();await login(session);wire.requests=[]
        let phase=PassportHistoryTestPhase()
        let host=UIHostingController(rootView:PassportHistoryTestPhaseHost(reader:session.roamPassportHistoryReader,phase:phase))
        let scene=try HostedNavigationSceneWindow();defer {scene.retire()}
        scene.window.rootViewController=host;scene.window.makeKeyAndVisible();host.loadViewIfNeeded()
        try await eventually {self.find("roam.serverHistory.record",in:scene.window) != nil}
        let before=wire.requests.count;phase.value = .background
        try await eventually {self.find("roam.serverHistory.record",in:scene.window) == nil}
        phase.value = .active
        try await eventually {self.find("roam.serverHistory.refresh",in:scene.window) != nil}
        XCTAssertEqual(wire.requests.count,before)
        try await tap("roam.serverHistory.refresh",in:scene.window)
        try await eventually {wire.requests.count == before+2}
    }
    private func eventually(_ condition:()->Bool)async throws {
        for _ in 0..<100 {if condition(){return};try await Task.sleep(for:.milliseconds(20))}
        XCTAssertTrue(condition())
    }
    private func tap(_ id:String,in window:UIWindow)async throws {
        try await eventually {self.find(id,in:window) != nil}
        let target=try XCTUnwrap(find(id,in:window))
        if let control=target as? UIControl {control.sendActions(for:.touchUpInside)}else{XCTAssertTrue(target.accessibilityActivate())}
    }
    private func find(_ id:String,in window:UIWindow)->NSObject? {
        var seen=Set<ObjectIdentifier>()
        func visit(_ node:NSObject)->NSObject? {
            guard seen.insert(ObjectIdentifier(node)).inserted else{return nil}
            if (node as? UIAccessibilityIdentification)?.accessibilityIdentifier == id{return node}
            if let elements=node.accessibilityElements {for case let child as NSObject in elements {if let found=visit(child){return found}}}
            if let view=node as? UIView {for child in view.subviews {if let found=visit(child){return found}}}
            let count=node.accessibilityElementCount()
            if count > 0 && count < 1000 {for index in 0..<count {if let child=node.accessibilityElement(at:index) as? NSObject,let found=visit(child){return found}}}
            return nil
        }
        return visit(window)
    }
    @MainActor private final class Grants {
        var retained:RoamPassportHistoryReadAccess?
        func select(_ context:RuntimeDependencyContext)->RoamPassportHistoryReadAccess? {
            if retained == nil {retained=try? .init(context:context,approval:.init(baseURL:context.baseURL,namespace:context.session.namespace,accountID:context.session.accountID,paths:RoamPassportHistoryReadRoute.paths))}
            return retained
        }
    }
    @MainActor private final class Vault:AppTokenStorage {
        var token:String?;func read()throws->String?{token};func write(_ value:String)throws{token=value};func clear()throws{token=nil}
    }
    @MainActor private final class Wire:HTTPTransport {
        var requests:[URLRequest]=[],account=81,status=200,hold=false,pending:CheckedContinuation<(Data,Int),Error>?
        private var held=Data()
        func finish(status:Int){let p=pending;pending=nil;p?.resume(returning:(held,status))}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request);let path=request.url!.lastPathComponent
            if path=="phone" {return(try JSONSerialization.data(withJSONObject:["code":200,"token":"synthetic-passport","data":["id":account,"role":"player"]]),200)}
            if path=="userInfo" {return(try JSONSerialization.data(withJSONObject:["code":200,"appUser":["userId":account,"role":"player"]]),200)}
            let row:[String:Any]=["sessionId":"9","distanceM":100,"finishedAt":1700000000000,"track":[[31.2,121.4],[31.3,121.5]]]
            let data:[String:Any]
            switch path {case "summary":data=["trips":20,"distanceM":NSNull(),"days":3,"shops":NSNull()]
            case "history":data=["items":[row],"hasMore":false,"nextBefore":NSNull()]
            case "record":data=row
            default:return(Data(#"{"code":404}"#.utf8),404)}
            let bytes=try JSONSerialization.data(withJSONObject:["code":200,"data":data])
            if hold {held=bytes;return try await withCheckedThrowingContinuation {pending=$0}}
            return(bytes,status)
        }
    }
    @MainActor private final class Local:RoamExperienceReading {
        var identity:RoamExperienceIdentity?,isConfigured=false,isOfflineExample=false
        init(identity:RoamExperienceIdentity?){self.identity=identity}
        func history()throws->[RoamHistoryRecord]{[]}
        func sessionFact(_ query:RoamRecoveryQuery)async throws->RoamSessionFact{throw APIError.notConfigured}
        func tilePage(afterID:Int,limit:Int)async throws->RoamTileMemoryPage{throw APIError.notConfigured}
        func album(page:Int,pageSize:Int)async throws->RoamAlbumPage{throw APIError.notConfigured}
        func shopBadge()async throws->RoamShopBadge?{throw APIError.notConfigured}
    }
}

@MainActor private final class PassportHistoryTestPhase:ObservableObject {@Published var value:ScenePhase = .active}
@MainActor private struct PassportHistoryTestPhaseHost:View {
    let reader:any RoamPassportHistoryReading
    @ObservedObject var phase:PassportHistoryTestPhase
    var body:some View {NavigationStack {RoamPassportHistoryView(reader:reader)}.environment(\.scenePhase,phase.value)}
}
