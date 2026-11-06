import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamPassportToolsGrantScopeHostTests: XCTestCase {
    func testPageOwnerUsesChosenGrantNotJustSameIdentity() throws {
        let r = try PassportScopeHostRig(), old = RoamPassportToolsPageOwner(r.reader)
        XCTAssertTrue(old.matches(r.reader)); try r.replaceGrant()
        XCTAssertEqual(old.identity, r.reader.identity); XCTAssertFalse(old.matches(r.reader))
        XCTAssertTrue(RoamPassportToolsPageOwner(r.reader).matches(r.reader)); XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testUnusedFallbackChangeCannotRetirePrivateGrantPage() throws {
        let r = try PassportScopeHostRig(); r.privateAccess = try r.privateGrant()
        let old = RoamPassportToolsPageOwner(r.reader)
        try r.replaceGrant(); XCTAssertTrue(old.matches(r.reader))
        r.privateAccess?.revoke(); XCTAssertFalse(old.matches(r.reader)); XCTAssertTrue(r.reader.isConfigured)
    }
    func testQueuedAnniversaryIntentCannotBorrowReplacementGrant() throws {
        let r = try PassportScopeHostRig(); var state = RoamAnniversaryListState(), nav = RoamAnniversaryNavigationState()
        state.bind(to: r.reader.identity); nav.bind(to: r.reader.identity)
        let visit = UUID(), old = RoamAnniversaryReadIntent(intent: .refresh, reader: r.reader, state: state, navigation: nav, visit: visit)
        XCTAssertTrue(old.matches(reader: r.reader, state: state, navigation: nav, visit: visit))
        try r.replaceGrant()
        XCTAssertFalse(old.matches(reader: r.reader, state: state, navigation: nav, visit: visit))
        let fresh = RoamAnniversaryReadIntent(intent: .refresh, reader: r.reader, state: state, navigation: nav, visit: visit)
        XCTAssertTrue(fresh.matches(reader: r.reader, state: state, navigation: nav, visit: visit))
        XCTAssertTrue(r.wire.requests.isEmpty)
    }
    func testNonSessionExampleAndNilRemainTheOriginalIdentityContract() {
        let fixture = RoamPassportToolsFixtureReader(), owner = RoamPassportToolsPageOwner(nil)
        XCTAssertNil(RoamPassportToolsPageOwner(fixture).readScope)
        XCTAssertTrue(RoamPassportToolsPageOwner(fixture).matches(fixture))
        XCTAssertTrue(owner.matches(nil)); XCTAssertFalse(owner.matches(fixture))
    }
    func testOriginalAnniversaryEntryRereadsNewGrantWithoutReusingOldIntent() async throws {
        let r = try PassportScopeHostRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        mount(r, window: scene.window)
        try await tap("roam.tools.anniversary.open", in: scene.window)
        try await eventually { self.find("roam.tools.anniversary.row", in: scene.window) != nil }
        XCTAssertEqual(r.wire.requests.count, 1)
        r.wire.version = "Fresh"; try r.replaceGrant()
        try await eventually { r.wire.requests.count == 2 && self.find("roam.tools.anniversary.row", in: scene.window) != nil }
        XCTAssertEqual(r.wire.paths, ["exploration-anniversary", "exploration-anniversary"])
        XCTAssertTrue(r.wire.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    }
    func testAnniversaryRouteCoverSurvivesStableScopeButReplacementRetiresDestination() async throws {
        let r = try PassportScopeHostRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        mount(r, window: scene.window)
        try await tap("roam.tools.anniversary.open", in: scene.window)
        try await tap("roam.tools.anniversary.openRoute", in: scene.window)
        try await eventually { self.find("passport.scope.route", in: scene.window) != nil }
        let original = RoamPassportToolsPageOwner(r.reader), count = r.wire.requests.count
        XCTAssertTrue(original.matches(r.reader)); XCTAssertEqual(r.wire.requests.count, count)
        try r.replaceGrant()
        try await eventually { self.find("passport.scope.route", in: scene.window) == nil }
        XCTAssertFalse(original.matches(r.reader))
        XCTAssertTrue(r.wire.requests.allSatisfy { $0.url?.lastPathComponent == "exploration-anniversary" })
    }
    func testOriginalMonthlyDetailCannotRemainOrRereadUnderReplacementGrant() async throws {
        let r = try PassportScopeHostRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        mount(r, window: scene.window)
        try await tap("roam.tools.recap.open", in: scene.window)
        try await tap("roam.tools.recap.row", in: scene.window)
        try await eventually { self.find("roam.tools.recap.detail.openRoute", in: scene.window) != nil }
        r.wire.version = "Fresh"; try r.replaceGrant()
        try await eventually { self.find("roam.tools.recap.detail.openRoute", in: scene.window) == nil }
        try await eventually { r.wire.requests.count == 2 && self.find("roam.tools.recap.row", in: scene.window) != nil }
        XCTAssertEqual(r.wire.paths, ["monthly-recap", "monthly-recap"])
    }
    func testMonthlyRevocationShowsUnavailableThenFreshGrantRecoversThroughOriginalEntry() async throws {
        let r = try PassportScopeHostRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        mount(r, window: scene.window); try await tap("roam.tools.recap.open", in: scene.window)
        try await eventually { self.find("roam.tools.recap.row", in: scene.window) != nil }
        r.readAccess?.revoke()
        try await eventually { self.find("roam.tools.recap.row", in: scene.window) == nil && self.find("roam.tools.recap.error", in: scene.window) != nil }
        XCTAssertEqual(r.wire.requests.count, 1)
        try r.replaceGrant()
        try await eventually { r.wire.requests.count == 2 && self.find("roam.tools.recap.row", in: scene.window) != nil }
    }
    func testHeldMonthlyReadCannotResurrectOldScopeAfterNewGrantRead() async throws {
        let r = try PassportScopeHostRig(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        r.wire.hold = true; mount(r, window: scene.window); try await tap("roam.tools.recap.open", in: scene.window)
        try await eventually { r.wire.pending != nil }
        r.wire.hold = false; r.wire.version = "Fresh"; try r.replaceGrant()
        try await eventually { r.wire.requests.count == 2 && self.find("roam.tools.recap.row", in: scene.window) != nil }
        r.wire.finish(); try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(r.wire.requests.count, 2)
        XCTAssertNil(find("roam.tools.recap.error", in: scene.window))
    }
    private func mount(_ rig: PassportScopeHostRig, window: UIWindow) {
        let host = UIHostingController(rootView: PassportScopeHost(rig: rig))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded()
    }
    private func eventually(_ ready: () -> Bool) async throws {
        for _ in 0..<150 { if ready() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Original passport tools host did not settle"); throw APIError.notConfigured
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        try await eventually { self.find(id, in: window) != nil }
        let target = try XCTUnwrap(find(id, in: window))
        if let control = target as? UIControl { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(target.accessibilityActivate()) }
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ node: NSObject) -> NSObject? {
            guard seen.insert(ObjectIdentifier(node)).inserted else { return nil }
            if (node as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return node }
            if let elements = node.accessibilityElements { for case let child as NSObject in elements { if let found = visit(child) { return found } } }
            if let view = node as? UIView { for child in view.subviews { if let found = visit(child) { return found } } }
            let count = node.accessibilityElementCount()
            if count > 0 && count < 1000 { for index in 0..<count { if let child = node.accessibilityElement(at: index) as? NSObject, let found = visit(child) { return found } } }
            return nil
        }
        return visit(window)
    }
}
@MainActor private struct PassportScopeHost: View {
    @ObservedObject var rig: PassportScopeHostRig
    var body: some View {
        NavigationStack {
            List {
                RoamPassportToolsSection(reader: rig.reader, routeDestination: { id in
                    AnyView(Text("Synthetic route " + id).accessibilityIdentifier("passport.scope.route"))
                })
            }
        }.environment(\.scenePhase, .active)
    }
}
@MainActor private final class PassportScopeHostRig: ObservableObject {
    static let base = URL(string: "https://example.test/passport-scope-host")!
    let context: RuntimeDependencyContext
    let wire = PassportScopeHostWire()
    @Published var privateAccess: RoamPrivateToolsAccess?
    @Published var readAccess: RoamPassportToolsReadAccess?
    lazy var reader = RoamPassportToolsSessionReader(service: try! .init(configuration: .init(baseURL: Self.base), transport: wire),
        current: { [weak self] in self?.context }, access: { [weak self] _ in self?.privateAccess },
        readAccess: { [weak self] _ in self?.readAccess })
    init() throws {
        context = .init(market: .china, baseURL: Self.base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "passport-scope-host", token: "synthetic-passport-scope"))
        try replaceGrant()
    }
    func replaceGrant() throws {
        readAccess = try .init(context: context, approval: .init(baseURL: Self.base, namespace: context.session.namespace,
            accountID: context.session.accountID, paths: Set(RoamPassportToolsService.paths)))
    }
    func privateGrant() throws -> RoamPrivateToolsAccess {
        try .init(context: context, approval: .init(baseURL: Self.base, namespace: context.session.namespace,
            accountID: context.session.accountID, paths: Set(RoamPassportToolsService.paths)))
    }
}
@MainActor private final class PassportScopeHostWire: HTTPTransport {
    var requests: [URLRequest] = []
    var paths: [String] { requests.compactMap { $0.url?.lastPathComponent } }
    var version = "Original", hold = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    private var held = Data()
    func finish() { let result = pending; pending = nil; result?.resume(returning: (held, 200)) }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard request.httpMethod == "GET", request.httpBody == nil else { XCTFail("No writer belongs here"); throw APIError.notConfigured }
        let values = Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        let data: Data
        switch request.url?.lastPathComponent {
        case "monthly-recap":
            let month = values["month"]!, kind = values["kind"]!
            data = Data(#"{"code":200,"data":{"month":"\#(month)","kind":"\#(kind)","timeZone":"Asia/Shanghai","counts":{"routes":1,"places":1,"stamps":1},"items":[{"id":"90","objectId":7001,"title":"\#(version) monthly","occurredAt":"\#(month)-01 10:00:00"}],"hasMore":false,"nextBeforeId":null}}"#.utf8)
        case "exploration-anniversary":
            let now = Int64(Date().timeIntervalSince1970 * 1000), today = RoamShanghaiCalendar.day(atMilliseconds: now)
            let month = Int(values["month"] ?? "") ?? today.month, day = Int(values["day"] ?? "") ?? today.day
            var year = today.year - 1
            if month == 2 && day == 29 { while !((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) { year -= 1 } }
            let completed = String(format: "%04d-%02d-%02d 12:34:56.000", year, month, day)
            let object: [String: Any] = ["month": month, "day": day, "referenceYear": today.year, "asOfMs": now,
                "items": [["id": "90", "topicId": "7001", "title": version + " anniversary", "completedAt": completed, "year": year, "yearsAgo": today.year - year]],
                "hasMore": false, "nextCursor": NSNull(), "timeZone": "Asia/Shanghai", "leapDayRule": "EXACT_MONTH_DAY_ONLY",
                "coverage": "RECORDED_OWN_COMPLETED_SESSIONS_WITH_CURRENT_VISIBLE_ROUTE", "metadataMode": "CURRENT_ROUTE_METADATA"]
            data = try JSONSerialization.data(withJSONObject: ["code": 200, "data": object])
        default: XCTFail("Unexpected original route"); throw APIError.notConfigured
        }
        if hold { held = data; return try await withCheckedThrowingContinuation { pending = $0 } }
        return (data, 200)
    }
}
