import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ProfileFavoriteTopicReadTests: XCTestCase {
    func testListSelectionNeedsSuccessfulCurrentLoadedIDAndScope() async throws {
        let h=try Harness();await h.login();let lists=h.session.profileFavoritesReader
        XCTAssertNil(lists.selectTopic(201,renderedScope:lists.scope))
        _ = try await lists.favoriteTopics(pageNumber:1,pageSize:10)
        XCTAssertNil(lists.selectTopic(999,renderedScope:lists.scope));XCTAssertNil(lists.selectTopic(201,renderedScope:UUID()))
        let selected=try XCTUnwrap(lists.selectTopic(201,renderedScope:lists.scope));XCTAssertTrue(selected.isCurrent)
        h.wire.topics=[];_ = try await lists.favoriteTopics(pageNumber:1,pageSize:10)
        XCTAssertFalse(selected.isCurrent);XCTAssertNil(lists.selectTopic(201,renderedScope:lists.scope))
    }
    func testPageFailureRetainsFirstReceiptButRefreshFailureInvalidatesIt() async throws {
        let h=try Harness();await h.login();let old=try await h.selection(), lists=h.session.profileFavoritesReader
        h.wire.status=503
        do {_ = try await lists.favoriteTopics(pageNumber:2,pageSize:10);XCTFail()}catch{}
        XCTAssertTrue(old.isCurrent)
        h.wire.status=200;h.wire.topics=[202];_ = try await lists.favoriteTopics(pageNumber:2,pageSize:10)
        XCTAssertNotNil(lists.selectTopic(202,renderedScope:lists.scope));XCTAssertTrue(old.isCurrent)
        h.wire.status=503
        do {_ = try await lists.favoriteTopics(pageNumber:1,pageSize:10);XCTFail()}catch{}
        XCTAssertFalse(old.isCurrent);XCTAssertNil(lists.selectTopic(202,renderedScope:lists.scope))
    }
    func testDefaultNilDetailIsUnavailableDespiteListAndGlobalDetailApproval() async throws {
        let h=try Harness(details:false);await h.login();let selected=try await h.selection(), reader=h.session.makeProfileFavoriteTopicReader(selected)
        h.wire.requests=[];XCTAssertFalse(reader.isConfigured)
        do {_ = try await reader.topicDetail(id:201);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testOriginalServiceDetailIncludesChaptersWithoutExtraCommentRead() async throws {
        let h=try Harness();await h.login();let selected=try await h.selection(), reader=h.session.makeProfileFavoriteTopicReader(selected)
        h.wire.requests=[];let detail=try await reader.topicDetail(id:201)
        XCTAssertEqual(detail.id,201);XCTAssertEqual(detail.name,"Saved topic");XCTAssertEqual(detail.chapters.map(\.id),[301])
        XCTAssertEqual(h.wire.paths,["info-to-user"])
        let request=try XCTUnwrap(h.wire.requests.first)
        XCTAssertEqual(ProfileFavoriteTopicReadRoute(request:request,baseURL:h.base)?.topicID,201)
        do {_ = try await reader.topicList(query:.init(),pageNumber:1);XCTFail()}catch{XCTAssertEqual(error as? APIError,.notConfigured)}
        do {_ = try await reader.topicDetail(id:202);XCTFail()}catch{XCTAssertEqual(error as? APIError,.invalidRequest)}
        XCTAssertEqual(h.wire.paths,["info-to-user"])
    }
    func testServerDenialAndMalformedDetailRemainFailuresExplicitRetryCanRecover() async throws {
        let h=try Harness();await h.login();let selected=try await h.selection(), reader=h.session.makeProfileFavoriteTopicReader(selected)
        for status in [403,404,503] {h.wire.status=status;do {_ = try await reader.topicDetail(id:201);XCTFail()}catch{XCTAssertEqual(error as? APIError,.httpStatus(status))}}
        h.wire.status=200
        for body in [#"{"code":200}"#,#"{"code":200,"data":{"id":202,"name":"Other"}}"#] {h.wire.override=body;do {_ = try await reader.topicDetail(id:201);XCTFail()}catch{XCTAssertEqual(error as? APIError,.malformedResponse)}}
        h.wire.override=nil;let recovered=try await reader.topicDetail(id:201);XCTAssertEqual(recovered.id,201)
    }
    func testCurrent401ExpiresButLate401AfterOwnerChangeCannot() async throws {
        let h=try Harness();await h.login();let selected=try await h.selection(), reader=h.session.makeProfileFavoriteTopicReader(selected)
        h.wire.hold=true;let held=expectation(description:"old owner");h.wire.onHeld={held.fulfill()}
        let task=Task {try await reader.topicDetail(id:201)};await fulfillment(of:[held],timeout:2)
        await h.session.logout();h.wire.account=82;h.grants.list=nil;h.grants.detail=nil;h.wire.hold=false;await h.login()
        h.wire.finish(status:401)
        do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
        XCTAssertEqual(h.session.account?.id,82);XCTAssertFalse(selected.isCurrent)
        let fresh=try await h.selection(), current=h.session.makeProfileFavoriteTopicReader(fresh);h.wire.status=401
        do {_ = try await current.topicDetail(id:201);XCTFail()}catch{}
        XCTAssertNil(h.session.account)
    }
    func testRevokedOrReplacedApprovalRejectsLateSuccessAnd401() async throws {
        for replace in [false,true] {for status in [200,401] {
            let h=try Harness();await h.login();let selected=try await h.selection(),reader=h.session.makeProfileFavoriteTopicReader(selected)
            h.wire.hold=true;let held=expectation(description:"approval");h.wire.onHeld={held.fulfill()}
            let task=Task {try await reader.topicDetail(id:201)};await fulfillment(of:[held],timeout:2)
            if replace {h.grants.detail=nil}else{h.grants.detail?.revoke()}
            h.wire.finish(status:status)
            do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
            XCTAssertEqual(h.session.account?.id,81)
        }}
    }
    func testRetiredSelectionRejectsHeldReplyAndFutureReads() async throws {
        let h=try Harness();await h.login();let selected=try await h.selection(),reader=h.session.makeProfileFavoriteTopicReader(selected)
        h.wire.hold=true;let held=expectation(description:"pop");h.wire.onHeld={held.fulfill()}
        let task=Task {try await reader.topicDetail(id:201)};await fulfillment(of:[held],timeout:2);selected.retire();h.wire.finish(status:200)
        do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
        let count=h.wire.requests.count
        do {_ = try await reader.topicDetail(id:201);XCTFail()}catch{}
        XCTAssertEqual(h.wire.requests.count,count)
    }
    func testScopedTransportCannotFallbackToGlobalTopicGrantOrOtherRoutes() async throws {
        let h=try Harness(details:false);await h.login();let selected=try await h.selection(),transport=h.transport(selected)
        h.wire.requests=[]
        do {_ = try await transport.send(h.request());XCTFail()}catch{}
        XCTAssertTrue(h.wire.requests.isEmpty);h.grants.details=true
        for (path,fields) in [("api/topic/info-to-user",["id":"202"]),("api/topic/info-to-user",["id":"201","member_id":"81"]),("api/comment/list",["owner_type":"1","owner_id":"201"]),("api/topic/like",["id":"201"]),("api/topic/list",["pageNum":"1"])] {
            do {_ = try await transport.send(h.request(path:path,fields:fields));XCTFail()}catch{}
        }
        XCTAssertTrue(h.wire.requests.isEmpty)
        _ = try await transport.replacingUnderlying(h.wire).scopedForManualMap(ManualMapAreaSelection()).send(h.request())
        XCTAssertEqual(h.wire.paths,["info-to-user"])
    }
    func testUnscopedExistingTopicReadAndDefaultOverrideRemainCompatible() async throws {
        let h=try Harness(details:false);await h.login();let selected=try await h.selection()
        let legacy=h.root.transport();legacy.current={h.identity(selected)};h.wire.requests=[]
        _ = try await legacy.send(h.request());XCTAssertEqual(h.wire.paths,["info-to-user"])
        XCTAssertNil(SessionTopicDetailView(id:201,session:h.session).topicReaderOverride)
    }
    func testExactTransportIdentityChangesRejectAllLateReplies() async throws {
        for kind in ["account","epoch","viewer","token","role"] {for status in [200,401] {
            let h=try Harness();await h.login();let selected=try await h.selection();let transport=h.transport(selected)
            var identity=h.identity(selected);transport.current={identity};h.wire.hold=true
            let held=expectation(description:kind);h.wire.onHeld={held.fulfill()}
            let task=Task {try await transport.send(h.request())};await fulfillment(of:[held],timeout:2)
            identity = .init(epoch:identity.epoch+(kind=="epoch" ? 1:0),accountID:kind=="account" ? 82:81,
                role:kind=="role" ? "merchant":"player",token:kind=="token" ? "other":"synthetic-topics",
                viewerRevision:identity.viewerRevision+(kind=="viewer" ? 1:0))
            h.wire.finish(status:status)
            do {_ = try await task.value;XCTFail()}catch{XCTAssertTrue(error is CancellationError)}
        }}
    }
    func testCurrentConcreteBindingDoesNotReadOrPopSuccessor() async throws {
        let h=try Harness();await h.login();let first=try await h.selection(),owner=ProfileFavoriteTopicNavigationOwner(),scope=h.session.profileFavoritesReader.scope
        owner.appear(scope:scope,foreground:true);XCTAssertTrue(owner.open(first,scope:scope));let binding=owner.binding(for:first)
        XCTAssertTrue(owner.close(id:first.id));let second=try await h.selection();XCTAssertTrue(owner.open(second,scope:scope))
        XCTAssertNil(binding.wrappedValue);binding.wrappedValue=nil;XCTAssertEqual(owner.selection?.id,second.id)
        XCTAssertFalse(owner.close(id:first.id));XCTAssertTrue(second.isCurrent)
    }
    func testHiddenForegroundAndScopeChangesCannotReviveSelection() async throws {
        let h=try Harness();await h.login();let old=try await h.selection(),owner=ProfileFavoriteTopicNavigationOwner(),scope=h.session.profileFavoritesReader.scope
        owner.appear(scope:scope,foreground:true);XCTAssertTrue(owner.open(old,scope:scope));owner.disappear();owner.setForeground(true)
        let next=try await h.selection();XCTAssertFalse(owner.open(next,scope:scope));XCTAssertFalse(old.isCurrent)
        owner.appear(scope:scope,foreground:true);XCTAssertTrue(owner.open(next,scope:scope));owner.updateScope(UUID())
        XCTAssertFalse(next.isCurrent);XCTAssertNil(owner.selection)
    }
    func testNormalFullDetailAndChapterCoverReturnUseSameReaderUntilRootLeaves() async throws {
        let h=try Harness();await h.login();let selected=try await h.selection(), reader=h.session.makeProfileFavoriteTopicReader(selected)
        let owner=ProfileFavoriteTopicNavigationOwner(),probe=Probe(),scope=h.session.profileFavoritesReader.scope
        let detail=try await reader.topicDetail(id:201);let chapter=try XCTUnwrap(detail.chapters.first);h.wire.requests=[]
        let host=UIHostingController(rootView:AnyView(NormalHost(owner:owner,scope:scope,reader:reader,session:h.session,chapter:chapter,probe:probe)))
        let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=host;window.makeKeyAndVisible()
        defer {window.isHidden=true;window.rootViewController=nil}
        host.loadViewIfNeeded();host.view.layoutIfNeeded()
        for _ in 0..<100 where probe.rootAppearances==0 {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertGreaterThan(probe.rootAppearances,0);XCTAssertTrue(h.wire.requests.isEmpty)
        XCTAssertTrue(owner.open(selected,scope:scope))
        for _ in 0..<100 where !h.wire.paths.contains("info-to-user") {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertTrue(h.wire.paths.contains("info-to-user"));XCTAssertEqual(probe.readerCreations,1)
        probe.covered=true
        for _ in 0..<100 where probe.childAppearances==0 {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertGreaterThan(probe.childAppearances,0);XCTAssertGreaterThan(probe.detailDisappearances,0)
        XCTAssertTrue(selected.isCurrent);XCTAssertEqual(owner.selection?.id,selected.id)
        probe.covered=false
        for _ in 0..<100 where probe.detailAppearances<2 {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertGreaterThanOrEqual(probe.detailAppearances,2);XCTAssertEqual(probe.readerCreations,1);XCTAssertTrue(reader.isConfigured)
        XCTAssertTrue(h.wire.paths.allSatisfy{$0=="info-to-user"})
        host.rootView=AnyView(Text("Root left"));host.view.layoutIfNeeded()
        for _ in 0..<100 where selected.isCurrent {try await Task.sleep(for:.milliseconds(20))}
        XCTAssertFalse(selected.isCurrent);XCTAssertNil(owner.selection)
    }
    func testNormalHostWithoutTopicApprovalDoesNotDispatchOrPretendLoaded() async throws {
        let h=try Harness(details:false);await h.login();let selected=try await h.selection(),reader=h.session.makeProfileFavoriteTopicReader(selected)
        h.wire.requests=[]
        let host=UIHostingController(rootView:NavigationStack {ProfileFavoriteTopicDestination(selection:selected,session:h.session,makeReader:{reader})})
        let window=UIWindow(frame:UIScreen.main.bounds);window.rootViewController=host;window.makeKeyAndVisible()
        defer {window.isHidden=true;window.rootViewController=nil}
        host.loadViewIfNeeded();host.view.layoutIfNeeded()
        for _ in 0..<30 {await Task.yield()}
        XCTAssertFalse(reader.isConfigured);XCTAssertTrue(h.wire.requests.isEmpty)
    }
    @MainActor private final class Probe:ObservableObject {
        @Published var covered=false
        var rootAppearances=0,readerCreations=0,detailAppearances=0,detailDisappearances=0,childAppearances=0
    }
    @MainActor private struct NormalHost:View {
        let owner:ProfileFavoriteTopicNavigationOwner
        let scope:UUID
        let reader:ProfileFavoriteTopicReader
        let session:AppSession
        let chapter:TopicChapter
        @ObservedObject var probe:Probe
        var body:some View {
            NavigationStack {
                Text("Saved topics").background {
                    ProfileFavoriteTopicNavigationLayer(owner:owner) { selected in
                        ProfileFavoriteTopicDestination(selection:selected,session:session,makeReader:{probe.readerCreations += 1;return reader})
                            .onAppear{probe.detailAppearances += 1}.onDisappear{probe.detailDisappearances += 1}
                            .navigationDestination(isPresented:$probe.covered) {
                                TopicChapterView(chapter:chapter,reader:reader,scope:reader.scope).onAppear{probe.childAppearances += 1}
                            }
                    }
                }
            }.onAppear{owner.appear(scope:scope,foreground:true);probe.rootAppearances += 1}.onDisappear{owner.disappear()}
        }
    }
    @MainActor private final class Harness {
        let base=URL(string:"https://favorite-topics.example/native")!
        let wire:Wire, grants:Grants, root:AppCompositionRoot, session:AppSession
        init(details:Bool = true) throws {
            let wire=Wire(),grants=Grants(),vault=Vault();grants.details=details
            self.wire=wire;self.grants=grants
            let defaults=UserDefaults(suiteName:"favorite-topic-"+UUID().uuidString)!
            let deployment=try ReviewedAppDeployment(market:.china,baseURL:base.absoluteString,
                approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.favoriteTopic",realm:"synthetic",contentDetails:.activityAndTopic)
            root = .init(deployment:.reviewed(deployment),storage:.init(defaults:defaults,tokenStore:{_ in vault}),makeTransport:{wire},
                profileFavoritesReadAccess:{grants.listAccess($0)},profileFavoriteTopicReadAccess:{grants.detailAccess($0)})
            session=root.makeSession()
        }
        func login() async {session.authChannels.cancel();await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456")}
        func selection() async throws -> ProfileFavoriteTopicSelection {
            let reader=session.profileFavoritesReader;_ = try await reader.favoriteTopics(pageNumber:1,pageSize:10)
            return try XCTUnwrap(reader.selectTopic(201,renderedScope:reader.scope))
        }
        func identity(_ selected:ProfileFavoriteTopicSelection)->CompositionHTTPTransport.SessionIdentity {
            .init(epoch:selected.context.session.epoch,accountID:selected.context.session.accountID,role:selected.context.role,token:selected.context.session.token,viewerRevision:selected.viewerRevision)
        }
        func transport(_ selected:ProfileFavoriteTopicSelection)->CompositionHTTPTransport {
            let value=root.transport();value.current={self.identity(selected)};return value.scopedForProfileFavoriteTopic(selected)
        }
        func request(path:String = ProfileFavoriteTopicReadRoute.path,fields:[String:String] = ["id":"201"])throws->URLRequest {
            try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent(path),fields:fields,token:"synthetic-topics")
        }
    }
    @MainActor private final class Grants {
        var details=true
        var list:ProfileFavoritesReadAccess?,detail:ProfileFavoriteTopicReadAccess?
        func listAccess(_ c:RuntimeDependencyContext)->ProfileFavoritesReadAccess? {
            if list==nil {list=try? .init(context:c,approval:.init(baseURL:c.baseURL,namespace:c.session.namespace,accountID:c.session.accountID,paths:ProfileFavoritesReadRoute.paths))};return list
        }
        func detailAccess(_ c:RuntimeDependencyContext)->ProfileFavoriteTopicReadAccess? {
            guard details else{return nil}
            if detail==nil {detail=try? .init(context:c,approval:.init(baseURL:c.baseURL,namespace:c.session.namespace,accountID:c.session.accountID,paths:[ProfileFavoriteTopicReadRoute.path]))};return detail
        }
    }
    @MainActor private final class Vault:AppTokenStorage {
        var token:String?
        func read()throws->String?{token};func write(_ value:String)throws{token=value};func clear()throws{token=nil}
    }
    @MainActor private final class Wire:HTTPTransport {
        static let success = #"{"code":200,"data":{"id":201,"name":"Saved topic","memberId":999,"chaptersList":[{"id":301,"title":"Chapter","nodes":[]}]}}"#
        var requests:[URLRequest]=[],topics=[201]
        var paths:[String]{requests.compactMap{$0.url?.lastPathComponent}}
        var status=200,account=81,hold=false,override:String?,onHeld:(()->Void)?
        var pending:CheckedContinuation<(Data,Int),Error>?
        func finish(status:Int){hold=false;let p=pending;pending=nil;p?.resume(returning:(Data(Self.success.utf8),status))}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request);let path=request.url!.lastPathComponent
            if path=="phone" {return(try JSONSerialization.data(withJSONObject:["code":200,"token":"synthetic-topics","data":["id":account,"role":"player"]]),200)}
            if path=="userInfo" {return(try JSONSerialization.data(withJSONObject:["code":200,"appUser":["userId":account,"role":"player"]]),200)}
            if path=="like_list" {return(try JSONSerialization.data(withJSONObject:["code":200,"data":["rows":topics.map{["id":$0,"name":"Saved topic","memberId":999] as [String:Any]}]]),status)}
            guard path=="info-to-user" else{return(Data(#"{"code":404}"#.utf8),404)}
            if hold {return try await withCheckedThrowingContinuation{pending=$0;onHeld?()}}
            return(Data((override ?? Self.success).utf8),status)
        }
    }
}
