import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Original local history -> Passport -> History -> Back. No remote service, transport or writer.
@MainActor final class RoamPassportHomeScopeRecoveryTests: XCTestCase {
    func testLocalHistoryRemainsReadableWithoutRemoteConfiguration() async throws {
        let rig = try PassportScopeRig(); try rig.seed(3)
        let window = mount(rig); defer { close(window) }
        XCTAssertFalse(try XCTUnwrap(rig.reader).isConfigured)
        try await trips(3, in: window)
        XCTAssertEqual(try rig.reader?.history().count, 3)
        XCTAssertGreaterThan(rig.storage.reads, 0); XCTAssertEqual(rig.storage.writes, 0)
    }

    func testSameIdentityReaderReplacementCannotInheritPriorSuccessAndRetryUsesOriginalStore() async throws {
        let rig = try PassportScopeRig(); try rig.seed(3)
        let window = mount(rig); defer { close(window) }
        try await trips(3, in: window)
        let original = try XCTUnwrap(rig.reader), originalScope = RoamPassportReaderScope(original)
        let bytes = rig.storage.rows
        rig.storage.failure = RoamExperienceFailure.historyUnreadable
        rig.reader = rig.makeReader()
        XCTAssertEqual(original.identity, rig.reader?.identity)
        XCTAssertNotEqual(originalScope, RoamPassportReaderScope(try XCTUnwrap(rig.reader)))
        try await reveal("roam.experience.error", in: window)
        XCTAssertNil(find("roam.home.passport.stat.trips", in: window))
        rig.storage.failure = nil
        try await tap("roam.experience.retry", in: window)
        try await trips(3, in: window)
        XCTAssertEqual(rig.storage.rows, bytes); XCTAssertEqual(rig.storage.writes, 0)
    }

    func testEpochAndRealmReplacementReloadCurrentLocalCountsWithoutRecreatingTheHost() async throws {
        let rig = try PassportScopeRig(); try rig.seed(3)
        let window = mount(rig); defer { close(window) }
        try await trips(3, in: window)
        let reads = rig.storage.reads
        rig.session = try PassportScopeRig.session(epoch: 2); try rig.seed(2)
        try await trips(2, in: window)
        XCTAssertGreaterThan(rig.storage.reads, reads)
        rig.session = try PassportScopeRig.session(epoch: 3, namespace: "other-local-namespace"); try rig.seed(1)
        try await trips(1, in: window)
        XCTAssertEqual(rig.storage.writes, 0)
    }

    func testNilReaderHidesOldStatisticsAndRestorationReadsFreshLocalHistory() async throws {
        let rig = try PassportScopeRig(); try rig.seed(3)
        let window = mount(rig); defer { close(window) }
        try await trips(3, in: window)
        rig.reader = nil
        try await reveal("roam.home.passport.unavailable", in: window)
        XCTAssertNil(find("roam.home.passport.stat.trips", in: window))
        XCTAssertNil(find("roam.home.passport.tile.history", in: window))
        try rig.seed(2); rig.reader = rig.makeReader()
        try await trips(2, in: window)
        XCTAssertEqual(rig.storage.writes, 0)
    }

    func testSessionLossRetiresCachedCountsAndCurrentSessionRecoveryReloads() async throws {
        let rig = try PassportScopeRig(); try rig.seed(3)
        let window = mount(rig); defer { close(window) }
        try await trips(3, in: window)
        rig.session = nil
        try await reveal("roam.experience.error", in: window)
        XCTAssertNil(find("roam.home.passport.stat.trips", in: window))
        rig.session = try PassportScopeRig.session(epoch: 2); try rig.seed(1)
        try await trips(1, in: window)
        XCTAssertEqual(rig.storage.writes, 0)
    }

    func testOriginalHistoryNavigationAndBackRereadsCurrentLocalRecordsWithoutInferringCompletion() async throws {
        let rig = try PassportScopeRig(); try rig.seed(3)
        let window = mount(rig); defer { close(window) }
        try await trips(3, in: window)
        try await tap("roam.home.passport.tile.history", in: window)
        try await reveal("roam.experience.history.record", in: window)
        let reads = rig.storage.reads
        try rig.seed(2)
        let navigation = try XCTUnwrap(navigation(window.rootViewController))
        XCTAssertNotNil(navigation.popViewController(animated: false))
        try await trips(2, in: window)
        XCTAssertGreaterThan(rig.storage.reads, reads); XCTAssertEqual(rig.storage.writes, 0)
    }

    func testOriginalReaderScopeSeparatesObjectAccountEpochDeploymentNamespaceAndNilSession() throws {
        let rig = try PassportScopeRig(), reader = try XCTUnwrap(rig.reader)
        let scope = RoamPassportReaderScope(reader)
        XCTAssertEqual(scope, RoamPassportReaderScope(reader))
        XCTAssertNotEqual(scope, RoamPassportReaderScope(rig.makeReader()))
        for replacement in [try PassportScopeRig.session(account: 8), try PassportScopeRig.session(epoch: 2),
                            try PassportScopeRig.session(deployment: "https://example.test/other"),
                            try PassportScopeRig.session(namespace: "other"), try PassportScopeRig.session(market: "us")] {
            rig.session = replacement
            XCTAssertNotEqual(scope, RoamPassportReaderScope(reader))
        }
        rig.session = nil
        XCTAssertNotEqual(scope, RoamPassportReaderScope(reader))
        XCTAssertEqual(rig.storage.reads, 0); XCTAssertEqual(rig.storage.writes, 0)
    }

