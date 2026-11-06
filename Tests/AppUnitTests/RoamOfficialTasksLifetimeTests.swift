import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// The original list model/detail, new memory readers, no action provider or real service.
@MainActor final class RoamOfficialTasksLifetimeTests: XCTestCase {
    private let live = OfficialEventBrowseQuery(bucket: .live, keyword: "")
    func testUnshownAndBackgroundListCannotStartEitherOriginalRead() async throws {
        let r = OfficialTaskLifetimeRig()
        r.page.readAction()(); await r.page.refreshAction()(); r.page.appear(foreground: false)
        await settle(); XCTAssertTrue(r.official.calls.isEmpty); XCTAssertFalse(r.page.isVisible)
        r.page.setForeground(true, preservingSnapshot: false)
        try await waitFor { r.page.model.snapshot != nil }
        XCTAssertEqual(r.official.calls, ["all", "mine"]); XCTAssertEqual(r.roam.reads, 0)
    }
    func testRenderedRetryAndRefreshCannotCrossLeaveAndReentry() async throws {
        let r = OfficialTaskLifetimeRig(); r.page.appear(foreground: true)
        try await waitFor { r.page.model.snapshot != nil }
        let retry = r.page.readAction(), refresh = r.page.refreshAction()
        r.page.disappear(preservingSnapshot: false); r.page.appear(foreground: true)
        retry(); await refresh(); try await waitFor { r.page.model.snapshot != nil }; await settle()
        XCTAssertEqual(r.official.calls, ["all", "mine", "all", "mine"])
    }
    func testQueuedTaskCannotStartAfterBackgroundBeforeItsFirstTurn() async throws {
        let r = OfficialTaskLifetimeRig(); r.page.appear(foreground: true)
        try await waitFor { r.page.model.snapshot != nil }
        r.page.readAction()()
        r.page.setForeground(false, preservingSnapshot: false)
        r.page.setForeground(true, preservingSnapshot: false)
        try await waitFor { r.page.model.snapshot != nil }; await settle()
        XCTAssertEqual(r.official.calls, ["all", "mine", "all", "mine"])
    }
    func testCancelledRefreshCannotStartPublicOrPrivateRead() async throws {
        let r = OfficialTaskLifetimeRig(); r.page.appear(foreground: true)
        try await waitFor { r.page.model.snapshot != nil }
        let refresh = r.page.refreshAction(), task = Task { await refresh() }
        task.cancel(); await task.value
        XCTAssertEqual(r.official.calls, ["all", "mine"])
    }
    func testLateFirstReadAfterLeaveNeverDispatchesPrivateSecondRead() async throws {
        let r = OfficialTaskLifetimeRig(); r.official.holdAll = true; r.page.appear(foreground: true)
        try await waitFor { !r.official.pendingAll.isEmpty }
        r.page.disappear(preservingSnapshot: false)
        r.official.pendingAll.removeFirst().resume(returning: [try OfficialTaskLifetimeOfficial.row(71)])
        await settle(); XCTAssertEqual(r.official.calls, ["all"]); XCTAssertNil(r.page.model.snapshot)
    }
    func testLatePrivateReadCannotOverwriteFreshForegroundSnapshot() async throws {
        let r = OfficialTaskLifetimeRig(); r.official.holdMine = true; r.page.appear(foreground: true)
        try await waitFor { !r.official.pendingMine.isEmpty }
        r.page.setForeground(false, preservingSnapshot: false)
        r.official.holdMine = false; r.official.rowID = 91; r.page.setForeground(true, preservingSnapshot: false)
        try await waitFor { r.page.model.snapshot?.all.first?.id == 91 }
        let fresh = try XCTUnwrap(r.page.model.snapshot)
        r.official.pendingMine.removeFirst().resume(returning: [try OfficialTaskLifetimeOfficial.row(81)])
        await settle(); XCTAssertEqual(r.page.model.snapshot?.id, fresh.id)
        XCTAssertEqual(r.page.model.snapshot?.mine.map(\.id), [101])
        XCTAssertEqual(r.official.calls, ["all", "mine", "all", "mine"])
    }
    func testPushedTargetSurvivesHiddenParentForegroundWithoutAnotherListRead() async throws {
        let r = OfficialTaskLifetimeRig(); r.page.appear(foreground: true)
        try await waitFor { r.page.model.snapshot != nil }
        let snapshot = try XCTUnwrap(r.page.model.snapshot)
        let target = try XCTUnwrap(r.page.model.select(eventID: 71, query: live, renderedSnapshotID: snapshot.id))
        r.page.disappear(preservingSnapshot: true)
        r.page.setForeground(false, preservingSnapshot: true); r.page.setForeground(true, preservingSnapshot: true)
        await settle(); XCTAssertFalse(r.page.isVisible); XCTAssertTrue(r.page.model.mayRemainOpen(target))
        XCTAssertEqual(r.page.model.snapshot?.id, snapshot.id); XCTAssertEqual(r.official.calls, ["all", "mine"])
        r.page.appear(foreground: true); try await waitFor { r.official.calls.count == 4 && r.page.model.snapshot != nil }
        XCTAssertFalse(r.page.model.mayRemainOpen(target)); XCTAssertNotEqual(r.page.model.snapshot?.id, snapshot.id)
    }
    func testSourceScopeChangeRejectsOldActionAndPreservesOriginalRevocationSignal() async throws {
        let r = OfficialTaskLifetimeRig(); r.page.appear(foreground: true)
        try await waitFor { r.page.model.snapshot != nil }
        let snapshot = try XCTUnwrap(r.page.model.snapshot)
        let target = try XCTUnwrap(r.page.model.select(eventID: 71, query: live, renderedSnapshotID: snapshot.id))
        let retry = r.page.readAction(); r.official.scope = UUID(); r.official.signal.invalidate(); retry(); await settle()
        XCTAssertEqual(r.official.calls, ["all", "mine"]); XCTAssertNil(r.page.model.snapshot)
        XCTAssertFalse(r.page.model.mayRemainOpen(target)); XCTAssertTrue(r.page.model.error is OfficialReadInvalidationFailure)
        r.official.isAuthenticated = false; r.page.appear(foreground: true)
        try await waitFor { r.page.model.error as? APIError == .unauthorized }
        XCTAssertEqual(r.official.calls, ["all", "mine"]); XCTAssertEqual(r.roam.reads, 0)
    }
    func testCurrentOwnerNotificationRecoversOnlyMountedForegroundList() async throws {
        let r = OfficialTaskLifetimeRig(); r.page.appear(foreground: true)
        try await waitFor { r.page.model.snapshot != nil }
        let stale = r.page.readAction(); r.official.scope = UUID(); r.official.rowID = 91
        r.page.ownerChanged(); stale()
        try await waitFor { r.page.model.snapshot?.all.first?.id == 91 }
        XCTAssertEqual(r.official.calls, ["all", "mine", "all", "mine"])
        r.page.disappear(preservingSnapshot: true); r.official.scope = UUID(); r.page.ownerChanged(); await settle()
        XCTAssertNil(r.page.model.snapshot); XCTAssertEqual(r.official.calls, ["all", "mine", "all", "mine"])
    }
    func testOriginalPartialFailureAndForbiddenKeepDistinctSnapshotRules() async throws {
        let r = OfficialTaskLifetimeRig(); r.page.appear(foreground: true)
        try await waitFor { r.page.model.snapshot != nil }
        let old = try XCTUnwrap(r.page.model.snapshot)
        r.official.mineFailure = APIError.httpStatus(503); await r.page.refreshAction()()
        XCTAssertEqual(r.page.model.snapshot?.id, old.id); XCTAssertNotNil(r.page.model.error)
        r.official.mineFailure = OfficialReadFailure.forbidden; await r.page.refreshAction()()
        XCTAssertNil(r.page.model.snapshot); XCTAssertEqual(r.page.model.error as? OfficialReadFailure, .forbidden)
        r.official.mineFailure = nil; r.official.empty = true; await r.page.refreshAction()()
        XCTAssertNotNil(r.page.model.snapshot); XCTAssertTrue(r.page.model.snapshot!.all.isEmpty); XCTAssertNil(r.page.model.error)
    }
    func testActualListHidesInBackgroundAndReturnsWithCurrentRows() async throws {
        let state = OfficialTaskLifetimeHostState(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        mount(state, in: scene.window); try await waitFor { self.find("roam.tasks.event.71", in: scene.window) != nil }
        state.phase = .background
        try await waitFor { self.find("roam.tasks.event.71", in: scene.window) == nil }
        XCTAssertNil(find("roam.tasks.empty", in: scene.window)); XCTAssertEqual(state.official.calls, ["all", "mine"])
        state.official.rowID = 91; state.phase = .active
        try await waitFor { self.find("roam.tasks.event.91", in: scene.window) != nil }
        XCTAssertNil(find("roam.tasks.event.71", in: scene.window)); XCTAssertEqual(state.official.calls, ["all", "mine", "all", "mine"])
    }
    func testActualDetailPushAndBackUseOriginalTargetWithoutHiddenParentRead() async throws {
        let state = OfficialTaskLifetimeHostState(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        mount(state, in: scene.window); try await tap("roam.tasks.event.71", in: scene.window)
        try await waitFor { state.official.details == [71] && self.find("official.detail.content", in: scene.window) != nil }
        state.phase = .background; try await Task.sleep(for: .milliseconds(150)); state.phase = .active
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(state.official.calls, ["all", "mine"])
        XCTAssertNotNil(find("official.detail.content", in: scene.window), "The original accepted detail must not lose its snapshot")
        state.official.rowID = 91
        let nav = try XCTUnwrap(navigation(scene.window.rootViewController)); XCTAssertNotNil(nav.popViewController(animated: false))
        try await waitFor { self.find("roam.tasks.event.91", in: scene.window) != nil }
        XCTAssertEqual(state.official.calls, ["all", "mine", "all", "mine"]); XCTAssertTrue(state.official.details.allSatisfy { $0 == 71 })
    }
    func testActualSameScopeReaderReplacementCannotRetainOldViewModel() async throws {
        let state = OfficialTaskLifetimeHostState(), old = state.official, scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        mount(state, in: scene.window); try await waitFor { self.find("roam.tasks.event.71", in: scene.window) != nil }
        let fresh = OfficialTaskLifetimeOfficial(); fresh.scope = old.scope; fresh.rowID = 91; state.official = fresh
        try await waitFor { self.find("roam.tasks.event.91", in: scene.window) != nil }
        XCTAssertNil(find("roam.tasks.event.71", in: scene.window))
        XCTAssertEqual(fresh.calls, ["all", "mine"]); XCTAssertEqual(old.calls, ["all", "mine"])
    }
    func testActualErrorRetrySuccessfulEmptyAndSignoutStayDistinct() async throws {
        let state = OfficialTaskLifetimeHostState(), scene = try HostedNavigationSceneWindow(); defer { scene.retire() }
        state.official.mineFailure = APIError.httpStatus(503); mount(state, in: scene.window)
        try await waitFor { self.find("roam.tasks.error", in: scene.window) != nil }
        XCTAssertNil(find("roam.tasks.empty", in: scene.window))
        state.official.mineFailure = nil; state.official.empty = true; try await tap("official.retry", in: scene.window)
        try await waitFor { self.find("roam.tasks.empty", in: scene.window) != nil }
        XCTAssertNil(find("roam.tasks.error", in: scene.window))
        let calls = state.official.calls; state.roam.identity = nil; state.official.isAuthenticated = false; state.revision += 1
        try await waitFor { self.find("roam.tasks.error", in: scene.window) != nil }
        XCTAssertNil(find("roam.tasks.empty", in: scene.window)); XCTAssertEqual(state.official.calls, calls)
    }
    private func mount(_ state: OfficialTaskLifetimeHostState, in window: UIWindow) {
        let host = UIHostingController(rootView: OfficialTaskLifetimeHost(state: state))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded()
    }
    private func settle() async { for _ in 0..<20 { await Task.yield() } }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Original official task journey did not settle"); throw APIError.notConfigured
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        for _ in 0..<100 {
            if let target = find(id, in: window) {
                if let control = target as? UIControl { control.sendActions(for: .touchUpInside) }
                else { XCTAssertTrue(target.accessibilityActivate()) }; return
            }
            scroll(window); try await Task.sleep(for: .milliseconds(30))
        }
        XCTFail("Missing original action: " + id); throw APIError.notConfigured
    }
    private func scroll(_ view: UIView) {
        if let value = view as? UIScrollView {
            let end = max(-value.adjustedContentInset.top, value.contentSize.height - value.bounds.height + value.adjustedContentInset.bottom)
            value.setContentOffset(CGPoint(x: value.contentOffset.x, y: value.contentOffset.y < end ? min(end, value.contentOffset.y + 300) : -value.adjustedContentInset.top), animated: false)
            value.layoutIfNeeded()
        }
        for child in view.subviews { scroll(child) }
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ root: NSObject) -> NSObject? {
            guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
            if (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
            if let view = root as? UIView { for child in view.subviews { if let result = visit(child) { return result } } }
            if let children = root.accessibilityElements { for case let child as NSObject in children { if let result = visit(child) { return result } } }
            let count = root.accessibilityElementCount()
            if count > 0 && count < 1000 { for index in 0..<count { if let child = root.accessibilityElement(at: index) as? NSObject, let result = visit(child) { return result } } }
            return nil
        }
        return visit(window)
    }
    private func navigation(_ root: UIViewController?) -> UINavigationController? {
        guard let root else { return nil }
        if let nav = root as? UINavigationController { return nav }
        for child in root.children { if let nav = navigation(child) { return nav } }; return nil
    }
}
@MainActor private final class OfficialTaskLifetimeRig {
    let roam = OfficialTaskLifetimeRoam(), official = OfficialTaskLifetimeOfficial()
    lazy var page = RoamOfficialTasksViewModel(roam: roam, official: official)
}
@MainActor private final class OfficialTaskLifetimeHostState: ObservableObject {
    let roam = OfficialTaskLifetimeRoam()
    @Published var official = OfficialTaskLifetimeOfficial()
    @Published var phase: ScenePhase = .active
    @Published var revision = 0
}
@MainActor private struct OfficialTaskLifetimeHost: View {
    @ObservedObject var state: OfficialTaskLifetimeHostState
    var body: some View {
        let _ = state.revision
        NavigationStack { RoamOfficialTasksView(roamReader: state.roam, reader: state.official) }
            .environment(\.scenePhase, state.phase).environment(\.locale, Locale(identifier: "en_US"))
    }
}
@MainActor private final class OfficialTaskLifetimeRoam: RoamExperienceReading {
    var identity: RoamExperienceIdentity? = .init(scope: try! .init(market: "cn", deployment: URL(string: "https://example.test/roam")!, accountID: 7, namespace: "official-task-lifetime"), epoch: 1)
    var isConfigured = false
    let isOfflineExample = true
    var reads = 0
    func history() throws -> [RoamHistoryRecord] { reads += 1; XCTFail("This entry needs no local history or location"); return [] }
    func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
    func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { throw APIError.notConfigured }
    func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
    func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
}
@MainActor private final class OfficialTaskLifetimeOfficial: OfficialEventReading {
    var isConfigured = true, isAuthenticated = true
    let isOfflineExample = true, signal = OfficialReadInvalidationSignal()
    var invalidationSignal: OfficialReadInvalidationSignal? { signal }
    var scope = UUID(), rowID = 71
    var calls: [String] = [], details: [Int] = []
    var empty = false, holdAll = false, holdMine = false
    var mineFailure: Error?
    var pendingAll: [CheckedContinuation<[OfficialEvent], Error>] = []
    var pendingMine: [CheckedContinuation<[OfficialEvent], Error>] = []
    func events(city: String?) async throws -> [OfficialEvent] {
        XCTAssertNil(city); calls.append("all")
        if holdAll { return try await withCheckedThrowingContinuation { pendingAll.append($0) } }
        return empty ? [] : [try Self.row(rowID)]
    }
    func myEvents() async throws -> [OfficialEvent] {
        calls.append("mine"); if let mineFailure { throw mineFailure }
        if holdMine { return try await withCheckedThrowingContinuation { pendingMine.append($0) } }
        return empty ? [] : [try Self.row(rowID + 10)]
    }
    func detail(id: Int) async throws -> OfficialEvent { details.append(id); return try Self.row(id) }
    func partyInbox() async throws -> [OfficialPartyInvite] { XCTFail("Unrelated private read"); throw APIError.notConfigured }
    func canPublish() async throws -> Bool { XCTFail("No publisher access"); throw APIError.notConfigured }
    func myPublished() async throws -> OfficialPublished { XCTFail("No author access"); throw APIError.notConfigured }
    func broadcastStats(id: Int) async throws -> OfficialBroadcastStats { XCTFail("No broadcast access"); throw APIError.notConfigured }
    static func row(_ id: Int) throws -> OfficialEvent {
        try JSONDecoder().decode(OfficialEvent.self, from: Data("{\"id\":\(id),\"title\":\"Synthetic official event \(id)\",\"status\":3,\"signed\":true}".utf8))
    }
}
