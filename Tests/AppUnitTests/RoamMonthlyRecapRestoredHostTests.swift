import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Three original lifecycle tests restored unchanged into a separate leaf.
@MainActor private final class ExportHostState: ObservableObject { @Published var phase: ScenePhase = .active }
@MainActor final class RoamMonthlyRecapRestoredHostTests: XCTestCase {
    private func exportWait(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail(message)
    }
    private func exportFind(_ root: NSObject, id: String, seen: inout Set<ObjectIdentifier>) -> NSObject? {
        guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
        if (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
        if let view = root as? UIView {
            for child in view.subviews { if let found = exportFind(child, id: id, seen: &seen) { return found } }
        }
        if let children = root.accessibilityElements {
            for child in children { if let child = child as? NSObject, let found = exportFind(child, id: id, seen: &seen) { return found } }
        }
        let count = root.accessibilityElementCount()
        if count > 0 && count < 1000 {
            for index in 0..<count {
                if let child = root.accessibilityElement(at: index) as? NSObject,
                   let found = exportFind(child, id: id, seen: &seen) { return found }
            }
        }
        return nil
    }
    private func exportFind(_ id: String, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>(); return exportFind(window, id: id, seen: &seen)
    }
    private func exportTap(_ id: String, in window: UIWindow) async throws {
        try await exportWait("Real export control " + id) { self.exportFind(id, in: window) != nil }
        let target = try XCTUnwrap(exportFind(id, in: window))
        if let control = target as? UIControl { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(target.accessibilityActivate()) }
    }
}

@MainActor private final class MonthlyRecapHostReader: RoamPassportToolsReading {
    var identity: RoamExperienceIdentity? = RoamPassportToolsFixtureReader().identity
    var isConfigured = true
    let isOfflineExample = true
    var queries: [RoamMonthlyRecapQuery] = []
    var hold = false, failNext = false
    var waiting: CheckedContinuation<RoamMonthlyRecapPage, Error>?
    private var heldQuery: RoamMonthlyRecapQuery?
    func anniversary(_ query: RoamAnniversaryQuery, boundary: RoamAnniversaryMemory?) async throws -> RoamAnniversaryPage { throw APIError.notConfigured }
    func monthlyRecap(_ query: RoamMonthlyRecapQuery) async throws -> RoamMonthlyRecapPage {
        queries.append(query)
        if hold { heldQuery = query; return try await withCheckedThrowingContinuation { waiting = $0 } }
        if failNext { failNext = false; throw APIError.httpStatus(503) }
        return try page(query)
    }
    func page(_ query: RoamMonthlyRecapQuery) throws -> RoamMonthlyRecapPage {
        let first = query.beforeID == nil, record = first ? "90" : "80", object = first ? "7001" : "7002"
        let cursor = first ? "90" : "null"
        let json = #"{"code":200,"data":{"month":"\#(query.month)","kind":"\#(query.kind.rawValue)","timeZone":"Asia/Shanghai","counts":{"routes":2,"places":2,"stamps":2},"items":[{"id":"\#(record)","objectId":\#(object),"title":"Original record \#(record)","occurredAt":"\#(query.month)-01 10:00:00"}],"hasMore":\#(first),"nextBeforeId":\#(cursor)}}"#
        return try RoamMonthlyRecapPage.decode(Data(json.utf8), query: query)
    }
    func release() throws {
        hold = false; let query = heldQuery; heldQuery = nil
        if let query { waiting?.resume(returning: try page(query)); waiting = nil }
    }
}

@MainActor private struct MonthlyRecapLifecycleHarness: View {
    let reader: MonthlyRecapHostReader
    @ObservedObject var state: ExportHostState
    var body: some View {
        NavigationStack {
            NavigationLink("Open original monthly recap") { RoamMonthlyRecapView(reader: reader) }
                .accessibilityIdentifier("recap.fixture.open")
        }.environment(\.scenePhase, state.phase).environment(\.locale, Locale(identifier: "en_US"))
    }
}

@MainActor extension RoamMonthlyRecapRestoredHostTests {
    func testHostedRecapMonthCursorFailureRetryAndExactDetailReturnKeepOriginalQuery() async throws {
        let reader = MonthlyRecapHostReader(), state = ExportHostState()
        let host = UIHostingController(rootView: MonthlyRecapLifecycleHarness(reader: reader, state: state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1100))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await exportTap("recap.fixture.open", in: window)
        try await exportWait("Initial original month ready") { reader.queries.count == 1 && self.exportFind("roam.tools.recap.row", in: window) != nil }
        try await exportTap("roam.tools.recap.previous", in: window)
        try await exportWait("Chosen original month read") { reader.queries.count == 2 && self.exportFind("roam.tools.recap.more", in: window) != nil }
        try await exportTap("roam.tools.recap.more", in: window)
        try await exportWait("Original continuation") { reader.queries.count == 3 && self.exportFind("roam.tools.recap.row", in: window) != nil }
        let original = try XCTUnwrap(reader.queries.last)
        XCTAssertEqual(original.month, "2026-09"); XCTAssertEqual(original.kind, .routes); XCTAssertEqual(original.beforeID, "90")
        reader.failNext = true; state.phase = .background
        try await exportWait("Private recap hidden") { self.exportFind("roam.tools.recap.row", in: window) == nil }
        state.phase = .active
        try await exportWait("Failed same-query foreground read stays error") { reader.queries.count == 4 && self.exportFind("roam.tools.recap.error", in: window) != nil }
        XCTAssertEqual(reader.queries.last, original); XCTAssertNil(exportFind("roam.tools.recap.empty", in: window))
        // Existing issue component uses the normal retry control (not a model direct call).
        try await exportTap("roam.experience.retry", in: window)
        try await exportWait("Original continuation retry succeeds") { reader.queries.count == 5 && self.exportFind("roam.tools.recap.row", in: window) != nil }
        XCTAssertEqual(reader.queries.last, original)
        try await exportTap("roam.tools.recap.row", in: window)
        try await exportTap("roam.tools.recap.detail.close", in: window)
        try await exportWait("Exact detail close rereads original same continuation") { reader.queries.count == 6 && self.exportFind("roam.tools.recap.row", in: window) != nil }
        XCTAssertEqual(reader.queries.last, original)
    }
    func testHostedRecapBackgroundDiscardsLateReadAndOnlyForegroundReadsAgain() async throws {
        let reader = MonthlyRecapHostReader(), state = ExportHostState(); reader.hold = true
        let host = UIHostingController(rootView: MonthlyRecapLifecycleHarness(reader: reader, state: state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1100))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await exportTap("recap.fixture.open", in: window)
        try await exportWait("Held original read") { reader.waiting != nil }
        state.phase = .background
        try await Task.sleep(nanoseconds: 50_000_000)
        try reader.release()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(reader.queries.count, 1); XCTAssertNil(exportFind("roam.tools.recap.row", in: window))
        state.phase = .active
        try await exportWait("Fresh original foreground read") { reader.queries.count == 2 && self.exportFind("roam.tools.recap.row", in: window) != nil }
        XCTAssertEqual(reader.queries[0], reader.queries[1])
    }
    func testHostedRecapDetailBackgroundDoesNotReadAndRevocationCannotExposeOldDetail() async throws {
        let reader = MonthlyRecapHostReader(), state = ExportHostState()
        let host = UIHostingController(rootView: MonthlyRecapLifecycleHarness(reader: reader, state: state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1100))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await exportTap("recap.fixture.open", in: window)
        try await exportTap("roam.tools.recap.row", in: window)
        try await exportWait("Original detail visible") { self.exportFind("roam.tools.recap.detail.close", in: window) != nil }
        let original = try XCTUnwrap(reader.queries.last)
        state.phase = .background
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(reader.queries.count, 1, "Hide/detail retirement cannot initiate a read")
        state.phase = .active
        try await exportWait("Foreground finishes same original detail return") { reader.queries.count == 2 && self.exportFind("roam.tools.recap.row", in: window) != nil }
        XCTAssertEqual(reader.queries.last, original)
        try await exportTap("roam.tools.recap.row", in: window)
        reader.isConfigured = false; state.phase = .background
        try await Task.sleep(nanoseconds: 50_000_000)
        state.phase = .active
        try await exportWait("Original revoked read unavailable") { self.exportFind("roam.tools.recap.error", in: window) != nil }
        XCTAssertEqual(reader.queries.count, 2); XCTAssertNil(exportFind("roam.tools.recap.row", in: window))
    }
}

/// New tests use the original production History/Passport/Hub consumers and the real scoped reader.
/// All transport and storage are in-memory. Topic destinations are read-only text probes.
@MainActor final class RoamMonthlyRecapNaturalEntryTests: XCTestCase {
    private enum Entry: CaseIterable { case hub, passport, hubHistory, passportHistory }

