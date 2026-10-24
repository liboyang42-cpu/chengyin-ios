import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileFavoritesReadTests: XCTestCase {
    func testDefaultNilNormalEntryHasNoDispatchAndNoFakeEmpty() async throws {
        let h = try ProfileFavoritesHarness(lists:false, details:false); await h.login(); h.wire.requests = []
        let reader = h.session.profileFavoritesReader, model = AccountCollectionPostsScreenModel()
        XCTAssertTrue(reader.isAuthenticated);XCTAssertFalse(reader.isConfigured)
        await model.refresh(reader:reader,pageSize:10)
        XCTAssertTrue(h.wire.requests.isEmpty)
        XCTAssertNotNil(model.state.issue);XCTAssertTrue(model.state.pagination.rows.isEmpty)
    }
    func testExistingLinksOnlyReplaceFavoritesReader() async throws {
        let h = try ProfileFavoritesHarness(); await h.login()
        let original = AccountCollectionAccountLinks(reader:h.session.accountCollectionReader,onOpenTopic:{ _ in })
        XCTAssertNil(original.favoritesReader)
        let linked = AccountCollectionAccountLinks(reader:h.session.accountCollectionReader,onOpenTopic:{ _ in },favoritesReader:h.session.profileFavoritesReader)
        XCTAssertTrue(linked.reader === h.session.accountCollectionReader)
        XCTAssertTrue(linked.favoritesReader === h.session.profileFavoritesReader)
        do { _ = try await h.session.profileFavoritesReader.ownedCoupons(keyword:nil);XCTFail() }
        catch { XCTAssertEqual(error as? APIError,.notConfigured) }
    }
    func testPostsPaginationFailureRetriesSamePageAndReturnRefreshReplacesReceipt() async throws {
        let h = try ProfileFavoritesHarness(); await h.login(); h.wire.requests = []
        let reader = h.session.profileFavoritesReader, model = AccountCollectionPostsScreenModel()
        h.wire.posts = [101,102];await model.refresh(reader:reader,pageSize:2)
        XCTAssertEqual(model.state.pagination.rows.map(\.id),[101,102])
        let first = try XCTUnwrap(reader.selectPost(.init(id:101,generation:.legacySquare),renderedScope:reader.scope))
        h.wire.status = 503;await model.loadMore(reader:reader,pageSize:2)
        XCTAssertNotNil(model.state.moreIssue);XCTAssertEqual(model.state.pagination.nextPage,2)
        XCTAssertEqual(model.state.pagination.rows.map(\.id),[101,102])
        h.wire.status = 200;h.wire.posts = [103];await model.loadMore(reader:reader,pageSize:2)
        XCTAssertEqual(model.state.pagination.rows.map(\.id),[101,102,103]);XCTAssertNil(model.state.moreIssue)
        XCTAssertEqual(h.wire.pages,[1,2,2]);first.retire()
        h.wire.posts = [103];await model.refresh(reader:reader,pageSize:2)
        XCTAssertEqual(model.state.pagination.rows.map(\.id),[103]);XCTAssertEqual(h.wire.pages,[1,2,2,1])
        XCTAssertFalse(first.isCurrent);XCTAssertNil(reader.selectPost(.init(id:101,generation:.legacySquare),renderedScope:reader.scope))
    }
    func testTopicsAndSuccessfulEmptyUseDedicatedCurrentUserRoutes() async throws {
        let h = try ProfileFavoritesHarness();await h.login();h.wire.requests = []
        let page = try await h.session.profileFavoritesReader.favoriteTopics(pageNumber:1,pageSize:10)
        XCTAssertEqual(page.rows.map(\.id),[201]);XCTAssertEqual(h.wire.paths,["like_list"])
        h.wire.posts = [];let model = AccountCollectionPostsScreenModel()
        await model.refresh(reader:h.session.profileFavoritesReader,pageSize:10)
        XCTAssertNil(model.state.issue);XCTAssertEqual(model.state.pagination.rows.count,0)
    }
    func testMalformedListIsFailureNotEmptyAndRetryCanRecover() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let model = AccountCollectionPostsScreenModel()
        h.wire.override = #"{"code":200}"#;await model.refresh(reader:h.session.profileFavoritesReader,pageSize:10)
        XCTAssertNotNil(model.state.issue)
        h.wire.override = nil;await model.refresh(reader:h.session.profileFavoritesReader,pageSize:10)
        XCTAssertNil(model.state.issue);XCTAssertEqual(model.state.pagination.rows.map(\.id),[101])
    }
    func testSelectionRequiresLoadedExactLegacyIDAndCurrentReceipt() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let reader = h.session.profileFavoritesReader
        XCTAssertNil(reader.selectPost(.init(id:101,generation:.legacySquare),renderedScope:reader.scope))
        _ = try await reader.favoritePosts(pageNumber:1,pageSize:10)
        XCTAssertNil(reader.selectPost(.init(id:101,generation:.communityV1),renderedScope:reader.scope))
        XCTAssertNil(reader.selectPost(.init(id:999,generation:.legacySquare),renderedScope:reader.scope))
        XCTAssertNil(reader.selectPost(.init(id:101,generation:.legacySquare),renderedScope:UUID()))
        let selected = try XCTUnwrap(reader.selectPost(.init(id:101,generation:.legacySquare),renderedScope:reader.scope))
        _ = try await reader.favoritePosts(pageNumber:1,pageSize:10)
        XCTAssertFalse(selected.isCurrent)
    }
    func testNewApprovalInstallRevokeAndReplacementChangesListScope() async throws {
        let h = try ProfileFavoritesHarness(lists:false);await h.login();let reader = h.session.profileFavoritesReader
        let absent = reader.scope;h.grants.lists = true;XCTAssertTrue(reader.isConfigured);XCTAssertNotEqual(reader.scope,absent)
        let active = reader.scope;h.grants.list?.revoke();XCTAssertFalse(reader.isConfigured);XCTAssertNotEqual(reader.scope,active)
        h.grants.list = nil;XCTAssertTrue(reader.isConfigured);XCTAssertNotEqual(reader.scope,active)
    }
    func testTransportDefaultNilAndWrongRequestsDispatchNothing() async throws {
        let h = try ProfileFavoritesHarness(lists:false);let transport = h.root.transport()
        transport.current = { .init(epoch:1,accountID:81,role:"player",token:"synthetic-favorites",viewerRevision:1) }
        do { _ = try await transport.send(h.request());XCTFail() } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty);h.grants.lists = true
        for path in ["api/topic/like","api/creativesquare/like","api/coupon/myrecvlist","api/creativesquare/info"] {
            do { _ = try await transport.send(h.request(path:path));XCTFail() } catch {}
        }
        var wrong = try h.request();wrong.setValue("other",forHTTPHeaderField:"Authorization")
        do { _ = try await transport.send(wrong);XCTFail() } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty)
        let clone = transport.replacingUnderlying(h.wire).scopedForManualMap(ManualMapAreaSelection())
        _ = try await clone.send(h.request());XCTAssertEqual(h.wire.paths,["list"])
    }
    func testTransportRejectsAllLateIdentityOrApprovalChangesIncluding401() async throws {
        for change in ["account","epoch","token","role","viewer","revoke","replace","remove"] {
            for status in [200,401] {
                let h = try ProfileFavoritesHarness(), transport = h.root.transport()
                var identity = CompositionHTTPTransport.SessionIdentity(epoch:1,accountID:81,role:"player",token:"synthetic-favorites",viewerRevision:1)
                transport.current = { identity };h.wire.holdPath = "list"
                let held = expectation(description:change);h.wire.onHeld = { held.fulfill() }
                let task = Task { try await transport.send(h.request()) };await fulfillment(of:[held],timeout:2)
                switch change {
                case "account":identity = .init(epoch:2,accountID:82,role:"player",token:"synthetic-favorites",viewerRevision:2)
                case "epoch":identity = .init(epoch:2,accountID:81,role:"player",token:"synthetic-favorites",viewerRevision:1)
                case "token":identity = .init(epoch:1,accountID:81,role:"player",token:"replacement",viewerRevision:1)
                case "role":identity = .init(epoch:1,accountID:81,role:"merchant",token:"synthetic-favorites",viewerRevision:1)
                case "viewer":identity = .init(epoch:1,accountID:81,role:"player",token:"synthetic-favorites",viewerRevision:2)
                case "revoke":h.grants.list?.revoke()
                case "replace":h.grants.list = nil
                default:h.grants.lists = false
                }
                h.wire.finish(status:status)
                do { _ = try await task.value;XCTFail(change) } catch { XCTAssertTrue(error is CancellationError) }
            }
        }
    }
    func testLate401CannotSignOutSuccessorAndOldSelectionCannotReopen() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let selected = try await h.selection()
        h.wire.holdPath = "list";let held = expectation(description:"old owner");h.wire.onHeld = { held.fulfill() }
        let task = Task { try await h.session.profileFavoritesReader.favoritePosts(pageNumber:2,pageSize:10) }
        await fulfillment(of:[held],timeout:2);await h.session.logout();h.wire.account = 82;h.grants.list = nil
        await h.login();h.wire.finish(status:401)
        do { _ = try await task.value;XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(h.session.account?.id,82);XCTAssertFalse(selected.isCurrent)
    }
    func testCurrentHTTPAndBusiness401ExpireCurrentSession() async throws {
        for status in [200,401] {
            let h = try ProfileFavoritesHarness();await h.login();h.wire.status = status;h.wire.override = #"{"code":401}"#
            do { _ = try await h.session.profileFavoritesReader.favoritePosts(pageNumber:1,pageSize:10);XCTFail() } catch {}
            XCTAssertNil(h.session.account);XCTAssertNil(h.vault.value)
        }
    }
    func testNormalFavoritesHostStartsItsApprovedListRead() async throws {
        let h = try ProfileFavoritesHarness();await h.login();h.wire.requests = []
        let host = UIHostingController(rootView:NavigationStack {
            AccountCollectionFavoritesView(reader:h.session.profileFavoritesReader,onOpenTopic:{ _ in },onOpenPost:{ _ in })
        }.environment(\.scenePhase,.active))
        let window = UIWindow(frame:UIScreen.main.bounds);window.rootViewController = host;window.makeKeyAndVisible()
        defer { window.isHidden = true;window.rootViewController = nil }
        host.loadViewIfNeeded();host.view.layoutIfNeeded()
        for _ in 0..<100 where h.wire.requests.isEmpty { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertEqual(h.wire.paths,["list"])
    }
}

