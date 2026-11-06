import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Original History entry consumers plus restored anniversary read/return state.
/// In-memory HTTP and local history only; the topic destination is a read-only probe.
@MainActor final class RoamAnniversaryHistoryRecoveryTests: XCTestCase {
    private enum Entry: CaseIterable { case hub, passport }
    private let tool = "roamSub.w208.history.tool.anniversary"

    func testBothHistoryEntriesForwardOriginalTopicForEmptyAndNonEmptyLocalHistory() async throws {
        for entry in Entry.allCases {
            for hasRecord in [false, true] {
                let r = try AnniversaryHistoryRig(hasRecord: hasRecord), window = mount(r, entry: entry)
                defer { close(window) }
                try await openHistory(entry, in: window)
                XCTAssertTrue(r.wire.requests.isEmpty)
                try await tap(tool, in: window)
                try await reveal("roam.tools.anniversary.row", in: window)
                try await tap("roam.tools.anniversary.openRoute", in: window)
                try await reveal("anniversary.history.topic", in: window)
                XCTAssertFalse(r.topics.isEmpty)
                XCTAssertTrue(r.topics.allSatisfy { $0 == "7100" }, "Use topic ID 7100, not memory ID 100")
                try pop(in: window)
                try await waitFor("Original return refreshes once") {
                    r.wire.requests.count == 2 && self.find("roam.tools.anniversary.row", in: window) != nil
                }
                XCTAssertNil(find("anniversary.history.topic", in: window))
                XCTAssertEqual(r.storage.writes, 0)
            }
        }
    }

    func testHistoryWithoutInjectedDestinationKeepsExistingUnavailableState() async throws {
        let r = try AnniversaryHistoryRig(hasRecord: false), window = mount(r, entry: .hub, includeDestination: false)
        defer { close(window) }
        try await openHistory(.hub, in: window); try await tap(tool, in: window)
        try await reveal("roam.tools.anniversary.routeUnavailable", in: window)
        XCTAssertNotNil(find("roam.tools.anniversary.row", in: window))
        XCTAssertNil(find("roam.tools.anniversary.openRoute", in: window))
        XCTAssertEqual(r.wire.requests.count, 1); XCTAssertTrue(r.topics.isEmpty)
    }

    func testMissingToolsReaderStillHidesHistoryToolsWithoutInventingGrant() async throws {
        let r = try AnniversaryHistoryRig(hasRecord: false), window = mount(r, entry: .passport, includeTools: false)
        defer { close(window) }
        try await openHistory(.passport, in: window)
        try await reveal("roam.experience.history.empty", in: window)
        XCTAssertNil(find(tool, in: window)); XCTAssertTrue(r.wire.requests.isEmpty)
        XCTAssertTrue(r.topics.isEmpty); XCTAssertEqual(r.storage.writes, 0)
    }

    func testHistoryRestorationCannotReadWithRevokedOriginalToolsAccess() async throws {
        let r = try AnniversaryHistoryRig(hasRecord: true), window = mount(r, entry: .hub)
        defer { close(window) }
        try await openHistory(.hub, in: window)
        r.access.revoke(); XCTAssertFalse(r.tools.isConfigured)
        try await tap(tool, in: window)
        try await reveal("roam.tools.anniversary.error", in: window)
        XCTAssertTrue(r.wire.requests.isEmpty); XCTAssertTrue(r.topics.isEmpty)
        XCTAssertNil(find("roam.tools.anniversary.row", in: window))
        XCTAssertNil(find("roam.tools.anniversary.openRoute", in: window))
        XCTAssertNil(find("roam.experience.retry", in: window))
    }

