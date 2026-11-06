import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Actual Browser entry consumers with the original tools reader and local history.
/// The destination is a read-only probe, not a replacement topic service or writer.
@MainActor final class RoamAnniversaryHostRestorationTests: XCTestCase {
    func testBrowserPassportReadFailureRetryExactTopicAndBack() async throws {
        let r = try AnniversaryHostRig(); r.wire.status = 503
        let window = mount(r); defer { close(window) }
        try await selectPassport(in: window)
        XCTAssertTrue(r.wire.requests.isEmpty)
        try await tap("roam.tools.anniversary.open", in: window)
        try await reveal("roam.experience.retry", in: window)
        XCTAssertEqual(r.wire.requests.count, 1); XCTAssertTrue(r.topics.isEmpty)
        r.wire.status = 200
        try await tap("roam.experience.retry", in: window)
        try await reveal("roam.tools.anniversary.row", in: window)
        try await openRouteAndReturn(in: window, rig: r, initialRequests: 2)
    }

    func testBrowserMenuHubForwardsTheSameOriginalTopicDestination() async throws {
        let r = try AnniversaryHostRig(), window = mount(r)
        defer { close(window) }
        try await tap("roam.toolbar.more", in: window)
        try await tap("roam.experience.open", in: window)
        try await reveal("roam.experience.hub", in: window)
        XCTAssertTrue(r.wire.requests.isEmpty)
        try await tap("roam.tools.anniversary.open", in: window)
        try await reveal("roam.tools.anniversary.row", in: window)
        try await openRouteAndReturn(in: window, rig: r, initialRequests: 1)
    }

    func testUninjectedBrowserKeepsSuccessfulHistoryCardButRouteUnavailable() async throws {
        let r = try AnniversaryHostRig(), window = mount(r, includeDestination: false)
        defer { close(window) }
        try await selectPassport(in: window)
        try await tap("roam.tools.anniversary.open", in: window)
        try await reveal("roam.tools.anniversary.routeUnavailable", in: window)
        XCTAssertNotNil(find("roam.tools.anniversary.row", in: window))
        XCTAssertNil(find("roam.tools.anniversary.openRoute", in: window))
        XCTAssertEqual(r.wire.requests.count, 1); XCTAssertTrue(r.topics.isEmpty)
        XCTAssertEqual(r.storage.writes, 0)
    }

    func testRestoredNavigationDoesNotGrantARevokedToolsReader() async throws {
        let r = try AnniversaryHostRig(), window = mount(r)
        defer { close(window) }
        try await selectPassport(in: window)
        r.access.revoke(); XCTAssertFalse(r.tools.isConfigured)
        try await tap("roam.tools.anniversary.open", in: window)
        try await reveal("roam.tools.anniversary.error", in: window)
        XCTAssertTrue(r.wire.requests.isEmpty); XCTAssertTrue(r.topics.isEmpty)
        XCTAssertNil(find("roam.tools.anniversary.row", in: window))
        XCTAssertNil(find("roam.tools.anniversary.openRoute", in: window))
        XCTAssertNil(find("roam.experience.retry", in: window))
        XCTAssertEqual(r.storage.writes, 0)
    }

    private func openRouteAndReturn(in window: UIWindow, rig r: AnniversaryHostRig, initialRequests: Int) async throws {
        XCTAssertEqual(r.wire.requests.count, initialRequests)
        try await tap("roam.tools.anniversary.openRoute", in: window)
        try await reveal("anniversary.host.topic.7001", in: window)
        XCTAssertFalse(r.topics.isEmpty)
        XCTAssertTrue(r.topics.allSatisfy { $0 == "7001" }, "Use the exact topicID, never memoryID 31")
        XCTAssertEqual(r.wire.requests.count, initialRequests, "Opening the supplied destination is not a new archive read")
        let navigation = try XCTUnwrap(navigation(in: window.rootViewController))
        XCTAssertNotNil(navigation.popViewController(animated: false))
        try await waitFor("Original return reloads the archive") {
            r.wire.requests.count == initialRequests + 1 && self.find("roam.tools.anniversary.row", in: window) != nil
        }
        XCTAssertNil(find("anniversary.host.topic.7001", in: window))
        XCTAssertEqual(r.storage.writes, 0)
        XCTAssertTrue(r.wire.requests.allSatisfy {
            $0.httpMethod == "GET" && $0.url?.lastPathComponent == "exploration-anniversary"
                && $0.value(forHTTPHeaderField: "Authorization") == "synthetic-anniversary-host"
        })
    }

