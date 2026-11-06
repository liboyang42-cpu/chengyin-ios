import Foundation
import XCTest
@testable import Questify

@MainActor private final class UsageHistoryHostVault: AppTokenStorage {
    var value: String? = "synthetic-usage-host"
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token }
    func clear() throws { value = nil }
}
@MainActor private final class UsageHistoryHostWire: HTTPTransport {
    var requests: [URLRequest] = []
    var role = "player", status = 200, code = 200
    var after: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.lastPathComponent == "userInfo" { return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200) }
        defer { after?() }
        var value: [String: Any] = ["accountId": 7, "scene": "app_launch", "readOnly": true, "nativeMarketBinding": "UNPROVEN"]
        let key = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "requestId" }?.value ?? "host-key"
        let row: [String: Any] = ["id": 3, "docType": "privacy", "docVersion": "v1", "eventType": "AGREE", "requestId": key, "occurredAt": 1]
        if request.url?.lastPathComponent == "request" {
            value["record"] = row; value["latestRecordId"] = 3
            value["document"] = ["docType": "privacy", "version": "v1", "availability": "MISSING"]
        } else { value["items"] = [row] }
        return (try JSONSerialization.data(withJSONObject: ["code": code, "data": value]), status)
    }
}
@MainActor private final class UsageHistoryHostFixture {
    let wire = UsageHistoryHostWire(), vault = UsageHistoryHostVault()
    let root: AppCompositionRoot
    let suite = "usage-history-" + UUID().uuidString
    let defaults: UserDefaults
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://usage-host.example.test/native",
            approvedBaseURLs: [.china: ["https://usage-host.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.usage.history." + UUID().uuidString.lowercased(), realm: "synthetic")
        let wire = wire, vault = vault
        root = .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
    }
    func boot() async -> AppSession { let session = root.makeSession(); await session.bootstrap(); wire.requests = []; return session }
    func cleanup() { root.usageConsentReadSelection.revoke(); defaults.removePersistentDomain(forName: suite) }
    func approval(paths: Set<String> = Set(UsageConsentReadRoute.paths)) throws -> UsageConsentReadApproval {
        let reviewed = try XCTUnwrap(root.reviewed), api = try XCTUnwrap(reviewed.regional.apiConfiguration)
        return try .init(market: .china, endpoint: .init(baseURL: api.baseURL, namespace: reviewed.storageScope.service, accountID: 7, paths: paths))
    }
    func context() throws -> RuntimeDependencyContext {
        let reviewed = try XCTUnwrap(root.reviewed), api = try XCTUnwrap(reviewed.regional.apiConfiguration)
        return .init(market: .china, baseURL: api.baseURL, role: "player", session: try .init(accountID: 7, epoch: 1,
            namespace: reviewed.storageScope.service, token: "synthetic-usage-host", role: "player"))
    }
    func request(_ context: RuntimeDependencyContext, path: String = UsageConsentReadRoute.history) -> URLRequest {
        var request = URLRequest(url: context.baseURL.appendingPathComponent(path)); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue("synthetic-usage-host", forHTTPHeaderField: "Authorization")
        return request
    }
}

