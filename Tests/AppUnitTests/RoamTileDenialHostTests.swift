import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// The actual Hub tile destination, original explicit read/continuation controls and
/// independently approved reader. The transport is memory-only and accepts only tile GETs.
@MainActor final class RoamTileDenialHostTests: XCTestCase {
    func testHTTPAndBusiness403RemovePrivateCountAndContinuationWithoutEmptySuccess() async throws {
        for result in [(403, 200), (200, 403)] {
            let r = try TileDenialHostRig(), host = UIHostingController(rootView: AnyView(Text("Preparing test")))
            let window = mount(host); defer { close(window) }
            host.rootView = tiles(r)
            try await waitFor("Original explicit read control") { self.find("roam.experience.tiles.load", in: window) != nil }
            XCTAssertTrue(r.wire.cursors.isEmpty)
            try await tap("roam.experience.tiles.load", in: window)
            try await waitFor("Read first page through real destination") {
                r.wire.cursors == [0] && self.find("roam.experience.tiles.loaded", in: window) != nil
            }
            r.wire.status = result.0; r.wire.code = result.1
            try await tap("roam.experience.tiles.load", in: window)
            try await waitFor("Denied presentation") { self.find("roam.experience.tiles.denied", in: window) != nil }
            for id in ["roam.experience.tiles.loaded", "roam.experience.tiles.load", "roam.experience.retry"] {
                XCTAssertNil(find(id, in: window), id)
            }
            XCTAssertEqual(r.wire.cursors, [0, 5]); XCTAssertTrue(r.reader.isConfigured)
            XCTAssertFalse(r.access.isRevoked)
        }
    }

    func test503With403BodyRetainsCountAndOriginalRetryUsesSameCursor() async throws {
        let r = try TileDenialHostRig(), host = UIHostingController(rootView: AnyView(Text("Preparing test")))
        let window = mount(host); defer { close(window) }
        host.rootView = tiles(r)
        try await tap("roam.experience.tiles.load", in: window)
        try await waitFor("Loaded first page") { self.find("roam.experience.tiles.loaded", in: window) != nil }
        r.wire.status = 503; r.wire.code = 403
        try await tap("roam.experience.tiles.load", in: window)
        try await waitFor("Original retry after transient failure") { self.find("roam.experience.retry", in: window) != nil }
        XCTAssertNotNil(find("roam.experience.tiles.loaded", in: window))
        XCTAssertNil(find("roam.experience.tiles.denied", in: window))
        r.wire.status = 200; r.wire.code = 200
        try await tap("roam.experience.retry", in: window)
        try await waitFor("Same cursor recovered") {
            r.wire.cursors == [0, 5, 5] && self.find("roam.experience.retry", in: window) == nil
        }
        XCTAssertNotNil(find("roam.experience.tiles.loaded", in: window))
        XCTAssertNil(find("roam.experience.tiles.load", in: window))
    }

    func testClosingAndReopeningDeniedDestinationRequiresExplicitReadFromZero() async throws {
        let r = try TileDenialHostRig(), host = UIHostingController(rootView: AnyView(Text("Preparing test")))
        let window = mount(host); defer { close(window) }
        host.rootView = tiles(r)
        try await tap("roam.experience.tiles.load", in: window)
        try await waitFor("Initial private count") { self.find("roam.experience.tiles.loaded", in: window) != nil }
        r.wire.status = 403
        try await tap("roam.experience.tiles.load", in: window)
        try await waitFor("Original denied state") { self.find("roam.experience.tiles.denied", in: window) != nil }
        host.rootView = AnyView(Text("Tile memory was closed")); host.view.layoutIfNeeded()
        try await waitFor("True host removal") { self.find("roam.experience.tileMemory", in: window) == nil }
        r.wire.status = 200; r.wire.empty = true
        host.rootView = tiles(r); host.view.layoutIfNeeded()
        try await waitFor("Reopened read control") { self.find("roam.experience.tiles.load", in: window) != nil }
        XCTAssertEqual(r.wire.cursors, [0, 5], "Reopening must not silently read or resume the old cursor")
        XCTAssertNil(find("roam.experience.tiles.loaded", in: window))
        XCTAssertNil(find("roam.experience.tiles.denied", in: window))
        try await tap("roam.experience.tiles.load", in: window)
        try await waitFor("Explicit first cursor really returned an empty success") {
            r.wire.cursors == [0, 5, 0] && self.find("roam.experience.tiles.loaded", in: window) != nil
        }
        XCTAssertNil(find("roam.experience.tiles.load", in: window))
        XCTAssertNil(find("roam.experience.tiles.denied", in: window))
    }

