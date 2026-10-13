import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ProfilePublicInfoReadTests: XCTestCase {
    func testSignedOutAndInvalidTargetsCannotCreateNormalReader() throws {
        let h=try Harness();XCTAssertNil(h.session.makeProfilePublicInfoReader(memberID:81))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testDefaultNilNormalReaderIsHonestUnavailableAndZeroDispatch() async throws {
        let h=try Harness(enabled:false);await h.login();let reader=try h.reader()
        h.wire.requests=[];XCTAssertFalse(reader.isConfigured)
        do {_ = try await reader.publicProfile(memberID:81);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        XCTAssertTrue(h.wire.requests.isEmpty)
        XCTAssertNil(h.session.makeProfilePublicInfoReader(memberID:0))
        h.grants.enabled=true;XCTAssertTrue(reader.isConfigured)
        let value=try await reader.publicProfile(memberID:81);XCTAssertEqual(value.id,81)
        XCTAssertEqual(h.wire.paths,["public-info"])
    }
    func testOriginalServicePublicTargetCanDifferFromCurrentViewerWithoutPrivateReads() async throws {
        let h=try Harness();await h.login();h.wire.target=82;let reader=try h.reader(member:82)
        h.wire.requests=[];let value=try await reader.publicProfile(memberID:82)
        XCTAssertEqual(value.id,82);XCTAssertEqual(value.nickname,"Public member");XCTAssertEqual(value.introduction,"Public introduction")
        XCTAssertEqual(value.interests.map(\.name),["Walking"]);XCTAssertEqual(reader.identity.accountID,81)
        XCTAssertEqual(h.wire.paths,["public-info"])
        XCTAssertEqual(ProfilePublicInfoReadRoute(request:try XCTUnwrap(h.wire.requests.first),baseURL:h.base)?.memberID,82)
        do {_ = try await reader.publicProfile(memberID:81);XCTFail()}catch{XCTAssertEqual(error as? APIError,.invalidRequest)}
        do {_ = try await reader.informationList();XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.information(id:1);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.invitationHistory(page:1);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        XCTAssertEqual(h.wire.paths,["public-info"])
    }
    func testDeniedMissingAndMalformedResponsesStayErrorsThenExplicitRetrySucceeds() async throws {
        let h=try Harness();await h.login();let reader=try h.reader()
        for status in [403,404,503] {h.wire.status=status;do {_ = try await reader.publicProfile(memberID:81);XCTFail()}catch{XCTAssertEqual(error as? APIError,.httpStatus(status))}}
        h.wire.status=200
        for body in [#"{"code":200}"#,#"{"code":200,"data":{"id":82}}"#,#"{"code":200,"data":{"id":"81"}}"#] {
            h.wire.override=body;do {_ = try await reader.publicProfile(memberID:81);XCTFail()}catch{XCTAssertEqual(error as? APIError,.malformedResponse)}
        }
        h.wire.override=nil;let recovered=try await reader.publicProfile(memberID:81);XCTAssertEqual(recovered.id,81)
    }
    func testCurrent401ExpiresButLate401NeverExpiresSuccessorAccount() async throws {
        let h=try Harness();await h.login();let reader=try h.reader()
        let held=expectation(description:"old profile");h.wire.hold=true;h.wire.onHeld={held.fulfill()}
        let task=Task{try await reader.publicProfile(memberID:81)};await fulfillment(of:[held],timeout:2)
        await h.session.logout();h.wire.account=82;h.wire.target=82;h.grants.access=nil;h.wire.hold=false;await h.login()
        h.wire.finish(status:401)
        do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(h.session.account?.id,82);XCTAssertFalse(reader.isCurrent)
        let fresh=try h.reader(member:82);h.wire.status=401
        do {_ = try await fresh.publicProfile(memberID:82);XCTFail()}catch{}
        XCTAssertNil(h.session.account)
    }
    func testApprovalRevokeReplacementAndTargetRetirementRejectLateReplies() async throws {
        for kind in ["revoke","replace","target"] {for status in [200,401] {
            let h=try Harness();await h.login();let reader=try h.reader()
            let held=expectation(description:kind);h.wire.hold=true;h.wire.onHeld={held.fulfill()}
            let task=Task{try await reader.publicProfile(memberID:81)};await fulfillment(of:[held],timeout:2)
            switch kind {case "revoke":h.grants.access?.revoke();case "replace":h.grants.access=nil;default:reader.target.retire()}
            h.wire.finish(status:status)
            do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
            XCTAssertEqual(h.session.account?.id,81)
        }}
    }
    func testHiddenForegroundDoesNotMountOrDispatchAndActualReturnReloads() async throws {
        let h=try Harness();await h.login();let reader=try h.reader()
        let revision=reader.presentationRevision;reader.disappear();reader.setForeground(false);reader.setForeground(true)
        XCTAssertEqual(reader.presentationRevision,revision);XCTAssertTrue(reader.isConfigured);XCTAssertFalse(reader.isVisible)
        h.wire.requests=[];do {_ = try await reader.publicProfile(memberID:81);XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
        reader.requestRefresh();XCTAssertEqual(reader.presentationRevision,revision);XCTAssertTrue(h.wire.requests.isEmpty)
        reader.appear(foreground:true);XCTAssertGreaterThan(reader.presentationRevision,revision)
        let value=try await reader.publicProfile(memberID:81);XCTAssertEqual(value.id,81)
    }
    func testCoveredExistingEditorKeepsExactContextUntilActualAccountRetires() async throws {
        let h=try Harness();await h.login();let reader=try h.reader()
        let data=ProfileSelfEditFixtureData(),coordinator=ProfileEditCoordinator(service:data,currentSession:{data.editSession})
        let access=ProfileSelfEditAccess(coordinator:coordinator,sessionRevision:1),navigation=ProfileSelfEditNavigation()
        let context=try XCTUnwrap(access.context(memberID:81,reader:reader,isCurrent:reader.isCurrent))
        let ticket=try XCTUnwrap(navigation.open(context));reader.disappear();reader.setForeground(false);reader.setForeground(true)
        let covered=access.context(memberID:81,reader:reader,isCurrent:reader.isCurrent)
        XCTAssertEqual(covered,context);XCTAssertTrue(navigation.isCurrent(ticket,context:covered));XCTAssertEqual(data.writes,0)
        XCTAssertTrue(navigation.finish(ticket.id,context:covered));reader.appear(foreground:true)
        let next=access.context(memberID:81,reader:reader,isCurrent:reader.isCurrent)
        XCTAssertNotEqual(next,context);XCTAssertFalse(navigation.isCurrent(ticket,context:next))
        await h.session.logout();XCTAssertNil(access.context(memberID:81,reader:reader,isCurrent:reader.isCurrent));XCTAssertEqual(data.writes,0)
    }
    func testHideBackgroundRefreshAndCancelledTaskRejectOldReply() async throws {
        for kind in ["hide","background","refresh","cancel"] {for status in [200,401] {
            let h=try Harness();await h.login();let reader=try h.reader()
            let held=expectation(description:kind);h.wire.hold=true;h.wire.onHeld={held.fulfill()}
            let task=Task{try await reader.publicProfile(memberID:81)};await fulfillment(of:[held],timeout:2)
            switch kind {case "hide":reader.disappear();case "background":reader.setForeground(false);case "refresh":reader.requestRefresh();default:task.cancel()}
            h.wire.finish(status:status)
            do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
            XCTAssertEqual(h.session.account?.id,81)
        }}
    }
    func testExactTransportRequiresTargetProofAndCannotFallbackToPrivateOrOtherRead() async throws {
        let h=try Harness();await h.login();let reader=try h.reader(), transport=h.transport(reader)
        h.wire.requests=[]
        let unscoped=h.root.transport();unscoped.current={h.identity(reader)}
        do {_ = try await unscoped.send(h.request());XCTFail()}catch{}
        for (path,fields) in [("api/user/public-info",["member_id":"82"]),("api/user/public-info",["member_id":"81","viewer_id":"81"]),("api/user/info",[:]),("api/userInfo",[:]),("api/user/action",["nickname":"X"]),("api/topic/list",["pageNum":"1"])] {
            do {_ = try await transport.send(h.request(path:path,fields:fields));XCTFail()}catch{}
        }
        XCTAssertTrue(h.wire.requests.isEmpty)
        _ = try await transport.replacingUnderlying(h.wire).scopedForManualMap(ManualMapAreaSelection()).send(h.request())
        XCTAssertEqual(h.wire.paths,["public-info"])
    }
    func testTransportFullSessionIdentityAndViewerRevisionFenceLateSuccessAnd401() async throws {
        for kind in ["account","epoch","viewer","role","token"] {for status in [200,401] {
            let h=try Harness();await h.login();let reader=try h.reader(), transport=h.transport(reader)
            var identity=h.identity(reader);transport.current={identity}
            let held=expectation(description:kind);h.wire.hold=true;h.wire.onHeld={held.fulfill()}
            let task=Task{try await transport.send(h.request())};await fulfillment(of:[held],timeout:2)
            identity = .init(epoch:identity.epoch+(kind=="epoch" ? 1:0),accountID:kind=="account" ? 82:81,
                role:kind=="role" ? "merchant":"player",token:kind=="token" ? "other":"synthetic-public",
                viewerRevision:identity.viewerRevision+(kind=="viewer" ? 1:0))
            h.wire.finish(status:status)
            do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
        }}
    }
    func testNormalHostDefaultNilShowsUnavailableWithoutDispatch() async throws {
        let h=try Harness(enabled:false);await h.login();let reader=try h.reader(),probe=Probe()
        h.wire.requests=[]
        let host=UIHostingController(rootView:NormalHost(reader:reader,session:h.session,probe:probe).environment(\.scenePhase,.active))
        let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=host;window.makeKeyAndVisible()
        defer{window.isHidden=true;window.rootViewController=nil}
        host.loadViewIfNeeded();host.view.layoutIfNeeded()
        for _ in 0..<100 where probe.appearances==0 {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertGreaterThan(probe.appearances,0);XCTAssertTrue(reader.hasAppeared);XCTAssertFalse(reader.isConfigured)
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testNormalFullProfileRefreshCoverReturnAndLeavingOwnOneReader() async throws {
        let h=try Harness();await h.login();let reader=try h.reader(),probe=Probe()
        h.wire.requests=[]
        let host=UIHostingController(rootView:AnyView(NormalHost(reader:reader,session:h.session,probe:probe).environment(\.scenePhase,.active)))
        let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=host;window.makeKeyAndVisible()
        defer{window.isHidden=true;window.rootViewController=nil}
        host.loadViewIfNeeded();host.view.layoutIfNeeded()
        for _ in 0..<100 where !h.wire.paths.contains("public-info") {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertTrue(h.wire.paths.contains("public-info"));XCTAssertTrue(reader.isVisible)
        let count=h.wire.paths.filter{$0=="public-info"}.count
        reader.requestRefresh()
        for _ in 0..<100 where h.wire.paths.filter({$0=="public-info"}).count==count {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertGreaterThan(h.wire.paths.filter{$0=="public-info"}.count,count)
        let revision=reader.presentationRevision;probe.covered=true
        for _ in 0..<100 where probe.childAppearances==0 {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertGreaterThan(probe.childAppearances,0);XCTAssertFalse(reader.isVisible)
        XCTAssertEqual(reader.presentationRevision,revision);XCTAssertTrue(reader.isConfigured);XCTAssertTrue(reader.isCurrent)
        probe.covered=false
        for _ in 0..<100 where !reader.isVisible {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertTrue(reader.isVisible);XCTAssertGreaterThan(reader.presentationRevision,revision)
        host.rootView=AnyView(Text("Left profile"));host.view.layoutIfNeeded()
        for _ in 0..<100 where reader.isVisible {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertFalse(reader.isVisible)
        XCTAssertTrue(h.wire.paths.allSatisfy{$0=="public-info"})
    }
    @MainActor private final class Probe:ObservableObject {
        @Published var covered=false
        var appearances=0,childAppearances=0
    }
    @MainActor private struct NormalHost:View {
        let reader:ProfilePublicInfoReader
        let session:AppSession
        @ObservedObject var probe:Probe
        var body:some View {
            NavigationStack {
                ProfilePublicInfoHost(reader:reader) { value in
                    SocialPublicProfileView(memberID:81,reader:value,squareReader:session.squareReader,isCurrent:{value.isCurrent})
                        .onAppear{probe.appearances += 1}
                        .navigationDestination(isPresented:$probe.covered) {
                            Text("Existing child destination").onAppear{probe.childAppearances += 1}
                        }
                }
            }
        }
    }
    @MainActor private final class Harness {
        let base=URL(string:"https://public-profile.example/native")!
        let wire:Wire,grants:Grants,root:AppCompositionRoot,session:AppSession
        init(enabled:Bool = true) throws {
            let wire=Wire(),grants=Grants(),vault=Vault();grants.enabled=enabled
            self.wire=wire;self.grants=grants
            let deployment=try ReviewedAppDeployment(market:.china,baseURL:base.absoluteString,
                approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.publicProfile",realm:"synthetic")
            root = .init(deployment:.reviewed(deployment),storage:.init(defaults:UserDefaults(suiteName:"public-info-"+UUID().uuidString)!,tokenStore:{_ in vault}),makeTransport:{wire},profilePublicInfoReadAccess:{grants.select($0)})
            session=root.makeSession()
        }
        func login()async{session.authChannels.cancel();await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456")}
        func reader(member:Int = 81)throws->ProfilePublicInfoReader {
            let value=try XCTUnwrap(session.makeProfilePublicInfoReader(memberID:member));value.appear(foreground:true);return value
        }
        func identity(_ reader:ProfilePublicInfoReader)->CompositionHTTPTransport.SessionIdentity {
            let t=reader.target
            return .init(epoch:t.context.session.epoch,accountID:t.context.session.accountID,role:t.context.role,token:t.context.session.token,viewerRevision:t.viewerRevision)
        }
        func transport(_ reader:ProfilePublicInfoReader)->CompositionHTTPTransport {
            let t=root.transport();t.current={self.identity(reader)};return t.scopedForProfilePublicInfo(reader.target)
        }
        func request(path:String = ProfilePublicInfoReadRoute.path,fields:[String:String] = ["member_id":"81"])throws->URLRequest {
            try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent(path),fields:fields,token:"synthetic-public")
        }
    }
    @MainActor private final class Grants {
        var enabled=true
        var access:ProfilePublicInfoReadAccess?
        func select(_ c:RuntimeDependencyContext)->ProfilePublicInfoReadAccess? {
            guard enabled else{return nil}
            if access==nil {access=try? .init(context:c,approval:.init(baseURL:c.baseURL,namespace:c.session.namespace,accountID:c.session.accountID,paths:[ProfilePublicInfoReadRoute.path]))}
            return access
        }
    }
    @MainActor private final class Vault:AppTokenStorage {
        var token:String?
        func read()throws->String?{token};func write(_ value:String)throws{token=value};func clear()throws{token=nil}
    }
    @MainActor private final class Wire:HTTPTransport {
        var requests:[URLRequest]=[]
        var paths:[String]{requests.compactMap{$0.url?.lastPathComponent}}
        var status=200,account=81,target=81,hold=false,override:String?,onHeld:(()->Void)?
        var pending:CheckedContinuation<(Data,Int),Error>?
        func success()->Data {Data("{\"code\":200,\"data\":{\"id\":\(target),\"nickname\":\"Public member\",\"introduction\":\"Public introduction\",\"sysCategoryList\":[{\"id\":1,\"categoryName\":\"Walking\"}]}}".utf8)}
        func finish(status:Int){hold=false;let p=pending;pending=nil;p?.resume(returning:(success(),status))}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request);let path=request.url!.lastPathComponent
            if path=="phone" {return(try JSONSerialization.data(withJSONObject:["code":200,"token":"synthetic-public","data":["id":account,"role":"player"]]),200)}
            if path=="userInfo" {return(try JSONSerialization.data(withJSONObject:["code":200,"appUser":["userId":account,"role":"player"]]),200)}
            guard path=="public-info" else{return(Data(#"{"code":404}"#.utf8),404)}
            if hold{return try await withCheckedThrowingContinuation{pending=$0;onHeld?()}}
            return(override.map{Data($0.utf8)} ?? success(),status)
        }
    }
}
