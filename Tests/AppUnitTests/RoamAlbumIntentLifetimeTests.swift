import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Original metadata album + real read service/pager, using only an in-memory multipart read route.
@MainActor final class RoamAlbumIntentLifetimeTests: XCTestCase {
    func testInitialInactiveMountDefersOriginalReadAndUnopenedModelDoesNotRead() async throws {
        let r = try AlbumIntentRig(), scope = try r.scope()
        let page = RoamAlbumReadPresentation(reader: r.reader, scope: scope)
        page.readAction()(); await page.refreshAction()(); page.appear(foreground: false)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(r.wire.pages.isEmpty)
        page.setForeground(true); try await waitFor { !page.loading && page.pager.loaded }
        XCTAssertEqual(r.wire.pages, [1]); XCTAssertTrue(scope.isCurrent)
    }
    func testQueuedInitialReadWaitsForCurrentForegroundWithoutDuplicateAppearanceRead() async throws {
        let r = try AlbumIntentRig(), page = RoamAlbumReadPresentation(reader: r.reader, scope: try r.scope())
        page.appear(foreground: true); page.setForeground(false); page.setForeground(true)
        try await waitFor { !page.loading && page.pager.loaded }
        XCTAssertEqual(r.wire.pages, [1])
        page.setForeground(false); page.setForeground(true)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(r.wire.pages, [1], "A completed visible page is not silently refreshed")
    }
    func testOldMoreAndRefreshCannotRunDuringDetailCoverOrAfterBack() async throws {
        let r = try AlbumIntentRig(), scope = try r.scope()
        let page = RoamAlbumReadPresentation(reader: r.reader, scope: scope)
        page.appear(foreground: true); try await waitFor { !page.loading && page.pager.loaded }
        let more = page.readAction(), refresh = page.refreshAction(), rows = page.pager.stamps
        page.disappear(); more(); await refresh()
        page.setForeground(false); page.setForeground(true)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(r.wire.pages, [1]); XCTAssertEqual(page.pager.stamps, rows)
        XCTAssertTrue(scope.isCurrent, "Cover cannot retire the existing detail's metadata scope")
        page.appear(foreground: true); more(); await refresh()
        try await waitFor { !page.loading && r.wire.pages == [1, 1] }
        XCTAssertEqual(page.pager.stamps.map(\.id), [1])
    }
    func testAlreadyQueuedMoreCannotStartWhenOriginalListIsCovered() async throws {
        let r = try AlbumIntentRig(), page = RoamAlbumReadPresentation(reader: r.reader, scope: try r.scope())
        page.appear(foreground: true); try await waitFor { !page.loading && page.pager.loaded }
        page.readAction()(); page.disappear()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(r.wire.pages, [1]); XCTAssertEqual(page.pager.stamps.map(\.id), [1]); XCTAssertFalse(page.loading)
    }
    func testOldReadIntentCannotRepeatOrChooseRefreshedPage() async throws {
        let r = try AlbumIntentRig(), page = RoamAlbumReadPresentation(reader: r.reader, scope: try r.scope())
        page.appear(foreground: true); try await waitFor { !page.loading && page.pager.loaded }
        let more = page.readAction(); more(); more()
        try await waitFor { !page.loading && !page.pager.hasMore }
        more(); let refresh = page.refreshAction(); await refresh(); more(); await refresh()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(r.wire.pages, [1, 2, 1]); XCTAssertEqual(page.pager.stamps.map(\.id), [1])
    }
    func testLateCoveredPageCannotClearOrReplaceBackRefresh() async throws {
        let r = try AlbumIntentRig(), scope = try r.scope()
        let page = RoamAlbumReadPresentation(reader: r.reader, scope: scope)
        page.appear(foreground: true); try await waitFor { !page.loading && page.pager.loaded }
        r.wire.hold = true; page.readAction()(); try await waitFor { r.wire.pending.count == 1 }
        page.disappear(); XCTAssertEqual(page.pager.stamps.map(\.id), [1]); XCTAssertTrue(scope.isCurrent)
        page.appear(foreground: true); try await waitFor { r.wire.pending.count == 2 }
        r.wire.finishFirst(id: 2)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(page.loading); XCTAssertFalse(page.pager.loaded)
        r.wire.finishFirst(id: 101); try await waitFor { !page.loading && page.pager.loaded }
        XCTAssertEqual(page.pager.stamps.map(\.id), [101]); XCTAssertEqual(r.wire.pages, [1, 2, 1])
    }
    func test503KeepsOriginalMetadataAndNewRetryUsesSamePage() async throws {
        let r = try AlbumIntentRig(), page = RoamAlbumReadPresentation(reader: r.reader, scope: try r.scope())
        page.appear(foreground: true); try await waitFor { !page.loading && page.pager.loaded }
        r.wire.status = 503; r.wire.code = 403; let more = page.readAction(); more()
        try await waitFor { !page.loading && page.pager.error != nil }
        XCTAssertEqual(page.pager.error as? APIError, .httpStatus(503)); XCTAssertEqual(page.pager.stamps.map(\.id), [1])
        more(); for _ in 0..<10 { await Task.yield() }; XCTAssertEqual(r.wire.pages, [1, 2])
        r.wire.status = 200; r.wire.code = 200; page.readAction()()
        try await waitFor { !page.loading && page.pager.error == nil }
        XCTAssertEqual(r.wire.pages, [1, 2, 2]); XCTAssertEqual(page.pager.stamps.map(\.id), [1, 2])
    }
    func testDeniedContinuationAndExplicitFirstPageRecoveryKeepOriginalMeaning() async throws {
        for result in [(401, 200), (403, 200), (200, 403)] {
            let r = try AlbumIntentRig(), page = RoamAlbumReadPresentation(reader: r.reader, scope: try r.scope())
            page.appear(foreground: true); try await waitFor { !page.loading && page.pager.loaded }
            r.wire.status = result.0; r.wire.code = result.1; page.readAction()()
            try await waitFor { !page.loading && page.pager.error != nil }
            XCTAssertFalse(page.pager.loaded); XCTAssertTrue(page.pager.stamps.isEmpty); XCTAssertFalse(page.pager.hasMore)
            XCTAssertFalse(r.access!.isRevoked)
            r.wire.status = 200; r.wire.code = 200; page.readAction()()
            for _ in 0..<10 { await Task.yield() }; XCTAssertEqual(r.wire.pages, [1, 2])
            r.wire.empty = true; await page.refreshAction()()
            XCTAssertEqual(r.wire.pages, [1, 2, 1]); XCTAssertTrue(page.pager.loaded)
            XCTAssertTrue(page.pager.stamps.isEmpty); XCTAssertNil(page.pager.error)
        }
    }
    func testFrozenScopeRetirementOrGrantReplacementCannotBeRevivedByOldAction() async throws {
        for change in ["retire", "replace", "revoke", "account"] {
            let r = try AlbumIntentRig(), scope = try r.scope()
            let page = RoamAlbumReadPresentation(reader: r.reader, scope: scope)
            page.appear(foreground: true); try await waitFor { !page.loading && page.pager.loaded }
            page.readAction()()
            switch change {
            case "retire": scope.retire()
            case "replace": try r.replaceAccess()
            case "revoke": r.access?.revoke()
            default: r.context = try AlbumIntentRig.context(account: 8)
            }
            for _ in 0..<10 { await Task.yield() }
            XCTAssertEqual(r.wire.pages, [1], change); XCTAssertFalse(page.loading, change); XCTAssertFalse(scope.isCurrent, change)
            page.disappear(); page.appear(foreground: true)
            for _ in 0..<10 { await Task.yield() }
            XCTAssertEqual(r.wire.pages, [1], change); XCTAssertFalse(page.isCurrent, change)
        }
    }
    func testNoApprovalStillShowsOriginalNotConfiguredWithoutImageOrCaptureAuthority() async throws {
        let r = try AlbumIntentRig(); r.access = nil
        let scope = try r.scope(), page = RoamAlbumReadPresentation(reader: r.reader, scope: scope)
        page.appear(foreground: true); try await waitFor { !page.loading && page.pager.error != nil }
        XCTAssertEqual(page.pager.error as? APIError, .notConfigured); XCTAssertTrue(r.wire.pages.isEmpty)
        let view = RoamStampAlbumView(reader: r.reader, readOnlyScope: scope)
        XCTAssertFalse(view.allowsCapture); XCTAssertFalse(view.allowsRemoteImages)
        XCTAssertFalse(page.pager.loaded); XCTAssertTrue(scope.isCurrent)
    }
    func testActualOriginalCardPushPreservesScopeAndBackRefreshesMetadataOnce() async throws {
        let state = try AlbumIntentHostState(), scene = try HostedNavigationSceneWindow()
        let window = scene.window; mount(state, window: window); defer { scene.retire() }
        try await waitFor { self.find("roam.experience.album.more", in: window) != nil }
        XCTAssertEqual(state.rig.wire.pages, [1]); XCTAssertTrue(state.scope.isCurrent)
        let nav = try XCTUnwrap(navigation(window.rootViewController)), count = nav.viewControllers.count
        try await tap("roam.experience.album.stamp", in: window)
        try await waitFor { nav.viewControllers.count == count + 1 && nav.topViewController?.transitionCoordinator == nil }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(state.scope.isCurrent); XCTAssertEqual(state.rig.wire.pages, [1])
        XCTAssertNil(find("roam.experience.album.openCamera", in: window))
        state.rig.wire.replacement = true
        XCTAssertNotNil(nav.popViewController(animated: false))
        try await waitFor { state.rig.wire.pages == [1, 1] && self.findLabel("Replacement metadata", in: window) != nil }
        XCTAssertTrue(state.scope.isCurrent); XCTAssertNil(findLabel("Original metadata", in: window))
    }
    func testActualBackgroundDoesNotReopenOriginalExpiredMetadataScope() async throws {
        let state = try AlbumIntentHostState(), scene = try HostedNavigationSceneWindow()
        let window = scene.window; mount(state, window: window); defer { scene.retire() }
        try await waitFor { self.find("roam.experience.album.more", in: window) != nil }
        state.phase = .background
        try await waitFor { !state.scope.isCurrent && self.find("roam.experience.album.scopeExpired", in: window) != nil }
        state.phase = .active; try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(state.scope.isCurrent); XCTAssertEqual(state.rig.wire.pages, [1])
        XCTAssertNil(find("roam.experience.album.stamp", in: window)); XCTAssertNil(find("roam.experience.album.more", in: window))
        state.open = false
        try await waitFor { self.find("roam.experience.album", in: window) == nil }
        state.scope = try state.rig.scope(); state.open = true
        try await waitFor { state.rig.wire.pages == [1, 1] && self.find("roam.experience.album.more", in: window) != nil }
        XCTAssertTrue(state.scope.isCurrent)
    }
    func testActualOriginalUnscopedTypedCallerReplacesReaderWithoutKeepingOldPager() async throws {
        let state = try AlbumIntentHostState(); state.scoped = false
        let scene = try HostedNavigationSceneWindow(), window = scene.window; mount(state, window: window); defer { scene.retire() }
        try await waitFor { self.findLabel("Original metadata", in: window) != nil }
        let old = state.rig, fresh = try AlbumIntentRig(); fresh.wire.replacement = true
        XCTAssertEqual(old.reader.identity, fresh.reader.identity); state.rig = fresh
        try await waitFor { fresh.wire.pages == [1] && self.findLabel("Replacement metadata", in: window) != nil }
        XCTAssertNil(findLabel("Original metadata", in: window)); XCTAssertEqual(old.wire.pages, [1])
        XCTAssertNil(find("roam.experience.album.openCamera", in: window))
    }
    private func mount(_ state: AlbumIntentHostState, window: UIWindow) {
        let host = UIHostingController(rootView: AlbumIntentHost(state: state))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded()
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTFail("Original album read/navigation did not settle"); throw APIError.notConfigured
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        for _ in 0..<35 { if find(id, in: window) != nil { break }; scroll(window); try await Task.sleep(nanoseconds: 40_000_000) }
        let target = try XCTUnwrap(find(id, in: window))
        if let control = target as? UIControl { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(target.accessibilityActivate()) }
    }
    private func scroll(_ view: UIView) {
        if let scroll = view as? UIScrollView {
            let end = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            if scroll.contentOffset.y < end { scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(end, scroll.contentOffset.y + 300)), animated: false); scroll.layoutIfNeeded() }
        }
        for child in view.subviews { scroll(child) }
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? { find(id: id, label: nil, in: window) }
    private func findLabel(_ label: String, in window: UIWindow) -> NSObject? { find(id: nil, label: label, in: window) }
    private func find(id: String?, label: String?, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ root: NSObject) -> NSObject? {
            guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
            if let id, (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
            if let label, root.accessibilityLabel?.contains(label) == true { return root }
            if let view = root as? UIView { for child in view.subviews { if let result = visit(child) { return result } } }
            if let children = root.accessibilityElements { for child in children { if let child = child as? NSObject, let result = visit(child) { return result } } }
            let count = root.accessibilityElementCount()
            if count > 0 && count < 1000 { for index in 0..<count { if let child = root.accessibilityElement(at: index) as? NSObject, let result = visit(child) { return result } } }
            return nil
        }
        return visit(window)
    }
    private func navigation(_ controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let result = controller as? UINavigationController { return result }
        for child in controller.children { if let result = navigation(child) { return result } }; return nil
    }
}
@MainActor private final class AlbumIntentHostState: ObservableObject {
    @Published var rig: AlbumIntentRig
    @Published var scope: RoamStampAlbumReadOnlyScope
    @Published var phase: ScenePhase = .active
    @Published var open = true
    @Published var scoped = true
    init() throws { let rig = try AlbumIntentRig(); self.rig = rig; scope = try rig.scope() }
}
@MainActor private struct AlbumIntentHost: View {
    @ObservedObject var state: AlbumIntentHostState
    var body: some View {
        NavigationStack {
            if state.open {
                if state.scoped { RoamAlbumMetadataDestination(reader: state.rig.reader, scope: state.scope) }
                else { RoamStampAlbumView(reader: state.rig.reader) }
            } else { Text("Original album closed") }
        }.environment(\.scenePhase, state.phase).environment(\.locale, Locale(identifier: "en_US"))
    }
}
@MainActor private final class AlbumIntentRig {
    let wire = AlbumIntentWire()
    var context: RuntimeDependencyContext?
    var access: RoamAlbumMetadataReadAccess?
    lazy var reader: RoamAlbumMetadataReader = .init(
        service: try! .init(configuration: .init(baseURL: AlbumIntentWire.base), transport: wire),
        current: { [weak self] in self?.context }, viewerRevision: { 1 }, access: { [weak self] _ in self?.access })
    init() throws { context = try Self.context(account: 7); try replaceAccess() }
    func scope() throws -> RoamStampAlbumReadOnlyScope {
        .init(reader: reader, identity: try XCTUnwrap(reader.identity), isCurrent: { true })
    }
    static func context(account: Int) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: AlbumIntentWire.base, role: "player",
              session: try .init(accountID: account, epoch: 1, namespace: "album-intent", token: "synthetic-album-intent"))
    }
    func replaceAccess() throws {
        let context = try XCTUnwrap(context)
        access = try .init(context: context, approval: .init(baseURL: context.baseURL, namespace: context.session.namespace,
            accountID: context.session.accountID, paths: [RoamAlbumMetadataReadRoute.path]))
    }
}
@MainActor private final class AlbumIntentWire: HTTPTransport {
    static let base = URL(string: "https://example.test/album-intent")!
    struct Pending { let page: Int; let continuation: CheckedContinuation<(Data, Int), Error> }
    var pages: [Int] = []
    var status = 200, code = 200
    var empty = false, hold = false, replacement = false
    var pending: [Pending] = []
    func finishFirst(id: Int) {
        let item = pending.removeFirst()
        item.continuation.resume(returning: (try! payload(page: item.page, pageSize: 20, id: id), 200))
    }
    private func payload(page: Int, pageSize: Int, id: Int) throws -> Data {
        let rows: [[String: Any]] = empty ? [] : [["id": id, "checkState": 0,
            "caption": replacement ? "Replacement metadata" : "Original metadata"]]
        return try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["list": rows,
            "total": empty ? 0 : 40, "pageNum": page, "pageSize": pageSize]])
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let route = try XCTUnwrap(RoamAlbumMetadataReadRoute(request: request, baseURL: Self.base))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-album-intent")
        XCTAssertEqual(route.pageSize, 20); pages.append(route.page)
        if hold { return try await withCheckedThrowingContinuation { pending.append(.init(page: route.page, continuation: $0)) } }
        if status != 200 || code != 200 { return (Data("{\"code\":\(code)}".utf8), status) }
        return (try payload(page: route.page, pageSize: route.pageSize, id: route.page + (replacement ? 100 : 0)), 200)
    }
}
