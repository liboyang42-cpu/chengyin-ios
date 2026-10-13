import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileFavoriteDetailTests: XCTestCase {
    func testListApprovalCannotOpenDetailAndDetailCannotReadTheList() async throws {
        let h = try ProfileFavoritesHarness(details:false);await h.login();let selected = try await h.selection()
        h.wire.requests = [];let reader = h.session.makeProfileFavoriteDetailReader(selected)
        XCTAssertFalse(reader.isConfigured)
        do { _ = try await reader.squareDetail(id:101);XCTFail() } catch { XCTAssertEqual(error as? APIError,.notConfigured) }
        XCTAssertTrue(h.wire.requests.isEmpty)
        let detailOnly = try ProfileFavoritesHarness(lists:false);await detailOnly.login()
        do { _ = try await detailOnly.session.profileFavoritesReader.favoritePosts(pageNumber:1,pageSize:10);XCTFail() } catch {}
        XCTAssertFalse(detailOnly.session.profileFavoritesReader.isConfigured)
    }
    func testExplicitSelectedDetailThenCommentsUseOnlyOriginalReadShapes() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let selected = try await h.selection()
        let reader = h.session.makeProfileFavoriteDetailReader(selected);h.wire.requests = []
        let post = try await reader.squareDetail(route:selected.route)
        XCTAssertEqual(post.id,101);XCTAssertEqual(post.memberID,991)
        let comments = try await reader.squareComments(route:selected.route,pageNumber:1)
        XCTAssertEqual(comments.items.map(\.id),[401]);XCTAssertEqual(h.wire.paths,["info","list"])
        XCTAssertTrue(h.wire.requests[1].url!.path.hasSuffix("/comment/list"))
        let fields = String(data:h.wire.requests[1].httpBody!,encoding:.utf8)!
        XCTAssertTrue(fields.contains("name=\"owner_type\"\r\n\r\n3\r\n"))
        XCTAssertTrue(fields.contains("name=\"owner_id\"\r\n\r\n101\r\n"))
    }
    func testConcurrentScreenReadsSharePendingDetailAndCommentsWaitForSuccess() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let selected = try await h.selection()
        let reader = h.session.makeProfileFavoriteDetailReader(selected);h.wire.requests = [];h.wire.holdPath = "info"
        let held = expectation(description:"info");h.wire.onHeld = { held.fulfill() }
        let detail = Task { try await reader.squareDetail(id:101) };await fulfillment(of:[held],timeout:2)
        let comments = Task { try await reader.squareComments(postID:101,pageNumber:1) }
        await Task.yield();XCTAssertEqual(h.wire.paths,["info"])
        h.wire.finish(body:#"{"code":200,"data":{"id":101,"memberId":991}}"#)
        let post = try await detail.value;let page = try await comments.value
        XCTAssertEqual(post.id,101);XCTAssertEqual(page.items.map(\.id),[401]);XCTAssertEqual(h.wire.paths,["info","list"])
    }
    func testUnavailableDetailNeverTriggersCommentsAndExplicitRetryCanRecover() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let selected = try await h.selection()
        let reader = h.session.makeProfileFavoriteDetailReader(selected);h.wire.requests = [];h.wire.status = 404
        do { _ = try await reader.squareComments(postID:101,pageNumber:1);XCTFail() } catch {}
        XCTAssertEqual(h.wire.paths,["info"])
        h.wire.status = 200;let comments = try await reader.squareComments(postID:101,pageNumber:1)
        XCTAssertEqual(comments.items.count,1);XCTAssertEqual(h.wire.paths,["info","info","list"])
    }
    func testMalformedOrCrossTargetCommentsAreNotEmptySuccess() async throws {
        for raw in [#"{"code":200}"#,#"{"code":200,"data":{"rows":[{"id":401,"ownerType":3,"ownerId":102}]}}"#] {
            let h = try ProfileFavoritesHarness();await h.login();let selected = try await h.selection()
            let reader = h.session.makeProfileFavoriteDetailReader(selected);_ = try await reader.squareDetail(id:101)
            h.wire.override = raw
            do { _ = try await reader.squareComments(postID:101,pageNumber:1);XCTFail() } catch { XCTAssertEqual(error as? APIError,.malformedResponse) }
        }
    }
    func testOtherIDGenerationFeedAndRawUnselectedTransportCannotDispatch() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let selected = try await h.selection()
        let reader = h.session.makeProfileFavoriteDetailReader(selected);h.wire.requests = []
        do { _ = try await reader.squareDetail(id:102);XCTFail() } catch {}
        do { _ = try await reader.squareDetail(route:.init(id:101,generation:.communityV1));XCTFail() } catch {}
        do { _ = try await reader.squareComments(postID:102,pageNumber:1);XCTFail() } catch {}
        do { _ = try await reader.squareFeed(query:.init(),cursor:nil);XCTFail() } catch {}
        let transport = h.root.transport()
        transport.current = { .init(epoch:selected.context.session.epoch,accountID:81,role:"player",token:"synthetic-favorites",viewerRevision:selected.viewerRevision) }
        do { _ = try await transport.send(h.request(path:"api/creativesquare/info",fields:["id":"101"]));XCTFail() } catch {}
        let scoped = transport.scopedForProfileFavorite(selected).replacingUnderlying(h.wire)
        do { _ = try await scoped.send(h.request(path:"api/comment/list",fields:["owner_type":"3","owner_id":"101","pageNum":"1","pageSize":"50"]));XCTFail() } catch {}
        do { _ = try await scoped.send(h.request(path:"api/creativesquare/info",fields:["id":"102"]));XCTFail() } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testRetiredAAndItsLateCloseNeverAffectFreshBSelection() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let a = try await h.selection()
        let oldReader = h.session.makeProfileFavoriteDetailReader(a);oldReader.retire()
        let b = try await h.selection(), newReader = h.session.makeProfileFavoriteDetailReader(b)
        oldReader.retire();XCTAssertFalse(a.isCurrent);XCTAssertTrue(b.isCurrent)
        h.wire.requests = []
        do { _ = try await oldReader.squareDetail(id:101);XCTFail() } catch {}
        let post = try await newReader.squareDetail(id:101);XCTAssertEqual(post.id,101)
        XCTAssertEqual(h.wire.paths,["info"])
    }
    func testHiddenSelectionRejectsPending401WithoutExpiringCurrentSession() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let selected = try await h.selection()
        let reader = h.session.makeProfileFavoriteDetailReader(selected);h.wire.holdPath = "info"
        let held = expectation(description:"hidden");h.wire.onHeld = { held.fulfill() }
        let task = Task { try await reader.squareDetail(id:101) };await fulfillment(of:[held],timeout:2)
        reader.retire();h.wire.finish(status:401)
        do { _ = try await task.value;XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNotNil(h.session.account)
    }
    func testSameOwnerDetailApprovalRevocationRejectsLateReplyAndCannotBorrowReplacement() async throws {
        for status in [200,401] {
            let h = try ProfileFavoritesHarness();await h.login();let selected = try await h.selection()
            let reader = h.session.makeProfileFavoriteDetailReader(selected);h.wire.holdPath = "info"
            let held = expectation(description:"revoke");h.wire.onHeld = { held.fulfill() }
            let task = Task { try await reader.squareDetail(id:101) };await fulfillment(of:[held],timeout:2)
            h.grants.detail?.revoke();h.wire.finish(status:status,body:#"{"code":200,"data":{"id":101}}"#)
            do { _ = try await task.value;XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertNotNil(h.session.account);XCTAssertFalse(reader.isConfigured)
        }
    }
    func testOldSelectedPageCannotReadAfterAccountSwitch() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let selected = try await h.selection()
        let reader = h.session.makeProfileFavoriteDetailReader(selected)
        await h.session.logout();h.wire.account = 82;h.grants.list = nil;h.grants.detail = nil;await h.login();h.wire.requests = []
        do { _ = try await reader.squareDetail(id:101);XCTFail() } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty);XCTAssertFalse(selected.isCurrent);XCTAssertEqual(h.session.account?.id,82)
    }
    func testNormalStableDestinationActuallyLoadsDetailAndCommentsThenRetires() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let selected = try await h.selection()
        let reader = h.session.makeProfileFavoriteDetailReader(selected), owner = ProfileFavoriteNavigationOwner(), probe = CoverProbe()
        let scope = h.session.profileFavoritesReader.scope;h.wire.requests = []
        let host = UIHostingController(rootView:AnyView(RouteFixture(owner:owner,scope:scope,reader:reader,account:h.session.socialAccountReader,probe:probe).environment(\.scenePhase,.active)))
        let window = UIWindow(frame:UIScreen.main.bounds);window.rootViewController = host;window.makeKeyAndVisible()
        defer { window.isHidden = true;window.rootViewController = nil }
        host.loadViewIfNeeded();host.view.layoutIfNeeded()
        for _ in 0..<100 where probe.rootAppearances == 0 { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertGreaterThan(probe.rootAppearances,0)
        XCTAssertTrue(owner.open(selected,scope:scope))
        for _ in 0..<100 where !h.wire.requests.contains(where:{ $0.url?.path.hasSuffix("/comment/list") == true }) { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertTrue(h.wire.paths.contains("info"));XCTAssertTrue(h.wire.requests.contains(where:{ $0.url?.path.hasSuffix("/comment/list") == true }))
        owner.binding(for:selected).wrappedValue = nil
        XCTAssertNil(owner.selection);XCTAssertFalse(selected.isCurrent)
        host.rootView = AnyView(Text("Returned"));host.view.layoutIfNeeded()
    }
    func testNormalDestinationBackgroundRetiresWithoutAnotherRead() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let selected = try await h.selection()
        let reader = h.session.makeProfileFavoriteDetailReader(selected), owner = ProfileFavoriteNavigationOwner(), probe = CoverProbe()
        let scope = h.session.profileFavoritesReader.scope
        func view(_ phase:ScenePhase) -> AnyView { AnyView(RouteFixture(owner:owner,scope:scope,reader:reader,account:h.session.socialAccountReader,probe:probe).environment(\.scenePhase,phase)) }
        let host = UIHostingController(rootView:view(.active)), window = UIWindow(frame:UIScreen.main.bounds)
        window.rootViewController = host;window.makeKeyAndVisible();defer { window.isHidden = true;window.rootViewController = nil }
        host.loadViewIfNeeded();host.view.layoutIfNeeded()
        for _ in 0..<100 where probe.rootAppearances == 0 { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertGreaterThan(probe.rootAppearances,0);XCTAssertTrue(owner.open(selected,scope:scope))
        for _ in 0..<100 where !h.wire.paths.contains("info") { try await Task.sleep(for:.milliseconds(20)) }
        host.rootView = view(.background);host.view.layoutIfNeeded()
        for _ in 0..<100 where selected.isCurrent { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertFalse(selected.isCurrent);let count = h.wire.requests.count
        do { _ = try await reader.squareDetail(id:101);XCTFail() } catch {}
        XCTAssertEqual(h.wire.requests.count,count)
    }
    func testConcreteBindingRejectsOldGetterAndPopAfterReplacement() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let a = try await h.selection()
        let owner = ProfileFavoriteNavigationOwner(), scope = h.session.profileFavoritesReader.scope
        owner.appear(scope:scope,foreground:true);XCTAssertTrue(owner.open(a,scope:scope))
        let old = owner.binding(for:a)
        let b = try await h.selection();XCTAssertTrue(owner.open(b,scope:scope))
        XCTAssertNil(old.wrappedValue);old.wrappedValue = nil
        XCTAssertEqual(owner.selection?.id,b.id);XCTAssertTrue(b.isCurrent);XCTAssertFalse(a.isCurrent)
        XCTAssertFalse(owner.close(id:a.id));XCTAssertEqual(owner.binding(for:b).wrappedValue?.id,b.id)
        owner.binding(for:b).wrappedValue = nil;XCTAssertNil(owner.selection);XCTAssertFalse(b.isCurrent)
    }
    func testHiddenRootCannotReopenOnForegroundWithoutRealAppearance() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let a = try await h.selection()
        let owner = ProfileFavoriteNavigationOwner(), scope = h.session.profileFavoritesReader.scope
        owner.appear(scope:scope,foreground:true);XCTAssertTrue(owner.open(a,scope:scope));owner.disappear()
        let b = try await h.selection();owner.setForeground(true)
        XCTAssertFalse(owner.open(b,scope:scope));XCTAssertNil(owner.selection);XCTAssertFalse(a.isCurrent)
        owner.appear(scope:scope,foreground:true);XCTAssertTrue(owner.open(b,scope:scope))
    }
    func testScopeChangeRetiresOldRouteAndOldPopCannotTouchNewOwner() async throws {
        let h = try ProfileFavoritesHarness();await h.login();let a = try await h.selection()
        let owner = ProfileFavoriteNavigationOwner(), scope = h.session.profileFavoritesReader.scope
        owner.appear(scope:scope,foreground:true);XCTAssertTrue(owner.open(a,scope:scope));let old = owner.binding(for:a)
        await h.session.logout();h.wire.account = 82;h.grants.list = nil;h.grants.detail = nil;await h.login()
        let b = try await h.selection(), fresh = h.session.profileFavoritesReader.scope
        owner.updateScope(fresh);XCTAssertTrue(owner.open(b,scope:fresh));old.wrappedValue = nil
        XCTAssertEqual(owner.selection?.id,b.id);XCTAssertTrue(b.isCurrent);XCTAssertFalse(a.isCurrent)
    }
    func testRealAuthorAndCommentAuthorChildNavigationReturnsToSameDetailReader() async throws {
        for author in [991,992] {
            let h = try ProfileFavoritesHarness();await h.login();let selected = try await h.selection()
            let reader = h.session.makeProfileFavoriteDetailReader(selected), owner = ProfileFavoriteNavigationOwner(), probe = CoverProbe()
            probe.author = author;let scope = h.session.profileFavoritesReader.scope
            let host = UIHostingController(rootView:AnyView(RouteFixture(owner:owner,scope:scope,reader:reader,account:h.session.socialAccountReader,probe:probe).environment(\.scenePhase,.active)))
            let window = UIWindow(frame:UIScreen.main.bounds);window.rootViewController = host;window.makeKeyAndVisible()
            defer { window.isHidden = true;window.rootViewController = nil }
            host.loadViewIfNeeded();host.view.layoutIfNeeded()
        for _ in 0..<100 where probe.rootAppearances == 0 { try await Task.sleep(for:.milliseconds(20)) }
        XCTAssertGreaterThan(probe.rootAppearances,0);XCTAssertTrue(owner.open(selected,scope:scope))
            for _ in 0..<100 where probe.detailAppearances == 0 { try await Task.sleep(for:.milliseconds(20)) }
            XCTAssertEqual(probe.readerCreations,1);probe.covered = true
            for _ in 0..<100 where probe.childAppearances == 0 { try await Task.sleep(for:.milliseconds(20)) }
            XCTAssertGreaterThan(probe.childAppearances,0);XCTAssertGreaterThan(probe.detailDisappearances,0)
            XCTAssertTrue(selected.isCurrent);XCTAssertEqual(owner.selection?.id,selected.id)
            probe.covered = false
            for _ in 0..<100 where probe.detailAppearances < 2 { try await Task.sleep(for:.milliseconds(20)) }
            XCTAssertGreaterThanOrEqual(probe.detailAppearances,2);XCTAssertEqual(probe.readerCreations,1)
            XCTAssertTrue(selected.isCurrent);XCTAssertTrue(reader.isConfigured)
            let value = try await reader.squareDetail(id:101);XCTAssertEqual(value.id,101)
            host.rootView = AnyView(Text("Root left"));host.view.layoutIfNeeded()
            for _ in 0..<100 where selected.isCurrent { try await Task.sleep(for:.milliseconds(20)) }
            XCTAssertFalse(selected.isCurrent);XCTAssertNil(owner.selection)
        }
    }
    @MainActor private final class CoverProbe: ObservableObject {
        @Published var covered = false
        var rootAppearances = 0
        var author = 991, detailAppearances = 0, detailDisappearances = 0, childAppearances = 0, readerCreations = 0
    }
    @MainActor private struct RouteFixture: View {
        let owner: ProfileFavoriteNavigationOwner
        let scope: UUID
        let reader: ProfileFavoriteDetailReader
        let account: any SocialAccountReading
        @ObservedObject var probe: CoverProbe
        @Environment(\.scenePhase) private var scenePhase
        var body: some View {
            NavigationStack {
                Text("Favorites")
                    .background {
                        ProfileFavoriteNavigationLayer(owner:owner) { selected in
                            ProfileFavoriteDetailDestination(selection:selected,makeReader:{ probe.readerCreations += 1;return reader },accountReader:account,actions:nil)
                                .onAppear { probe.detailAppearances += 1 }
                                .onDisappear { probe.detailDisappearances += 1 }
                                .navigationDestination(isPresented:$probe.covered) {
                                    SocialPublicProfileView(memberID:probe.author,reader:account,squareReader:reader,actions:nil)
                                        .onAppear { probe.childAppearances += 1 }
                                }
                        }
                    }
            }
            .onAppear { owner.appear(scope:scope,foreground:scenePhase == .active);probe.rootAppearances += 1 }
            .onDisappear { owner.disappear() }
            .onChange(of:scenePhase) { _,phase in owner.setForeground(phase == .active) }
        }
    }
}
