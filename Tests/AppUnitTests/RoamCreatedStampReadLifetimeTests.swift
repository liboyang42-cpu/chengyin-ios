import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Read-only result-page tests. Synthetic confirmed targets use the existing typed contract;
/// no test performs a create, upload, camera request, network call or real album access.
@MainActor final class RoamCreatedStampReadLifetimeTests: XCTestCase {
    func testUnmountedIntentCannotReadAndAppearanceFindsOnlyOriginalConfirmedID() async throws {
        let r = try CreatedStampIntentReader(), target = try r.target()
        r.pages[1] = try r.page([8, 29, 31])
        let page = RoamCreatedStampReadPresentation(target: target, reader: r)
        page.readAction(refresh: true)(); await drain(); XCTAssertTrue(r.requests.isEmpty)
        page.appear(); try await waitFor { page.lookup.phase == .found }
        XCTAssertEqual(page.lookup.stamp?.id, 29); XCTAssertEqual(r.requests, [1])
        page.readAction()(); await drain(); XCTAssertEqual(r.requests, [1])
    }
    func testOldRenderedRefreshAndMoreCannotCancelFreshReturnRead() async throws {
        let r = try CreatedStampIntentReader(); r.pages[1] = try r.page([8], total: 40)
        let page = try RoamCreatedStampReadPresentation(target: r.target(), reader: r)
        page.appear(); try await waitFor { page.lookup.phase == .more }
        let refresh = page.readAction(refresh: true), more = page.readAction()
        page.disappear(); refresh(); more(); await drain(); XCTAssertEqual(r.requests, [1])
        r.hold = true; page.appear(); try await waitFor { r.pending.count == 1 }
        defer { r.releaseAll() }
        refresh(); more(); await drain()
        XCTAssertEqual(page.lookup.phase, .loading); XCTAssertEqual(r.requests, [1, 1])
        r.release(2, page: try r.page([29], caption: "Current return"))
        try await waitFor { page.lookup.phase == .found }
        XCTAssertEqual(page.lookup.stamp?.caption, "Current return")
    }
    func testCancelledQueuedRefreshCannotEnterLookupAfterVisitRetires() async throws {
        let r = try CreatedStampIntentReader(); r.pages[1] = try r.page([29])
        let page = try RoamCreatedStampReadPresentation(target: r.target(), reader: r)
        page.appear(); try await waitFor { page.lookup.phase == .found }
        page.readAction(refresh: true)(); page.disappear(); page.appear()
        try await waitFor { page.lookup.phase == .found && r.requests.count == 2 }
        await drain(); XCTAssertEqual(r.requests, [1, 1]); XCTAssertEqual(page.lookup.stamp?.id, 29)
    }
    func testLateOldLookupCannotClearOrReplaceNewVisitResponse() async throws {
        let r = try CreatedStampIntentReader(); r.hold = true
        let page = try RoamCreatedStampReadPresentation(target: r.target(), reader: r)
        page.appear(); try await waitFor { r.pending.count == 1 }
        defer { r.releaseAll() }
        page.disappear(); page.appear(); try await waitFor { r.pending.count == 2 }
        r.release(2, page: try r.page([29], caption: "New visit"))
        try await waitFor { page.lookup.phase == .found }
        r.release(1, page: try r.page([29], caption: "Old visit")); await drain()
        XCTAssertEqual(page.lookup.stamp?.caption, "New visit"); XCTAssertEqual(r.requests, [1, 1])
        page.readAction(refresh: true)(); try await waitFor { r.pending.count == 1 }
        XCTAssertEqual(r.requests, [1, 1, 1])
        r.release(3, page: try r.page([29], caption: "Explicit retry"))
        try await waitFor { page.lookup.stamp?.caption == "Explicit retry" }
    }
    func testConsumedMoreCannotRepeatOrChooseNewRefreshCursor() async throws {
        let r = try CreatedStampIntentReader()
        r.pages[1] = try r.page([8], total: 40); r.pages[2] = try r.page([29], number: 2, total: 40)
        let page = try RoamCreatedStampReadPresentation(target: r.target(), reader: r)
        page.appear(); try await waitFor { page.lookup.phase == .more }
        let more = page.readAction(); more(); more()
        try await waitFor { page.lookup.phase == .found }
        XCTAssertEqual(r.requests, [1, 2]); XCTAssertEqual(page.lookup.stamp?.id, 29)
        page.readAction(refresh: true)(); try await waitFor { page.lookup.phase == .more }
        more(); await drain(); XCTAssertEqual(r.requests, [1, 2, 1])
        page.readAction()(); try await waitFor { page.lookup.phase == .found }
        XCTAssertEqual(r.requests, [1, 2, 1, 2])
    }
    func testTransientSecondPageFailureKeepsOriginalRetryPage() async throws {
        let r = try CreatedStampIntentReader()
        r.pages[1] = try r.page([8], total: 40); r.pages[2] = try r.page([29], number: 2, total: 40)
        let page = try RoamCreatedStampReadPresentation(target: r.target(), reader: r)
        page.appear(); try await waitFor { page.lookup.phase == .more }
        r.failure = APIError.httpStatus(503); let more = page.readAction(); more()
        try await waitFor { page.lookup.phase == .failed }
        XCTAssertEqual(page.lookup.error as? APIError, .httpStatus(503)); XCTAssertNil(page.lookup.stamp)
        r.failure = nil; more(); await drain(); XCTAssertEqual(r.requests, [1, 2])
        page.readAction()(); try await waitFor { page.lookup.phase == .found }
        XCTAssertEqual(r.requests, [1, 2, 2])
    }
    func testUnconfiguredErrorAndExplicitRetryDoNotInventReadApproval() async throws {
        let r = try CreatedStampIntentReader(); r.pages[1] = try r.page([29]); r.isConfigured = false
        let page = try RoamCreatedStampReadPresentation(target: r.target(), reader: r)
        page.appear(); try await waitFor { page.lookup.phase == .failed }
        XCTAssertEqual(page.lookup.error as? APIError, .notConfigured); XCTAssertTrue(r.requests.isEmpty)
        r.isConfigured = true; await drain(); XCTAssertTrue(r.requests.isEmpty)
        page.readAction()(); try await waitFor { page.lookup.phase == .found }
        XCTAssertEqual(r.requests, [1])
    }
    func testCancelledCallerCannotResetCompletedCurrentLookup() async throws {
        let r = try CreatedStampIntentReader(); r.pages[1] = try r.page([29])
        let page = try RoamCreatedStampReadPresentation(target: r.target(), reader: r)
        page.appear(); try await waitFor { page.lookup.phase == .found }
        let refresh = page.readAction(refresh: true), gate = CreatedStampIntentGate()
        let old = Task { await gate.wait(); refresh() }
        try await waitFor { gate.isWaiting }; old.cancel(); gate.release(); await old.value; await drain()
        XCTAssertEqual(page.lookup.phase, .found); XCTAssertEqual(page.lookup.stamp?.id, 29)
        XCTAssertEqual(r.requests, [1])
    }
    func testExactTargetReaderAndAccountFenceSurvivesQueuedIntent() async throws {
        for changedOwner in [false, true] {
            let r = try CreatedStampIntentReader(); r.pages[1] = try r.page([29])
            let target = try r.target(), other = try CreatedStampIntentReader()
            XCTAssertNotEqual(RoamCreatedStampReadOwner(target: target, reader: r), RoamCreatedStampReadOwner(target: target, reader: other))
            let page = RoamCreatedStampReadPresentation(target: target, reader: r)
            page.appear(); try await waitFor { page.lookup.phase == .found }
            page.readAction(refresh: true)()
            r.identity = changedOwner ? try CreatedStampIntentReader.identity(account: 8) : try CreatedStampIntentReader.identity(epoch: 2)
            await drain(); XCTAssertEqual(r.requests, [1]); XCTAssertFalse(target.isCurrent(reader: r))
            page.disappear(); page.appear(); await drain(); XCTAssertEqual(r.requests, [1]); XCTAssertNil(page.lookup.stamp)
            let replaced = RoamCreatedStampReadPresentation(target: target, reader: other)
            replaced.appear(); await drain(); XCTAssertTrue(other.requests.isEmpty)
        }
    }
    func testOriginalHiddenMissingAndDeniedStatesAreNotFabricatedMatches() async throws {
        for kind in ["hidden", "missing", "denied"] {
            let r = try CreatedStampIntentReader()
            r.pages[1] = try r.page(kind == "missing" ? [8] : [29], state: kind == "hidden" ? 3 : 0)
            if kind == "denied" { r.failure = APIError.unauthorized }
            let page = try RoamCreatedStampReadPresentation(target: r.target(), reader: r)
            page.appear()
            let expected: RoamCreatedStampLookup.Phase = kind == "hidden" ? .hidden : (kind == "missing" ? .missing : .unavailable)
            try await waitFor { page.lookup.phase == expected }
            XCTAssertNil(page.lookup.stamp); XCTAssertEqual(r.requests, [1])
            page.readAction()(); await drain(); XCTAssertEqual(r.requests, [1])
        }
    }
    func testActualResultPushesOriginalAlbumAndBackRereadsExactConfirmedID() async throws {
        let state = try CreatedStampIntentHostState(), scene = try HostedNavigationSceneWindow()
        let window = scene.window; mount(state, window: window); defer { scene.retire(); state.reader.releaseAll() }
        try await waitFor { self.find("roam.createdStamp.match", in: window) != nil }
        XCTAssertEqual(state.reader.requests, [1])
        let nav = try XCTUnwrap(navigation(window.rootViewController)), count = nav.viewControllers.count
        try await tap("roam.createdStamp.browse", in: window)
        try await waitFor { nav.viewControllers.count == count + 1 && self.find("roam.experience.album.stamp", in: window) != nil }
        XCTAssertEqual(state.reader.requests, [1, 1])
        state.reader.pages[1] = try state.reader.page([8, 29], caption: "Refreshed result")
        XCTAssertNotNil(nav.popViewController(animated: false))
        try await waitFor { state.reader.requests == [1, 1, 1] && self.findLabel("Refreshed result", in: window) != nil }
        XCTAssertNotNil(find("roam.createdStamp.match", in: window)); XCTAssertTrue(state.target.isCurrent(reader: state.reader))
    }
    func testActualSameIdentityReaderReplacementUsesNewConfirmedTargetNotOldLookup() async throws {
        let state = try CreatedStampIntentHostState(), scene = try HostedNavigationSceneWindow()
        let window = scene.window; mount(state, window: window); defer { scene.retire(); state.reader.releaseAll() }
        try await waitFor { self.findLabel("Original result", in: window) != nil }
        let old = state.reader, fresh = try CreatedStampIntentReader()
        fresh.pages[1] = try fresh.page([31], caption: "Different confirmed result")
        XCTAssertEqual(old.identity, fresh.identity)
        state.reader = fresh; state.target = try fresh.target(id: 31)
        try await waitFor { fresh.requests == [1] && self.findLabel("Different confirmed result", in: window) != nil }
        XCTAssertNil(findLabel("Original result", in: window)); XCTAssertEqual(old.requests, [1])
        XCTAssertTrue(state.target.isCurrent(reader: fresh)); XCTAssertFalse(state.target.isCurrent(reader: old))
    }
    func testActualForeignAccountCannotUseOldResultOrBrowseItsAlbum() async throws {
        let state = try CreatedStampIntentHostState(), scene = try HostedNavigationSceneWindow()
        let window = scene.window; mount(state, window: window); defer { scene.retire(); state.reader.releaseAll() }
        try await waitFor { self.findLabel("Original result", in: window) != nil }
        let foreign = try CreatedStampIntentReader(); foreign.identity = try CreatedStampIntentReader.identity(account: 8)
        state.reader = foreign
        try await waitFor { self.find("roam.createdStamp.changed", in: window) != nil }
        XCTAssertTrue(foreign.requests.isEmpty); XCTAssertNil(find("roam.createdStamp.browse", in: window))
        XCTAssertNil(find("roam.createdStamp.match", in: window)); XCTAssertNil(findLabel("Original result", in: window))
    }
    private func drain() async { for _ in 0..<12 { await Task.yield() } }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTFail("Original created-stamp lookup/navigation did not settle"); throw APIError.notConfigured
    }
    private func mount(_ state: CreatedStampIntentHostState, window: UIWindow) {
        let host = UIHostingController(rootView: CreatedStampIntentHost(state: state))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded()
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
        guard let controller else { return nil }; if let result = controller as? UINavigationController { return result }
        for child in controller.children { if let result = navigation(child) { return result } }; return nil
    }
}

