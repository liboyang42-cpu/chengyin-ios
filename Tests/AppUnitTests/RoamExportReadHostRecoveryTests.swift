import XCTest
import SwiftUI
import UIKit
import Combine
@testable import Questify

/// Native controls and lifecycle only. Never activates Files, Share, GPS or a business writer.
@MainActor final class RoamExportReadHostRecoveryTests: XCTestCase {
    func testOriginalPassportExportEntryReadsExactCheckpointAfterBackgroundedLateChunk() async throws {
        let state = ExportReadHostState(), tools = ExportReadHostTools(); state.tools = tools
        let window = mount(state, passport: true); defer { close(window) }
        try await tap("roam.export.open", in: window)
        XCTAssertEqual(tools.prepareCalls, 0)
        try await tap("roam.export.prepare", in: window)
        try await waitFor { tools.prepareCalls == 1 && self.find("roam.export.readNext", in: window) != nil }
        try await tap("roam.export.readNext", in: window)
        try await waitFor { tools.pages.count == 1 && self.find("roam.export.readNext", in: window) != nil }
        XCTAssertNil(find("roam.export.save", in: window)); XCTAssertNil(find("roam.export.share", in: window))
        tools.holdPage = true
        try await tap("roam.export.readNext", in: window)
        try await waitFor { tools.heldPage != nil }
        state.phase = .background
        try await waitFor { self.find("roam.export.progress", in: window) == nil }
        tools.releasePage()
        state.phase = .active
        try await waitFor { self.find("roam.export.readNext", in: window) != nil }
        XCTAssertEqual(tools.pages.count, 2, "Foreground does not retry automatically")
        XCTAssertNil(find("roam.export.save", in: window))
        try await tap("roam.export.readNext", in: window)
        try await waitFor { self.find("roam.export.save", in: window) != nil }
        XCTAssertNotNil(find("roam.export.share", in: window))
        XCTAssertEqual(tools.prepareCalls, 1); XCTAssertEqual(tools.pages[1], tools.pages[2])
        XCTAssertEqual(tools.pages.map(\.offset), [0, 2, 2])
    }
    func testSameIdentityReaderReplacementRecreatesOriginalExportStateWithoutAutomaticRead() async throws {
        let state = ExportReadHostState(), first = ExportReadHostTools(); state.tools = first
        let window = mount(state); defer { close(window) }
        try await tap("roam.export.prepare", in: window)
        try await waitFor { first.prepareCalls == 1 && self.find("roam.export.readNext", in: window) != nil }
        let replacement = ExportReadHostTools()
        XCTAssertEqual(first.identity, replacement.identity)
        state.tools = replacement
        try await waitFor { self.find("roam.export.prepare", in: window) != nil }
        XCTAssertNil(find("roam.export.progress", in: window))
        XCTAssertEqual(replacement.prepareCalls, 0)
        try await tap("roam.export.prepare", in: window)
        try await waitFor { replacement.prepareCalls == 1 }
        XCTAssertTrue(first.pages.isEmpty)
    }
    func testQueuedPrepareCannotDispatchAfterLeaveAndForegroundAloneCannotRemount() async throws {
        let tools = ExportReadHostTools(), owner = RoamExportReadPresentation(tools: tools)
        owner.appear(foreground: true)
        let range = owner.model.presets[0]
        owner.prepare(startDate: range.startDate, endDate: range.endDateExclusive)
        owner.leave(); owner.resume(foreground: true)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(owner.active); XCTAssertEqual(tools.prepareCalls, 0)
        owner.appear(foreground: true); owner.prepare(startDate: range.startDate, endDate: range.endDateExclusive)
        try await waitFor { tools.prepareCalls == 1 && owner.model.phase == .prepared }
        owner.leave()
    }
    func testNativeReplacementRejectsOldCallbacksAndTeardownDoesNotPublish() async throws {
        let tools = ExportReadHostTools(), owner = RoamExportReadPresentation(tools: tools)
        let old = RoamExportReadLifetimeController(owner: owner)
        owner.appear(foreground: true)
        let range = owner.model.presets[0]
        await owner.model.prepare(startDate: range.startDate, endDateExclusive: range.endDateExclusive)
        await owner.model.readNext()
        tools.holdPage = true; owner.readNext()
        try await waitFor { tools.heldPage != nil }
        var publications = 0
        let subscription = owner.objectWillChange.sink { publications += 1 }
        owner.dismantleLifetime(old.lifetimeID)
        XCTAssertEqual(publications, 0); XCTAssertFalse(owner.active)
        let fresh = RoamExportReadLifetimeController(owner: owner)
        owner.appear(foreground: true)
        XCTAssertTrue(owner.isCurrentLifetime(fresh.lifetimeID)); XCTAssertTrue(owner.active)
        publications = 0
        old.viewDidAppear(false); old.viewWillDisappear(false); old.viewDidDisappear(false)
        owner.dismantleLifetime(old.lifetimeID)
        XCTAssertEqual(publications, 0); XCTAssertTrue(owner.active)
        tools.releasePage()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(owner.model.file); XCTAssertNil(owner.model.deliveryLease)
        XCTAssertEqual(owner.model.read, 2)
        owner.dismantleLifetime(fresh.lifetimeID)
        XCTAssertEqual(publications, 0)
        withExtendedLifetime(subscription) {}
    }
    func testOrdinaryNativeCoverPreservesReadScopeButActualRemovalRetiresIt() async throws {
        let tools = ExportReadHostTools(), owner = RoamExportReadPresentation(tools: tools)
        let anchor = RoamExportReadLifetimeController(owner: owner), host = UIViewController()
        host.addChild(anchor); host.view.addSubview(anchor.view); anchor.didMove(toParent: host)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 900))
        window.rootViewController = host; window.makeKeyAndVisible(); defer { close(window) }
        owner.appear(foreground: true)
        let range = owner.model.presets[0]
        await owner.model.prepare(startDate: range.startDate, endDateExclusive: range.endDateExclusive)
        let checkpoint = owner.model.checkpoint
        let cover = UIViewController(); cover.modalPresentationStyle = .fullScreen
        host.present(cover, animated: false)
        try await waitFor { host.presentedViewController === cover }
        XCTAssertTrue(owner.active); XCTAssertEqual(owner.model.checkpoint, checkpoint)
        host.dismiss(animated: false)
        try await waitFor { host.presentedViewController == nil }
        XCTAssertTrue(owner.active); XCTAssertEqual(tools.prepareCalls, 1)
        owner.dismantleLifetime(anchor.lifetimeID)
        XCTAssertFalse(owner.active); XCTAssertEqual(owner.model.checkpoint, checkpoint)
    }
    func testCompletedFileNeverBecomesDeliverableAgainThroughOwnerForegroundReturn() async throws {
        let tools = ExportReadHostTools(), owner = RoamExportReadPresentation(tools: tools)
        owner.appear(foreground: true)
        let range = owner.model.presets[0]
        await owner.model.prepare(startDate: range.startDate, endDateExclusive: range.endDateExclusive)
        await owner.model.readNext(); await owner.model.readNext()
        let lease = try XCTUnwrap(owner.model.deliveryLease)
        XCTAssertNotNil(owner.model.shareableFile)
        owner.suspend(); owner.resume(foreground: true); owner.model.renewDelivery()
        XCTAssertTrue(lease.isRevoked); XCTAssertTrue(owner.model.deliveryLease === lease)
        XCTAssertNil(owner.model.shareableFile); XCTAssertEqual(tools.pages.count, 2)
        owner.leave()
    }
    func testActualPassportPopDuringReadDiscardsLateResultAndReopenRequiresExplicitPrepare() async throws {
        let state = ExportReadHostState(), tools = ExportReadHostTools(); state.tools = tools
        let window = mount(state, passport: true); defer { close(window) }
        try await tap("roam.export.open", in: window)
        try await tap("roam.export.prepare", in: window)
        try await waitFor { tools.prepareCalls == 1 && self.find("roam.export.readNext", in: window) != nil }
        tools.holdPage = true
        try await tap("roam.export.readNext", in: window)
        try await waitFor { tools.heldPage != nil }
        let navigation = try XCTUnwrap(navigation(window.rootViewController))
        XCTAssertNotNil(navigation.popViewController(animated: false))
        try await waitFor { self.find("roam.export.open", in: window) != nil }
        tools.releasePage()
        try await tap("roam.export.open", in: window)
        try await waitFor { self.find("roam.export.prepare", in: window) != nil }
        XCTAssertNil(find("roam.export.save", in: window)); XCTAssertNil(find("roam.export.progress", in: window))
        XCTAssertEqual(tools.prepareCalls, 1); XCTAssertEqual(tools.pages.count, 1)
    }
    private func mount(_ state: ExportReadHostState, passport: Bool = false) -> UIWindow {
        let host = UIHostingController(rootView: ExportReadHostHarness(state: state, passport: passport))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1100))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTFail("Original export control/read state did not settle"); throw APIError.notConfigured
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
@MainActor private final class ExportReadHostState: ObservableObject {
    @Published var phase: ScenePhase = .active
    @Published var tools: ExportReadHostTools = .init()
}
@MainActor private struct ExportReadHostHarness: View {
    @ObservedObject var state: ExportReadHostState
    let passport: Bool
    var body: some View {
        NavigationStack {
            if passport { RoamHomePassportView(reader: nil, privateToolsReader: state.tools) }
            else { RoamExplorationExportView(tools: state.tools) }
        }.environment(\.scenePhase, state.phase).environment(\.locale, Locale(identifier: "en_US"))
    }
}

