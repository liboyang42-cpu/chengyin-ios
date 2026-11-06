import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Real local journal/reader, existing Browser and dormant live/check destinations. No GPS or remote service.
@MainActor final class RoamHomeResumeEntryRecoveryTests: XCTestCase {
    func testCurrentLocalJournalCanOfferNavigationWithoutRemoteReadConfiguration() throws {
        let rig = try ResumeEntryRig(); try rig.seed(.unfinished)
        let reader = try XCTUnwrap(rig.reader), bytes = rig.storage.rows, writes = rig.storage.writes
        var entry = RoamHomeRecoveryEntry(); entry.appear(reader: reader, foreground: true, hasDestination: true)
        XCTAssertFalse(reader.isConfigured); XCTAssertEqual(entry.banner(reader: reader), .recovered)
        let reads = rig.storage.reads
        entry.continueToExistingDestination(reader: reader, hasDestination: true, rendered: entry.revision)
        let target = try XCTUnwrap(entry.target)
        XCTAssertTrue(entry.matches(target, reader: reader, hasDestination: true))
        XCTAssertGreaterThan(rig.storage.reads, reads, "Tap rechecks the actual current local journal")
        XCTAssertEqual(rig.storage.rows, bytes); XCTAssertEqual(rig.storage.writes, writes)
    }
    func testPendingFinishOnlyOffersOriginalCheckAndCannotActivateContinue() throws {
        let rig = try ResumeEntryRig(); try rig.seed(.finishPending); let reader = try XCTUnwrap(rig.reader)
        var entry = RoamHomeRecoveryEntry(); entry.appear(reader: reader, foreground: true, hasDestination: true)
        XCTAssertEqual(entry.banner(reader: reader), .needsCheck)
        entry.continueToExistingDestination(reader: reader, hasDestination: true, rendered: entry.revision)
        XCTAssertNil(entry.target)
    }
    func testTapRechecksChangedFinishOrMissingRecordWithoutInferringSettlement() throws {
        for next in [RoamLocalWalkStatus.finishPending, .none] {
            let rig = try ResumeEntryRig(); try rig.seed(.unfinished); let reader = try XCTUnwrap(rig.reader)
            var entry = RoamHomeRecoveryEntry(); entry.appear(reader: reader, foreground: true, hasDestination: true)
            let shown = entry.revision
            try rig.seed(next); let bytes = rig.storage.rows, writes = rig.storage.writes
            entry.continueToExistingDestination(reader: reader, hasDestination: true, rendered: shown)
            XCTAssertNil(entry.target)
            XCTAssertEqual(entry.banner(reader: reader), next == .finishPending ? .needsCheck : nil)
            XCTAssertEqual(rig.storage.rows, bytes); XCTAssertEqual(rig.storage.writes, writes)
        }
    }
    func testFailedCorruptAndUnavailableLocalReadsHideStaleNoticeWithoutDeletingMetadata() throws {
        let rig = try ResumeEntryRig(); try rig.seed(.unfinished); let reader = try XCTUnwrap(rig.reader)
        var entry = RoamHomeRecoveryEntry(); entry.appear(reader: reader, foreground: true, hasDestination: true)
        let bytes = rig.storage.rows, writes = rig.storage.writes
        rig.storage.failRead = true; entry.reload(reader: reader, hasDestination: true)
        XCTAssertNil(entry.banner(reader: reader)); XCTAssertEqual(rig.storage.rows, bytes)
        rig.storage.failRead = false
        for key in Array(rig.storage.rows.keys) { rig.storage.rows[key] = Data("corrupt".utf8) }
        let corrupt = rig.storage.rows; entry.reload(reader: reader, hasDestination: true)
        XCTAssertNil(entry.banner(reader: reader)); XCTAssertEqual(rig.storage.rows, corrupt)
        rig.storage.rows = bytes; entry.reload(reader: reader, hasDestination: true)
        XCTAssertEqual(entry.banner(reader: reader), .recovered)
        let noJournal = rig.makeReader(hasJournal: false)
        entry.reload(reader: noJournal, hasDestination: true)
        XCTAssertNil(entry.banner(reader: noJournal)); XCTAssertEqual(rig.storage.writes, writes)
        entry.reload(reader: nil, hasDestination: true); XCTAssertNil(entry.banner(reader: nil))
    }
    func testIdentityChangeInsideOriginalLocalReadRejectsItsResult() throws {
        let rig = try ResumeEntryRig(); try rig.seed(.unfinished); let reader = try XCTUnwrap(rig.reader)
        let replacement = try ResumeEntryRig.session(epoch: 2), bytes = rig.storage.rows
        rig.storage.onRead = { rig.session = replacement }
        var entry = RoamHomeRecoveryEntry(); entry.appear(reader: reader, foreground: true, hasDestination: true)
        XCTAssertNil(entry.banner(reader: reader)); XCTAssertNil(entry.target); XCTAssertEqual(rig.storage.rows, bytes)
    }
    func testReaderAccountEpochRealmMarketAndExactNamespaceRetireOldTarget() throws {
        let replacements = [try ResumeEntryRig.session(account: 8), try ResumeEntryRig.session(epoch: 2),
                            try ResumeEntryRig.session(deployment: "https://example.test/other"),
                            try ResumeEntryRig.session(market: "us"), try ResumeEntryRig.session(namespace: "other")]
        for replacement in replacements {
            let rig = try ResumeEntryRig(); try rig.seed(.unfinished); let reader = try XCTUnwrap(rig.reader)
            var entry = RoamHomeRecoveryEntry(); entry.appear(reader: reader, foreground: true, hasDestination: true)
            entry.continueToExistingDestination(reader: reader, hasDestination: true, rendered: entry.revision)
            let target = try XCTUnwrap(entry.target)
            rig.session = replacement
            XCTAssertNil(entry.banner(reader: reader)); XCTAssertFalse(entry.matches(target, reader: reader, hasDestination: true))
            entry.reload(reader: reader, hasDestination: true); XCTAssertNil(entry.target)
        }
        let rig = try ResumeEntryRig(); try rig.seed(.unfinished); let reader = try XCTUnwrap(rig.reader)
        var entry = RoamHomeRecoveryEntry(); entry.appear(reader: reader, foreground: true, hasDestination: true)
        entry.continueToExistingDestination(reader: reader, hasDestination: true, rendered: entry.revision)
        let target = try XCTUnwrap(entry.target)
        XCTAssertFalse(entry.matches(target, reader: rig.makeReader(), hasDestination: true))
        rig.session = try ResumeEntryRig.session(namespace: "\u{00E9}")
        let first = RoamHomeRecoveryOwner(reader: reader)
        rig.session = try ResumeEntryRig.session(namespace: "e\u{0301}")
        XCTAssertNotEqual(first, RoamHomeRecoveryOwner(reader: reader))
    }
    func testOldVisibleActionCannotActivateAfterBackgroundDepartureOrMissingDestination() throws {
        let rig = try ResumeEntryRig(); try rig.seed(.unfinished); let reader = try XCTUnwrap(rig.reader)
        var entry = RoamHomeRecoveryEntry(); entry.appear(reader: reader, foreground: true, hasDestination: true)
        let old = entry.revision
        entry.setForeground(false, reader: reader, hasDestination: true)
        entry.continueToExistingDestination(reader: reader, hasDestination: true, rendered: old)
        XCTAssertNil(entry.target); XCTAssertNil(entry.banner(reader: reader))
        entry.setForeground(true, reader: reader, hasDestination: true)
        entry.continueToExistingDestination(reader: reader, hasDestination: true, rendered: old)
        XCTAssertNil(entry.target)
        let current = entry.revision; entry.disappear()
        entry.continueToExistingDestination(reader: reader, hasDestination: true, rendered: current)
        XCTAssertNil(entry.target)
        entry.appear(reader: reader, foreground: true, hasDestination: false)
        entry.continueToExistingDestination(reader: reader, hasDestination: false, rendered: entry.revision)
        XCTAssertNil(entry.target); XCTAssertEqual(entry.banner(reader: reader), .recovered)
    }
    func testPushKeepsOnlyItsCurrentNavigationThenReturnRereadsJournal() throws {
        let rig = try ResumeEntryRig(); try rig.seed(.unfinished); let reader = try XCTUnwrap(rig.reader)
        var entry = RoamHomeRecoveryEntry(); entry.appear(reader: reader, foreground: true, hasDestination: true)
        entry.continueToExistingDestination(reader: reader, hasDestination: true, rendered: entry.revision)
        let target = try XCTUnwrap(entry.target); entry.disappear()
        XCTAssertTrue(entry.matches(target, reader: reader, hasDestination: true)); XCTAssertNil(entry.banner(reader: reader))
        XCTAssertFalse(entry.matches(target, reader: reader, hasDestination: false))
        entry.target = nil; try rig.seed(.finishPending)
        entry.appear(reader: reader, foreground: true, hasDestination: true)
        XCTAssertEqual(entry.banner(reader: reader), .needsCheck); XCTAssertNil(entry.target)
    }
    func testOriginalBrowserContinueOpensDormantLiveDestinationAndBackReloadsPendingState() async throws {
        let rig = try ResumeEntryRig(); try rig.seed(.unfinished)
        let window = mount(rig); defer { close(window) }
        let bytes = rig.storage.rows, writes = rig.storage.writes
        try await tap("roam.home.recovery.continue", in: window)
        try await waitFor { self.find("roam.live.session", in: window) != nil && rig.live.phase == .unavailable }
        XCTAssertEqual(rig.live.phase, .unavailable)
        XCTAssertEqual(rig.storage.rows, bytes); XCTAssertEqual(rig.storage.writes, writes)
        try rig.seed(.finishPending); let reads = rig.storage.reads
        XCTAssertNotNil(try XCTUnwrap(navigation(window.rootViewController)).popViewController(animated: false))
        try await waitFor { self.find("roam.home.recovery.check", in: window) != nil }
        XCTAssertNil(find("roam.home.recovery.continue", in: window)); XCTAssertGreaterThan(rig.storage.reads, reads)
    }
    func testOriginalPendingCheckDestinationRemainsIndependentAndDoesNotAutoRead() async throws {
        let rig = try ResumeEntryRig(); try rig.seed(.finishPending)
        let window = mount(rig); defer { close(window) }
        let writes = rig.storage.writes
        try await tap("roam.home.recovery.check", in: window)
        try await waitFor { self.find("roam.experience.recovery", in: window) != nil }
        XCTAssertNil(find("roam.home.recovery.continue", in: window)); XCTAssertEqual(rig.storage.writes, writes)
        XCTAssertEqual(rig.live.phase, .ready, "Check must not construct or prepare the live screen")
    }
    func testBrowserWithoutLiveDestinationKeepsNoticeButDoesNotInventAContinueFallback() async throws {
        let rig = try ResumeEntryRig(); try rig.seed(.unfinished); rig.hasLiveDestination = false
        let window = mount(rig); defer { close(window) }
        try await waitFor { self.find("roam.home.recovery.recovered", in: window) != nil }
        XCTAssertNil(find("roam.home.recovery.continue", in: window))
        XCTAssertNil(find("roam.home.recovery.check", in: window))
    }
    func testVisibleBrowserRefreshesCurrentLocalStateAfterForegroundAndReaderReplacement() async throws {
        let rig = try ResumeEntryRig(); try rig.seed(.unfinished)
        let window = mount(rig); defer { close(window) }
        try await waitFor { self.find("roam.home.recovery.continue", in: window) != nil }
        rig.phase = .background
        try await waitFor { self.find("roam.home.recovery.recovered", in: window) == nil }
        try rig.seed(.finishPending); rig.phase = .active
        try await waitFor { self.find("roam.home.recovery.check", in: window) != nil }
        try rig.seed(.none); rig.reader = rig.makeReader()
        try await waitFor { self.find("roam.home.recovery.needsCheck", in: window) == nil }
        XCTAssertNil(find("roam.home.recovery.continue", in: window))
    }

