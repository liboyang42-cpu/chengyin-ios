import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Exercises the real Hub → History → existing tools NavigationLinks. All storage
/// and HTTP are new in-memory test doubles; no fixture, remote or writer is changed.
@MainActor final class RoamHistoryHubToolsTests: XCTestCase {
    private let anniversary = "roamSub.w208.history.tool.anniversary"
    private let recap = "roamSub.w208.history.tool.recap"
    private let export = "roamSub.w208.history.tool.export"

    func testHubHistoryForwardsOriginalToolsThroughReadFailureRetryAndBack() async throws {
        let r = try HubHistoryToolsRig(hasRecord: true); r.wire.failAnniversary = true
        let window = mount(r, includeTools: true, includePrivate: true)
        defer { close(window) }
        try await openHistory(in: window, rig: r)
        for id in [anniversary, recap, export] { try await reveal(id, in: window) }
        XCTAssertTrue(r.wire.requests.isEmpty, "History must not eagerly read any remote tool")
        try await tap(anniversary, in: window)
        try await waitFor("The original anniversary request fails") { r.wire.anniversaryCalls == 1 }
        try await reveal("roam.experience.retry", in: window)
        r.wire.failAnniversary = false
        try await tap("roam.experience.retry", in: window)
        try await waitFor("The original reader retries successfully") {
            r.wire.anniversaryCalls == 2 && self.find("roam.tools.anniversary.empty", in: window) != nil
        }
        try pop(in: window)
        try await reveal(anniversary, in: window)
        XCTAssertEqual(r.wire.anniversaryCalls, 2); XCTAssertEqual(r.wire.monthlyCalls, 0)
        XCTAssertTrue(r.wire.requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == "synthetic-hub-tools" })
        XCTAssertEqual(r.storage.writes, 0)
    }

    func testEmptyHistoryStillOffersOriginalMonthlyRecapAndReturns() async throws {
        let r = try HubHistoryToolsRig(hasRecord: false)
        let window = mount(r, includeTools: true, includePrivate: false)
        defer { close(window) }
        try await openHistory(in: window, rig: r)
        try await reveal(recap, in: window)
        XCTAssertNil(find(export, in: window)); XCTAssertTrue(r.wire.requests.isEmpty)
        try await tap(recap, in: window)
        try await waitFor("Original monthly recap returns a successful empty page") {
            r.wire.monthlyCalls == 1 && self.find("roam.tools.recap.empty", in: window) != nil
        }
        XCTAssertEqual(r.wire.anniversaryCalls, 0)
        try pop(in: window); try await reveal(recap, in: window)
        XCTAssertEqual(r.wire.monthlyCalls, 1); XCTAssertEqual(r.storage.writes, 0)
    }

    func testPrivateExportUsesOriginalUnconfiguredReaderWithoutGrantOrAutomaticPrepare() async throws {
        let r = try HubHistoryToolsRig(hasRecord: false)
        XCTAssertFalse(r.privateTools.isConfigured); XCTAssertFalse(r.privateTools.allowsWrites)
        let window = mount(r, includeTools: true, includePrivate: true)
        defer { close(window) }
        try await openHistory(in: window, rig: r); try await tap(export, in: window)
        try await reveal("roam.export.prepare", in: window)
        XCTAssertTrue(r.wire.requests.isEmpty)
        try await tap("roam.export.prepare", in: window)
        try await waitFor("The original missing export approval remains closed") {
            self.find("roam.private.issue", in: window) != nil
        }
        XCTAssertTrue(r.wire.requests.isEmpty); XCTAssertFalse(r.privateTools.allowsWrites)
        XCTAssertNil(find("roam.export.share", in: window)); XCTAssertNil(find("roam.export.save", in: window))
        try pop(in: window); try await reveal(export, in: window)
        XCTAssertTrue(r.wire.requests.isEmpty); XCTAssertEqual(r.storage.writes, 0)
    }

    func testNilToolsKeepsHistoryToolRowHiddenEvenWithPrivateReader() async throws {
        let r = try HubHistoryToolsRig(hasRecord: false)
        let window = mount(r, includeTools: false, includePrivate: true)
        defer { close(window) }
        try await openHistory(in: window, rig: r)
        try await reveal("roam.experience.history.empty", in: window)
        for id in [anniversary, recap, export] { XCTAssertNil(find(id, in: window)) }
        XCTAssertTrue(r.wire.requests.isEmpty); XCTAssertEqual(r.storage.writes, 0)
    }

    func testNilPrivateToolsDoesNotInventAnExportDestination() async throws {
        let r = try HubHistoryToolsRig(hasRecord: true)
        let window = mount(r, includeTools: true, includePrivate: false)
        defer { close(window) }
        try await openHistory(in: window, rig: r)
        try await reveal(anniversary, in: window); try await reveal(recap, in: window)
        XCTAssertNil(find(export, in: window)); XCTAssertTrue(r.wire.requests.isEmpty)
        XCTAssertEqual(r.storage.writes, 0)
    }

    func testRevokedOriginalToolsReaderCannotDispatchFromHistoryLink() async throws {
        let r = try HubHistoryToolsRig(hasRecord: true)
        let window = mount(r, includeTools: true, includePrivate: true)
        defer { close(window) }
        try await openHistory(in: window, rig: r); try await reveal(anniversary, in: window)
        r.access.revoke(); XCTAssertFalse(r.tools.isConfigured)
        try await tap(anniversary, in: window)
        try await waitFor("The original revoked reader shows its unavailable state") {
            self.find("roam.tools.anniversary.error", in: window) != nil
        }
        XCTAssertTrue(r.wire.requests.isEmpty)
        XCTAssertNil(find("roam.experience.retry", in: window))
        XCTAssertFalse(r.privateTools.allowsWrites); XCTAssertEqual(r.storage.writes, 0)
    }

    private func mount(_ r: HubHistoryToolsRig, includeTools: Bool, includePrivate: Bool) -> UIWindow {
        let tools: (any RoamPassportToolsReading)? = includeTools ? r.tools : nil
        let privateTools: (any RoamPrivateToolsServing)? = includePrivate ? r.privateTools : nil
        let host = UIHostingController(rootView: NavigationStack {
            RoamExperienceHubView(reader: r.reader, toolsReader: tools, privateToolsReader: privateTools)
        }.environment(\.locale, Locale(identifier: "en_US")))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host; window.makeKeyAndVisible()
        host.loadViewIfNeeded(); host.view.layoutIfNeeded(); return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    private func openHistory(in window: UIWindow, rig: HubHistoryToolsRig) async throws {
        try await reveal("roam.experience.history.open", in: window)
        let reads = rig.storage.reads
        try await tap("roam.experience.history.open", in: window)
        try await waitFor("The normal history destination reads the original local store") { rig.storage.reads > reads }
    }
    private func waitFor(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<150 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(message); throw APIError.notConfigured
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        return find(id, root: window, seen: &seen)
    }
    private func find(_ id: String, root: NSObject, seen: inout Set<ObjectIdentifier>) -> NSObject? {
        guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
        if (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
        if let view = root as? UIView {
            for child in view.subviews { if let found = find(id, root: child, seen: &seen) { return found } }
        }
        if let children = root.accessibilityElements {
            for child in children {
                if let child = child as? NSObject, let found = find(id, root: child, seen: &seen) { return found }
            }
        }
        let count = root.accessibilityElementCount()
        if count > 0 && count < 1000 {
            for index in 0..<count {
                if let child = root.accessibilityElement(at: index) as? NSObject,
                   let found = find(id, root: child, seen: &seen) { return found }
            }
        }
        return nil
    }
    private func scrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, !scroll.isHidden, scroll.contentSize.height > scroll.bounds.height { return scroll }
        for child in view.subviews { if let scroll = scrollView(in: child) { return scroll } }
        return nil
    }
    private func reveal(_ id: String, in window: UIWindow) async throws {
        for _ in 0..<20 {
            if find(id, in: window) != nil { return }
            if let scroll = scrollView(in: window) {
                let bottom = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(bottom, scroll.contentOffset.y + 180)), animated: false)
                scroll.layoutIfNeeded()
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("The original navigation must expose \(id)"); throw APIError.notConfigured
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        try await reveal(id, in: window)
        let control = try XCTUnwrap(find(id, in: window))
        if let button = control as? UIControl { button.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(control.accessibilityActivate(), "The real SwiftUI control must activate") }
    }
    private func navigation(in controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let navigation = controller as? UINavigationController { return navigation }
        for child in controller.children { if let navigation = navigation(in: child) { return navigation } }
        return nil
    }
    private func pop(in window: UIWindow) throws {
        let navigation = try XCTUnwrap(navigation(in: window.rootViewController))
        XCTAssertNotNil(navigation.popViewController(animated: false))
    }
}