@MainActor private final class CreatedStampIntentHostState: ObservableObject {
    @Published var reader: CreatedStampIntentReader
    @Published var target: RoamCreatedStampTarget
    init() throws {
        let reader = try CreatedStampIntentReader(); self.reader = reader; target = try reader.target()
        reader.pages[1] = try reader.page([29], caption: "Original result")
    }
}
@MainActor private struct CreatedStampIntentHost: View {
    @ObservedObject var state: CreatedStampIntentHostState
    var body: some View {
        NavigationStack {
            RoamCreatedStampView(target: state.target, album: .init(reader: state.reader, camera: { AnyView(Text("Camera not exercised")) }))
        }.environment(\.scenePhase, .active).environment(\.locale, Locale(identifier: "en_US"))
    }
}
@MainActor private final class CreatedStampIntentGate {
    private var waiter: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { waiter != nil }
    func wait() async { await withCheckedContinuation { waiter = $0 } }
    func release() { let saved = waiter; waiter = nil; saved?.resume() }
}
@MainActor private final class CreatedStampIntentReader: RoamExperienceReading {
    var identity: RoamExperienceIdentity?
    var isConfigured = true
    let isOfflineExample = true
    var pages: [Int: RoamAlbumPage] = [:]
    var failure: Error?
    var requests: [Int] = []
    var hold = false
    var pending: [Int: CheckedContinuation<RoamAlbumPage, Error>] = [:]
    init() throws { identity = try Self.identity() }
    static func identity(account: Int = 3, epoch: UInt64 = 1) throws -> RoamExperienceIdentity {
        .init(scope: try .init(market: "cn", deployment: URL(string: "https://api.example.com/")!, accountID: account, namespace: "created-stamp-read"), epoch: epoch)
    }
    func target(id: Int = 29) throws -> RoamCreatedStampTarget {
        let scope = try XCTUnwrap(identity?.scope)
        let origin = try RetainedImageScope(accountID: scope.accountID, epoch: UUID(), realm: scope.deployment, destination: .stamp, namespace: scope.namespace)
        return try XCTUnwrap(RoamCreatedStampTarget(phase: .created(id), origin: origin, reader: self))
    }
    func page(_ ids: [Int], number: Int = 1, total: Int? = nil, state: Int = 0, caption: String = "Original result") throws -> RoamAlbumPage {
        let rows: [[String: Any]] = ids.map { ["id": $0, "picUrl": "", "caption": caption, "checkState": state] }
        return try JSONDecoder().decode(RoamAlbumPage.self, from: JSONSerialization.data(withJSONObject: ["list": rows, "total": total ?? ids.count, "pageNum": number, "pageSize": 20]))
    }
    func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage {
        XCTAssertEqual(pageSize, 20); requests.append(page)
        if let failure { throw failure }
        if hold {
            let index = requests.count
            return try await withCheckedThrowingContinuation { pending[index] = $0 }
        }
        return try XCTUnwrap(pages[page])
    }
    func release(_ index: Int, page: RoamAlbumPage) {
        let continuation = pending.removeValue(forKey: index)
        XCTAssertNotNil(continuation); continuation?.resume(returning: page)
    }
    func releaseAll() {
        let remaining = Array(pending.values); pending.removeAll()
        remaining.forEach { $0.resume(throwing: CancellationError()) }
    }
    func history() throws -> [RoamHistoryRecord] { XCTFail("Unexpected history read"); return [] }
    func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
    func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
    func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
}