    func testAllOriginalEntriesUseTypedTopicAndExactDetailReturnWithoutWrites() async throws {
        for entry in Entry.allCases {
            let rig = try MonthlyNaturalRig(), window = mount(rig, entry: entry)
            defer { close(window) }
            try await open(entry, in: window)
            try await tap("roam.tools.recap.row", in: window)
            try await tap("roam.tools.recap.detail.openRoute", in: window)
            try await reveal("monthly.original.topic", in: window)
            XCTAssertFalse(rig.topics.isEmpty)
            XCTAssertTrue(rig.topics.allSatisfy { $0 == "7001" }, "Only objectId 7001 is a topic; record ID 90 is not")
            let navigation = try XCTUnwrap(navigations(window.rootViewController).last { $0.viewControllers.count > 1 })
            XCTAssertNotNil(navigation.popViewController(animated: false))
            try await tap("roam.tools.recap.detail.close", in: window)
            try await waitFor("Exact detail close rereads once") {
                rig.wire.requests.count == 2 && self.find("roam.tools.recap.row", in: window) != nil
            }
            XCTAssertEqual(rig.wire.queries[0], rig.wire.queries[1])
            XCTAssertEqual(rig.storage.writes, 0)
        }
    }

    func testNilOriginalDestinationStillOpensReadOnlyRecordWithoutRoute() async throws {
        for entry in [Entry.hub, .passportHistory] {
            let rig = try MonthlyNaturalRig(), window = mount(rig, entry: entry, includeDestination: false)
            defer { close(window) }
            try await open(entry, in: window); try await tap("roam.tools.recap.row", in: window)
            try await reveal("roam.tools.recap.detail.close", in: window)
            XCTAssertNil(find("roam.tools.recap.detail.openRoute", in: window))
            XCTAssertTrue(rig.topics.isEmpty); XCTAssertEqual(rig.wire.requests.count, 1)
            try await tap("roam.tools.recap.detail.close", in: window)
            try await waitFor("Read-only record return") { rig.wire.requests.count == 2 }
            XCTAssertEqual(rig.wire.queries[0], rig.wire.queries[1])
        }
    }

