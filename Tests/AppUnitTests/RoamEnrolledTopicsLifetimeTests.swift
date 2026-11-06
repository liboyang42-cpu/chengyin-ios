import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Only the existing wallet reads. No payment, ticket mutation, play factory, GPS or local journal.
@MainActor final class RoamEnrolledTopicsLifetimeTests: XCTestCase {
    func testConstructedOrBackgroundedPageNeverStartsOriginalRead() async throws {
        let r = EnrolledLifetimeRig(); let model = r.page
        model.readAction()(); await model.refreshAction()()
        model.appear(foreground: false)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(r.tickets.reads, 0); XCTAssertNil(model.model.snapshot)
        model.setForeground(true, preservingSnapshot: false)
        try await waitFor { r.tickets.reads == 1 && model.model.snapshot != nil }
        XCTAssertEqual(r.roam.reads, 0)
    }
    func testOldRenderedRetryAndRefreshCannotExecuteAfterLeaveReappear() async throws {
        let r = EnrolledLifetimeRig(); r.page.appear(foreground: true)
        try await waitFor { r.page.model.snapshot != nil }
        let retry = r.page.readAction(), refresh = r.page.refreshAction()
        r.page.disappear(preservingSnapshot: false); r.page.appear(foreground: true)
        retry(); await refresh()
        try await waitFor { r.tickets.reads == 2 && r.page.model.snapshot != nil }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(r.tickets.reads, 2)
    }
    func testAlreadyQueuedRetryRetiresBeforeTaskStartAcrossForegroundReturn() async throws {
        let r = EnrolledLifetimeRig(); r.page.appear(foreground: true)
        try await waitFor { r.page.model.snapshot != nil }
        r.page.readAction()()
        r.page.setForeground(false, preservingSnapshot: false)
        r.page.setForeground(true, preservingSnapshot: false)
        try await waitFor { r.tickets.reads == 2 && r.page.model.snapshot != nil }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(r.tickets.reads, 2)
    }
    func testLateReadAfterBackgroundCannotReplaceFreshForegroundSnapshot() async throws {
        let r = EnrolledLifetimeRig(); r.tickets.hold = true; r.page.appear(foreground: true)
        try await waitFor { r.tickets.pending.count == 1 }
        r.page.setForeground(false, preservingSnapshot: false)
        r.tickets.hold = false; r.tickets.rowID = 3; r.page.setForeground(true, preservingSnapshot: false)
        try await waitFor { r.page.model.snapshot?.topics.first?.id == 3 }
        r.tickets.pending.removeFirst().resume(returning: .init(tickets: [try EnrolledLifetimeTickets.row(id: 1)]))
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(r.page.model.snapshot?.topics.map(\.id), [3]); XCTAssertEqual(r.tickets.reads, 2)
    }
    func testPushRetainsExactRegistrationSnapshotButForegroundCannotReloadHiddenOrigin() async throws {
        let r = EnrolledLifetimeRig(); r.page.appear(foreground: true)
        try await waitFor { r.page.model.snapshot != nil }
        let snapshot = try XCTUnwrap(r.page.model.snapshot)
        let target = try XCTUnwrap(r.page.model.select(registrationID: 1, snapshotID: snapshot.id))
        r.page.disappear(preservingSnapshot: true)
        r.page.setForeground(false, preservingSnapshot: true); r.page.setForeground(true, preservingSnapshot: true)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(r.page.isVisible); XCTAssertTrue(r.page.model.mayRemainOpen(target))
        XCTAssertEqual(r.tickets.reads, 1); XCTAssertEqual(target.registrationID, 1)
        r.page.disappear(preservingSnapshot: false)
        XCTAssertFalse(r.page.model.mayRemainOpen(target)); XCTAssertNil(r.page.model.snapshot)
    }
    func testCurrentOwnerRevocationRejectsOldActionBeforeReadAndDoesNotInventRoamGrant() async throws {
        let r = EnrolledLifetimeRig(); r.roam.isConfigured = false
        r.page.appear(foreground: true); try await waitFor { r.page.model.snapshot != nil }
        let retry = r.page.readAction(); r.tickets.scope = UUID(); retry()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(r.tickets.reads, 1); XCTAssertNil(r.page.model.snapshot)
        r.tickets.isAuthenticated = false; r.page.appear(foreground: true)
        try await waitFor { r.page.model.issue == .login }
        XCTAssertEqual(r.tickets.reads, 1); XCTAssertEqual(r.roam.reads, 0)
    }
    func testActualListBackgroundReturnReadsCurrentCancelledStatusWithoutOldAction() async throws {
        let state = EnrolledLifetimeHostState(), window = mount(state); defer { close(window) }
        try await waitFor { self.find("roam.chapters.row.1", in: window) != nil }
        state.phase = .background
        try await waitFor { self.find("roam.chapters.row.1", in: window) == nil }
        XCTAssertNil(find("roam.chapters.empty", in: window))
        state.tickets.status = 3; state.phase = .active
        try await waitFor { self.find("roam.chapters.status.1", in: window) != nil }
        XCTAssertNil(find("roam.chapters.row.1", in: window)); XCTAssertEqual(state.tickets.reads, 2)
        XCTAssertTrue(state.tickets.details.isEmpty)
    }
    func testActualDetailPushBackgroundAndBackKeepOriginalCurrentReaderAuthority() async throws {
        let state = EnrolledLifetimeHostState(), window = mount(state); defer { close(window) }
        try await tap("roam.chapters.row.1", in: window)
        try await waitFor { state.tickets.details == [1] && self.find("ticketWallet.detail", in: window) != nil }
        XCTAssertNil(find("ticketWallet.play.open", in: window), "No fake play provider")
        state.phase = .background
        try await Task.sleep(nanoseconds: 100_000_000)
        state.phase = .active
        try await waitFor { state.tickets.details.count == 2 }
        XCTAssertEqual(state.tickets.reads, 1, "Pushed detail owns its current refresh; hidden list must not clear its source snapshot")
        XCTAssertNotNil(find("ticketWallet.detail", in: window))
        state.tickets.status = 3
        let nav = try XCTUnwrap(navigation(window.rootViewController)); XCTAssertNotNil(nav.popViewController(animated: false))
        try await waitFor { self.find("roam.chapters.status.1", in: window) != nil }
        XCTAssertEqual(state.tickets.reads, 2); XCTAssertEqual(state.tickets.details, [1, 1])
    }
    func testActualSameScopeReaderReplacementDoesNotKeepOriginalViewModel() async throws {
        let state = EnrolledLifetimeHostState(), old = state.tickets, window = mount(state); defer { close(window) }
        try await waitFor { self.find("roam.chapters.row.1", in: window) != nil }
        let fresh = EnrolledLifetimeTickets(); fresh.scope = old.scope; fresh.rowID = 3; state.tickets = fresh
        try await waitFor { self.find("roam.chapters.row.3", in: window) != nil }
        XCTAssertNil(find("roam.chapters.row.1", in: window)); XCTAssertEqual(fresh.reads, 1); XCTAssertEqual(old.reads, 1)
    }
    func testActualFailedReadRetryAndSuccessfulEmptyRemainDistinct() async throws {
        let state = EnrolledLifetimeHostState(); state.tickets.failure = APIError.httpStatus(503)
        let window = mount(state); defer { close(window) }
        try await waitFor { self.find("roam.chapters.error", in: window) != nil }
        XCTAssertNil(find("roam.chapters.empty", in: window))
        state.tickets.failure = nil; state.tickets.empty = true
        try await tap("ticketWallet.retry", in: window)
        try await waitFor { self.find("roam.chapters.empty", in: window) != nil }
        XCTAssertNil(find("roam.chapters.error", in: window)); XCTAssertEqual(state.tickets.reads, 2)
    }
    func testActualSignOutHidesRowsAndNoFreshReadIsStarted() async throws {
        let state = EnrolledLifetimeHostState(), window = mount(state); defer { close(window) }
        try await waitFor { self.find("roam.chapters.row.1", in: window) != nil }
        state.roam.identity = nil; state.tickets.isAuthenticated = false; state.revision += 1
        try await waitFor { self.find("roam.chapters.row.1", in: window) == nil && self.find("roam.chapters.error", in: window) != nil }
        XCTAssertEqual(state.tickets.reads, 1); XCTAssertTrue(state.tickets.details.isEmpty)
    }
    private func mount(_ state: EnrolledLifetimeHostState) -> UIWindow {
        let host = UIHostingController(rootView: EnrolledLifetimeHost(state: state))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1100))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTFail("Original enrolled-topic control/read state did not settle"); throw APIError.notConfigured
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
@MainActor private final class EnrolledLifetimeRig {
    let roam = EnrolledLifetimeRoam(), tickets = EnrolledLifetimeTickets()
    lazy var page = RoamEnrolledChaptersViewModel(roam: roam, tickets: tickets)
}
@MainActor private final class EnrolledLifetimeHostState: ObservableObject {
    @Published var roam = EnrolledLifetimeRoam()
    @Published var tickets = EnrolledLifetimeTickets()
    @Published var phase: ScenePhase = .active
    @Published var revision = 0
}
@MainActor private struct EnrolledLifetimeHost: View {
    @ObservedObject var state: EnrolledLifetimeHostState
    var body: some View {
        let _ = state.revision
        NavigationStack { RoamEnrolledChaptersView(roam: state.roam, tickets: state.tickets) }
            .environment(\.scenePhase, state.phase).environment(\.locale, Locale(identifier: "en_US"))
    }
}
@MainActor private final class EnrolledLifetimeRoam: RoamExperienceReading {
    var identity: RoamExperienceIdentity? = .init(scope: try! .init(market: "cn", deployment: URL(string: "https://example.test/roam")!, accountID: 7, namespace: "enrolled"), epoch: 1)
    var isConfigured = false
    let isOfflineExample = true
    var reads = 0
    func history() throws -> [RoamHistoryRecord] { reads += 1; XCTFail("No local history needed"); return [] }
    func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
    func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { throw APIError.notConfigured }
    func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
    func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
}
@MainActor private final class EnrolledLifetimeTickets: TicketWalletReading {
    var isConfigured = true, isAuthenticated = true
    let isOfflineExample = true
    var scope = UUID(), rowID = 1, status = 2
    var reads = 0, details: [Int] = []
    var hold = false, empty = false
    var failure: Error?
    var pending: [CheckedContinuation<TicketWalletSnapshot, Error>] = []
    func ticketWallet() async throws -> TicketWalletSnapshot {
        reads += 1
        if let failure { throw failure }
        if hold { return try await withCheckedThrowingContinuation { pending.append($0) } }
        return .init(tickets: empty ? [] : [try Self.row(id: rowID, status: status)])
    }
    func ticketDetail(id: Int) async throws -> TicketWalletTicket {
        details.append(id); return try Self.row(id: id, status: status)
    }
    static func row(id: Int, status: Int = 2) throws -> TicketWalletTicket {
        try JSONDecoder().decode(TicketWalletTicket.self, from: Data("{\"id\":\(id),\"ownerType\":1,\"ownerId\":\(100 + id),\"registrationStatus\":\(status),\"cmsTopic\":{\"name\":\"Synthetic enrolled topic \(id)\"}}".utf8))
    }
}