    private func mount(_ r: AnniversaryHostRig, includeDestination: Bool = true) -> UIWindow {
        let destination: ((String) -> AnyView)? = includeDestination ? { topicID in
            r.topics.append(topicID)
            return AnyView(Text("Original topic destination: " + topicID)
                .accessibilityIdentifier("anniversary.host.topic." + topicID))
        } : nil
        let host = UIHostingController(rootView: RoamBrowserView(reader: r.map, experienceReader: r.history,
            toolsReader: r.tools, passportToolsReader: r.tools, anniversaryRouteDestination: destination)
            .environment(\.locale, Locale(identifier: "en_US")))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 1100))
        window.rootViewController = host; window.makeKeyAndVisible()
        host.loadViewIfNeeded(); host.view.layoutIfNeeded(); return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    private func selectPassport(in window: UIWindow) async throws {
        try await waitFor("Original tab picker") { self.segment(in: window) != nil }
        let picker = try XCTUnwrap(segment(in: window))
        XCTAssertEqual(picker.numberOfSegments, 2)
        picker.selectedSegmentIndex = 1; picker.sendActions(for: .valueChanged)
        try await reveal("roam.home.passport", in: window)
    }
    private func segment(in view: UIView) -> UISegmentedControl? {
        if let picker = view as? UISegmentedControl { return picker }
        for child in view.subviews { if let picker = segment(in: child) { return picker } }
        return nil
    }
    private func waitFor(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(message); throw APIError.notConfigured
    }
    private func reveal(_ id: String, in window: UIWindow) async throws {
        for _ in 0..<35 {
            if find(id, in: window) != nil { return }
            scroll(window); try await Task.sleep(nanoseconds: 40_000_000)
        }
        XCTFail("Original control not found: " + id); throw APIError.notConfigured
    }
    private func scroll(_ view: UIView) {
        if let scroll = view as? UIScrollView {
            let maxY = max(-scroll.adjustedContentInset.top,
                scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            if scroll.contentOffset.y < maxY {
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x,
                    y: min(maxY, scroll.contentOffset.y + max(160, scroll.bounds.height * 0.6))), animated: false)
                scroll.layoutIfNeeded()
            }
        }
        for child in view.subviews { scroll(child) }
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        try await reveal(id, in: window)
        let control = try XCTUnwrap(find(id, in: window))
        if let control = control as? UIControl { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(control.accessibilityActivate(), "Actual native control must activate") }
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ root: NSObject) -> NSObject? {
            guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
            if (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
            if let view = root as? UIView {
                for child in view.subviews { if let found = visit(child) { return found } }
            }
            if let children = root.accessibilityElements {
                for child in children { if let child = child as? NSObject, let found = visit(child) { return found } }
            }
            let count = root.accessibilityElementCount()
            if count > 0 && count < 1000 {
                for i in 0..<count {
                    if let child = root.accessibilityElement(at: i) as? NSObject, let found = visit(child) { return found }
                }
            }
            return nil
        }
        if let found = visit(window) { return found }
        // UIKit may host the original toolbar menu in another window of this scene.
        for sibling in window.windowScene?.windows ?? [] { if let found = visit(sibling) { return found } }
        return nil
    }
    private func navigation(in controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let navigation = controller as? UINavigationController { return navigation }
        for child in controller.children { if let value = navigation(in: child) { return value } }
        return nil
    }
}

@MainActor private final class AnniversaryHostRig {
    let map: RoamSessionReader
    let history: RoamExperienceSessionReader
    let tools: RoamPassportToolsSessionReader
    let access: RoamPrivateToolsAccess
    let storage: AnniversaryHostStorage
    let wire: AnniversaryHostWire
    var topics: [String] = []
    init() throws {
        let storage = AnniversaryHostStorage(), wire = AnniversaryHostWire()
        self.storage = storage; self.wire = wire
        let base = URL(string: "https://example.test/anniversary-host")!
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "anniversary-host", token: "synthetic-anniversary-host"))
        let access = try RoamPrivateToolsAccess(context: context, approval: .init(baseURL: base,
            namespace: context.session.namespace, accountID: context.session.accountID, paths: Set(RoamPassportToolsService.paths)))
        self.access = access
        let scope = try RoamHistoryScope(market: "cn", deployment: base, accountID: 7, namespace: context.session.namespace)
        let session = try RoamExperienceSession(scope: scope, epoch: 1, token: "synthetic-anniversary-host")
        history = .init(service: nil, store: .init(storage: storage, currentScope: { scope }), currentSession: { session })
        tools = .init(service: .init(configuration: try .init(baseURL: base), transport: wire),
                      current: { context }, access: { _ in access })
        // The map stays unconfigured. This navigation never contacts MapKit/place services.
        map = .init(service: nil, currentSession: { nil }, searchArea: { nil })
    }
}
@MainActor private final class AnniversaryHostStorage: RoamHistoryDataStoring {
    var writes = 0
    func read(key: String) throws -> Data? { nil }
    func write(_ data: Data, key: String) throws { writes += 1; XCTFail("No history writer belongs to this navigation") }
}
@MainActor private final class AnniversaryHostWire: HTTPTransport {
    var requests: [URLRequest] = []
    var status = 200
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard request.httpMethod == "GET", request.url?.lastPathComponent == "exploration-anniversary" else {
            XCTFail("Unexpected route or write"); throw APIError.notConfigured
        }
        if status != 200 { return (Data(#"{"code":503}"#.utf8), status) }
        let fields = Dictionary(uniqueKeysWithValues:
            (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let ms = Int64(Date().timeIntervalSince1970 * 1000)
        let today = RoamShanghaiCalendar.day(atMilliseconds: ms)
        let month = Int(fields["month"] ?? "") ?? today.month, day = Int(fields["day"] ?? "") ?? today.day
        var year = today.year - 1
        if month == 2 && day == 29 {
            while !((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) { year -= 1 }
        }
        let completed = String(format: "%04d-%02d-%02d 12:34:56.000", year, month, day)
        let data: [String: Any] = ["month": month, "day": day, "referenceYear": today.year,
            "timeZone": "Asia/Shanghai", "asOfMs": ms, "items": [["id": "31", "topicId": "7001", "title": "Saved route",
                "completedAt": completed, "year": year, "yearsAgo": today.year - year]],
            "hasMore": false, "nextCursor": NSNull(), "leapDayRule": "EXACT_MONTH_DAY_ONLY",
            "coverage": "RECORDED_OWN_COMPLETED_SESSIONS_WITH_CURRENT_VISIBLE_ROUTE", "metadataMode": "CURRENT_ROUTE_METADATA"]
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
}