    private func mount(_ rig: PassportScopeRig) -> UIWindow {
        let host = UIHostingController(rootView: PassportScopeHarness(rig: rig))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 430, height: 1100))
        window.rootViewController = host; window.makeKeyAndVisible()
        host.loadViewIfNeeded(); host.view.layoutIfNeeded(); return window
    }
    private func close(_ window: UIWindow) { window.isHidden = true; window.rootViewController = nil }
    private func trips(_ count: Int, in window: UIWindow) async throws {
        try await waitFor("Original current-owner trip count \(count)") {
            self.find("roam.home.passport.stat.trips", in: window)?.accessibilityLabel?.contains(String(count)) == true
        }
        XCTAssertNotNil(find("roam.home.passport.tile.history", in: window))
    }
    private func waitFor(_ message: String, _ condition: () -> Bool) async throws {
        for _ in 0..<150 { if condition() { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        XCTFail(message); throw APIError.notConfigured
    }
    private func reveal(_ id: String, in window: UIWindow) async throws {
        for _ in 0..<35 {
            if find(id, in: window) != nil { return }
            scroll(window); try await Task.sleep(nanoseconds: 40_000_000)
        }
        XCTFail("Original control missing: " + id); throw APIError.notConfigured
    }
    private func scroll(_ view: UIView) {
        if let scroll = view as? UIScrollView {
            let end = max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            if scroll.contentOffset.y < end {
                scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: min(end, scroll.contentOffset.y + 300)), animated: false)
                scroll.layoutIfNeeded()
            }
        }
        for child in view.subviews { scroll(child) }
    }
    private func tap(_ id: String, in window: UIWindow) async throws {
        try await reveal(id, in: window)
        let target = try XCTUnwrap(find(id, in: window))
        if let control = target as? UIControl { control.sendActions(for: .touchUpInside) }
        else { XCTAssertTrue(target.accessibilityActivate()) }
    }
    private func find(_ id: String, in window: UIWindow) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ root: NSObject) -> NSObject? {
            guard seen.insert(ObjectIdentifier(root)).inserted else { return nil }
            if (root as? UIAccessibilityIdentification)?.accessibilityIdentifier == id { return root }
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
    private func navigation(_ controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let result = controller as? UINavigationController { return result }
        for child in controller.children { if let result = navigation(child) { return result } }
        return nil
    }
}

@MainActor private struct PassportScopeHarness: View {
    @ObservedObject var rig: PassportScopeRig
    var body: some View {
        // Changing a normal host value does not reset the Passport view's identity or its @State.
        let context = rig.session?.identity
        return NavigationStack {
            RoamHomePassportView(reader: rig.reader, discoverDestination: {
                AnyView(Text(String(describing: context)))
            })
        }.environment(\.locale, Locale(identifier: "en_US"))
    }
}
@MainActor private final class PassportScopeRig: ObservableObject {
    @Published var session: RoamExperienceSession?
    @Published var reader: RoamExperienceSessionReader? = nil
    let storage = PassportScopeStorage()
    private var store: RoamHistoryStore!
    init() throws {
        session = try Self.session()
        store = .init(storage: storage, currentScope: { [weak self] in self?.session?.identity.scope })
        reader = makeReader()
    }
    static func session(account: Int = 7, epoch: UInt64 = 1, market: String = "cn",
                        deployment: String = "https://example.test/passport-scope", namespace: String = "passport-original") throws -> RoamExperienceSession {
        try .init(scope: .init(market: market, deployment: XCTUnwrap(URL(string: deployment)), accountID: account, namespace: namespace), epoch: epoch, token: "synthetic-passport-local")
    }
    func makeReader() -> RoamExperienceSessionReader {
        .init(service: nil, store: store, currentSession: { [weak self] in self?.session })
    }
    func seed(_ count: Int) throws {
        struct Seed: Encodable { let version = 1; let scope: RoamHistoryScope; let records: [RoamHistoryRecord] }
        let scope = try XCTUnwrap(session?.identity.scope)
        let records = try (0..<count).map { offset in
            try JSONDecoder().decode(RoamHistoryRecord.self, from: JSONSerialization.data(withJSONObject:
                ["ts": 1_700_000_000_000 + offset, "distance": 1, "shops": 1, "zone": "Synthetic local record"]))
        }
        storage.rows[scope.storageKey] = try JSONEncoder().encode(Seed(scope: scope, records: records))
    }
}
@MainActor private final class PassportScopeStorage: RoamHistoryDataStoring {
    var rows: [String: Data] = [:], failure: Error?
    var reads = 0, writes = 0
    func read(key: String) throws -> Data? { reads += 1; if let failure { throw failure }; return rows[key] }
    func write(_ data: Data, key: String) throws { writes += 1; XCTFail("This journey has no local history writer") }
}
