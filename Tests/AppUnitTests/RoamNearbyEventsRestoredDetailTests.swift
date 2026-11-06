import XCTest
import SwiftUI
@testable import Questify

@MainActor final class RoamNearbyEventsRestoredDetailTests: XCTestCase {
    private func activity(_ id: Int = 71) throws -> ActivityDetailAccess {
        .allowed(try JSONDecoder().decode(ActivityDetail.self, from: Data("{\"id\":\(id),\"name\":\"Synthetic activity\"}".utf8)))
    }
    private func topic(_ id: Int = 81) throws -> TopicDetail {
        try JSONDecoder().decode(TopicDetail.self, from: Data("{\"id\":\(id),\"name\":\"Synthetic topic\"}".utf8))
    }
    func testActivityFacadeReadsExactActivityWithoutExposingSessionOrList() async throws {
        let base = ActivityBase(result: try activity()), reader = RoamNearbyEventsActivityReader(id: 71, base: base)
        let value = try await reader.activityDetail(id: 71)
        XCTAssertEqual(value, try activity()); XCTAssertEqual(base.ids, [71]); XCTAssertFalse(reader.activityListIsConfigured)
        let view = ActivityDetailView(id: 71, reader: reader, registrationEnabled: false)
        XCTAssertFalse(view.registrationEnabled); XCTAssertNil(view.playReaderForActivity); XCTAssertNil(view.peopleProfile)
        do { _ = try await reader.activities(page: 1, keyword: ""); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await reader.activityDetail(id: 81); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertEqual(base.ids, [71])
    }
    func testActivityGateDenialMissingAndRetryNeverFallbackToListedCard() async throws {
        let base = ActivityBase(result: .clubRequired(clubID: 41, message: "Synthetic gate"))
        let reader = RoamNearbyEventsActivityReader(id: 71, base: base)
        let gated = try await reader.activityDetail(id: 71)
        XCTAssertEqual(gated, .clubRequired(clubID: 41, message: "Synthetic gate"))
        for error in [APIError.httpStatus(403), .httpStatus(404), .httpStatus(410), .unauthorized] {
            base.error = error
            do { _ = try await reader.activityDetail(id: 71); XCTFail() } catch { XCTAssertEqual(error as? APIError, base.error) }
        }
        base.error = nil; base.result = try activity()
        let recovered = try await reader.activityDetail(id: 71); XCTAssertEqual(recovered, try activity())
    }
    func testActivityRejectsSubstitutedResponseID() async throws {
        let base = ActivityBase(result: try activity(81)), reader = RoamNearbyEventsActivityReader(id: 71, base: base)
        do { _ = try await reader.activityDetail(id: 71); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testActivityScopeChangeRetiresLateSuccessAndError() async throws {
        for failed in [false, true] {
            let base = ActivityBase(result: try activity()), reader = RoamNearbyEventsActivityReader(id: 71, base: base)
            base.hold = true; let held = expectation(description: "activity held"); base.onHeld = { held.fulfill() }
            let task = Task { try await reader.activityDetail(id: 71) }; await fulfillment(of: [held], timeout: 2)
            base.activityPresentationIdentity = "new-session"
            base.pending?.resume(with: failed ? .failure(APIError.unauthorized) : .success(try activity()))
            do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertFalse(reader.isConfigured)
        }
    }
    func testActivityCancellationRejectsLateDetail() async throws {
        let base = ActivityBase(result: try activity()), reader = RoamNearbyEventsActivityReader(id: 71, base: base)
        base.hold = true; let held = expectation(description: "cancelled activity"); base.onHeld = { held.fulfill() }
        let task = Task { try await reader.activityDetail(id: 71) }; await fulfillment(of: [held], timeout: 2)
        task.cancel(); base.pending?.resume(returning: try activity())
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testTopicFacadePreservesSourceTopicButGrantsNoRegistrationOrWriter() async throws {
        let base = TopicBase(result: try topic()), reader = RoamNearbyEventsTopicReader(id: 81, base: base)
        let result = try await reader.topicDetail(id: 81); XCTAssertEqual(result.id, 81)
        let view = TopicDetailView(id: 81, reader: reader)
        XCTAssertNil(view.activityDestination); XCTAssertNil(view.selfPlayDestination); XCTAssertNil(view.reviewOwner); XCTAssertNil(view.publisherDestination)
        do { _ = try await reader.topicDetail(id: 71); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        do { _ = try await reader.topicList(query: .init(), pageNumber: 1); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(base.ids, [81])
    }
    func testTopicRejectsSubstitutedIDAndNewScopeCannotReopen() async throws {
        let base = TopicBase(result: try topic(82)), reader = RoamNearbyEventsTopicReader(id: 81, base: base)
        do { _ = try await reader.topicDetail(id: 81); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        base.scope = UUID(); XCTAssertFalse(reader.isConfigured)
        do { _ = try await reader.topicDetail(id: 81); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(base.ids, [81])
    }
    func testTopicScopeChangeRetiresLateSuccessAndError() async throws {
        for failed in [false, true] {
            let base = TopicBase(result: try topic()), reader = RoamNearbyEventsTopicReader(id: 81, base: base)
            base.hold = true; let held = expectation(description: "topic held"); base.onHeld = { held.fulfill() }
            let task = Task { try await reader.topicDetail(id: 81) }; await fulfillment(of: [held], timeout: 2)
            base.scope = UUID()
            base.pending?.resume(with: failed ? .failure(APIError.unauthorized) : .success(try topic()))
            do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        }
    }
    @MainActor private final class ActivityBase: ActivityReading {
        var isConfigured = true, activityPresentationIdentity = "synthetic-session"
        var result: ActivityDetailAccess, error: APIError?, ids: [Int] = []
        var hold = false, onHeld: (() -> Void)?
        var pending: CheckedContinuation<ActivityDetailAccess, Error>?
        init(result: ActivityDetailAccess) { self.result = result }
        func activities(page: Int, keyword: String) async throws -> [ActivitySummary] { XCTFail("No list grant"); return [] }
        func activityDetail(id: Int) async throws -> ActivityDetailAccess {
            ids.append(id)
            if hold { return try await withCheckedThrowingContinuation { pending = $0; onHeld?() } }
            if let error { throw error }; return result
        }
    }
    @MainActor private final class TopicBase: TopicReading {
        var isConfigured = true
        let isOfflineExample = true
        var scope = UUID(), ids: [Int] = []
        var result: TopicDetail, hold = false, onHeld: (() -> Void)?
        var pending: CheckedContinuation<TopicDetail, Error>?
        init(result: TopicDetail) { self.result = result }
        func topicList(query: TopicQuery, pageNumber: Int) async throws -> TopicPage { throw APIError.notConfigured }
        func topicDetail(id: Int) async throws -> TopicDetail {
            ids.append(id)
            if hold { return try await withCheckedThrowingContinuation { pending = $0; onHeld?() } }
            return result
        }
    }
}


import UIKit

/// New actual-browser hosts use the original approved entry reader and an in-memory HTTP transport.
/// The detail destination is a read-only probe; neither GPS nor business writers are exercised.
@MainActor final class RoamNearbyEventsOriginalHostTests: XCTestCase {
    func testOptionalTeamFailureKeepsOriginalActivityAndOpensOnlyExactReadOnlyTopic() async throws {
        let rig = try NearbyEntryRig(), window = mount(rig)
        defer { close(window) }
        try await reveal("roam.home.peek.teamsFailed", in: window)
        try await tap("roam.home.peek.card.activity-71", in: window)
        try await reveal("roam.home.sheet.primary", in: window)
        XCTAssertNil(find("roam.home.sheet.createTeam", in: window))
        try await tap("roam.home.sheet.primary", in: window)
        try await reveal("nearby.original.readOnly", in: window)
        XCTAssertFalse(rig.opened.isEmpty); XCTAssertTrue(rig.opened.allSatisfy { $0 == .topic(81) })
        XCTAssertEqual(rig.legacyOpens, 0, "The current root's separate detail closure must win")
        rig.access.revoke()
        try await waitFor("Old entry scope cannot keep a detail open") {
            self.find("nearby.original.readOnly", in: window) == nil
        }
        XCTAssertEqual(rig.wire.requests.count, 1); XCTAssertEqual(rig.legacyOpens, 0)
    }

    func testMissingManualCentreUsesOriginalAreaActionWithoutDispatchOrLocation() async throws {
        let rig = try NearbyEntryRig(selectArea: false), window = mount(rig)
        defer { close(window) }
        try await reveal("roam.home.peek.areaRequired", in: window)
        XCTAssertTrue(rig.wire.requests.isEmpty)
        let title = String(localized: LocalizedStringResource("roam.area.title", locale: Locale(identifier: "en_US")))
        try await tap(title, in: window, byLabel: true)
        try await reveal("roam.home.peek.card.activity-71", in: window)
        XCTAssertEqual(rig.areaChoices, 1); XCTAssertEqual(rig.wire.requests.count, 1)
        XCTAssertEqual(rig.wire.fields.last, ["lat":"31.2", "lng":"121.4", "radius":"3000"])
    }

    func testExplicitTeamRetryReadsOriginalSameCentreAndDoesNotInventEmptySuccess() async throws {
        let rig = try NearbyEntryRig(), window = mount(rig)
        defer { close(window) }
        try await reveal("roam.home.peek.teamsFailed", in: window)
        XCTAssertNotNil(find("roam.home.peek.card.activity-71", in: window))
        XCTAssertNil(find("roam.home.peek.empty", in: window))
        rig.teamsFail = false
        try await tap("roam.home.peek.teamsRetry", in: window)
        try await waitFor("Original activity and optional teams recover") {
            rig.wire.requests.count == 2 && self.find("roam.home.peek.teamsFailed", in: window) == nil &&
            self.find("roam.home.peek.card.activity-71", in: window) != nil
        }
        XCTAssertEqual(rig.wire.fields[0], rig.wire.fields[1]); XCTAssertEqual(rig.teamAreas.count, 2)
        XCTAssertEqual(rig.teamAreas[0], rig.teamAreas[1]); XCTAssertTrue(rig.opened.isEmpty)
    }

    func testCurrentHTTPFailureRetiresCardThenOriginalRetryRecoversWithoutGrantExpansion() async throws {
        let rig = try NearbyEntryRig(), window = mount(rig)
        defer { close(window) }
        try await reveal("roam.home.peek.card.activity-71", in: window)
        rig.wire.status = 503
        try await tap("roam.home.peek.refresh", in: window)
        try await reveal("roam.home.peek.failed", in: window)
        XCTAssertNil(find("roam.home.peek.card.activity-71", in: window)); XCTAssertNil(find("roam.home.peek.empty", in: window))
        rig.wire.status = 200
        try await tap("roam.home.peek.retry", in: window)
        try await reveal("roam.home.peek.card.activity-71", in: window)
        XCTAssertEqual(rig.wire.requests.count, 3)
        rig.access.revoke()
        try await reveal("roam.home.peek.unavailable", in: window)
        XCTAssertNil(find("roam.home.peek.card.activity-71", in: window)); XCTAssertEqual(rig.wire.requests.count, 3)
    }

    private func mount(_ rig: NearbyEntryRig) -> UIWindow {
        let host = UIHostingController(rootView: RoamBrowserView(reader: rig.map,
            onChooseArea: { rig.chooseArea() }, eventDestination: { _ in
                rig.legacyOpens += 1; return AnyView(Text("Legacy business destination"))
            }, nearbyEventDestination: { value in
                rig.opened.append(value); return AnyView(Text("Original read-only detail").accessibilityIdentifier("nearby.original.readOnly"))
            }, entryReader: rig.reader, entryTeams: { area in
                rig.teamAreas.append(area); return rig.teamsFail ? nil : []
            }).environment(\.locale, Locale(identifier: "en_US")).environment(\.scenePhase, .active))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1100))
        window.rootViewController = host; window.makeKeyAndVisible()
        host.loadViewIfNeeded(); host.view.layoutIfNeeded(); return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    private func waitFor(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTFail(message); throw APIError.notConfigured
    }
    private func reveal(_ id: String, in window: UIWindow, byLabel: Bool = false) async throws {
        for _ in 0..<35 {
            if find(id, in: window, byLabel: byLabel) != nil { return }
            scroll(window); try await Task.sleep(nanoseconds: 40_000_000)
        }
        XCTFail("Original control missing: " + id); throw APIError.notConfigured
    }
    private func scroll(_ view: UIView) {
        if let scroll = view as? UIScrollView {
            let maxY = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            if scroll.contentOffset.y < maxY {
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(maxY, scroll.contentOffset.y + 300)), animated: false)
                scroll.layoutIfNeeded()
            }
        }
        for child in view.subviews { scroll(child) }
    }
    private func tap(_ id: String, in window: UIWindow, byLabel: Bool = false) async throws {
        try await reveal(id, in: window, byLabel: byLabel)
        let target = try XCTUnwrap(find(id, in: window, byLabel: byLabel))
        if let control = target as? UIControl { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(target.accessibilityActivate()) }
    }
    private func find(_ id: String, in window: UIWindow, byLabel: Bool = false) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ root: NSObject) -> NSObject? {
            guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
            if byLabel && root.accessibilityLabel == id { return root }
            if !byLabel && (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
            if let view = root as? UIView { for child in view.subviews { if let value = visit(child) { return value } } }
            if let children = root.accessibilityElements {
                for child in children { if let child = child as? NSObject, let value = visit(child) { return value } }
            }
            let count = root.accessibilityElementCount()
            if count > 0 && count < 1000 {
                for index in 0..<count { if let child = root.accessibilityElement(at: index) as? NSObject, let value = visit(child) { return value } }
            }
            return nil
        }
        return visit(window)
    }
}

@MainActor private final class NearbyEntryRig {
    let reader: RoamEntryNearbyReader
    let access: RoamEntryNearbyReadAccess
    let map: RoamSessionReader
    let selection: ManualMapAreaSelection
    let wire: NearbyEntryWire
    var teamsFail = true, legacyOpens = 0, areaChoices = 0
    var teamAreas: [RoamSearchArea] = [], opened: [RoamEventDestination] = []
    private let area = RoamSearchArea(coordinate: RoamCoordinate(latitude: 31.2, longitude: 121.4)!, label: "Synthetic manual centre")
    init(selectArea: Bool = true) throws {
        let selection = ManualMapAreaSelection(), wire = NearbyEntryWire()
        self.selection = selection; self.wire = wire
        let base = URL(string: "https://example.test/nearby-original")!
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 81, epoch: 1, namespace: "nearby-original", token: "synthetic-nearby-original"))
        let access = try RoamEntryNearbyReadAccess(context: context, approval: .init(baseURL: base,
            namespace: context.session.namespace, accountID: 81, paths: [RoamEntryNearbyRoute.path]))
        self.access = access
        reader = .init(configuration: try .init(baseURL: base), transport: wire, current: { context }, viewerRevision: { 0 },
                       area: { selection.snapshot }, access: { _ in access })
        map = .init(service: nil, currentSession: { nil }, searchArea: { nil })
        if selectArea { selection.select(area) }
    }
    func chooseArea() { areaChoices += 1; selection.select(area) }
}
@MainActor private final class NearbyEntryWire: HTTPTransport {
    var requests: [URLRequest] = [], fields: [[String: String]] = []
    var status = 200
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard request.httpMethod == "GET", request.url?.path.hasSuffix("/api/roam/entry/nearby") == true,
              request.value(forHTTPHeaderField: "Authorization") == "synthetic-nearby-original" else {
            XCTFail("Only original approved entry GET is expected"); throw APIError.notConfigured
        }
        fields.append(Dictionary(uniqueKeysWithValues: (URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") }))
        if status != 200 { return (Data(#"{"code":503}"#.utf8), status) }
        return (Data(#"{"code":200,"data":{"radius":3000,"items":[{"id":71,"kind":"activity","topicId":81,"name":"Synthetic activity","productType":2}]}}"#.utf8), 200)
    }
}