    func testPlaceAndStampIDsNeverBecomeTopicsThroughOriginalKindPicker() async throws {
        for (index, kind) in [(1, "places"), (2, "stamps")] {
            let rig = try MonthlyNaturalRig(), window = mount(rig, entry: .passport)
            defer { close(window) }
            try await open(.passport, in: window)
            try await reveal("roam.tools.recap.kindPicker", in: window)
            let picker = try XCTUnwrap(segmented(in: window))
            picker.selectedSegmentIndex = index; picker.sendActions(for: .valueChanged)
            try await waitFor("Original selected kind read") {
                rig.wire.queries.last?["kind"] == kind && self.find("roam.tools.recap.row", in: window) != nil
            }
            try await tap("roam.tools.recap.row", in: window)
            try await reveal("roam.tools.recap.detail.close", in: window)
            XCTAssertNil(find("roam.tools.recap.detail.openRoute", in: window))
            XCTAssertTrue(rig.topics.isEmpty)
            try await tap("roam.tools.recap.detail.close", in: window)
            try await waitFor("Same non-route kind return") { rig.wire.requests.count == 3 }
            XCTAssertEqual(rig.wire.queries[1], rig.wire.queries[2]); XCTAssertEqual(rig.storage.writes, 0)
        }
    }

    func testOriginalReadApprovalRevocationHidesDetailAndRowsWithoutAnotherRequest() async throws {
        let rig = try MonthlyNaturalRig(), window = mount(rig, entry: .hubHistory)
        defer { close(window) }
        try await open(.hubHistory, in: window); try await tap("roam.tools.recap.row", in: window)
        try await reveal("roam.tools.recap.detail.openRoute", in: window)
        let calls = rig.wire.requests.count
        rig.access.revoke(); XCTAssertFalse(rig.tools.isConfigured)
        try await waitFor("Revoked route and private rows disappear") {
            self.find("roam.tools.recap.detail.openRoute", in: window) == nil &&
            self.find("roam.tools.recap.row", in: window) == nil
        }
        XCTAssertTrue(rig.topics.isEmpty); XCTAssertEqual(rig.wire.requests.count, calls)
        XCTAssertEqual(rig.storage.writes, 0)
    }

