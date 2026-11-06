import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Existing typed tile reader + service + pager, with a memory-only transport admitting tile GETs.
@MainActor final class RoamTileIntentLifetimeTests: XCTestCase {
    func testConstructedBackgroundAndForegroundEntryNeverReadAutomatically() async throws {
        let r = try TileIntentRig(), page = RoamTileMemoryPresentation(reader: r.reader)
        page.readAction()(); await page.refreshAction()()
        page.appear(foreground: false); page.readAction()(); await page.refreshAction()()
        page.setForeground(true)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(r.wire.cursors.isEmpty); XCTAssertFalse(page.pager.loaded)
        page.readAction()(); try await waitFor { page.pager.loaded && !page.loading }
        XCTAssertEqual(r.wire.cursors, [0])
    }
    func testOldRenderedReadAndRefreshCannotEnterNewVisit() async throws {
        let r = try TileIntentRig(), page = RoamTileMemoryPresentation(reader: r.reader)
        page.appear(foreground: true)
        let read = page.readAction(), refresh = page.refreshAction()
        page.disappear(); page.appear(foreground: true)
        read(); await refresh()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(r.wire.cursors.isEmpty)
        page.readAction()(); try await waitFor { !page.loading && page.pager.loaded }
        XCTAssertEqual(r.wire.cursors, [0])
    }
    func testAlreadyQueuedReadCannotStartAfterImmediateBackgroundAndReturn() async throws {
        let r = try TileIntentRig(), page = RoamTileMemoryPresentation(reader: r.reader)
        page.appear(foreground: true); page.readAction()()
        page.setForeground(false); page.setForeground(true)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(r.wire.cursors.isEmpty); XCTAssertFalse(page.loading)
        page.readAction()(); try await waitFor { !page.loading && page.pager.loaded }
        XCTAssertEqual(r.wire.cursors, [0])
    }
    func testReadActionIsConsumedOnceAndOldMoreCannotChooseRefreshedCursor() async throws {
        let r = try TileIntentRig(), page = RoamTileMemoryPresentation(reader: r.reader)
        page.appear(foreground: true)
        let first = page.readAction(); first(); first()
        try await waitFor { !page.loading && page.pager.loaded }
        first(); let more = page.readAction()
        await page.refreshAction()(); more()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(r.wire.cursors, [0, 0]); XCTAssertEqual(page.pager.tiles, ["wx4g0ec"])
        page.readAction()(); try await waitFor { !page.loading && !page.pager.hasMore }
        XCTAssertEqual(r.wire.cursors, [0, 0, 5]); XCTAssertEqual(page.pager.tiles, ["wx4g0ec", "wx4g0ed"])
    }
    func testFailedReadNeedsFreshIntentAnd503RetainsOriginalCursor() async throws {
        let r = try TileIntentRig(), page = RoamTileMemoryPresentation(reader: r.reader)
        page.appear(foreground: true); await page.refreshAction()()
        r.wire.status = 503; r.wire.code = 403
        let more = page.readAction(); more()
        try await waitFor { !page.loading && page.pager.error != nil }
        XCTAssertEqual(page.pager.error as? APIError, .httpStatus(503))
        XCTAssertEqual(page.pager.tiles, ["wx4g0ec"])
        more(); for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(r.wire.cursors, [0, 5])
        r.wire.status = 200; r.wire.code = 200; page.readAction()()
        try await waitFor { !page.loading && page.pager.error == nil }
        XCTAssertEqual(r.wire.cursors, [0, 5, 5])
    }
    func testLateReadAfterBackgroundCannotClearNewReadOrPublishOldPage() async throws {
        let r = try TileIntentRig(), page = RoamTileMemoryPresentation(reader: r.reader)
        page.appear(foreground: true); r.wire.hold = true; page.readAction()()
        try await waitFor { r.wire.pending.count == 1 }
        page.setForeground(false); page.setForeground(true)
        page.readAction()(); try await waitFor { r.wire.pending.count == 2 }
        r.wire.finishFirst(tile: "wx4g0ed")
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(page.loading); XCTAssertFalse(page.pager.loaded)
        r.wire.finishFirst(tile: "wx4g0ec")
        try await waitFor { !page.loading && page.pager.loaded }
        XCTAssertEqual(page.pager.tiles, ["wx4g0ec"]); XCTAssertEqual(r.wire.cursors, [0, 0])
    }
    func testOldRefreshCannotResetSuccessorReadOrPrivatePage() async throws {
        let r = try TileIntentRig(), page = RoamTileMemoryPresentation(reader: r.reader)
        page.appear(foreground: true); let oldRefresh = page.refreshAction()
        page.readAction()(); try await waitFor { !page.loading && page.pager.loaded }
        await oldRefresh()
        XCTAssertEqual(r.wire.cursors, [0]); XCTAssertEqual(page.pager.tiles, ["wx4g0ec"])
    }
    func testRevocationReplacementAndAccountChangeRejectQueuedOriginalIntent() async throws {
        for change in ["revoke", "replace", "account", "nil"] {
            let r = try TileIntentRig(), page = RoamTileMemoryPresentation(reader: r.reader)
            page.appear(foreground: true); page.readAction()()
            switch change {
            case "revoke": r.access?.revoke()
            case "replace": try r.replaceAccess()
            case "account": r.context = try TileIntentRig.context(account: 8)
            default: r.context = nil
            }
            for _ in 0..<10 { await Task.yield() }
            XCTAssertTrue(r.wire.cursors.isEmpty, change); XCTAssertFalse(page.loading, change)
            XCTAssertFalse(page.pager.loaded, change); XCTAssertFalse(page.isVisible, change)
        }
    }
    func testDenialStillRequiresExplicitRefreshAndCannotBecomeSuccessfulEmpty() async throws {
        for result in [(401, 200), (403, 200), (200, 403)] {
            let r = try TileIntentRig(), page = RoamTileMemoryPresentation(reader: r.reader)
            page.appear(foreground: true); await page.refreshAction()()
            r.wire.status = result.0; r.wire.code = result.1; page.readAction()()
            try await waitFor { !page.loading && page.pager.error != nil }
            XCTAssertFalse(page.pager.loaded); XCTAssertFalse(page.pager.hasMore); XCTAssertTrue(page.pager.tiles.isEmpty)
            r.wire.status = 200; r.wire.code = 200; page.readAction()()
            for _ in 0..<10 { await Task.yield() }
            XCTAssertEqual(r.wire.cursors, [0, 5]); XCTAssertFalse(r.access!.isRevoked)
            r.wire.empty = true; await page.refreshAction()()
            XCTAssertEqual(r.wire.cursors, [0, 5, 0]); XCTAssertTrue(page.pager.loaded)
            XCTAssertTrue(page.pager.tiles.isEmpty); XCTAssertNil(page.pager.error)
        }
    }
    func testActualDestinationBackgroundHidesCountAndReturnNeedsExplicitZeroCursorRead() async throws {
        let state = try TileIntentHostState(), window = mount(state); defer { close(window) }
        try await waitFor { self.find("roam.experience.tiles.load", in: window) != nil }
        XCTAssertTrue(state.rig.wire.cursors.isEmpty)
        try await tap("roam.experience.tiles.load", in: window)
        try await waitFor { self.find("roam.experience.tiles.loaded", in: window) != nil }
        state.phase = .background
        try await waitFor { self.find("roam.experience.tiles.loaded", in: window) == nil && self.find("roam.experience.tiles.load", in: window) == nil }
        state.phase = .active
        try await waitFor { self.find("roam.experience.tiles.load", in: window) != nil }
        XCTAssertNil(find("roam.experience.tiles.loaded", in: window)); XCTAssertEqual(state.rig.wire.cursors, [0])
        try await tap("roam.experience.tiles.load", in: window)
        try await waitFor { state.rig.wire.cursors == [0, 0] && self.find("roam.experience.tiles.loaded", in: window) != nil }
    }
    func testActualSameIdentityReaderReplacementCannotContinueOldPager() async throws {
        let state = try TileIntentHostState(), window = mount(state); defer { close(window) }
        try await tap("roam.experience.tiles.load", in: window)
        try await waitFor { self.find("roam.experience.tiles.loaded", in: window) != nil }
        let old = state.rig; state.rig = try TileIntentRig()
        XCTAssertEqual(old.reader.identity, state.rig.reader.identity)
        try await waitFor { self.find("roam.experience.tiles.loaded", in: window) == nil && self.find("roam.experience.tiles.load", in: window) != nil }
        XCTAssertTrue(state.rig.wire.cursors.isEmpty)
        try await tap("roam.experience.tiles.load", in: window)
        try await waitFor { state.rig.wire.cursors == [0] && self.find("roam.experience.tiles.loaded", in: window) != nil }
        XCTAssertEqual(old.wire.cursors, [0])
    }
    func testActualNoApprovalAndReissuedApprovalRemainReadOnlyAndExplicit() async throws {
        let state = try TileIntentHostState(); state.rig.access = nil
        let window = mount(state); defer { close(window) }
        try await waitFor { self.find("roam.experience.tiles.load", in: window) != nil }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(state.rig.reader.isConfigured); XCTAssertTrue(state.rig.wire.cursors.isEmpty)
        try state.rig.replaceAccess(); state.revision += 1
        try await Task.sleep(nanoseconds: 100_000_000)
        try await tap("roam.experience.tiles.load", in: window)
        try await waitFor { self.find("roam.experience.tiles.loaded", in: window) != nil }
        state.rig.access?.revoke(); state.revision += 1
        try await waitFor { self.find("roam.experience.tiles.loaded", in: window) == nil }
        XCTAssertEqual(state.rig.wire.cursors, [0]); XCTAssertFalse(state.rig.reader.isConfigured)
        try state.rig.replaceAccess(); state.revision += 1
        try await Task.sleep(nanoseconds: 100_000_000)
        try await waitFor { self.find("roam.experience.tiles.load", in: window) != nil }
        XCTAssertEqual(state.rig.wire.cursors, [0])
        try await tap("roam.experience.tiles.load", in: window)
        try await waitFor { state.rig.wire.cursors == [0, 0] }
    }
    func testActualDepartureAndReopenRetireHeldReadWithoutAutomaticRecovery() async throws {
        let state = try TileIntentHostState(); state.rig.wire.hold = true
        let window = mount(state); defer { close(window) }
        try await tap("roam.experience.tiles.load", in: window)
        try await waitFor { state.rig.wire.pending.count == 1 }
        state.open = false
        try await waitFor { self.find("roam.experience.tileMemory", in: window) == nil }
        state.rig.wire.finishFirst(tile: "wx4g0ed"); state.rig.wire.hold = false; state.open = true
        try await waitFor { self.find("roam.experience.tiles.load", in: window) != nil }
        XCTAssertNil(find("roam.experience.tiles.loaded", in: window)); XCTAssertEqual(state.rig.wire.cursors, [0])
        try await tap("roam.experience.tiles.load", in: window)
        try await waitFor { state.rig.wire.cursors == [0, 0] && self.find("roam.experience.tiles.loaded", in: window) != nil }
    }
    private func mount(_ state: TileIntentHostState) -> UIWindow {
        let host = UIHostingController(rootView: TileIntentHost(state: state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1000))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTFail("Original tile read/control did not settle"); throw APIError.notConfigured
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        try await waitFor { self.find(id, in: window) != nil }
        let target = try XCTUnwrap(find(id, in: window))
        if let control = target as? UIControl { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(target.accessibilityActivate()) }
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ root: NSObject) -> NSObject? {
            guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
            if (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
            if let view = root as? UIView { for child in view.subviews { if let result = visit(child) { return result } } }
            if let children = root.accessibilityElements { for child in children { if let child = child as? NSObject, let result = visit(child) { return result } } }
            let count = root.accessibilityElementCount()
            if count > 0 && count < 1000 { for index in 0..<count { if let child = root.accessibilityElement(at: index) as? NSObject, let result = visit(child) { return result } } }
            return nil
        }
        return visit(window)
    }
}