/// Synthetic read-only host specimens. No login/provider, legal acceptance or backend execution is claimed.
@MainActor final class UsageConsentHistoryHostTests: XCTestCase {
    private func fixture() throws -> UsageHistoryHostFixture {
        let value = try UsageHistoryHostFixture(); addTeardownBlock { @MainActor in value.cleanup() }; return value
    }
    func testNormalHostHasNoReadSourceByDefault() async throws {
        let f = try fixture(), session = await f.boot()
        XCTAssertNil(session.makeUsageConsentReadCoordinator()); XCTAssertNil(session.usageConsentReadIdentity.approval)
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertFalse(UsageConsentPolicy.liveRecordingApproved)
    }
    func testNormalSettingsHostReadsHistoryThenExactOriginalWithoutMutation() async throws {
        let f = try fixture(), session = await f.boot(); try f.root.usageConsentReadSelection.replace(with: f.approval())
        let flow = try XCTUnwrap(session.makeUsageConsentReadCoordinator()), owner = flow.beginPresentation()
        await flow.reload(intent: try XCTUnwrap(flow.captureRead(owner)))
        XCTAssertEqual(flow.items.first?.docType, "privacy")
        await flow.read("host-key", intent: try XCTUnwrap(flow.captureRead(owner)))
        XCTAssertEqual(flow.detail?.record.requestId, "host-key"); XCTAssertEqual(flow.detail?.document.availability, "MISSING")
        XCTAssertEqual(f.wire.requests.map(\.httpMethod), ["GET", "GET"])
        XCTAssertTrue(f.wire.requests.allSatisfy { $0.httpBody == nil && $0.value(forHTTPHeaderField: "Authorization") == "synthetic-usage-host" })
    }
    func testOriginalOnlyHostGrantWorksAfterUnavailableHistory() async throws {
        let f = try fixture(), session = await f.boot(); try f.root.usageConsentReadSelection.replace(with: f.approval(paths: [UsageConsentReadRoute.original]))
        let flow = try XCTUnwrap(session.makeUsageConsentReadCoordinator()), owner = flow.beginPresentation()
        await flow.reload(intent: try XCTUnwrap(flow.captureRead(owner)))
        XCTAssertEqual(flow.failure, .unavailable); XCTAssertTrue(f.wire.requests.isEmpty)
        await flow.read("original / + 键", intent: try XCTUnwrap(flow.captureRead(owner)))
        XCTAssertEqual(flow.detail?.record.requestId, "original / + 键"); XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testSourceRevocationImmediatelyClearsAlreadyDisplayedEvidenceAndQueuedRead() async throws {
        let f = try fixture(), session = await f.boot(); try f.root.usageConsentReadSelection.replace(with: f.approval())
        let flow = try XCTUnwrap(session.makeUsageConsentReadCoordinator()), owner = flow.beginPresentation()
        await flow.reload(intent: try XCTUnwrap(flow.captureRead(owner))); XCTAssertFalse(flow.items.isEmpty)
        let queued = try XCTUnwrap(flow.captureRead(owner)), oldIdentity = session.usageConsentReadIdentity
        f.root.usageConsentReadSelection.revoke()
        XCTAssertTrue(flow.items.isEmpty); XCTAssertNil(flow.detail); XCTAssertFalse(flow.loaded)
        XCTAssertNotEqual(session.usageConsentReadIdentity, oldIdentity); XCTAssertNil(session.makeUsageConsentReadCoordinator())
        await flow.read("host-key", intent: queued); XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testNewIssuanceRetiresOldReaderAndCannotReuseRetiredApproval() async throws {
        let f = try fixture(), session = await f.boot(), original = try f.approval()
        try f.root.usageConsentReadSelection.replace(with: original)
        let old = try XCTUnwrap(session.makeUsageConsentReadCoordinator()), lease = old.beginPresentation(), queued = try XCTUnwrap(old.captureRead(lease))
        try f.root.usageConsentReadSelection.replace(with: f.approval())
        let new = try XCTUnwrap(session.makeUsageConsentReadCoordinator()), newLease = new.beginPresentation()
        old.endPresentation(lease); await old.reload(intent: queued)
        XCTAssertNotNil(new.captureRead(newLease)); XCTAssertTrue(f.wire.requests.isEmpty)
        XCTAssertThrowsError(try f.root.usageConsentReadSelection.replace(with: original))
        await new.reload(intent: try XCTUnwrap(new.captureRead(newLease))); XCTAssertTrue(new.loaded)
    }
    func testRoleRefreshRetiresOldCapturedReadWithoutUsingNewCredentials() async throws {
        let f = try fixture(), session = await f.boot(); try f.root.usageConsentReadSelection.replace(with: f.approval())
        let flow = try XCTUnwrap(session.makeUsageConsentReadCoordinator()), owner = flow.beginPresentation()
        await flow.reload(intent: try XCTUnwrap(flow.captureRead(owner)))
        await flow.read("host-key", intent: try XCTUnwrap(flow.captureRead(owner)))
        XCTAssertFalse(flow.items.isEmpty); XCTAssertNotNil(flow.detail)
        let queued = try XCTUnwrap(flow.captureRead(owner)), old = session.usageConsentReadIdentity
        f.wire.role = "merchant"; await session.refreshOwnAccount(); f.wire.requests = []
        XCTAssertNotEqual(session.usageConsentReadIdentity, old)
        // No UI lifecycle callback is needed to hide the old account evidence.
        XCTAssertTrue(flow.items.isEmpty); XCTAssertNil(flow.detail); XCTAssertNil(flow.nextBeforeId); XCTAssertFalse(flow.loaded)
        await flow.reload(intent: queued); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testLateRevoked401CannotExpireCurrentAccountOrExposeEvidence() async throws {
        for status in [200, 401] {
            let f = try fixture(), session = await f.boot(); try f.root.usageConsentReadSelection.replace(with: f.approval())
            let flow = try XCTUnwrap(session.makeUsageConsentReadCoordinator())
            f.wire.code = 401; f.wire.status = status; f.wire.after = { f.root.usageConsentReadSelection.revoke() }
            await flow.reload()
            XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(f.vault.value, "synthetic-usage-host")
            XCTAssertTrue(flow.items.isEmpty); XCTAssertFalse(flow.loaded)
        }
    }
    func testCompleteViewerRevisionABARejectsOldTransport() async throws {
        let f = try fixture(), context = try f.context(), grant = try f.approval(), host = f.root.transport()
        var viewer = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-usage-host", viewerRevision: 1)
        host.current = { viewer }
        let scoped = try XCTUnwrap(host.makeUsageConsentReadTransport(context: context, approval: grant, currentRuntime: { context }, stillApproved: { true }))
        viewer = .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-usage-host", viewerRevision: 3)
        do { _ = try await scoped.send(f.request(context)); XCTFail() } catch {}
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testFactoryRejectsRoleTokenOrRealmMismatchBeforeNetwork() throws {
        let f = try fixture(), context = try f.context(), grant = try f.approval(), host = f.root.transport()
        host.current = { .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-usage-host", viewerRevision: 1) }
        XCTAssertNil(host.makeUsageConsentReadTransport(context: context, approval: grant, currentRuntime: { context }, stillApproved: { true }))
        host.current = { .init(epoch: 1, accountID: 7, role: "player", token: "other-token", viewerRevision: 1) }
        XCTAssertNil(host.makeUsageConsentReadTransport(context: context, approval: grant, currentRuntime: { context }, stillApproved: { true }))
        let foreign = RuntimeDependencyContext(market: context.market, baseURL: URL(string: "https://foreign.example.test")!, role: context.role, session: context.session)
        XCTAssertNil(f.root.selectedUsageConsentReadApproval(foreign)); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testGenericTransportCannotBorrowIndependentReadSourceOrSendConsent() async throws {
        let f = try fixture(), context = try f.context(); try f.root.usageConsentReadSelection.replace(with: f.approval())
        let host = f.root.transport(); host.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-usage-host") }
        for path in [UsageConsentReadRoute.history, "api/compliance/consents", "api/agreement/consent"] {
            var request = f.request(context, path: path); if path != UsageConsentReadRoute.history { request.httpMethod = "POST" }
            do { _ = try await host.send(request); XCTFail() } catch {}
        }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testReadHistoryDoesNotChangeLocalChoiceOrPendingLegalRecords() async throws {
        let f = try fixture(), session = await f.boot(); try f.root.usageConsentReadSelection.replace(with: f.approval())
        let policy = UsageConsentPolicy(storage: UserDefaultsUsageConsentStorage(defaults: f.defaults))
        try policy.agree(agreementChecked: true); let before = policy.pendingRecords(accountID: 7)
        let flow = try XCTUnwrap(session.makeUsageConsentReadCoordinator()); await flow.reload(); await flow.read("host-key")
        XCTAssertEqual(policy.pendingRecords(accountID: 7), before); XCTAssertTrue(policy.granted)
        XCTAssertFalse(UsageConsentPolicy.liveRecordingApproved)
        XCTAssertTrue(f.wire.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testEvidenceAndSourceBoundaryCatalogIsBilingual() throws {
        let keys = ["usageEvidence.title", "usageEvidence.boundary", "usageEvidence.history", "usageEvidence.original", "usageEvidence.nativeBindingUnavailable", "usageEvidence.timeUnavailable", "usageEvidence.source.SOURCE_AVAILABLE", "usageEvidence.source.MISSING"]
        let app = Bundle(for: AppSession.self)
        for language in ["en", "zh-Hans"] {
            let bundle = try XCTUnwrap(Bundle(path: XCTUnwrap(app.path(forResource: language, ofType: "lproj"))))
            for key in keys { XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: "UsageConsentEvidence"), key) }
        }
    }
}