    private func tiles(_ r: TileDenialHostRig) -> AnyView {
        // Exactly the original typed destination expression in RoamExperienceHubView.
        AnyView(NavigationStack { RoamTileMemoryView(reader: r.reader).id(r.reader.scope) }
            .environment(\.scenePhase, .active).environment(\.locale, Locale(identifier: "en_US")))
    }
    private func mount(_ host: UIHostingController<AnyView>) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.makeKeyAndVisible()
        host.loadViewIfNeeded(); host.view.layoutIfNeeded(); return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    private func waitFor(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(message); throw APIError.notConfigured
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        return find(root: window, id: id, seen: &seen)
    }
    private func find(root: NSObject, id: String, seen: inout Set<ObjectIdentifier>) -> NSObject? {
        guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
        if (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
        if let view = root as? UIView {
            for child in view.subviews { if let value = find(root: child, id: id, seen: &seen) { return value } }
        }
        if let children = root.accessibilityElements {
            for child in children {
                if let child = child as? NSObject, let value = find(root: child, id: id, seen: &seen) { return value }
            }
        }
        let count = root.accessibilityElementCount()
        if count > 0 && count < 1000 {
            for index in 0..<count {
                if let child = root.accessibilityElement(at: index) as? NSObject,
                   let value = find(root: child, id: id, seen: &seen) { return value }
            }
        }
        return nil
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        try await waitFor("The original control must exist: \(id)") { self.find(id, in: window) != nil }
        let control = try XCTUnwrap(find(id, in: window))
        if let button = control as? UIControl { button.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(control.accessibilityActivate(), "The actual tile control must activate") }
    }
}

@MainActor private final class TileDenialHostRig {
    let wire: TileDenialHostWire
    let access: RoamTileMemoryReadAccess
    let reader: RoamTileMemoryReader
    init() throws {
        let wire = TileDenialHostWire(); self.wire = wire
        let context = RuntimeDependencyContext(market: .china, baseURL: TileDenialHostWire.base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "tile-denial-host", token: "synthetic-tile-host"))
        let access = try RoamTileMemoryReadAccess(context: context, approval: .init(baseURL: context.baseURL,
            namespace: context.session.namespace, accountID: context.session.accountID, paths: [RoamTileMemoryReadRoute.path]))
        self.access = access
        reader = .init(service: .init(configuration: try .init(baseURL: context.baseURL), transport: wire),
                       current: { context }, viewerRevision: { 1 }, access: { _ in access })
    }
}
@MainActor private final class TileDenialHostWire: HTTPTransport {
    static let base = URL(string: "https://example.test/tile-denial-host")!
    var cursors: [Int] = []
    var status = 200, code = 200
    var empty = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let route = try XCTUnwrap(RoamTileMemoryReadRoute(request: request, baseURL: Self.base))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-tile-host")
        XCTAssertEqual(route.limit, 1000); cursors.append(route.afterID)
        if status != 200 || code != 200 { return (Data("{\"code\":\(code)}".utf8), status) }
        let tiles: [String] = empty ? [] : (route.afterID == 0 ? ["wx4g0ec"] : ["wx4g0ec", "wx4g0ed"])
        let body: [String: Any] = ["code": 200, "data": ["tiles": tiles,
            "nextAfterId": empty ? route.afterID : (route.afterID == 0 ? 5 : 7), "hasMore": !empty && route.afterID == 0]]
        return (try JSONSerialization.data(withJSONObject: body), 200)
    }
}
