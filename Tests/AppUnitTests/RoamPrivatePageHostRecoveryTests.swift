import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Original controls with memory-only tools. No PhotoKit, GPS, export or live operation.
@MainActor final class RoamPrivatePageHostRecoveryTests: XCTestCase {
    func testQueuedOriginalActionCannotBeginAfterInactiveBackgroundDepartureOrRevocation() async throws {
        for boundary in ["inactive", "background", "leave", "revoke", "identity"] {
            let tools = PrivatePageHostTools(), page = RoamPrivatePageOwner(tools: tools)
            XCTAssertTrue(page.appear(foreground: true)); var sent = 0, read = 0
            page.settle(write: true, { sent += 1 }, refresh: { read += 1 })
            page.read { read += 1 }
            switch boundary {
            case "inactive": page.inactive(); _ = page.activate(foreground: true)
            case "background": page.retire(); _ = page.activate(foreground: true)
            case "leave": page.retire(leaving: true); _ = page.activate(foreground: true)
            case "revoke": tools.isConfigured = false
            default: tools.identity = nil
            }
            for _ in 0..<15 { await Task.yield() }
            XCTAssertEqual(sent, 0, boundary); XCTAssertEqual(read, 0, boundary)
        }
    }
    func testReadOnlyGrantPermitsOriginalReceiptButNeverWriter() async throws {
        let tools = PrivatePageHostTools(); tools.allowsWrites = false
        let page = RoamPrivatePageOwner(tools: tools); _ = page.appear(foreground: true)
        var writes = 0, receipts = 0
        page.settle(write: true, { writes += 1 }, refresh: {})
        for _ in 0..<10 { await Task.yield() }
        page.settle(write: false, { receipts += 1 }, refresh: {})
        try await waitFor { receipts == 1 }
        XCTAssertEqual(writes, 0)
    }
    func testIssuedOperationIsNotCancelledAndReturnWaitsThenOnlyRefreshesMetadata() async throws {
        let tools = PrivatePageHostTools(), page = RoamPrivatePageOwner(tools: tools)
        _ = page.appear(foreground: true)
        var gate: CheckedContinuation<Void, Never>?, entered = 0, callbacks = 0, reads = 0, cancelled = false
        page.settle(write: true, {
            entered += 1; await withCheckedContinuation { gate = $0 }; cancelled = Task.isCancelled; return true
        }, refresh: { reads += 1 }, finished: { _ in callbacks += 1 })
        try await waitFor { gate != nil }; page.retire(); _ = page.activate(foreground: true)
        page.settle(write: true, { entered += 1; return true }, refresh: { reads += 1 })
        page.read { reads += 1 }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertTrue(page.settlementInFlight); XCTAssertEqual(entered, 1); XCTAssertEqual(reads, 0)
        gate?.resume(); gate = nil
        try await waitFor { reads == 1 }
        XCTAssertFalse(cancelled); XCTAssertEqual(callbacks, 0); XCTAssertEqual(entered, 1)
    }
    func testInactiveSystemInterruptionPreservesIssuedCompletionAndOrdinaryReadReleasesBusy() async throws {
        let tools = PrivatePageHostTools(), page = RoamPrivatePageOwner(tools: tools); _ = page.appear(foreground: true)
        var gate: CheckedContinuation<Void, Never>?, completed = 0
        page.settle(write: true, { await withCheckedContinuation { gate = $0 } }, refresh: {}, finished: { _ in completed += 1 })
        try await waitFor { gate != nil }; page.inactive(); gate?.resume(); gate = nil
        try await waitFor { completed == 1 }; XCTAssertFalse(page.foreground)
        _ = page.activate(foreground: true)
        page.read { await withCheckedContinuation { gate = $0 } }
        try await waitFor { gate != nil }; page.inactive(); gate?.resume(); gate = nil
        try await waitFor { !page.readInFlight }; _ = page.activate(foreground: true)
        var refreshed = false; page.read { refreshed = true }; try await waitFor { refreshed }
    }
    func testPageScopeIncludesActualReaderExactScopeAndEpoch() throws {
        let first = PrivatePageHostTools(), second = PrivatePageHostTools()
        XCTAssertEqual(first.identity, second.identity); XCTAssertNotEqual(RoamPrivatePageScope(first), RoamPrivatePageScope(second))
        let initial = RoamPrivatePageScope(first), identity = try XCTUnwrap(first.identity)
        first.identity = .init(scope: identity.scope, epoch: identity.epoch + 1)
        XCTAssertNotEqual(initial, RoamPrivatePageScope(first))
        let base = URL(string: "https://example.test/native")!
        first.identity = .init(scope: try RoamHistoryScope(market: "cn", deployment: base, accountID: 7, namespace: "caf\u{00E9}"), epoch: 1)
        let composed = RoamPrivatePageScope(first)
        first.identity = .init(scope: try RoamHistoryScope(market: "cn", deployment: base, accountID: 7, namespace: "cafe\u{0301}"), epoch: 1)
        XCTAssertNotEqual(composed, RoamPrivatePageScope(first), "Use original exact storage scope, not canonical-equivalent Swift String equality")
    }
    func testActualPassportCapsuleEntryHidesBodyOnBackgroundThenReadsMetadataOnly() async throws {
        let state = PrivatePageHostState(), tools = state.tools
        let window = mount(state, destination: "passport"); defer { close(window) }
        try await tap("roam.home.passport.tile.capsule", in: window)
        try await waitFor { tools.capsuleLists == 1 }
        try await tap("roam.capsule.row.open", in: window)
        try await waitFor { self.find("roam.capsule.body", in: window) != nil }
        state.phase = .background
        try await waitFor { self.find("roam.capsule.body", in: window) == nil }
        XCTAssertNil(find("roam.capsule.empty", in: window))
        state.phase = .active
        try await waitFor { tools.capsuleLists == 2 && self.find("roam.capsule.row.open", in: window) != nil }
        XCTAssertNil(find("roam.capsule.body", in: window)); XCTAssertEqual(tools.capsuleDetails, 1)
        XCTAssertTrue(tools.fixture.dispatchedWrites.isEmpty)
    }
    func testActualGoalFormSurvivesSameOwnerBackgroundButNoCreateIsSent() async throws {
        let state = PrivatePageHostState(), tools = state.tools
        let window = mount(state, destination: "goals"); defer { close(window) }
        try await waitFor { tools.goalLists == 1 }
        try await tap("roam.goals.new", in: window)
        try await waitFor { self.find("roam.goals.metricPicker", in: window) != nil }
        state.phase = .background
        try await waitFor { self.find("roam.goals.metricPicker", in: window) == nil }
        XCTAssertNil(find("roam.goals.empty", in: window))
        state.phase = .active
        try await waitFor { tools.goalLists == 2 && self.find("roam.goals.metricPicker", in: window) != nil }
        XCTAssertTrue(tools.fixture.dispatchedWrites.isEmpty)
    }
    func testActualCapsuleUnsubmittedFormClearsOnBackgroundWithoutTouchingPending() async throws {
        let state = PrivatePageHostState(), tools = state.tools
        let pending = RoamCapsuleDraft(body: "pending stays", unlockDate: "2030-01-01"); tools.pendingCapsule = pending
        let window = mount(state, destination: "capsule"); defer { close(window) }
        try await waitFor { tools.capsuleLists == 1 }
        try await tap("roam.capsule.write", in: window)
        try await waitFor { self.find("roam.capsule.text", in: window) != nil }
        state.phase = .background
        try await waitFor { self.find("roam.capsule.text", in: window) == nil }
        state.phase = .active
        try await waitFor { tools.capsuleLists == 2 }
        XCTAssertNil(find("roam.capsule.text", in: window)); XCTAssertEqual(tools.pendingCapsule, pending)
        XCTAssertTrue(tools.fixture.dispatchedWrites.isEmpty)
    }
    func testActualSameIdentityReaderReplacementCannotKeepOldCapsuleDetail() async throws {
        let state = PrivatePageHostState(), old = state.tools
        let window = mount(state, destination: "capsule"); defer { close(window) }
        try await waitFor { old.capsuleLists == 1 }; try await tap("roam.capsule.row.open", in: window)
        try await waitFor { self.find("roam.capsule.body", in: window) != nil }
        let fresh = PrivatePageHostTools(); XCTAssertEqual(old.identity, fresh.identity); state.tools = fresh
        try await waitFor { fresh.capsuleLists == 1 && self.find("roam.capsule.body", in: window) == nil }
        XCTAssertEqual(old.capsuleDetails, 1); XCTAssertEqual(fresh.capsuleDetails, 0)
    }
    func testActualGrantWithdrawalHidesDetailThenRestorationReadsOnlyOriginalList() async throws {
        let state = PrivatePageHostState(), tools = state.tools
        let window = mount(state, destination: "goals"); defer { close(window) }
        try await waitFor { tools.goalLists == 1 }; try await tap("roam.goals.row", in: window)
        try await waitFor { self.find("roam.goals.detail", in: window) != nil }
        tools.isConfigured = false; state.revision += 1
        try await waitFor { self.find("roam.goals.detail", in: window) == nil && self.find("roam.private.issue", in: window) != nil }
        tools.isConfigured = true; tools.allowsWrites = false; state.revision += 1
        try await waitFor { tools.goalLists == 2 }
        XCTAssertNil(find("roam.goals.detail", in: window)); XCTAssertNil(find("roam.goals.new", in: window))
        XCTAssertTrue(tools.fixture.dispatchedWrites.isEmpty)
    }
    private func mount(_ state: PrivatePageHostState, destination: String) -> UIWindow {
        let host = UIHostingController(rootView: PrivatePageHostHarness(state: state, destination: destination))
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
@MainActor private final class PrivatePageHostState: ObservableObject {
    @Published var phase: ScenePhase = .active
    @Published var tools = PrivatePageHostTools()
    @Published var revision = 0
}
@MainActor private struct PrivatePageHostHarness: View {
    @ObservedObject var state: PrivatePageHostState
    let destination: String
    var body: some View {
        let _ = state.revision
        NavigationStack {
            if destination == "passport" { RoamHomePassportView(reader: nil, privateToolsReader: state.tools) }
            else if destination == "goals" { RoamExplorationGoalsView(tools: state.tools) }
            else { RoamCapsuleView(tools: state.tools) }
        }.environment(\.scenePhase, state.phase).environment(\.locale, Locale(identifier: "en_US"))
    }
}
@MainActor private final class PrivatePageHostTools: RoamPrivateToolsServing {
    let fixture = RoamPrivateToolsFixture()
    var identity: RoamExperienceIdentity?
    var isConfigured = true, allowsWrites = true
    let isOfflineExample = true
    var now: Date { fixture.now }
    var pendingCapsule: RoamCapsuleDraft?
    var pendingGoal: RoamGoalDraft?
    var confirmedCancelledGoals: Set<String> = []
    var capsuleLists = 0, capsuleDetails = 0, goalLists = 0
    init() { identity = fixture.identity }
    func capsules(beforeID: String?) async throws -> RoamCapsulePage { capsuleLists += 1; return try await fixture.capsules(beforeID: beforeID) }
    func capsule(id: String) async throws -> RoamCapsule { capsuleDetails += 1; return try await fixture.capsule(id: id) }
    func goals(beforeID: String?) async throws -> RoamGoalPage { goalLists += 1; return try await fixture.goals(beforeID: beforeID) }
    func goal(id: String) async throws -> RoamExplorationGoal { try await fixture.goal(id: id) }
    func capsuleReceipt(requestID: String) async throws -> RoamCapsule { throw APIError.notConfigured }
    func createCapsule(_ draft: RoamCapsuleDraft) async throws -> RoamCapsule { XCTFail("Host tests never dispatch a writer"); throw APIError.notConfigured }
    func deleteCapsule(id: String) async throws -> RoamCapsule { XCTFail("Host tests never dispatch a writer"); throw APIError.notConfigured }
    func goalReceipt(requestID: String) async throws -> RoamExplorationGoal { throw APIError.notConfigured }
    func createGoal(_ draft: RoamGoalDraft) async throws -> RoamExplorationGoal { XCTFail("Host tests never dispatch a writer"); throw APIError.notConfigured }
    func cancelGoal(id: String) async throws -> RoamExplorationGoal { XCTFail("Host tests never dispatch a writer"); throw APIError.notConfigured }
    func prepareExport(_ request: RoamExportRequest) async throws -> RoamExportCheckpoint { throw APIError.notConfigured }
    func exportPage(_ checkpoint: RoamExportCheckpoint) async throws -> RoamExportChunk { throw APIError.notConfigured }
}
