import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Actual private-tool controls with original reader and memory-only HTTP/journal. Never dispatches a writer.
@MainActor final class RoamPrivateReadDenialHostTests: XCTestCase {
    func testActualCapsuleContinuation403RemovesRowsAndExplicitRetryReadsFirstPage() async throws {
        let r = try PrivateReadDenialRig(), state = PrivateDenialHostState(reader: r.reader)
        let window = mount(state, destination: "capsule"); defer { close(window) }
        try await waitFor { r.wire.cursors.count == 1 }
        r.wire.status = 403; try await tap("roam.capsule.more", in: window)
        try await waitFor { self.find("roam.private.issue", in: window) != nil }
        XCTAssertNil(find("roam.capsule.row.open", in: window)); XCTAssertNil(find("roam.capsule.more", in: window))
        XCTAssertNil(find("roam.capsule.empty", in: window))
        r.wire.status = 200; r.wire.offset = 100
        XCTAssertEqual(r.wire.cursors, [nil, "12"])
        try await tap("roam.private.retry", in: window)
        try await waitFor { r.wire.cursors.count == 3 && self.find("roam.capsule.row.open", in: window) != nil }
        XCTAssertEqual(r.wire.cursors, [nil, "12", nil]); XCTAssertNil(find("roam.private.issue", in: window))
    }
    func testActualGoalDetailBusiness403RemovesPreviousDetailAndMetadata() async throws {
        let r = try PrivateReadDenialRig(), state = PrivateDenialHostState(reader: r.reader)
        let window = mount(state, destination: "goals"); defer { close(window) }
        try await waitFor { r.wire.cursors.count == 1 }; try await tap("roam.goals.row", in: window)
        try await waitFor { self.find("roam.goals.detail", in: window) != nil }
        r.wire.code = 403; try await tap("roam.goals.row", in: window)
        try await waitFor { self.find("roam.private.issue", in: window) != nil }
        XCTAssertNil(find("roam.goals.detail", in: window)); XCTAssertNil(find("roam.goals.row", in: window))
        XCTAssertNil(find("roam.goals.more", in: window)); XCTAssertNil(find("roam.goals.empty", in: window))
        r.wire.code = 200; try await tap("roam.private.retry", in: window)
        try await waitFor { r.wire.cursors.count == 2 && self.find("roam.goals.row", in: window) != nil }
        XCTAssertNil(find("roam.goals.detail", in: window)); XCTAssertEqual(r.wire.cursors, [nil, nil])
    }
    func testActualGoalTransientFailureKeepsRowsAndOriginalContinuationRetry() async throws {
        let r = try PrivateReadDenialRig(), state = PrivateDenialHostState(reader: r.reader)
        let window = mount(state, destination: "goals"); defer { close(window) }
        try await waitFor { r.wire.cursors.count == 1 }
        r.wire.status = 503; r.wire.code = 403; try await tap("roam.goals.more", in: window)
        try await waitFor { self.find("roam.private.issue", in: window) != nil }
        XCTAssertNotNil(find("roam.goals.row", in: window)); XCTAssertNotNil(find("roam.goals.more", in: window))
        r.wire.status = 200; r.wire.code = 200; try await tap("roam.goals.more", in: window)
        try await waitFor { r.wire.cursors.count == 3 && self.find("roam.private.issue", in: window) == nil }
        XCTAssertEqual(r.wire.cursors, [nil, "22", "22"])
    }
    func testActualReceiptRefusalKeepsReceiptOnlyLockAndNoEmptyOrWriter() async throws {
        let r = try PrivateReadDenialRig(seedLocks: true), state = PrivateDenialHostState(reader: r.reader)
        let window = mount(state, destination: "capsule"); defer { close(window) }
        try await waitFor { r.wire.cursors.count == 1 }
        let bytes = r.storage.values
        r.wire.status = 403; try await tap("roam.capsule.verify", in: window)
        try await waitFor { self.find("roam.private.issue", in: window) != nil }
        XCTAssertNotNil(find("roam.capsule.pending", in: window)); XCTAssertNotNil(find("roam.capsule.verify", in: window))
        XCTAssertNil(find("roam.capsule.retryOriginal", in: window)); XCTAssertNil(find("roam.capsule.empty", in: window))
        XCTAssertNil(find("roam.capsule.row.open", in: window)); XCTAssertEqual(r.storage.values, bytes)
        r.wire.status = 200; try await tap("roam.capsule.verify", in: window)
        try await waitFor { self.find("roam.capsule.pending", in: window) == nil && self.find("roam.capsule.row.open", in: window) != nil }
        XCTAssertNil(r.reader.unresolvedCapsuleRequestID); XCTAssertNotNil(r.reader.unresolvedGoalRequestID)
        XCTAssertTrue(r.wire.methods.allSatisfy { $0 == "GET" })
    }
    func testOriginalPassportLeaveAndReopenAfterDenialStartsFreshMetadata() async throws {
        let r = try PrivateReadDenialRig(), state = PrivateDenialHostState(reader: r.reader)
        let window = mount(state, destination: "passport"); defer { close(window) }
        try await tap("roam.home.passport.tile.goals", in: window)
        try await waitFor { r.wire.cursors.count == 1 }
        r.wire.status = 403; try await tap("roam.goals.more", in: window)
        try await waitFor { self.find("roam.private.issue", in: window) != nil }
        let nav = try XCTUnwrap(navigation(window.rootViewController)); XCTAssertNotNil(nav.popViewController(animated: false))
        try await waitFor { self.find("roam.home.passport.tile.goals", in: window) != nil }
        r.wire.status = 200; r.wire.offset = 100
        try await tap("roam.home.passport.tile.goals", in: window)
        try await waitFor { r.wire.cursors.count == 3 && self.find("roam.goals.row", in: window) != nil }
        XCTAssertEqual(r.wire.cursors, [nil, "22", nil]); XCTAssertNil(find("roam.goals.detail", in: window))
    }
    private func mount(_ state: PrivateDenialHostState, destination: String) -> UIWindow {
        let host = UIHostingController(rootView: PrivateDenialHostHarness(state: state, destination: destination))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1100))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTFail("Original private page control/read state did not settle"); throw APIError.notConfigured
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        for _ in 0..<35 {
            if find(id, in: window) != nil { break }
            scroll(window); try await Task.sleep(nanoseconds: 40_000_000)
        }
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
    private func navigation(_ controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let result = controller as? UINavigationController { return result }
        for child in controller.children { if let result = navigation(child) { return result } }; return nil
    }
}
@MainActor private final class PrivateDenialHostState: ObservableObject {
    @Published var reader: RoamPrivateToolsSessionReader
    init(reader: RoamPrivateToolsSessionReader) { self.reader = reader }
}
@MainActor private struct PrivateDenialHostHarness: View {
    @ObservedObject var state: PrivateDenialHostState
    let destination: String
    var body: some View {
        NavigationStack {
            if destination == "passport" { RoamHomePassportView(reader: nil, privateToolsReader: state.reader) }
            else if destination == "goals" { RoamExplorationGoalsView(tools: state.reader) }
            else { RoamCapsuleView(tools: state.reader) }
        }.environment(\.scenePhase, .active).environment(\.locale, Locale(identifier: "en_US"))
    }
}
@MainActor private final class PrivateReadDenialRig {
    static let base = URL(string: "https://example.test/private-denial")!
    let wire = PrivateReadDenialWire()
    let storage = RoamPrivatePendingInMemoryJournalStorage()
    let scope: RoamHistoryScope
    let context: RuntimeDependencyContext
    let access: RoamPrivateToolsAccess
    var unauthorized = 0
    lazy var journal = RoamPrivatePendingJournal(storage: storage)
    private(set) var reader: RoamPrivateToolsSessionReader!
    private(set) var capsule: RoamCapsuleCoordinator!
    private(set) var goal: RoamGoalsCoordinator!
    init(seedLocks: Bool = false) throws {
        scope = try .init(market: "cn", deployment: Self.base, accountID: 7, namespace: "denial")
        context = .init(market: .china, baseURL: Self.base, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "denial", token: "synthetic"))
        access = try .init(context: context, approval: .init(baseURL: Self.base, namespace: "denial", accountID: 7, paths: RoamPrivateToolsRoute.reads))
        if seedLocks {
            let journal = RoamPrivatePendingJournal(storage: storage)
            try journal.record(kind: .capsuleCreate, requestID: "capsule_request_0001", scope: scope, now: Date())
            try journal.record(kind: .goalCreate, requestID: "goals_request_000001", scope: scope, now: Date())
        }
        let service = try RoamPrivateToolsService(configuration: .init(baseURL: Self.base), transport: wire)
        reader = .init(service: service, current: { [weak self] in self?.context }, access: { [weak self] _ in self?.access }, onUnauthorized: { [weak self] _ in self?.unauthorized += 1 }, journal: journal)
        capsule = .init(tools: reader); goal = .init(tools: reader)
    }
}
@MainActor private final class PrivateReadDenialWire: HTTPTransport {
    var status = 200, code = 200, offset = 0
    var malformed = false, empty = false, hold = false
    var failure: Error?
    var held: CheckedContinuation<(Data, Int), Error>?
    var cursors: [String?] = [], paths: [String] = [], methods: [String] = []
    func release(status: Int, code: Int) { let pending = held; held = nil; pending?.resume(returning: (Data("{\"code\":\(code)}".utf8), status)) }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let url = try XCTUnwrap(request.url), path = url.path
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func field(_ key: String) -> String? { query.first { $0.name == key }?.value }
        paths.append(path); methods.append(request.httpMethod ?? "")
        XCTAssertEqual(request.httpMethod, "GET", "Only original read routes are used")
        if path.hasSuffix("/list") { cursors.append(field("beforeId")) }
        if hold { return try await withCheckedThrowingContinuation { held = $0 } }
        if let failure { throw failure }
        if status != 200 || code != 200 { return (Data("{\"code\":\(code)}".utf8), status) }
        if malformed { return (Data(#"{"code":200,"data":{}}"#.utf8), 200) }
        let capsule = path.contains("/capsules/"), list = path.hasSuffix("/list")
        let more = field("beforeId") != nil
        let id = field("id") ?? String((capsule ? 12 : 22) + offset - (more ? 1 : 0))
        var row: [String: Any]
        if capsule {
            row = ["id": id, "state": "OPEN", "unlockAtMs": 1_792_209_600_000, "createdAtMs": 1_775_102_400_000]
            if !list { row["body"] = "Synthetic private body" }
        } else {
            row = ["id": id, "requestId": field("requestId") ?? "goals_request_000001", "metric": "DISTINCT_ROUTES", "target": 5, "startDate": "2026-10-19", "endDateExclusive": "2026-11-01", "progress": 2, "state": "ACTIVE", "privateCommemoration": false, "timeZone": "Asia/Shanghai", "countingVersion": "COMPLETED_SESSION_AGGREGATE_V1", "asOfMs": 1_792_382_400_000, "createdAtMs": 1_792_382_400_000]
        }
        let data: [String: Any] = list ? ["items": empty ? [] : [row], "hasMore": !empty && !more, "nextBeforeId": !empty && !more ? id as Any : NSNull()] : row
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
}