@MainActor private final class HubHistoryToolsRig {
    let context: RuntimeDependencyContext
    let access: RoamPrivateToolsAccess
    let storage: HubHistoryToolsStorage
    let wire: HubHistoryToolsWire
    let reader: RoamExperienceSessionReader
    let tools: RoamPassportToolsSessionReader
    let privateTools: RoamPrivateToolsSessionReader
    init(hasRecord: Bool) throws {
        let storage = HubHistoryToolsStorage(), wire = HubHistoryToolsWire()
        self.storage = storage; self.wire = wire
        let base = try XCTUnwrap(URL(string: "https://example.test/hub"))
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "hub-history-tools", token: "synthetic-hub-tools"))
        self.context = context
        let approval = try OperationEndpointApproval(baseURL: base, namespace: context.session.namespace,
            accountID: context.session.accountID, paths: Set(RoamPassportToolsService.paths))
        let access = try RoamPrivateToolsAccess(context: context, approval: approval); self.access = access
        let scope = try RoamHistoryScope(market: "cn", deployment: base, accountID: 7, namespace: context.session.namespace)
        let session = try RoamExperienceSession(scope: scope, epoch: 1, token: "synthetic-hub-tools")
        let store = RoamHistoryStore(storage: storage, currentScope: { scope })
        reader = .init(service: nil, store: store, currentSession: { session })
        tools = .init(service: .init(configuration: try .init(baseURL: base), transport: wire),
                      current: { context }, access: { _ in access })
        // Export exists as an owner-only read surface but receives no approval. No live journal.
        privateTools = .init(service: .init(configuration: try .init(baseURL: base), transport: wire),
                             current: { context }, access: { _ in nil }, journal: nil)
        let records = hasRecord ? [try JSONDecoder().decode(RoamHistoryRecord.self,
            from: Data(#"{"ts":1700000000000,"distance":1,"shops":1}"#.utf8))] : []
        struct Seed: Encodable { let version = 1; let scope: RoamHistoryScope; let records: [RoamHistoryRecord] }
        storage.data = try JSONEncoder().encode(Seed(scope: scope, records: records))
    }
}
@MainActor private final class HubHistoryToolsStorage: RoamHistoryDataStoring {
    var data: Data?; var reads = 0; var writes = 0
    func read(key: String) throws -> Data? { reads += 1; return data }
    func write(_ data: Data, key: String) throws { writes += 1; XCTFail("No history writer belongs to this navigation") }
}
@MainActor private final class HubHistoryToolsWire: HTTPTransport {
    var requests: [URLRequest] = []
    var failAnniversary = false
    var anniversaryCalls: Int { requests.filter { $0.url?.lastPathComponent == "exploration-anniversary" }.count }
    var monthlyCalls: Int { requests.filter { $0.url?.lastPathComponent == "monthly-recap" }.count }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard request.httpMethod == "GET", let url = request.url else { XCTFail("No write or export request is approved"); throw APIError.notConfigured }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let fields = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        let now = Date(), ms = Int64(Date().timeIntervalSince1970 * 1000)
        let today = RoamShanghaiCalendar.day(atMilliseconds: ms)
        let json: [String: Any]
        switch url.lastPathComponent {
        case "exploration-anniversary":
            if failAnniversary { return (Data(#"{"code":503}"#.utf8), 503) }
            json = ["month": Int(fields["month"] ?? "") ?? today.month, "day": Int(fields["day"] ?? "") ?? today.day,
                "referenceYear": today.year, "timeZone": "Asia/Shanghai", "asOfMs": ms, "items": [], "hasMore": false,
                "nextCursor": NSNull(), "leapDayRule": "EXACT_MONTH_DAY_ONLY",
                "coverage": "RECORDED_OWN_COMPLETED_SESSIONS_WITH_CURRENT_VISIBLE_ROUTE", "metadataMode": "CURRENT_ROUTE_METADATA"]
        case "monthly-recap":
            json = ["month": fields["month"] ?? RoamShanghaiCalendar.month(now: now), "kind": fields["kind"] ?? "routes",
                "timeZone": "Asia/Shanghai", "generatedAtMs": ms, "counts": ["routes": 0, "places": 0, "stamps": 0],
                "items": [], "hasMore": false, "nextBeforeId": NSNull()]
        default: XCTFail("Unexpected tool endpoint"); throw APIError.notConfigured
        }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": json]), 200)
    }
}