    private func mount(_ rig: ResumeEntryRig) -> UIWindow {
        let host = UIHostingController(rootView: ResumeEntryHarness(rig: rig))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1000))
        window.rootViewController = host; window.makeKeyAndVisible(); host.loadViewIfNeeded(); host.view.layoutIfNeeded(); return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTFail("Original resume control did not settle"); throw APIError.notConfigured
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        try await waitFor { self.find(id, in: window) != nil }
        let target = try XCTUnwrap(find(id, in: window))
        if let control = target as? UIControl { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(target.accessibilityActivate()) }
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
        guard let controller else { return nil }; if let result = controller as? UINavigationController { return result }
        for child in controller.children { if let result = navigation(child) { return result } }; return nil
    }
}
@MainActor private struct ResumeEntryHarness: View {
    @ObservedObject var rig: ResumeEntryRig
    var body: some View {
        RoamBrowserView(reader: rig.map, experienceReader: rig.reader,
            liveDestination: rig.hasLiveDestination ? { AnyView(RoamLiveSessionView(controller: rig.live)) } : nil)
            .environment(\.scenePhase, rig.phase).environment(\.locale, Locale(identifier: "en_US"))
    }
}
@MainActor private final class ResumeEntryRig: ObservableObject {
    @Published var session: RoamExperienceSession?
    @Published var reader: RoamExperienceSessionReader? = nil
    @Published var phase: ScenePhase = .active
    @Published var hasLiveDestination = true
    let storage = ResumeEntryStorage()
    let map = RoamFixtureReader(scenario: .unconfigured)
    var journal: RoamLiveJournal { RoamLiveJournal(storage: storage) }
    private var store: RoamHistoryStore!
    var live: RoamLiveSessionController!
    init() throws {
        session = try Self.session()
        store = .init(storage: storage, currentScope: { [weak self] in self?.session?.identity.scope })
        reader = makeReader()
        live = .init(service: nil, location: nil, journal: journal, history: store)
    }
    static func session(account: Int = 7, epoch: UInt64 = 1, market: String = "cn",
                        deployment: String = "https://example.test/resume", namespace: String = "local-resume") throws -> RoamExperienceSession {
        try .init(scope: .init(market: market, deployment: XCTUnwrap(URL(string: deployment)), accountID: account, namespace: namespace), epoch: epoch, token: "synthetic-local-resume")
    }
    func makeReader(hasJournal: Bool = true) -> RoamExperienceSessionReader {
        .init(service: nil, store: store, localJournal: hasJournal ? journal : nil, currentSession: { [weak self] in self?.session })
    }
    func seed(_ status: RoamLocalWalkStatus) throws {
        if status == .none { storage.rows = [:]; return }
        let scope = try XCTUnwrap(session?.identity.scope)
        var value = RoamLiveRecord(scope: scope, clientSessionKey: String(repeating: "a", count: 32), startedAt: Date(timeIntervalSince1970: 1000))
        value.finishRequested = status == .finishPending
        try journal.write(value)
    }
}
@MainActor private final class ResumeEntryStorage: RoamHistoryDataStoring {
    var rows: [String: Data] = [:]
    var reads = 0, writes = 0, failRead = false
    var onRead: (() -> Void)?
    func read(key: String) throws -> Data? {
        reads += 1; onRead?(); if failRead { throw RoamExperienceFailure.historyUnreadable }; return rows[key]
    }
    func write(_ data: Data, key: String) throws { writes += 1; rows[key] = data }
}
