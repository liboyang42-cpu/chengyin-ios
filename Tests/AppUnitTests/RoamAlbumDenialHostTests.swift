import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Actual metadata album, its original page button and original denied/failed UI.
/// The only transport is in memory. The read-only scope forbids pictures and capture.
@MainActor final class RoamAlbumDenialHostTests: XCTestCase {
    func testHTTPAndBusiness403RemoveOldCardsTotalAndLoadMoreWithoutEmptyAlbum() async throws {
        for result in [(403, 200), (200, 403)] {
            let r = try AlbumDenialHostRig(), host = UIHostingController(rootView: AnyView(Text("Preparing test")))
            let window = mount(host); defer { close(window) }
            host.rootView = album(r)
            try await waitFor("The real metadata album shows page one") {
                r.wire.pages == [1] && self.find("roam.experience.album.more", in: window) != nil
            }
            XCTAssertNotNil(find("roam.experience.album.stamp", in: window))
            XCTAssertNotNil(find("roam.experience.album.total", in: window))
            r.wire.status = result.0; r.wire.code = result.1
            try await tap("roam.experience.album.more", in: window)
            try await waitFor("Permission refusal must replace private rows") {
                self.find("roam.experience.album.denied", in: window) != nil
            }
            for id in ["roam.experience.album.stamp", "roam.experience.album.total", "roam.experience.album.more",
                       "roam.experience.album.empty", "roam.experience.retry"] {
                XCTAssertNil(find(id, in: window), id)
            }
            XCTAssertEqual(r.wire.pages, [1, 2]); XCTAssertTrue(r.reader.isConfigured)
            // The response refuses the read, not the separately issued object. No grant is mutated.
            XCTAssertFalse(r.access.isRevoked)
        }
    }

    func test503KeepsConfirmedMetadataAndOriginalRetryReadsSamePage() async throws {
        let r = try AlbumDenialHostRig(), host = UIHostingController(rootView: AnyView(Text("Preparing test")))
        let window = mount(host); defer { close(window) }
        host.rootView = album(r)
        try await waitFor("Initial page") { self.find("roam.experience.album.more", in: window) != nil }
        r.wire.status = 503; r.wire.code = 403
        try await tap("roam.experience.album.more", in: window)
        try await waitFor("Transient error retains the retry control") { self.find("roam.experience.retry", in: window) != nil }
        XCTAssertNotNil(find("roam.experience.album.stamp", in: window))
        XCTAssertNotNil(find("roam.experience.album.total", in: window))
        XCTAssertNil(find("roam.experience.album.denied", in: window))
        r.wire.status = 200; r.wire.code = 200
        try await tap("roam.experience.retry", in: window)
        try await waitFor("Same continuation succeeds") {
            r.wire.pages == [1, 2, 2] && self.find("roam.experience.retry", in: window) == nil
        }
        XCTAssertNotNil(find("roam.experience.album.stamp", in: window))
        XCTAssertNil(find("roam.experience.album.more", in: window))
    }

    func testLeavingAndReopeningAfter403StartsFreshMetadataAtPageOne() async throws {
        let r = try AlbumDenialHostRig(), host = UIHostingController(rootView: AnyView(Text("Preparing test")))
        let window = mount(host); defer { close(window) }
        host.rootView = album(r)
        try await waitFor("Original page") { self.find("roam.experience.album.more", in: window) != nil }
        r.wire.status = 403
        try await tap("roam.experience.album.more", in: window)
        try await waitFor("Denied page") { self.find("roam.experience.album.denied", in: window) != nil }
        host.rootView = AnyView(Text("The album was closed")); host.view.layoutIfNeeded()
        try await waitFor("Original album removed") { self.find("roam.experience.album", in: window) == nil }
        r.wire.status = 200; r.wire.replacement = true
        host.rootView = album(r); host.view.layoutIfNeeded()
        try await waitFor("Reopened original screen reads new first page") {
            r.wire.pages == [1, 2, 1] && self.find("roam.experience.album.more", in: window) != nil
        }
        XCTAssertNotNil(find("roam.experience.album.stamp", in: window))
        XCTAssertNil(find("roam.experience.album.denied", in: window))
        XCTAssertNil(findLabel("Original metadata", in: window))
        XCTAssertNotNil(findLabel("Replacement metadata", in: window))
    }

    private func album(_ r: AlbumDenialHostRig) -> AnyView {
        AnyView(NavigationStack { RoamAlbumMetadataDestination(reader: r.reader) }
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
        return find(root: window, id: id, label: nil, seen: &seen)
    }
    private func findLabel(_ label: String, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        return find(root: window, id: nil, label: label, seen: &seen)
    }
    private func find(root: NSObject, id: String?, label: String?, seen: inout Set<ObjectIdentifier>) -> NSObject? {
        guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
        if let id, (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
        if let label, root.accessibilityLabel?.contains(label) == true { return root }
        if let view = root as? UIView {
            for child in view.subviews { if let value = find(root: child, id: id, label: label, seen: &seen) { return value } }
        }
        if let children = root.accessibilityElements {
            for child in children {
                if let child = child as? NSObject, let value = find(root: child, id: id, label: label, seen: &seen) { return value }
            }
        }
        let count = root.accessibilityElementCount()
        if count > 0 && count < 1000 {
            for index in 0..<count {
                if let child = root.accessibilityElement(at: index) as? NSObject,
                   let value = find(root: child, id: id, label: label, seen: &seen) { return value }
            }
        }
        return nil
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        try await waitFor("The original control must exist: \(id)") { self.find(id, in: window) != nil }
        let control = try XCTUnwrap(find(id, in: window))
        if let button = control as? UIControl { button.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(control.accessibilityActivate(), "The actual album control must activate") }
    }
}

@MainActor private final class AlbumDenialHostRig {
    let wire: AlbumDenialHostWire
    let access: RoamAlbumMetadataReadAccess
    let reader: RoamAlbumMetadataReader
    init() throws {
        let wire = AlbumDenialHostWire(); self.wire = wire
        let context = RuntimeDependencyContext(market: .china, baseURL: AlbumDenialHostWire.base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "album-denial-host", token: "synthetic-album-host"))
        let access = try RoamAlbumMetadataReadAccess(context: context, approval: .init(baseURL: context.baseURL,
            namespace: context.session.namespace, accountID: context.session.accountID, paths: [RoamAlbumMetadataReadRoute.path]))
        self.access = access
        reader = .init(service: .init(configuration: try .init(baseURL: context.baseURL), transport: wire),
                       current: { context }, viewerRevision: { 1 }, access: { _ in access })
    }
}
@MainActor private final class AlbumDenialHostWire: HTTPTransport {
    static let base = URL(string: "https://example.test/album-denial-host")!
    var pages: [Int] = []
    var status = 200, code = 200
    var replacement = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let route = try XCTUnwrap(RoamAlbumMetadataReadRoute(request: request, baseURL: Self.base))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-album-host")
        pages.append(route.page)
        if status != 200 || code != 200 { return (Data("{\"code\":\(code)}".utf8), status) }
        let body: [String: Any] = ["code": 200, "data": ["list": [["id": route.page + (replacement ? 100 : 0),
            "checkState": 0, "caption": replacement ? "Replacement metadata" : "Original metadata"]],
            "total": 40, "pageNum": route.page, "pageSize": route.pageSize]]
        return (try JSONSerialization.data(withJSONObject: body), 200)
    }
}