    func testTwoPageReturnFailureKeepsOldRowsThenRetriesSameDayAndLoadedDepthAtomically() async throws {
        let r = try AnniversaryHistoryRig(hasRecord: false); r.wire.twoPages = true
        let window = mount(r, entry: .hub); defer { close(window) }
        try await openHistory(.hub, in: window); try await tap(tool, in: window)
        try await tap("roam.tools.anniversary.more", in: window)
        try await waitFor("Two confirmed pages") { r.wire.requests.count == 2 }
        try await tap("roam.tools.anniversary.openRoute", in: window)
        try await reveal("anniversary.history.topic", in: window)
        r.wire.version = "Fresh"; r.wire.failContinuation = true
        try pop(in: window)
        try await reveal("roam.experience.retry", in: window)
        XCTAssertEqual(r.wire.cursors, [nil, "page_a", nil, "page_a"])
        XCTAssertTrue(r.wire.days.dropFirst().allSatisfy { $0 == r.wire.confirmedDay })
        XCTAssertNotNil(find("roam.tools.anniversary.row", in: window), "Failure cannot erase confirmed private history")
        XCTAssertNil(findLabel("Fresh", in: window), "A first successful refresh page cannot partially replace old rows")
        r.wire.failContinuation = false
        try await tap("roam.experience.retry", in: window)
        try await waitFor("Both refresh pages succeed") {
            r.wire.requests.count == 6 && self.find("roam.experience.retry", in: window) == nil
        }
        XCTAssertEqual(r.wire.cursors, [nil, "page_a", nil, "page_a", nil, "page_a"])
        XCTAssertTrue(r.wire.days.dropFirst().allSatisfy { $0 == r.wire.confirmedDay })
        XCTAssertNil(find("roam.tools.anniversary.more", in: window))
        XCTAssertEqual(r.storage.writes, 0)
    }

    func testRevocationWhileTopicIsOpenRetiresOriginalRouteAndPrivateRowsWithoutNewRead() async throws {
        let r = try AnniversaryHistoryRig(hasRecord: false), window = mount(r, entry: .passport)
        defer { close(window) }
        try await openHistory(.passport, in: window); try await tap(tool, in: window)
        try await tap("roam.tools.anniversary.openRoute", in: window)
        try await reveal("anniversary.history.topic", in: window)
        let reads = r.wire.requests.count
        r.access.revoke()
        try await waitFor("The old route no longer shows its destination") {
            self.find("anniversary.history.topic", in: window) == nil
        }
        XCTAssertNil(find("roam.tools.anniversary.row", in: window))
        XCTAssertEqual(r.wire.requests.count, reads)
        XCTAssertEqual(r.storage.writes, 0)
    }

    private func mount(_ r: AnniversaryHistoryRig, entry: Entry, includeDestination: Bool = true,
                       includeTools: Bool = true) -> UIWindow {
        let route: ((String) -> AnyView)? = includeDestination ? { topic in
            r.topics.append(topic)
            return AnyView(Text("Original topic: " + topic).accessibilityIdentifier("anniversary.history.topic"))
        } : nil
        let tools: (any RoamPassportToolsReading)? = includeTools ? r.tools : nil
        let host = UIHostingController(rootView: NavigationStack {
            switch entry {
            case .hub:
                RoamExperienceHubView(reader: r.history, toolsReader: tools, anniversaryRouteDestination: route)
            case .passport:
                RoamHomePassportView(reader: r.history, toolsReader: tools, anniversaryRouteDestination: route)
            }
        }.environment(\.locale, Locale(identifier: "en_US")).environment(\.scenePhase, .active))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 1100))
        window.rootViewController = host; window.makeKeyAndVisible()
        host.loadViewIfNeeded(); host.view.layoutIfNeeded(); return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    private func openHistory(_ entry: Entry, in window: UIWindow) async throws {
        try await tap(entry == .hub ? "roam.experience.history.open" : "roam.home.passport.tile.history", in: window)
        try await reveal("roam.experience.history", in: window)
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
        else { XCTAssertTrue(control.accessibilityActivate(), "Original control must activate") }
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? { search(window, id: id) }
    private func findLabel(_ text: String, in window: UIWindow) -> NSObject? { search(window, text: text) }
    private func search(_ window: UIWindow, id: String? = nil, text: String? = nil) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ root: NSObject) -> NSObject? {
            guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
            if let id, (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
            if let text, root.accessibilityLabel?.contains(text) == true { return root }
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
        return visit(window)
    }
    private func navigation(in controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let navigation = controller as? UINavigationController { return navigation }
        for child in controller.children { if let value = navigation(in: child) { return value } }
        return nil
    }
    private func pop(in window: UIWindow) throws {
        let navigation = try XCTUnwrap(navigation(in: window.rootViewController))
        XCTAssertNotNil(navigation.popViewController(animated: false))
    }
}

