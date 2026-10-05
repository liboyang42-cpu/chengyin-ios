import XCTest
@testable import Questify

@MainActor final class WorkshopOwnedSessionBindingTests: XCTestCase {
    private final class Reader: WorkshopOwnedReading {
        var calls = 0
        func list(lifetime: WorkshopOwnedReadLifetime) async throws -> WorkshopOwnedPage { calls += 1; throw WorkshopOwnedIssue.unavailable }
        func detail(claimId: String, lifetime: WorkshopOwnedReadLifetime) async throws -> WorkshopOwnedDetail { calls += 1; throw WorkshopOwnedIssue.unavailable }
    }
    private func context(account: Int = 7, epoch: UInt64 = 1, namespace: String = "test", token: String = "token", role: String = "player", sessionRole: String = "player", base: String = "https://workshop-read.example/native") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: base)!, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token, role: sessionRole))
    }
    private func browser(_ context: RuntimeDependencyContext) -> WorkshopOwnedBrowser { browser(context, reader: Reader()) }
    private func browser(_ context: RuntimeDependencyContext, reader: Reader) -> WorkshopOwnedBrowser {
        .init(reader: reader, lease: .init(context: context, current: { context }))
    }
    func testNilContextOrConfigurationNeverConstructs() throws {
        let binding = WorkshopOwnedSessionBinding(), c = try context()
        var calls = 0
        binding.reconcile(context: c) { _ in calls += 1; return nil }
        binding.reconcile(context: nil, configurationRevision: UUID()) { _ in calls += 1; return nil }
        XCTAssertEqual(calls, 0); XCTAssertNil(binding.browser)
    }
    func testRepeatedReconciliationRetainsSameBrowserWithoutFetching() throws {
        let binding = WorkshopOwnedSessionBinding(), c = try context(), revision = UUID(), reader = Reader()
        var builds = 0
        binding.reconcile(context: c, configurationRevision: revision) { self.browser($0, reader: reader) }
        let first = try XCTUnwrap(binding.browser)
        binding.reconcile(context: c, configurationRevision: revision) { _ in builds += 1; return nil }
        XCTAssertTrue(binding.browser === first); XCTAssertEqual(builds, 0); XCTAssertEqual(reader.calls, 0)
    }
    func testCloseListRetainsBindingForSafeReopen() throws {
        let binding = WorkshopOwnedSessionBinding(), c = try context(), revision = UUID()
        binding.reconcile(context: c, configurationRevision: revision) { self.browser($0) }
        let first = try XCTUnwrap(binding.browser); first.closeList()
        binding.reconcile(context: c, configurationRevision: revision) { _ in XCTFail("unexpected rebuild"); return nil }
        XCTAssertTrue(binding.browser === first); XCTAssertEqual(first.phase, .idle)
    }
    func testEveryAuthorityReplacementInvalidatesBeforeFactory() throws {
        let original = try context()
        let replacements = try [context(account: 8), context(epoch: 2), context(namespace: "other"), context(token: "other"), context(role: "creator"), context(sessionRole: "creator"), context(base: "https://other.example/native")]
        for replacement in replacements {
            let binding = WorkshopOwnedSessionBinding(), revision = UUID()
            binding.reconcile(context: original, configurationRevision: revision) { self.browser($0) }
            let old = try XCTUnwrap(binding.browser)
            binding.reconcile(context: replacement, configurationRevision: revision) { next in
                XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(binding.browser); return self.browser(next)
            }
            XCTAssertFalse(binding.browser === old)
        }
    }
    func testConfigurationReplacementAndRemovalInvalidate() throws {
        let binding = WorkshopOwnedSessionBinding(), c = try context()
        binding.reconcile(context: c, configurationRevision: UUID()) { self.browser($0) }
        let old = try XCTUnwrap(binding.browser)
        binding.reconcile(context: c, configurationRevision: UUID()) { next in XCTAssertEqual(old.phase, .invalidated); return self.browser(next) }
        let next = try XCTUnwrap(binding.browser)
        binding.reconcile(context: c) { _ in XCTFail("missing configuration"); return nil }
        XCTAssertNil(binding.browser); XCTAssertEqual(next.phase, .invalidated)
    }
    func testExplicitInvalidationFencesIntermediateABA() throws {
        let binding = WorkshopOwnedSessionBinding(), c = try context(), revision = UUID()
        binding.reconcile(context: c, configurationRevision: revision) { self.browser($0) }
        let old = try XCTUnwrap(binding.browser)
        binding.invalidate() // Host does this before the intermediate identity mutation.
        binding.reconcile(context: c, configurationRevision: revision) { self.browser($0) }
        XCTAssertEqual(old.phase, .invalidated); XCTAssertFalse(binding.browser === old)
    }
    func testMissingFactoryResultRemainsClosedUntilExplicitConfigurationChange() throws {
        let binding = WorkshopOwnedSessionBinding(), c = try context(), revision = UUID()
        binding.reconcile(context: c, configurationRevision: revision) { _ in nil }
        binding.reconcile(context: c, configurationRevision: revision) { _ in XCTFail("must not synthesize approval"); return nil }
        XCTAssertNil(binding.browser)
    }
}