@MainActor private final class ExportReadHostTools: RoamPrivateToolsServing {
    let fixture = RoamPrivateToolsFixture()
    var identity: RoamExperienceIdentity?
    var isConfigured = true
    var now: Date
    let allowsWrites = false, isOfflineExample = true
    var pendingCapsule: RoamCapsuleDraft?
    var pendingGoal: RoamGoalDraft?
    var confirmedCancelledGoals: Set<String> = []
    var prepareCalls = 0
    var pages: [RoamExportCheckpoint] = []
    var holdPrepare = false
    var heldPrepare: CheckedContinuation<Void, Never>?
    var holdPage = false
    var heldPage: CheckedContinuation<Void, Never>?
    var failNextPage = false
    init() { identity = fixture.identity; now = fixture.now }
    func prepareExport(_ request: RoamExportRequest) async throws -> RoamExportCheckpoint {
        prepareCalls += 1
        if holdPrepare { await withCheckedContinuation { heldPrepare = $0 } }
        return try await fixture.prepareExport(request)
    }
    func exportPage(_ checkpoint: RoamExportCheckpoint) async throws -> RoamExportChunk {
        pages.append(checkpoint)
        if holdPage { await withCheckedContinuation { heldPage = $0 } }
        if failNextPage { failNextPage = false; throw APIError.httpStatus(503) }
        return try await fixture.exportPage(checkpoint)
    }
    func releasePrepare() { holdPrepare = false; heldPrepare?.resume(); heldPrepare = nil }
    func releasePage() { holdPage = false; heldPage?.resume(); heldPage = nil }
    func capsules(beforeID: String?) async throws -> RoamCapsulePage { throw APIError.notConfigured }
    func capsule(id: String) async throws -> RoamCapsule { throw APIError.notConfigured }
    func capsuleReceipt(requestID: String) async throws -> RoamCapsule { throw APIError.notConfigured }
    func createCapsule(_ draft: RoamCapsuleDraft) async throws -> RoamCapsule { throw APIError.notConfigured }
    func deleteCapsule(id: String) async throws -> RoamCapsule { throw APIError.notConfigured }
    func goals(beforeID: String?) async throws -> RoamGoalPage { throw APIError.notConfigured }
    func goal(id: String) async throws -> RoamExplorationGoal { throw APIError.notConfigured }
    func goalReceipt(requestID: String) async throws -> RoamExplorationGoal { throw APIError.notConfigured }
    func createGoal(_ draft: RoamGoalDraft) async throws -> RoamExplorationGoal { throw APIError.notConfigured }
    func cancelGoal(id: String) async throws -> RoamExplorationGoal { throw APIError.notConfigured }
}