@MainActor private final class AnniversaryHistoryRig {
    let history: RoamExperienceSessionReader
    let tools: RoamPassportToolsSessionReader
    let access: RoamPassportToolsReadAccess
    let storage: AnniversaryHistoryStorage
    let wire: AnniversaryHistoryWire
    var topics: [String] = []
    init(hasRecord: Bool) throws {
        let storage = AnniversaryHistoryStorage(), wire = AnniversaryHistoryWire()
        self.storage = storage; self.wire = wire
        let base = URL(string: "https://example.test/anniversary-history")!
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "anniversary-history", token: "synthetic-anniversary-history"))
        let access = try RoamPassportToolsReadAccess(context: context, approval: .init(baseURL: base,
            namespace: context.session.namespace, accountID: context.session.accountID, paths: Set(RoamPassportToolsService.paths)))
        self.access = access
        let scope = try RoamHistoryScope(market: "cn", deployment: base, accountID: 7, namespace: context.session.namespace)
        let session = try RoamExperienceSession(scope: scope, epoch: 1, token: "synthetic-anniversary-history")
        history = .init(service: nil, store: .init(storage: storage, currentScope: { scope }), currentSession: { session })
        tools = .init(configuration: try .init(baseURL: base), transport: wire,
                      currentSession: { session }, current: { context }, access: { _ in access })
        let records = hasRecord ? [try JSONDecoder().decode(RoamHistoryRecord.self,
            from: Data(#"{"ts":1700000000000,"distance":1,"shops":1}"#.utf8))] : []
        struct Seed: Encodable { let version = 1; let scope: RoamHistoryScope; let records: [RoamHistoryRecord] }
        storage.data = try JSONEncoder().encode(Seed(scope: scope, records: records))
    }
}
@MainActor private final class AnniversaryHistoryStorage: RoamHistoryDataStoring {
    var data: Data?
    var writes = 0
    func read(key: String) throws -> Data? { data }
    func write(_ data: Data, key: String) throws { writes += 1; XCTFail("No history writer belongs to this navigation") }
}
@MainActor private final class AnniversaryHistoryWire: HTTPTransport {
    var requests: [URLRequest] = [], cursors: [String?] = [], days: [String] = []
    var twoPages = false, failContinuation = false
    var version = "Original"
    private let asOfMs = Int64(Date().timeIntervalSince1970 * 1000)
    var confirmedDay: String {
        let day = RoamShanghaiCalendar.day(atMilliseconds: asOfMs); return "\(day.month)-\(day.day)"
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard request.httpMethod == "GET", request.url?.lastPathComponent == "exploration-anniversary",
              request.value(forHTTPHeaderField: "Authorization") == "synthetic-anniversary-history" else {
            XCTFail("Unexpected endpoint or write"); throw APIError.notConfigured
        }
        let fields = Dictionary(uniqueKeysWithValues:
            (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let cursor = fields["cursor"]; cursors.append(cursor)
        let today = RoamShanghaiCalendar.day(atMilliseconds: asOfMs)
        let month = Int(fields["month"] ?? "") ?? today.month, day = Int(fields["day"] ?? "") ?? today.day
        days.append(fields["month"].map { $0 + "-" + (fields["day"] ?? "") } ?? "server-today")
        if cursor != nil && failContinuation { return (Data(#"{"code":503}"#.utf8), 503) }
        var year = today.year - 1
        if month == 2 && day == 29 {
            while !((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) { year -= 1 }
        }
        let completed = String(format: "%04d-%02d-%02d 12:34:56.000", year, month, day)
        let start = cursor == nil ? 100 : 80
        let items: [[String: Any]] = (0..<(twoPages ? 20 : 1)).map { offset in
            let id = start - offset
            return ["id": String(id), "topicId": String(7000 + id), "title": version + " row " + String(id),
                    "completedAt": completed, "year": year, "yearsAgo": today.year - year]
        }
        let more = twoPages && cursor == nil
        let data: [String: Any] = ["month": month, "day": day, "referenceYear": today.year,
            "timeZone": "Asia/Shanghai", "asOfMs": asOfMs, "items": items,
            "hasMore": more, "nextCursor": more ? "page_a" as Any : NSNull(), "leapDayRule": "EXACT_MONTH_DAY_ONLY",
            "coverage": "RECORDED_OWN_COMPLETED_SESSIONS_WITH_CURRENT_VISIBLE_ROUTE", "metadataMode": "CURRENT_ROUTE_METADATA"]
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
}
