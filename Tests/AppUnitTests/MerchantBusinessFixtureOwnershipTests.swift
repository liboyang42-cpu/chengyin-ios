#if DEBUG
import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class MerchantBusinessFixtureOwnershipTests: XCTestCase {
    @MainActor private final class RebuildSignal: ObservableObject {
        @Published var revision = 0
    }
    @MainActor private struct RebuildingParent: View {
        @ObservedObject var signal: RebuildSignal
        let observe: (MerchantBusinessFixtureOwner, Int) -> Void
        var body: some View {
            // A new fixture View value is constructed on every parent redraw.
            MerchantBusinessFixtureHostView(ownerObserver: observe, probeRevision: signal.revision)
        }
    }
    @MainActor private final class FixtureMount {
        let signal = RebuildSignal()
        private let sceneWindow: HostedNavigationSceneWindow
        private var window: UIWindow { sceneWindow.window }
        var observe: ((MerchantBusinessFixtureOwner, Int) -> Void)?
        private var host: UIHostingController<RebuildingParent>?
        init() throws { sceneWindow = try HostedNavigationSceneWindow() }
        func show() {
            let host = UIHostingController(rootView: RebuildingParent(signal: signal, observe: { [weak self] owner, revision in
                self?.observe?(owner, revision)
            }))
            self.host = host; window.rootViewController = host; window.makeKeyAndVisible()
        }
        func close() { observe = nil; sceneWindow.retire(); host = nil }
    }
    private func renderedOwner(_ mount: FixtureMount, revision: Int,
                               trigger: () -> Void) async throws -> MerchantBusinessFixtureOwner {
        let rendered = expectation(description: "Actual merchant fixture rendered at parent revision \(revision)")
        var result: MerchantBusinessFixtureOwner?
        mount.observe = { owner, observedRevision in
            guard observedRevision == revision, result == nil else { return }
            result = owner; rendered.fulfill()
        }
        defer { mount.observe = nil }
        trigger()
        await fulfillment(of: [rendered], timeout: 2)
        return try XCTUnwrap(result, "The actual SwiftUI host must render before ownership is asserted")
    }
    private func reserveUnknownIntent(_ owner: MerchantBusinessFixtureOwner) throws -> MerchantBusinessIntent {
        let intent = MerchantBusinessIntent(scope: try XCTUnwrap(owner.reader.scope), merchantID: 610,
                                            target: "review:63001", requestID: "synthetic-fixture-unknown-intent")
        try owner.journal.reserve(intent)
        return intent
    }
    private func routes(_ owner: MerchantBusinessFixtureOwner) -> [MerchantBusinessHomeRoute] {
        let targets: [MerchantBusinessHomeRoute.Target] = [
            .query(.customers(.init())), .query(.aftercare(.pending, page: 1)),
            .query(.reviews(page: 1)), .scan, .cityNode
        ]
        return targets.map { .init(target: $0, reader: owner.reader, journal: owner.journal) }
    }
    private func assertRetained(_ current: MerchantBusinessFixtureOwner, original: MerchantBusinessFixtureOwner,
                                intent: MerchantBusinessIntent, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(current === original, file: file, line: line)
        XCTAssertTrue(current.reader === original.reader, file: file, line: line)
        XCTAssertTrue(current.journal === original.journal, file: file, line: line)
        XCTAssertEqual(try current.journal.intents(), [intent], file: file, line: line)
        XCTAssertThrowsError(try current.journal.reserve(intent), file: file, line: line) { error in
            XCTAssertEqual(error as? MerchantBusinessFailure, .pending, file: file, line: line)
        }
    }

    func testActualHostedParentRedrawRetainsReaderJournalAndPreexistingRoutes() async throws {
        let mount = try FixtureMount()
        defer { mount.close() }
        let original = try await renderedOwner(mount, revision: 0) { mount.show() }
        let intent = try reserveUnknownIntent(original), preexisting = routes(original)
        let originalScope = original.reader.scope
        for revision in [1, 2] {
            let current = try await renderedOwner(mount, revision: revision) { mount.signal.revision = revision }
            try assertRetained(current, original: original, intent: intent)
            XCTAssertEqual(current.reader.scope, originalScope)
            for route in preexisting {
                XCTAssertTrue(route.isCurrent(reader: current.reader, journal: current.journal))
                XCTAssertTrue(route.reader === original.reader)
                XCTAssertTrue(route.journal === original.journal)
            }
        }
    }

    func testIndependentlyMountedHostsIsolateReaderJournalAndUnknownIntents() async throws {
        let firstMount = try FixtureMount()
        defer { firstMount.close() }
        let first = try await renderedOwner(firstMount, revision: 0) { firstMount.show() }
        // Construct the second scene window after the first becomes key, and
        // retire in reverse order so each helper restores its previous key window.
        let secondMount = try FixtureMount()
        defer { secondMount.close() }
        let second = try await renderedOwner(secondMount, revision: 0) { secondMount.show() }
        XCTAssertFalse(first === second)
        XCTAssertFalse(first.reader === second.reader)
        XCTAssertFalse(first.journal === second.journal)
        let intent = try reserveUnknownIntent(first), preexisting = routes(first)
        XCTAssertTrue(try second.journal.intents().isEmpty)
        for route in preexisting {
            XCTAssertFalse(route.isCurrent(reader: second.reader, journal: second.journal))
            XCTAssertFalse(route.isCurrent(reader: first.reader, journal: second.journal))
            XCTAssertFalse(route.isCurrent(reader: second.reader, journal: first.journal))
        }
        try second.journal.reserve(intent)
        try second.journal.complete(intent)
        XCTAssertTrue(try second.journal.intents().isEmpty)
        XCTAssertEqual(try first.journal.intents(), [intent])
        let firstScope = first.reader.scope
        second.reader.scope = nil
        let secondAfter = try await renderedOwner(secondMount, revision: 1) { secondMount.signal.revision = 1 }
        XCTAssertTrue(secondAfter === second)
        XCTAssertNil(secondAfter.reader.scope)
        XCTAssertTrue(try secondAfter.journal.intents().isEmpty)
        let firstAfter = try await renderedOwner(firstMount, revision: 1) { firstMount.signal.revision = 1 }
        try assertRetained(firstAfter, original: first, intent: intent)
        XCTAssertEqual(firstAfter.reader.scope, firstScope)
        for route in preexisting {
            XCTAssertTrue(route.isCurrent(reader: firstAfter.reader, journal: firstAfter.journal))
        }
    }

    private func assertContextChangeRejectsPreexistingRoutes(
        _ replacement: (MerchantBusinessScope) -> MerchantBusinessScope?
    ) async throws {
        let mount = try FixtureMount()
        defer { mount.close() }
        let original = try await renderedOwner(mount, revision: 0) { mount.show() }
        let intent = try reserveUnknownIntent(original), preexisting = routes(original)
        let scope = try XCTUnwrap(original.reader.scope), changed = replacement(scope)
        XCTAssertNotEqual(changed, scope)
        original.reader.scope = changed
        let current = try await renderedOwner(mount, revision: 1) { mount.signal.revision = 1 }
        try assertRetained(current, original: original, intent: intent)
        XCTAssertEqual(current.reader.scope, changed)
        for route in preexisting {
            XCTAssertFalse(route.isCurrent(reader: current.reader, journal: current.journal))
            XCTAssertEqual(route.context.scope, scope)
            XCTAssertTrue(route.reader === original.reader)
            XCTAssertTrue(route.journal === original.journal)
            XCTAssertNotEqual(route, MerchantBusinessHomeRoute(target: route.target, reader: current.reader, journal: current.journal))
        }
    }
    func testHostedSignOutRejectsOldRoutesWithoutClearingUnknownIntent() async throws {
        try await assertContextChangeRejectsPreexistingRoutes { _ in nil }
    }
    func testHostedNewAccountRejectsOldRoutesWithoutRebindingDependencies() async throws {
        try await assertContextChangeRejectsPreexistingRoutes {
            .init(realm: $0.realm, accountID: $0.accountID + 1, epoch: $0.epoch)
        }
    }
    func testHostedNewEpochRejectsOldRoutesWithoutRebindingDependencies() async throws {
        try await assertContextChangeRejectsPreexistingRoutes {
            .init(realm: $0.realm, accountID: $0.accountID, epoch: $0.epoch + 1)
        }
    }
}
#endif
