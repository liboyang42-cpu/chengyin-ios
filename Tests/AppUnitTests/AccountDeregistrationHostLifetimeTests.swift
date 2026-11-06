import Foundation
import SwiftUI
import XCTest
@testable import Questify

@MainActor private final class C08HostVault: AppTokenStorage {
    var token: String? = "synthetic-c08-7"
    func read() throws -> String? { token }
    func write(_ value: String) throws { token = value }
    func clear() throws { token = nil }
}
@MainActor private final class C08HostWire: HTTPTransport {
    var requests: [URLRequest] = []
    var role = "player", replyStatus = 200, replyCode = 200
    var onStatus: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.lastPathComponent == "userInfo" {
            return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
        }
        onStatus?()
        return (Data("{\"code\":\(replyCode),\"data\":{\"status\":\"NORMAL\"}}".utf8), replyStatus)
    }
}
@MainActor private final class C08HostFixture {
    let vault = C08HostVault(), wire = C08HostWire()
    let source: AccountDeregistrationOriginalConfigurationSource
    let root: AppCompositionRoot
    let suite = "c08-host-" + UUID().uuidString
    let defaults: UserDefaults
    init(includeSource: Bool = true) throws {
        source = try .init()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://c08.example.test/native",
            approvedBaseURLs: [.china: ["https://c08.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.c08." + UUID().uuidString.lowercased(), realm: "synthetic",
            accountDeregistrationOriginalSource: includeSource ? source : nil)
        let vault = vault, wire = wire
        root = .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
    }
    func cleanup() { source.revoke(); defaults.removePersistentDomain(forName: suite) }
    func boot() async -> AppSession {
        let session = root.makeSession(); await session.bootstrap(); wire.requests = []; return session
    }
    func grant() throws -> AccountDeregistrationOriginalApproval {
        let reviewed = try XCTUnwrap(root.reviewed), api = try XCTUnwrap(reviewed.regional.apiConfiguration)
        return try .init(endpoint: .init(baseURL: api.baseURL, namespace: reviewed.storageScope.service, accountID: 7,
            paths: AccountDeregistrationOriginalClient.readPaths), issuanceID: UUID())
    }
    func context() throws -> RuntimeDependencyContext {
        let reviewed = try XCTUnwrap(root.reviewed), api = try XCTUnwrap(reviewed.regional.apiConfiguration)
        return .init(market: .china, baseURL: api.baseURL, role: "player", session: try .init(accountID: 7, epoch: 1,
            namespace: reviewed.storageScope.service, token: "synthetic-c08-7", role: "player"))
    }
}

/// Local synthetic wire only. These are authored native tests, not runtime acceptance evidence.
@MainActor final class AccountDeregistrationHostLifetimeTests: XCTestCase {
    private func fixture(includeSource: Bool = true) throws -> C08HostFixture {
        let h = try C08HostFixture(includeSource: includeSource)
        addTeardownBlock { @MainActor in h.cleanup() }; return h
    }
    func testNormalSessionDefaultsToNilSourceAndNoDeletionReads() async throws {
        let h = try fixture(includeSource: false), session = await h.boot()
        XCTAssertEqual(session.account?.id, 7); XCTAssertNil(h.root.reviewed?.accountDeregistrationOriginalSource)
        let coordinator = try XCTUnwrap(session.accountComplianceCoordinator)
        await coordinator.load()
        XCTAssertEqual(coordinator.state.error, "compliance.unavailable"); XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testEmptySourceDoesNotBecomeApproval() async throws {
        let h = try fixture(), session = await h.boot()
        let coordinator = try XCTUnwrap(session.accountComplianceCoordinator)
        await coordinator.load()
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testExplicitReadOnlySourceReachesNormalCoordinatorAndRevocationClearsState() async throws {
        let h = try fixture(), session = await h.boot(); try h.source.replace(with: h.grant())
        let coordinator = try XCTUnwrap(session.accountComplianceCoordinator), model = ComplianceViewModel(coordinator, isDeregistration: true)
        await coordinator.load(intent: try XCTUnwrap(model.cancellationIntent()))
        XCTAssertEqual(model.state.step, .notice); XCTAssertEqual(model.state.status?.status, "NORMAL")
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.wire.requests.first?.httpMethod, "GET")
        h.source.revoke()
        XCTAssertNil(model.state.status); XCTAssertNil(model.cancellationIntent(resume: true))
        await coordinator.precheckAndAgree(documentRead: true, explicitAgreement: true, expectedConsentVersion: "synthetic-v1")
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testOldModelDismissalCannotInvalidateReplacementModel() async throws {
        let h = try fixture(), session = await h.boot(); try h.source.replace(with: h.grant())
        let coordinator = try XCTUnwrap(session.accountComplianceCoordinator)
        let old = ComplianceViewModel(coordinator, isDeregistration: true), new = ComplianceViewModel(coordinator, isDeregistration: true)
        let intent = try XCTUnwrap(new.cancellationIntent()); old.endPresentation()
        XCTAssertNil(old.cancellationIntent()); XCTAssertTrue(coordinator.isCurrentDeregistrationIntent(intent))
        await coordinator.load(intent: intent)
        XCTAssertEqual(new.state.status?.status, "NORMAL"); XCTAssertNil(old.state.status)
    }
    func testPauseRequiresSameOwnerResumeAndDoesNotAutomaticallyRead() async throws {
        let h = try fixture(), session = await h.boot(); try h.source.replace(with: h.grant())
        let coordinator = try XCTUnwrap(session.accountComplianceCoordinator), model = ComplianceViewModel(coordinator, isDeregistration: true)
        let old = try XCTUnwrap(model.cancellationIntent()); model.pauseCancellation()
        await coordinator.load(intent: old); XCTAssertTrue(h.wire.requests.isEmpty)
        XCTAssertNil(model.cancellationIntent()); let fresh = try XCTUnwrap(model.cancellationIntent(resume: true))
        XCTAssertTrue(h.wire.requests.isEmpty); await coordinator.load(intent: fresh)
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testSourceReissueCannotResumeOldPresentationOrReuseIssuance() async throws {
        let h = try fixture(), session = await h.boot(), approval = try h.grant(); try h.source.replace(with: approval)
        let coordinator = try XCTUnwrap(session.accountComplianceCoordinator), old = ComplianceViewModel(coordinator, isDeregistration: true)
        let intent = try XCTUnwrap(old.cancellationIntent()); try h.source.replace(with: h.grant())
        XCTAssertNil(old.cancellationIntent(resume: true)); await coordinator.load(intent: intent)
        XCTAssertTrue(h.wire.requests.isEmpty)
        XCTAssertThrowsError(try h.source.replace(with: approval))
    }
    func testRoleRefreshRetiresExistingModelEvenWhenComplianceSessionTupleIsUnchanged() async throws {
        let h = try fixture(), session = await h.boot(); try h.source.replace(with: h.grant())
        let coordinator = try XCTUnwrap(session.accountComplianceCoordinator), model = ComplianceViewModel(coordinator, isDeregistration: true)
        let intent = try XCTUnwrap(model.cancellationIntent())
        h.wire.role = "merchant"; await session.refreshOwnAccount(); h.wire.requests = []
        XCTAssertNil(model.cancellationIntent(resume: true)); await coordinator.load(intent: intent)
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testLateRevoked401CannotLogOutNormalSession() async throws {
        for status in [200, 401] {
            let h = try fixture(), session = await h.boot(); try h.source.replace(with: h.grant())
            let coordinator = try XCTUnwrap(session.accountComplianceCoordinator)
            h.wire.replyStatus = status; h.wire.replyCode = 401; h.wire.onStatus = { h.source.revoke() }
            await coordinator.load()
            XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(h.vault.token, "synthetic-c08-7")
            XCTAssertNil(coordinator.state.status)
        }
    }
    func testFullViewerRevisionABAFenceRejectsOldTransport() async throws {
        let h = try fixture(), context = try h.context(), approval = try h.grant(), host = h.root.transport()
        var viewer = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-c08-7", viewerRevision: 1)
        host.current = { viewer }
        let scoped = try XCTUnwrap(host.makeAccountDeregistrationOriginalTransport(context: context, approval: approval, currentRuntime: { context }, stillApproved: { true }))
        viewer = .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-c08-7", viewerRevision: 3)
        let client = AccountDeregistrationOriginalClient(context: context, approval: approval, transport: scoped, current: { context }, stillApproved: { true }, onUnauthorized: { XCTFail() })
        do { _ = try await client.status(session: .init(accountID: 7, epoch: 1, market: "CN", namespace: context.session.namespace)); XCTFail() } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testGenericTransportDoesNotBorrowDedicatedSource() async throws {
        let h = try fixture(), context = try h.context(), approval = try h.grant(); try h.source.replace(with: approval)
        let host = h.root.transport(); host.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-c08-7") }
        let client = AccountDeregistrationOriginalClient(context: context, approval: approval, transport: host, current: { context }, stillApproved: { true }, onUnauthorized: { XCTFail() })
        do { _ = try await client.status(session: .init(accountID: 7, epoch: 1, market: "CN", namespace: context.session.namespace)); XCTFail() } catch {}
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testPartialIdentityCannotConstructDedicatedTransport() throws {
        let h = try fixture(), context = try h.context(), approval = try h.grant(), host = h.root.transport()
        for viewer in [CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: nil, token: "synthetic-c08-7"),
                       .init(epoch: 1, accountID: 7, role: "player", token: nil),
                       .init(epoch: 1, accountID: nil, role: "player", token: "synthetic-c08-7")] {
            host.current = { viewer }
            XCTAssertNil(host.makeAccountDeregistrationOriginalTransport(context: context, approval: approval, currentRuntime: { context }, stillApproved: { true }))
        }
    }
    func testAllNewDisplayKeysAreBundledInBothLanguages() throws {
        let app = Bundle(for: ComplianceViewModel.self)
        for language in ["en", "zh-Hans"] {
            let bundle = try XCTUnwrap(Bundle(path: XCTUnwrap(app.path(forResource: language, ofType: "lproj"))))
            for number in 1...45 {
                let key = "c08.display.\(number)"
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: "AccountDeregistrationPresentation"), key)
            }
            for key in ["compliance.cancellationConfirmed", "compliance.completed", "compliance.impactChanged"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: key, value: nil, table: "AccountDeregistrationPresentation"), key)
            }
        }
    }
}
