import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// The App admission is tested against the original Core list/navigation generations.
/// Hosted reads use the existing session reader and an in-memory original GET service.
@MainActor final class RoamAnniversaryReadIntentTests: XCTestCase {
    func testCurrentMoreUsesOriginalCursorAndIsConsumedByOriginalBegin() throws {
        let rig = try AnniversaryIntentRig(); var list = try seeded(rig.tools), nav = navigation(rig.tools)
        let visit = UUID(), offered = intent(.more, rig.tools, list, nav, visit)
        XCTAssertTrue(offered.matches(reader: rig.tools, state: list, navigation: nav, visit: visit))
        let request = try XCTUnwrap(list.begin(offered.intent, owner: rig.tools.identity))
        XCTAssertEqual(request.query.cursor, "page_a"); XCTAssertEqual(request.query.month, 10)
        XCTAssertFalse(offered.matches(reader: rig.tools, state: list, navigation: nav, visit: visit))
    }
    func testOldMoreCannotSelectAnotherDayOrDateABAContinuation() throws {
        let rig = try AnniversaryIntentRig(); var list = try seeded(rig.tools)
        let nav = navigation(rig.tools), visit = UUID(), old = intent(.more, rig.tools, list, nav, visit)
        XCTAssertTrue(list.select(try XCTUnwrap(.init(month: 10, day: 20))))
        XCTAssertFalse(old.matches(reader: rig.tools, state: list, navigation: nav, visit: visit))
        XCTAssertTrue(list.select(try XCTUnwrap(.init(month: 10, day: 19))))
        let refresh = try XCTUnwrap(list.begin(.refresh, owner: rig.tools.identity))
        XCTAssertTrue(try list.accept([page(cursor: "replacement")], for: refresh, owner: rig.tools.identity))
        XCTAssertFalse(old.matches(reader: rig.tools, state: list, navigation: nav, visit: visit))
        XCTAssertEqual(list.page?.nextCursor, "replacement")
    }
    func testCoverAndNewVisitBothInvalidateAlreadyRenderedIntent() throws {
        let rig = try AnniversaryIntentRig(); var list = try seeded(rig.tools)
        let nav = navigation(rig.tools), visit = UUID(), old = intent(.more, rig.tools, list, nav, visit)
        XCTAssertFalse(old.matches(reader: rig.tools, state: list, navigation: nav, visit: UUID()))
        list.suspend()
        XCTAssertFalse(old.matches(reader: rig.tools, state: list, navigation: nav, visit: visit))
        XCTAssertEqual(list.rows.count, 20)
    }
    func testRouteOpenCoverAndExactPopCannotReuseOldListIntent() throws {
        let rig = try AnniversaryIntentRig(); let list = try seeded(rig.tools), visit = UUID()
        var nav = navigation(rig.tools)
        let old = intent(.more, rig.tools, list, nav, visit), memory = try XCTUnwrap(list.rows.first)
        XCTAssertTrue(nav.open(try XCTUnwrap(.init(memory: memory)), memory: memory, currentRows: list.rows, owner: rig.tools.identity))
        let lease = try XCTUnwrap(nav.openedPresentation)
        XCTAssertFalse(old.matches(reader: rig.tools, state: list, navigation: nav, visit: visit))
        nav.noteCovered(lease, owner: rig.tools.identity); XCTAssertTrue(nav.mayRemainOpen(lease, owner: rig.tools.identity))
        XCTAssertTrue(nav.completeReturn(presentation: lease, owner: rig.tools.identity))
        XCTAssertFalse(old.matches(reader: rig.tools, state: list, navigation: nav, visit: visit))
        XCTAssertFalse(nav.completeReturn(presentation: lease, owner: rig.tools.identity))
    }
    func testSameIdentityReplacementReaderCannotInheritAnOldIntent() throws {
        let original = try AnniversaryIntentRig(), fresh = try AnniversaryIntentRig()
        let list = try seeded(original.tools), nav = navigation(original.tools), visit = UUID()
        let old = intent(.more, original.tools, list, nav, visit)
        XCTAssertEqual(original.tools.identity, fresh.tools.identity)
        XCTAssertFalse(old.matches(reader: fresh.tools, state: list, navigation: nav, visit: visit))
        XCTAssertTrue(fresh.wire.cursors.isEmpty)
    }
    func testOldRetryCannotReinterpretNewCursorExpiredRefreshIntent() throws {
        let rig = try AnniversaryIntentRig(); var list = try seeded(rig.tools)
        let nav = navigation(rig.tools), visit = UUID()
        let first = try XCTUnwrap(list.begin(.more, owner: rig.tools.identity))
        list.fail(APIError.httpStatus(503), for: first, owner: rig.tools.identity)
        let oldRetry = intent(list.retryIntent, rig.tools, list, nav, visit)
        XCTAssertEqual(oldRetry.intent, .more)
        let second = try XCTUnwrap(list.begin(.more, owner: rig.tools.identity))
        list.fail(APIError.httpStatus(400), for: second, owner: rig.tools.identity)
        XCTAssertEqual(list.retryIntent, .refresh)
        XCTAssertFalse(oldRetry.matches(reader: rig.tools, state: list, navigation: nav, visit: visit))
        XCTAssertEqual(oldRetry.intent, .more, "A retained closure cannot read a newer retryIntent")
        XCTAssertEqual(intent(list.retryIntent, rig.tools, list, nav, visit).intent, .refresh)
    }
    func testRevokedReadClearsRowsWithoutTurningOldMoreIntoRecovery() throws {
        let rig = try AnniversaryIntentRig(); var list = try seeded(rig.tools)
        let nav = navigation(rig.tools), visit = UUID(), old = intent(.more, rig.tools, list, nav, visit)
        list.revokeAccess(APIError.httpStatus(403)); rig.access.revoke()
        XCTAssertFalse(old.matches(reader: rig.tools, state: list, navigation: nav, visit: visit))
        XCTAssertTrue(list.rows.isEmpty); XCTAssertEqual(list.displayedDay, .init(month: 10, day: 19))
        XCTAssertFalse(rig.tools.isConfigured); XCTAssertTrue(rig.wire.cursors.isEmpty)
    }
    func testFreshReturnIntentKeepsOriginalAtomicLoadedDepth() throws {
        let rig = try AnniversaryIntentRig(); var list = try seeded(rig.tools)
        let nav = navigation(rig.tools), visit = UUID()
        let more = try XCTUnwrap(list.begin(.more, owner: rig.tools.identity))
        XCTAssertTrue(try list.accept([page(start: 80, cursor: nil)], for: more, owner: rig.tools.identity))
        list.suspend(); list.requestRefresh()
        let fresh = intent(.refresh, rig.tools, list, nav, visit)
        XCTAssertTrue(fresh.matches(reader: rig.tools, state: list, navigation: nav, visit: visit))
        let request = try XCTUnwrap(list.begin(fresh.intent, owner: rig.tools.identity))
        XCTAssertEqual(request.pageCount, 2); XCTAssertNil(request.query.cursor)
        list.fail(APIError.httpStatus(503), for: request, owner: rig.tools.identity)
        XCTAssertEqual(list.rows.count, 40); XCTAssertEqual(list.loadedPageCount, 2)
    }
    func testActualInitialReadMoreAndTransientRetryKeepExactOriginalCursor() async throws {
        let state = try AnniversaryIntentHostState(), scene = try HostedNavigationSceneWindow()
        mount(state, window: scene.window); defer { scene.retire() }
        try await waitFor { self.find("roam.tools.anniversary.more", in: scene.window) != nil }
        XCTAssertEqual(state.rig.wire.cursors, [nil])
        state.rig.wire.failContinuation = true
        try await tap("roam.tools.anniversary.more", in: scene.window)
        try await waitFor { self.find("roam.experience.retry", in: scene.window) != nil }
        XCTAssertEqual(state.rig.wire.cursors, [nil, "page_a"])
        state.rig.wire.failContinuation = false
        try await tap("roam.experience.retry", in: scene.window)
        try await waitFor { state.rig.wire.cursors.count == 3 && self.find("roam.experience.retry", in: scene.window) == nil }
        XCTAssertEqual(state.rig.wire.cursors, [nil, "page_a", "page_a"])
        XCTAssertNil(find("roam.tools.anniversary.more", in: scene.window))
    }
    func testActualRouteCoverForegroundAndBackRefreshOriginalDepthOnce() async throws {
        let state = try AnniversaryIntentHostState(), scene = try HostedNavigationSceneWindow(), window = scene.window
        mount(state, window: window); defer { scene.retire() }
        try await tap("roam.tools.anniversary.more", in: window)
        try await waitFor { state.rig.wire.cursors.count == 2 && self.find("roam.tools.anniversary.more", in: window) == nil }
        try await tap("roam.tools.anniversary.openRoute", in: window)
        try await waitFor { self.find("anniversary.intent.topic", in: window) != nil }
        state.phase = .background; try await Task.sleep(nanoseconds: 100_000_000)
        state.phase = .active; try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(state.rig.wire.cursors, [nil, "page_a"], "Hidden list cannot take a foreground read")
        let nav = try XCTUnwrap(navigationController(window.rootViewController))
        XCTAssertNotNil(nav.popViewController(animated: false))
        try await waitFor { state.rig.wire.cursors.count == 4 && self.find("roam.tools.anniversary.row", in: window) != nil }
        XCTAssertEqual(state.rig.wire.cursors, [nil, "page_a", nil, "page_a"])
        XCTAssertEqual(Set(state.rig.wire.days.dropFirst()).count, 1)
    }
    func testActualFirstReadCoveredBeforeCompletionStillRestartsOnReturn() async throws {
        let state = try AnniversaryIntentHostState(); state.rig.wire.hold = true
        let scene = try HostedNavigationSceneWindow(), window = scene.window; mount(state, window: window); defer { scene.retire() }
        try await waitFor { state.rig.wire.pending != nil }
        state.covered = true
        try await waitFor { self.find("anniversary.intent.cover", in: window) != nil }
        state.rig.wire.finish(); state.rig.wire.hold = false
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(state.rig.wire.cursors, [nil])
        let nav = try XCTUnwrap(navigationController(window.rootViewController)); XCTAssertNotNil(nav.popViewController(animated: false))
        try await waitFor { state.rig.wire.cursors == [nil, nil] && self.find("roam.tools.anniversary.row", in: window) != nil }
    }
    func testActualReplacementReaderRetiresOldHeldResponseAndShowsOnlyNewRows() async throws {
        let state = try AnniversaryIntentHostState(); state.rig.wire.hold = true
        let scene = try HostedNavigationSceneWindow(), window = scene.window; mount(state, window: window); defer { scene.retire() }
        try await waitFor { state.rig.wire.pending != nil }
        let old = state.rig, fresh = try AnniversaryIntentRig(); fresh.wire.version = "Fresh"
        state.rig = fresh
        try await waitFor { fresh.wire.cursors.count == 1 && self.find("roam.tools.anniversary.row", in: window) != nil }
        old.wire.finish()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(fresh.wire.cursors, [nil]); XCTAssertEqual(old.wire.cursors, [nil])
        XCTAssertNotNil(find(label: "Fresh row", in: window)); XCTAssertNil(find(label: "Original row", in: window))
    }
    private func intent(_ intent: RoamAnniversaryListState.Intent, _ reader: any RoamPassportToolsReading,
                        _ state: RoamAnniversaryListState, _ navigation: RoamAnniversaryNavigationState, _ visit: UUID) -> RoamAnniversaryReadIntent {
        .init(intent: intent, reader: reader, state: state, navigation: navigation, visit: visit)
    }
    private func navigation(_ reader: any RoamPassportToolsReading) -> RoamAnniversaryNavigationState {
        var nav = RoamAnniversaryNavigationState(); nav.bind(to: reader.identity); return nav
    }
    private func seeded(_ reader: any RoamPassportToolsReading) throws -> RoamAnniversaryListState {
        var list = RoamAnniversaryListState(); list.bind(to: reader.identity)
        let first = try XCTUnwrap(list.begin(.refresh, owner: reader.identity))
        XCTAssertTrue(try list.accept([page()], for: first, owner: reader.identity)); return list
    }
    private func page(start: Int = 100, cursor: String? = "page_a") throws -> RoamAnniversaryPage {
        let rows: [[String: Any]] = (0..<20).map { offset in
            ["id": String(start-offset), "topicId": String(7000+start-offset), "title": "Original",
             "completedAt": "2024-10-19 12:00:00.000", "year": 2024, "yearsAgo": 2]
        }
        let data: [String: Any] = ["month": 10, "day": 19, "referenceYear": 2026,
            "asOfMs": Int64(1_792_382_400_000), "items": rows, "hasMore": cursor != nil,
            "nextCursor": cursor.map { $0 as Any } ?? NSNull(), "timeZone": "Asia/Shanghai",
            "leapDayRule": "EXACT_MONTH_DAY_ONLY", "coverage": "RECORDED_OWN_COMPLETED_SESSIONS_WITH_CURRENT_VISIBLE_ROUTE", "metadataMode": "CURRENT_ROUTE_METADATA"]
        return try .decode(JSONSerialization.data(withJSONObject: ["code": 200, "data": data]),
                           query: .init(month: 10, day: 19))
    }
    private func mount(_ state: AnniversaryIntentHostState, window: UIWindow) {
        let host = UIHostingController(rootView: AnniversaryIntentHost(state: state))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded()
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTFail("Original anniversary navigation/read did not settle"); throw APIError.notConfigured
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        for _ in 0..<60 { if find(id, in: window) != nil { break }; scroll(window); try await Task.sleep(nanoseconds: 40_000_000) }
        let target = try XCTUnwrap(find(id, in: window))
        if let control = target as? UIControl { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(target.accessibilityActivate()) }
    }
    private func scroll(_ view: UIView) {
        if let scroll = view as? UIScrollView {
            let end = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            if scroll.contentOffset.y < end { scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(end, scroll.contentOffset.y + 500)), animated: false); scroll.layoutIfNeeded() }
            else { scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top), animated: false); scroll.layoutIfNeeded() }
        }
        for child in view.subviews { scroll(child) }
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? { find(id: id, label: nil, in: window) }
    private func find(label: String, in window: UIWindow) -> NSObject? { find(id: nil, label: label, in: window) }
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
    private func navigationController(_ controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }; if let result = controller as? UINavigationController { return result }
        for child in controller.children { if let result = navigationController(child) { return result } }; return nil
    }
}
@MainActor private final class AnniversaryIntentHostState: ObservableObject {
    @Published var rig: AnniversaryIntentRig
    @Published var phase: ScenePhase = .active
    @Published var covered = false
    init() throws { rig = try AnniversaryIntentRig() }
}
@MainActor private struct AnniversaryIntentHost: View {
    @ObservedObject var state: AnniversaryIntentHostState
    var body: some View {
        NavigationStack {
            RoamAnniversaryView(reader: state.rig.tools, routeDestination: { id in
                AnyView(Text("Current topic " + id).accessibilityIdentifier("anniversary.intent.topic"))
            })
            .navigationDestination(isPresented: $state.covered) {
                Text("Temporary host cover").accessibilityIdentifier("anniversary.intent.cover")
            }
        }.environment(\.scenePhase, state.phase).environment(\.locale, Locale(identifier: "en_US"))
    }
}
@MainActor private final class AnniversaryIntentRig {
    let tools: RoamPassportToolsSessionReader
    let access: RoamPassportToolsReadAccess
    let wire = AnniversaryIntentWire()
    init() throws {
        let base = URL(string: "https://example.test/anniversary-intent")!
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "anniversary-intent", token: "synthetic-anniversary-intent"))
        let access = try RoamPassportToolsReadAccess(context: context, approval: .init(baseURL: base,
            namespace: context.session.namespace, accountID: 7, paths: Set(RoamPassportToolsService.paths)))
        self.access = access
        let scope = try RoamHistoryScope(market: "cn", deployment: base, accountID: 7, namespace: context.session.namespace)
        let session = try RoamExperienceSession(scope: scope, epoch: 1, token: "synthetic-anniversary-intent")
        tools = .init(configuration: try .init(baseURL: base), transport: wire,
                      currentSession: { session }, current: { context }, access: { _ in access })
    }
}
@MainActor private final class AnniversaryIntentWire: HTTPTransport {
    var cursors: [String?] = [], days: [String] = []
    var failContinuation = false, hold = false
    var version = "Original"
    var pending: CheckedContinuation<(Data, Int), Error>?
    private var heldPayload: Data?
    private let asOfMs = Int64(Date().timeIntervalSince1970 * 1000)
    func finish() { let value = pending; pending = nil; value?.resume(returning: (heldPayload!, 200)); heldPayload = nil }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard request.httpMethod == "GET", request.httpBody == nil, request.url?.lastPathComponent == "exploration-anniversary",
              request.value(forHTTPHeaderField: "Authorization") == "synthetic-anniversary-intent" else {
            XCTFail("Only the original anniversary GET belongs here"); throw APIError.notConfigured
        }
        let fields = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let cursor = fields["cursor"]; cursors.append(cursor)
        let today = RoamShanghaiCalendar.day(atMilliseconds: asOfMs)
        let month = Int(fields["month"] ?? "") ?? today.month, day = Int(fields["day"] ?? "") ?? today.day
        days.append("\(month)-\(day)")
        if cursor != nil && failContinuation { return (Data(#"{"code":503}"#.utf8), 503) }
        var year = today.year - 1
        if month == 2 && day == 29 { while !((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) { year -= 1 } }
        let completed = String(format: "%04d-%02d-%02d 12:34:56.000", year, month, day), start = cursor == nil ? 100 : 80
        let rows: [[String: Any]] = (0..<20).map { offset in
            let id = start - offset
            return ["id": String(id), "topicId": String(7000 + id), "title": version + " row " + String(id),
                    "completedAt": completed, "year": year, "yearsAgo": today.year - year]
        }
        let data: [String: Any] = ["month": month, "day": day, "referenceYear": today.year, "timeZone": "Asia/Shanghai",
            "asOfMs": asOfMs, "items": rows, "hasMore": cursor == nil, "nextCursor": cursor == nil ? "page_a" as Any : NSNull(),
            "leapDayRule": "EXACT_MONTH_DAY_ONLY", "coverage": "RECORDED_OWN_COMPLETED_SESSIONS_WITH_CURRENT_VISIBLE_ROUTE", "metadataMode": "CURRENT_ROUTE_METADATA"]
        let payload = try JSONSerialization.data(withJSONObject: ["code": 200, "data": data])
        if hold { heldPayload = payload; return try await withCheckedThrowingContinuation { pending = $0 } }
        return (payload, 200)
    }
}