@MainActor final class ProfileFavoritesHarness {
    let wire: ProfileFavoritesWire
    let grants: ProfileFavoritesGrants
    let vault: ProfileFavoritesVault
    let root: AppCompositionRoot
    let session: AppSession
    let base = URL(string:"https://favorites.example/native")!
    init(lists:Bool = true, details:Bool = true) throws {
        let wire = ProfileFavoritesWire(), grants = ProfileFavoritesGrants(), vault = ProfileFavoritesVault()
        grants.lists = lists;grants.details = details
        self.wire = wire;self.grants = grants;self.vault = vault
        let defaults = UserDefaults(suiteName:"favorites-" + UUID().uuidString)!
        let deployment = try ReviewedAppDeployment(market:.china,baseURL:base.absoluteString,
            approvedBaseURLs:[.china:[base.absoluteString]],verifiedCapabilities:[.domesticChinaPhone],bundleIdentifier:"test.favorites",realm:"synthetic")
        root = .init(deployment:.reviewed(deployment),storage:.init(defaults:defaults,tokenStore:{ _ in vault }),makeTransport:{ wire },
                     profileFavoritesReadAccess:{ grants.selectList($0) },profileFavoriteDetailAccess:{ grants.selectDetail($0) })
        session = root.makeSession()
    }
    func login() async { session.authChannels.cancel();await session.authChannels.loginWithPhone(phone:"10000000000",code:"123456") }
    func selection() async throws -> ProfileFavoritePostSelection {
        let reader = session.profileFavoritesReader;_ = try await reader.favoritePosts(pageNumber:1,pageSize:10)
        return try XCTUnwrap(reader.selectPost(.init(id:101,generation:.legacySquare),renderedScope:reader.scope))
    }
    func request(path:String = "api/creativesquare/list",fields:[String:String] = ["favorite_only":"1","pageNum":"1","pageSize":"10"]) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent(path),fields:fields,token:"synthetic-favorites")
    }
}
@MainActor final class ProfileFavoritesGrants {
    var lists = true, details = true
    var list:ProfileFavoritesReadAccess?, detail:ProfileFavoriteDetailAccess?
    func selectList(_ c:RuntimeDependencyContext) -> ProfileFavoritesReadAccess? {
        guard lists else { return nil }
        if list == nil { list = try? .init(context:c,approval:.init(baseURL:c.baseURL,namespace:c.session.namespace,accountID:c.session.accountID,paths:ProfileFavoritesReadRoute.paths)) }
        return list
    }
    func selectDetail(_ c:RuntimeDependencyContext) -> ProfileFavoriteDetailAccess? {
        guard details else { return nil }
        if detail == nil { detail = try? .init(context:c,approval:.init(baseURL:c.baseURL,namespace:c.session.namespace,accountID:c.session.accountID,paths:ProfileFavoriteDetailRoute.paths)) }
        return detail
    }
}
@MainActor final class ProfileFavoritesVault: AppTokenStorage {
    var value:String?
    func read() throws -> String? { value }
    func write(_ token:String) throws { value = token }
    func clear() throws { value = nil }
}
@MainActor final class ProfileFavoritesWire: HTTPTransport {
    var requests:[URLRequest] = [], pages:[Int] = [], posts = [101]
    var account = 81, status = 200
    var override:String?, holdPath:String?, onHeld:(() -> Void)?
    var pending:CheckedContinuation<(Data,Int),Error>?
    var paths:[String] { requests.compactMap { $0.url?.lastPathComponent } }
    func finish(status:Int = 200,body:String = #"{"code":200,"data":{"rows":[]}}"#) {
        let p = pending;pending = nil;holdPath = nil;p?.resume(returning:(Data(body.utf8),status))
    }
    func send(_ request:URLRequest) async throws -> (Data,Int) {
        requests.append(request);let path = request.url!.lastPathComponent
        if path == "phone" { return (try JSONSerialization.data(withJSONObject:["code":200,"token":"synthetic-favorites","data":["id":account,"role":"player"]]),200) }
        if path == "userInfo" { return (try JSONSerialization.data(withJSONObject:["code":200,"appUser":["userId":account,"role":"player"]]),200) }
        let body = String(data:request.httpBody ?? Data(),encoding:.utf8) ?? ""
        if let range = body.range(of:"name=\"pageNum\"\r\n\r\n"),let page = Int(body[range.upperBound...].components(separatedBy:"\r\n")[0]) { pages.append(page) }
        if path == holdPath { return try await withCheckedThrowingContinuation { pending = $0;onHeld?() } }
        if let override { return (Data(override.utf8),status) }
        let payload:[String:Any]
        if path == "info" { payload = ["id":101,"memberId":991,"content":"Saved post"] }
        else if request.url!.path.hasSuffix("/comment/list") { payload = ["rows":[["id":401,"ownerType":3,"ownerId":101,"memberId":992,"content":"Comment"]]] }
        else if path == "like_list" { payload = ["rows":[["id":201,"memberId":993,"name":"Saved topic"]]] }
        else { payload = ["rows":posts.map { ["id":$0,"memberId":991,"content":"Saved post"] as [String:Any] }] }
        return (try JSONSerialization.data(withJSONObject:["code":200,"data":payload]),status)
    }
}
