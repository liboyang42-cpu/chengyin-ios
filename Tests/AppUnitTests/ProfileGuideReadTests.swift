import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ProfileGuideReadTests:XCTestCase {
    func testSettingsGuideModeRunsOnlyAfterDismissAndOnlyOnce() {
        var owner = SettingsGuideHandoff(), calls = 0
        XCTAssertTrue(owner.begin()); let id = owner.presentation
        XCTAssertTrue(owner.request(id) { calls += 1 })
        XCTAssertEqual(calls, 0)
        XCTAssertFalse(owner.request(id) { calls += 10 })
        XCTAssertFalse(owner.begin())
        owner.finish(id)?()
        XCTAssertEqual(calls, 1)
        XCTAssertNil(owner.finish(id))
        XCTAssertTrue(owner.begin())
    }
    func testOldSettingsCallbacksCannotRouteOrConsumeNewPresentation() {
        var owner = SettingsGuideHandoff(), calls = 0
        XCTAssertTrue(owner.begin()); let old = owner.presentation
        XCTAssertNil(owner.finish(old))
        XCTAssertTrue(owner.begin()); let next = owner.presentation
        XCTAssertFalse(owner.request(old) { calls += 10 })
        XCTAssertTrue(owner.request(next) { calls += 1 })
        XCTAssertNil(owner.finish(old))
        owner.finish(next)?()
        XCTAssertEqual(calls, 1)
    }
    func testSettingsGuideConstructionKeepsExistingIndependentGrantClosed() async throws {
        let h = try Harness(enabled: false); await h.login(); h.wire.requests = []
        let guide = ProfileGuideHost(reader: h.session.makeProfileGuideReader(),
            makeArticleReader: { h.session.makeProfileGuideArticleReader($0) }, templateReader: h.session)
        _ = guide
        XCTAssertTrue(h.wire.requests.isEmpty)
        let reader = try h.reader()
        XCTAssertFalse(reader.isConfigured)
    }

    func testSignedOutAndDefaultNilNeverDispatchGuideRequests()async throws {
        let h=try Harness(enabled:false);XCTAssertNil(h.session.makeProfileGuideReader());await h.login()
        let reader=try h.reader();h.wire.requests=[];XCTAssertFalse(reader.isConfigured)
        do {_ = try await reader.informationList();XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        XCTAssertTrue(h.wire.requests.isEmpty)
        h.grants.enabled=true;let rows=try await reader.informationList();XCTAssertEqual(rows.map(\.id),[21])
        XCTAssertEqual(h.wire.paths,["infomation_list"])
    }
    func testNormalOriginalListToExplicitArticleOnlyUsesTwoOriginalRequests()async throws {
        let h=try Harness();await h.login();let reader=try h.reader();h.wire.requests=[]
        let rows=try await reader.informationList(),row=try XCTUnwrap(rows.first),selection=try XCTUnwrap(reader.select(row))
        let article=h.session.makeProfileGuideArticleReader(selection);article.appear(foreground:true)
        let result=try await article.information(id:21);XCTAssertEqual(result.title,"Guide");XCTAssertEqual(result.contents,"<h1>Guide</h1><p>Read safely</p>")
        XCTAssertEqual(h.wire.paths,["infomation_list","infomation_detail"])
        let list=try XCTUnwrap(h.wire.requests.first);XCTAssertNil(list.httpBody);XCTAssertEqual(list.httpMethod,"POST")
        XCTAssertEqual(ProfileGuideReadRoute(request:try XCTUnwrap(h.wire.requests.last),baseURL:h.base),.detail(21))
        do {_ = try await reader.information(id:21);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await article.information(id:22);XCTFail()}catch{XCTAssertEqual(error as? APIError,.invalidRequest)}
        do {_ = try await article.informationList();XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        XCTAssertEqual(h.wire.requests.count,2)
    }
    func testOnlyExactAcceptedRowCanCreateArticleAndRefreshRetiresOldSourceEvenSameID()async throws {
        let h=try Harness();await h.login();let reader=try h.reader()
        let fabricated=try JSONDecoder().decode(SocialInformation.self,from:Data(#"{"id":21,"title":"Fabricated","contents":"Not read"}"#.utf8))
        XCTAssertNil(reader.select(fabricated))
        let a=try await firstRow(reader),selected=try XCTUnwrap(reader.select(a))
        h.wire.title="Changed guide";let b=try await firstRow(reader)
        XCTAssertEqual(a.id,b.id);XCTAssertNotEqual(a,b);XCTAssertNil(reader.select(a));XCTAssertFalse(selected.isCurrent)
        XCTAssertNotNil(reader.select(b));XCTAssertNil(reader.select(fabricated))
    }
    func testListCoverKeepsArticleReceiptAndHiddenForegroundCannotRead()async throws {
        let h=try Harness();await h.login();let reader=try h.reader()
        let row=try await firstRow(reader),selected=try XCTUnwrap(reader.select(row))
        let article=h.session.makeProfileGuideArticleReader(selected);reader.disappear();reader.setForeground(false);reader.setForeground(true)
        XCTAssertFalse(reader.isVisible);XCTAssertTrue(selected.isCurrent);XCTAssertNil(reader.select(row))
        h.wire.requests=[];do {_ = try await reader.informationList();XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
        reader.refresh();XCTAssertTrue(h.wire.requests.isEmpty);article.appear(foreground:true)
        let value=try await article.information(id:21);XCTAssertEqual(value.id,21)
        article.disappear();XCTAssertFalse(selected.isCurrent);reader.appear(foreground:true)
        let fresh=try await firstRow(reader);XCTAssertNotNil(reader.select(fresh))
    }
    func testOldArticleCloseCannotRetireNewSelection()async throws {
        let h=try Harness();await h.login();let list=try h.reader(),row=try await firstRow(list)
        let first=try XCTUnwrap(list.select(row)),a=h.session.makeProfileGuideArticleReader(first);a.appear(foreground:true);a.disappear()
        let second=try XCTUnwrap(list.select(row)),b=h.session.makeProfileGuideArticleReader(second);b.appear(foreground:true)
        a.disappear();a.setForeground(true);XCTAssertTrue(second.isCurrent);XCTAssertFalse(first.isCurrent)
        let result=try await b.information(id:21);XCTAssertEqual(result.id,21)
    }
    func testEmptyErrorRemovedAndExplicitRetryAreDistinct()async throws {
        let h=try Harness();await h.login();let list=try h.reader()
        h.wire.empty=true;let empty=try await list.informationList();XCTAssertTrue(empty.isEmpty)
        h.wire.empty=false;let row=try await firstRow(list),selection=try XCTUnwrap(list.select(row))
        let article=h.session.makeProfileGuideArticleReader(selection);article.appear(foreground:true)
        for payload in ["null","{}"] {h.wire.detail=payload;let missing=try await article.information(id:21);XCTAssertTrue(missing.isRemoved)}
        h.wire.status=503;do {_ = try await article.information(id:21);XCTFail()}catch{XCTAssertEqual(error as? APIError,.httpStatus(503))}
        h.wire.status=200;h.wire.detail=nil;let recovered=try await article.information(id:21);XCTAssertEqual(recovered.id,21)
    }
    func testApprovalReplacementRevocationAndAccountChangeRejectLateArticleResponses()async throws {
        for kind in ["replace","revoke","account"] {for status in [200,401] {
            let h=try Harness();await h.login();let list=try h.reader(),row=try await firstRow(list)
            let selection=try XCTUnwrap(list.select(row)),article=h.session.makeProfileGuideArticleReader(selection);article.appear(foreground:true)
            h.wire.hold=true;let held=expectation(description:kind);h.wire.onHeld={held.fulfill()}
            let task=Task{try await article.information(id:21)};await fulfillment(of:[held],timeout:2)
            if kind=="replace" {h.grants.access=nil}else if kind=="revoke" {h.grants.access?.revoke()}else{
                await h.session.logout();h.wire.account=82;h.grants.access=nil;h.wire.hold=false;await h.login()
            }
            h.wire.finish(status:status)
            do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
            XCTAssertEqual(h.session.account?.id,kind=="account" ? 82:81)
        }}
    }
    func testHiddenListAndBackgroundArticleRetireHeldResultsWithoutExpiringCurrentOwner()async throws {
        for articleRead in [false,true] {
            let h=try Harness();await h.login();let list=try h.reader(),row=try await firstRow(list)
            let article=h.session.makeProfileGuideArticleReader(try XCTUnwrap(list.select(row)));article.appear(foreground:true)
            h.wire.hold=true;let held=expectation(description:"hidden");h.wire.onHeld={held.fulfill()}
            let task=Task{if articleRead {_ = try await article.information(id:21)}else{_ = try await list.informationList()}}
            await fulfillment(of:[held],timeout:2)
            if articleRead{article.setForeground(false)}else{list.disappear()}
            h.wire.finish(status:401)
            do{try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
            XCTAssertEqual(h.session.account?.id,81)
        }
    }
    func testCurrent401ExpiresAndTaskCancellationDoesNot()async throws {
        let h=try Harness();await h.login();let list=try h.reader()
        h.wire.hold=true;let held=expectation(description:"cancel");h.wire.onHeld={held.fulfill()}
        let task=Task{try await list.informationList()};await fulfillment(of:[held],timeout:2);task.cancel();h.wire.finish(status:401)
        do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(h.session.account?.id,81);h.wire.status=401
        do {_ = try await list.informationList();XCTFail()}catch{}
        XCTAssertNil(h.session.account)
    }
    func testTransportSelectedIDAndPurposeCannotFallbackOrBorrowOtherRoutes()async throws {
        let h=try Harness();await h.login();let list=try h.reader(),row=try await firstRow(list),selected=try XCTUnwrap(list.select(row))
        let transport=h.root.transport();transport.current={h.identity(list)};let scoped=transport.scopedForProfileGuide(selected);h.wire.requests=[]
        do{_ = try await transport.send(h.request(id:21));XCTFail()}catch{}
        for request in [try h.request(id:22),try h.request(),try AuthRequestBuilder.makeFormRequest(url:h.base.appendingPathComponent("api/common/upload"),fields:["id":"21"],token:"synthetic-guide")] {
            do{_ = try await scoped.send(request);XCTFail()}catch{}
        }
        XCTAssertTrue(h.wire.requests.isEmpty)
        _ = try await scoped.replacingUnderlying(h.wire).scopedForManualMap(ManualMapAreaSelection()).send(h.request(id:21))
        XCTAssertEqual(h.wire.paths,["infomation_detail"])
    }
    func testTransportEpochViewerTokenAndRoleChangesRejectLateResponses()async throws {
        for kind in ["epoch","viewer","token","role"] {
            let h=try Harness();await h.login();let list=try h.reader();let transport=h.root.transport()
            var identity=h.identity(list);transport.current={identity}
            h.wire.hold=true;let held=expectation(description:kind);h.wire.onHeld={held.fulfill()}
            let task=Task{try await transport.send(h.request())};await fulfillment(of:[held],timeout:2)
            identity = .init(epoch:identity.epoch+(kind=="epoch" ? 1:0),accountID:81,role:kind=="role" ? "merchant":"player",token:kind=="token" ? "other":"synthetic-guide",viewerRevision:identity.viewerRevision+(kind=="viewer" ? 1:0))
            h.wire.finish(status:401);do{_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
        }
    }
    func testOrdinaryGuideHostKeepsStaticModesAndDefaultNilDoesNoRead()async throws {
        let h=try Harness(enabled:false);await h.login();let reader=try h.reader();h.wire.requests=[]
        let view=ProfileGuideHost(reader:reader,makeArticleReader:{h.session.makeProfileGuideArticleReader($0)})
        let host=UIHostingController(rootView:NavigationStack{view}.environment(\.scenePhase,.active))
        let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=host;window.makeKeyAndVisible()
        defer{window.isHidden=true;window.rootViewController=nil};host.loadViewIfNeeded();host.view.layoutIfNeeded()
        for _ in 0..<30{await Task.yield()}
        XCTAssertTrue(reader.hasAppeared);XCTAssertFalse(reader.isConfigured);XCTAssertTrue(h.wire.requests.isEmpty)
        XCTAssertEqual(SocialGuideMode.allCases.count,3)
    }
    func testOrdinaryConfiguredGuideLoadsOriginalListAndRefreshesWithoutWrites()async throws {
        let h=try Harness();await h.login();let reader=try h.reader();h.wire.requests=[]
        let view=ProfileGuideHost(reader:reader,makeArticleReader:{h.session.makeProfileGuideArticleReader($0)})
        let host=UIHostingController(rootView:AnyView(NavigationStack{view}.environment(\.scenePhase,.active)))
        let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=host;window.makeKeyAndVisible()
        defer{window.isHidden=true;window.rootViewController=nil};host.loadViewIfNeeded();host.view.layoutIfNeeded()
        for _ in 0..<100 where h.wire.requests.isEmpty{try await Task.sleep(for:.milliseconds(20))}
        XCTAssertEqual(h.wire.paths,["infomation_list"]);reader.refresh()
        for _ in 0..<100 where h.wire.requests.count<2{try await Task.sleep(for:.milliseconds(20))}
        XCTAssertEqual(h.wire.paths,["infomation_list","infomation_list"])
        host.rootView=AnyView(Text("Left guide"));host.view.layoutIfNeeded()
        for _ in 0..<100 where reader.isVisible{try await Task.sleep(for:.milliseconds(20))}
        XCTAssertFalse(reader.isVisible);let count=h.wire.requests.count
        reader.setForeground(false);reader.setForeground(true);reader.refresh()
        XCTAssertEqual(h.wire.requests.count,count)
    }
    func testActualArticleDestinationReadsOriginalViewAndRetiresOnRealRemoval()async throws {
        let h=try Harness();await h.login();let list=try h.reader(),row=try await firstRow(list)
        var article:ProfileGuideArticleReader?
        let view=ProfileGuideArticleDestination(row:row,reader:list,makeReader:{let value=h.session.makeProfileGuideArticleReader($0);article=value;return value})
        h.wire.requests=[]
        let host=UIHostingController(rootView:AnyView(NavigationStack{view}.environment(\.scenePhase,.active)))
        let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=host;window.makeKeyAndVisible()
        defer{window.isHidden=true;window.rootViewController=nil};host.loadViewIfNeeded();host.view.layoutIfNeeded()
        for _ in 0..<100 where !h.wire.paths.contains("infomation_detail"){try await Task.sleep(for:.milliseconds(20))}
        XCTAssertEqual(h.wire.paths,["infomation_detail"]);let captured=try XCTUnwrap(article)
        XCTAssertTrue(captured.selection.isCurrent);host.rootView=AnyView(Text("Returned to guide"));host.view.layoutIfNeeded()
        for _ in 0..<100 where captured.selection.isCurrent{try await Task.sleep(for:.milliseconds(20))}
        XCTAssertFalse(captured.selection.isCurrent);XCTAssertTrue(list.isConfigured)
    }
    private func firstRow(_ reader:ProfileGuideListReader)async throws->SocialInformation {
        let rows=try await reader.informationList();return try XCTUnwrap(rows.first)
    }
    @MainActor private final class Harness {
        let base=URL(string:"https://guide.example/native")!
        let wire:Wire,grants:Grants,root:AppCompositionRoot,session:AppSession
        init(enabled:Bool=true)throws{
            let wire=Wire(),grants=Grants(),vault=Vault();grants.enabled=enabled;self.wire=wire;self.grants=grants
            let deployment=try ReviewedAppDeployment(market:.china,baseURL:base.absoluteString,approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.guide",realm:"synthetic")
            root = .init(deployment:.reviewed(deployment),storage:.init(defaults:UserDefaults(suiteName:"guide-"+UUID().uuidString)!,tokenStore:{_ in vault}),makeTransport:{wire},profileGuideReadAccess:{grants.select($0)});session=root.makeSession()
        }
        func login()async{session.authChannels.cancel();await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456")}
        func reader()throws->ProfileGuideListReader{let reader=try XCTUnwrap(session.makeProfileGuideReader());reader.appear(foreground:true);return reader}
        func identity(_ reader:ProfileGuideListReader)->CompositionHTTPTransport.SessionIdentity{.init(epoch:reader.context.session.epoch,accountID:reader.context.session.accountID,role:reader.context.role,token:reader.context.session.token,viewerRevision:reader.viewerRevision)}
        func request(id:Int?=nil)throws->URLRequest{try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent(id==nil ? ProfileGuideReadRoute.listPath:ProfileGuideReadRoute.detailPath),fields:id.map{["id":String($0)]} ?? [:],token:"synthetic-guide",includesBody:id != nil)}
    }
    @MainActor private final class Grants {
        var enabled=true,access:ProfileGuideReadAccess?
        func select(_ c:RuntimeDependencyContext)->ProfileGuideReadAccess?{guard enabled else{return nil};if access==nil{access=try? .init(context:c,approval:.init(baseURL:c.baseURL,namespace:c.session.namespace,accountID:c.session.accountID,paths:ProfileGuideReadRoute.paths))};return access}
    }
    @MainActor private final class Vault:AppTokenStorage{
        var token:String?;func read()throws->String?{token};func write(_ value:String)throws{token=value};func clear()throws{token=nil}
    }
    @MainActor private final class Wire:HTTPTransport {
        var requests:[URLRequest]=[];var paths:[String]{requests.compactMap{$0.url?.lastPathComponent}}
        var account=81,status=200,empty=false,hold=false,title="Guide",detail:String?,onHeld:(()->Void)?
        var pending:CheckedContinuation<(Data,Int),Error>?
        func finish(status:Int){hold=false;let p=pending;pending=nil;p?.resume(returning:(Data(#"{"code":200,"data":null}"#.utf8),status))}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request);let path=request.url!.lastPathComponent
            if path=="phone"{return(try JSONSerialization.data(withJSONObject:["code":200,"token":"synthetic-guide","data":["id":account,"role":"player"]]),200)}
            if path=="userInfo"{return(try JSONSerialization.data(withJSONObject:["code":200,"appUser":["userId":account,"role":"player"]]),200)}
            guard ["infomation_list","infomation_detail"].contains(path) else{return(Data(#"{"code":404}"#.utf8),404)}
            if hold{return try await withCheckedThrowingContinuation{pending=$0;onHeld?()}}
            let row:[String:Any]=["id":21,"title":title,"subtitle":"Instructions","contents":"<h1>Guide</h1><p>Read safely</p>"]
            if path=="infomation_detail",let detail{return(Data(("{\"code\":200,\"data\":"+detail+"}").utf8),status)}
            return(try JSONSerialization.data(withJSONObject:["code":200,"data":path=="infomation_list" ? (empty ? []:[row]) as Any:row]),status)
        }
    }
}