@MainActor private final class TileIntentHostState: ObservableObject {
    @Published var rig: TileIntentRig
    @Published var phase: ScenePhase = .active
    @Published var open = true
    @Published var revision = 0
    init() throws { rig = try TileIntentRig() }
}
@MainActor private struct TileIntentHost: View {
    @ObservedObject var state: TileIntentHostState
    var body: some View {
        let _ = state.revision
        NavigationStack {
            if state.open { RoamTileMemoryView(reader: state.rig.reader) }
            else { Text("Original tile page closed") }
        }.environment(\.scenePhase, state.phase).environment(\.locale, Locale(identifier: "en_US"))
    }
}
@MainActor private final class TileIntentRig {
    let wire = TileIntentWire()
    var context: RuntimeDependencyContext?
    var access: RoamTileMemoryReadAccess?
    lazy var reader: RoamTileMemoryReader = .init(
        service: try! .init(configuration: .init(baseURL: TileIntentWire.base), transport: wire),
        current: { [weak self] in self?.context }, viewerRevision: { 1 }, access: { [weak self] _ in self?.access })
    init() throws { context = try Self.context(account: 7); try replaceAccess() }
    static func context(account: Int) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: TileIntentWire.base, role: "player",
              session: try .init(accountID: account, epoch: 1, namespace: "tile-intent", token: "synthetic-tile-intent"))
    }
    func replaceAccess() throws {
        let context = try XCTUnwrap(context)
        access = try .init(context: context, approval: .init(baseURL: context.baseURL, namespace: context.session.namespace,
            accountID: context.session.accountID, paths: [RoamTileMemoryReadRoute.path]))
    }
}
@MainActor private final class TileIntentWire: HTTPTransport {
    static let base = URL(string: "https://example.test/tile-intent")!
    var cursors: [Int] = []
    var status = 200, code = 200
    var empty = false, hold = false
    var pending: [CheckedContinuation<(Data, Int), Error>] = []
    func finishFirst(tile: String) {
        let value = pending.removeFirst()
        value.resume(returning: (Data("{\"code\":200,\"data\":{\"tiles\":[\"\(tile)\"],\"nextAfterId\":5,\"hasMore\":false}}".utf8), 200))
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let route = try XCTUnwrap(RoamTileMemoryReadRoute(request: request, baseURL: Self.base))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-tile-intent")
        XCTAssertEqual(route.limit, 1000); cursors.append(route.afterID)
        if hold { return try await withCheckedThrowingContinuation { pending.append($0) } }
        if status != 200 || code != 200 { return (Data("{\"code\":\(code)}".utf8), status) }
        let tiles: [String] = empty ? [] : (route.afterID == 0 ? ["wx4g0ec"] : ["wx4g0ec", "wx4g0ed"])
        let body: [String: Any] = ["code": 200, "data": ["tiles": tiles,
            "nextAfterId": empty ? route.afterID : (route.afterID == 0 ? 5 : 7), "hasMore": !empty && route.afterID == 0]]
        return (try JSONSerialization.data(withJSONObject: body), 200)
    }
}