    private func mount(_ rig: MonthlyNaturalRig, entry: Entry, includeDestination: Bool = true) -> UIWindow {
        let route: ((String) -> AnyView)? = includeDestination ? { id in
            rig.topics.append(id)
            return AnyView(Text("Original topic " + id).accessibilityIdentifier("monthly.original.topic"))
        } : nil
        let host = UIHostingController(rootView: NavigationStack {
            switch entry {
            case .hub, .hubHistory:
                RoamExperienceHubView(reader: rig.history, toolsReader: rig.tools, anniversaryRouteDestination: route)
            case .passport, .passportHistory:
                RoamHomePassportView(reader: rig.history, toolsReader: rig.tools, anniversaryRouteDestination: route)
            }
        }.environment(\.locale, Locale(identifier: "en_US")).environment(\.scenePhase, .active))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1100))
        window.rootViewController = host; window.makeKeyAndVisible()
        host.loadViewIfNeeded(); host.view.layoutIfNeeded(); return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    private func open(_ entry: Entry, in window: UIWindow) async throws {
        switch entry {
        case .hub, .passport: try await tap("roam.tools.recap.open", in: window)
        case .hubHistory:
            try await tap("roam.experience.history.open", in: window)
            try await tap("roamSub.w208.history.tool.recap", in: window)
        case .passportHistory:
            try await tap("roam.home.passport.tile.history", in: window)
            try await tap("roamSub.w208.history.tool.recap", in: window)
        }
        try await reveal("roam.tools.recap.row", in: window)
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
        let target = try XCTUnwrap(find(id, in: window))
        if let control = target as? UIControl { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(target.accessibilityActivate(), "Original control must activate") }
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
                for index in 0..<count {
                    if let child = root.accessibilityElement(at: index) as? NSObject, let found = visit(child) { return found }
                }
            }
            return nil
        }
        return visit(window)
    }
    private func segmented(in view: UIView) -> UISegmentedControl? {
        if let value = view as? UISegmentedControl { return value }
        for child in view.subviews { if let value = segmented(in: child) { return value } }
        return nil
    }
    private func navigations(_ controller: UIViewController?) -> [UINavigationController] {
        guard let controller else { return [] }
        var values = (controller as? UINavigationController).map { [$0] } ?? []
        for child in controller.children { values += navigations(child) }
        values += navigations(controller.presentedViewController)
        return values
    }
}

@MainActor private final class MonthlyNaturalRig {
    let history: RoamExperienceSessionReader
    let tools: RoamPassportToolsSessionReader
    let access: RoamPassportToolsReadAccess
    let wire: MonthlyNaturalWire
    let storage: MonthlyNaturalStorage
    var topics: [String] = []
    init() throws {
        let wire = MonthlyNaturalWire(), storage = MonthlyNaturalStorage()
        self.wire = wire; self.storage = storage
        let base = URL(string: "https://example.test/monthly-restoration")!
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "monthly-original", token: "synthetic-monthly-original"))
        let access = try RoamPassportToolsReadAccess(context: context, approval: .init(baseURL: base,
            namespace: context.session.namespace, accountID: context.session.accountID, paths: Set(RoamPassportToolsService.paths)))
        self.access = access
        let scope = try RoamHistoryScope(market: "cn", deployment: base, accountID: 7, namespace: context.session.namespace)
        let session = try RoamExperienceSession(scope: scope, epoch: 1, token: "synthetic-monthly-original")
        history = .init(service: nil, store: .init(storage: storage, currentScope: { scope }), currentSession: { session })
        tools = .init(configuration: try .init(baseURL: base), transport: wire,
                      currentSession: { session }, current: { context }, access: { _ in access })
    }
}
@MainActor private final class MonthlyNaturalStorage: RoamHistoryDataStoring {
    var writes = 0
    func read(key: String) throws -> Data? { nil }
    func write(_ data: Data, key: String) throws { writes += 1; XCTFail("Monthly navigation has no history writer") }
}
@MainActor private final class MonthlyNaturalWire: HTTPTransport {
    var requests: [URLRequest] = []
    var queries: [[String: String]] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard request.httpMethod == "GET", request.url?.lastPathComponent == "monthly-recap",
              request.value(forHTTPHeaderField: "Authorization") == "synthetic-monthly-original" else {
            XCTFail("Unexpected endpoint or writer"); throw APIError.notConfigured
        }
        let fields = Dictionary(uniqueKeysWithValues:
            (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        queries.append(fields)
        guard let month = fields["month"], let kind = fields["kind"], ["routes", "places", "stamps"].contains(kind) else {
            throw APIError.invalidRequest
        }
        let objectID = kind == "routes" ? "7001" : kind == "places" ? "8001" : "90"
        let json = #"{"code":200,"data":{"month":"\#(month)","kind":"\#(kind)","timeZone":"Asia/Shanghai","counts":{"routes":1,"places":1,"stamps":1},"items":[{"id":"90","objectId":"\#(objectID)","title":"Original \#(kind) record","occurredAt":"\#(month)-01 10:00:00"}],"hasMore":false,"nextBeforeId":null}}"#
        return (Data(json.utf8), 200)
    }
}
