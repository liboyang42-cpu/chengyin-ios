import Foundation
import XCTest
@testable import Questify

/// Exercises the actual AppSession factory, not NativeChannelNotificationBinding.make.
/// Only the separately granted unread-recovery GET is used. On the audited source,
/// factory/dispatcher/coordinator constructors and this path do not read or write
/// ProjectEditSecureStorage. ACK, ordinary activate(), and receipt recovery are
/// deliberately absent because that real factory has no injected journal seam.
@MainActor final class NativeChannelNotificationAppSessionFactoryTests: XCTestCase {
    func testActualFactoryDefaultSelectorStaysClosedBeforeAndAfterRealLogin() async throws {
        let h = try Harness(injectSelector: false); defer { h.clean() }
        XCTAssertNil(h.session.makeNativeChannelNotificationFlow(scope: nil))
        XCTAssertTrue(h.wire.requests.isEmpty)
        await h.login()
        XCTAssertEqual(h.session.account?.id, 7)
        XCTAssertNil(h.session.makeNativeChannelNotificationFlow(scope: nil))
        XCTAssertTrue(h.wire.notificationRequests.isEmpty)
        XCTAssertTrue(h.session.isSignedIn)
    }

    func testAbsentAncestorNeverSelectsAuthorityOrSendsFromActualFactory() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approveUnread()
        h.visit = false
        let before = h.selection.calls
        XCTAssertNil(h.session.makeNativeChannelNotificationFlow(scope: nil, sourceCurrent: { h.visit }))
        XCTAssertEqual(h.selection.calls, before)
        XCTAssertTrue(h.wire.notificationRequests.isEmpty)
    }

    func testActualFactoryUnreadOnlyUsesExactGETAndCurrentCredential() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approveUnread()
        let flow = try h.make()
        await flow.activateUnreadRecovery()
        XCTAssertEqual(flow.state, .ready)
        XCTAssertEqual(flow.unread?.total, 3)
        XCTAssertFalse(flow.canRead); XCTAssertFalse(flow.canSave); XCTAssertFalse(flow.canMute)
        XCTAssertFalse(flow.canAck); XCTAssertFalse(flow.canCheckReceipt)
        XCTAssertNil(flow.directory); XCTAssertNil(flow.pendingRequestID)
        let request = try XCTUnwrap(h.wire.notificationRequests.first)
        XCTAssertEqual(h.wire.notificationRequests.count, 1)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/native/api/im/unread-summary")
        XCTAssertNil(request.httpBody); XCTAssertNil(request.url?.query)
        XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), h.wire.token)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Content-Type"))
    }

    func testActualAncestorExitAndReopenCannotReviveCapturedFlow() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approveUnread()
        let old = try h.make(); await old.activateUnreadRecovery()
        XCTAssertNotNil(old.unread)
        let before = h.wire.notificationRequests.count
        h.visit = false
        XCTAssertFalse(old.isCurrent); XCTAssertNil(old.unread)
        await old.refreshUnreadRecovery()
        XCTAssertEqual(h.wire.notificationRequests.count, before)
        h.visit = true
        XCTAssertFalse(old.isCurrent)
        await old.refreshUnreadRecovery()
        XCTAssertEqual(h.wire.notificationRequests.count, before)
        let fresh = try h.make(); XCTAssertFalse(fresh === old)
        await fresh.activateUnreadRecovery()
        XCTAssertEqual(fresh.unread?.total, 3)
        XCTAssertEqual(h.wire.notificationRequests.count, before + 1)
    }

    func testReadRevocationAndSameVersionReissueDoNotReviveCapturedFlow() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login()
        let source = try h.approveUnread()
        let old = try h.make(); await old.activateUnreadRecovery()
        let before = h.wire.notificationRequests.count
        source.unreadAllowed = false
        XCTAssertFalse(old.isCurrent); XCTAssertNil(old.unread)
        await old.refreshUnreadRecovery()
        XCTAssertEqual(h.wire.notificationRequests.count, before)
        source.unreadAllowed = true // Same object/version/revision, not a new grant.
        XCTAssertFalse(old.isCurrent)
        await old.refreshUnreadRecovery()
        XCTAssertEqual(h.wire.notificationRequests.count, before)
        let fresh = try h.make(); await fresh.activateUnreadRecovery()
        XCTAssertEqual(fresh.unread?.total, 3)
        XCTAssertEqual(h.wire.notificationRequests.count, before + 1)
    }

    func testReplacementDuringSuccessfulResponseCannotPublishOldPayload() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approveUnread()
        let old = try h.make()
        let replacement = Source(context: try XCTUnwrap(h.session.currentRuntimeDependencyContext))
        h.wire.beforeUnreadReply = { h.selection.value = replacement }
        await old.activateUnreadRecovery()
        XCTAssertFalse(old.isCurrent); XCTAssertNil(old.unread)
        XCTAssertTrue(h.session.isSignedIn); XCTAssertNotNil(replacement.authorizationVersion)
        let fresh = try h.make(); await fresh.activateUnreadRecovery()
        XCTAssertEqual(fresh.unread?.total, 3)
        XCTAssertEqual(h.wire.notificationRequests.count, 2)
    }

    func testLate401RetiresOnlyOriginalSourceNotReplacementOrRealSession() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login()
        let original = try h.approveUnread()
        let old = try h.make()
        let replacement = Source(context: try XCTUnwrap(h.session.currentRuntimeDependencyContext))
        let replacementVersion = replacement.authorizationVersion
        h.wire.unreadStatus = 401
        h.wire.beforeUnreadReply = { h.selection.value = replacement }
        await old.activateUnreadRecovery()
        XCTAssertNil(original.authorizationVersion); XCTAssertEqual(original.retirements, 1)
        XCTAssertEqual(replacement.authorizationVersion, replacementVersion)
        XCTAssertEqual(replacement.retirements, 0)
        XCTAssertTrue(h.session.isSignedIn); XCTAssertEqual(h.vault.token, h.wire.token)
        XCTAssertFalse(old.isCurrent); XCTAssertNil(old.unread)
        h.wire.unreadStatus = 200
        let fresh = try h.make(); await fresh.activateUnreadRecovery()
        XCTAssertEqual(fresh.unread?.total, 3)
        XCTAssertEqual(h.wire.notificationRequests.count, 2)
    }

    func testRealLogoutAndReauthenticationKeepOldFactoryFlowRetired() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approveUnread()
        let old = try h.make(); await old.activateUnreadRecovery()
        await h.session.logout()
        XCTAssertFalse(h.session.isSignedIn); XCTAssertNil(h.vault.token)
        XCTAssertFalse(old.isCurrent); XCTAssertNil(old.unread)
        XCTAssertNil(h.session.makeNativeChannelNotificationFlow(scope: nil))
        let before = h.wire.notificationRequests.count
        await old.refreshUnreadRecovery()
        XCTAssertEqual(h.wire.notificationRequests.count, before)
        h.wire.token = "synthetic-notification-reauth"
        await h.login(); try h.approveUnread()
        XCTAssertFalse(old.isCurrent)
        let fresh = try h.make(); await fresh.activateUnreadRecovery()
        XCTAssertEqual(fresh.unread?.total, 3)
        XCTAssertEqual(h.wire.notificationRequests.last?.value(forHTTPHeaderField: "Authorization"), h.wire.token)
    }

    func testActualRoleABAInvalidatesOldFactoryAndUsesFreshContext() async throws {
        let h = try Harness(); defer { h.clean() }; await h.login(); try h.approveUnread()
        let old = try h.make(); await old.activateUnreadRecovery()
        let before = h.wire.notificationRequests.count
        h.wire.role = "merchant"; await h.session.refreshOwnAccount()
        XCTAssertEqual(h.session.account?.effectiveRole, "merchant")
        XCTAssertFalse(old.isCurrent); XCTAssertNil(old.unread)
        await old.refreshUnreadRecovery()
        XCTAssertEqual(h.wire.notificationRequests.count, before)
        h.wire.role = "player"; await h.session.refreshOwnAccount()
        XCTAssertEqual(h.session.account?.effectiveRole, "player")
        XCTAssertFalse(old.isCurrent)
        try h.approveUnread()
        let fresh = try h.make(); await fresh.activateUnreadRecovery()
        XCTAssertEqual(fresh.unread?.total, 3)
        XCTAssertEqual(h.wire.notificationRequests.count, before + 1)
    }

    @MainActor private final class Source: NativeChannelNotificationAuthorizing {
        var currentContext: RuntimeDependencyContext?
        var authorizationVersion: UUID? = UUID()
        private let revision = UUID()
        var unreadAllowed = true
        private(set) var retirements = 0
        init(context: RuntimeDependencyContext) { currentContext = context }
        func authorizationRevision(for operation: NativeChannelNotificationOperation,
                                   scope: NativeChannelNotificationScope?) -> UUID? {
            authorizationVersion != nil && unreadAllowed && operation == .unread && scope == nil ? revision : nil
        }
        func retireAuthorization(context: RuntimeDependencyContext, authorizationVersion: UUID) {
            guard ContentDraftContextFence.matches(currentContext, context),
                  self.authorizationVersion == authorizationVersion else { return }
            self.authorizationVersion = nil; retirements += 1
        }
    }
    @MainActor private final class Selection {
        var value: Source?
        var calls = 0
    }
    @MainActor private final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ value: String) throws { token = value }
        func clear() throws { token = nil }
    }
    @MainActor private final class Harness {
        let suite: String
        let wire: Wire
        let vault: Vault
        let selection: Selection
        let session: AppSession
        var visit = true
        init(injectSelector: Bool = true) throws {
            let suite = "notification-real-factory-" + UUID().uuidString
            let wire = Wire(), vault = Vault(), selection = Selection()
            self.suite = suite; self.wire = wire; self.vault = vault; self.selection = selection
            let base = "https://example.test/native"
            let deployment = try ReviewedAppDeployment(market: .china, baseURL: base,
                approvedBaseURLs: [.china: [base]], verifiedCapabilities: [.domesticChinaPhone],
                bundleIdentifier: "test.notification-real-factory", realm: "synthetic")
            let storage = AppScopedStorageFactory(defaults: try XCTUnwrap(UserDefaults(suiteName: suite)),
                                                 tokenStore: { _ in vault })
            var root = AppCompositionRoot(deployment: .reviewed(deployment), storage: storage, makeTransport: { wire })
            if injectSelector {
                root.nativeChannelNotificationAuthorization = { _, _ in
                    selection.calls += 1
                    return selection.value
                }
            }
            session = root.makeSession()
        }
        func login() async {
            session.authChannels.cancel()
            await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
            XCTAssertEqual(session.account?.id, 7)
        }
        @discardableResult func approveUnread() throws -> Source {
            let source = Source(context: try XCTUnwrap(session.currentRuntimeDependencyContext))
            selection.value = source
            return source
        }
        func make() throws -> NativeChannelNotificationCoordinator {
            try XCTUnwrap(session.makeNativeChannelNotificationFlow(scope: nil, sourceCurrent: { [weak self] in self?.visit == true }))
        }
        func clean() { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    }
    @MainActor private final class Wire: HTTPTransport {
        var token = "synthetic-notification-owner-7"
        var role = "player"
        var unreadStatus = 200
        var beforeUnreadReply: (() -> Void)?
        var requests: [URLRequest] = []
        var notificationRequests: [URLRequest] { requests.filter { $0.url?.path.contains("/api/im/") == true } }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let path = request.url?.path ?? ""
            let body: [String: Any]
            switch path {
            case "/native/api/im/unread-summary":
                let callback = beforeUnreadReply; beforeUnreadReply = nil; callback?()
                if unreadStatus == 401 { return (Data(), 401) }
                body = ["code": 200, "data": ["total": 3, "mention_count": 0, "has_mention": 0,
                                             "by_tab": ["dm": 0, "sys": 0, "channel": 3]]]
            default:
                if path.hasSuffix("/phone") { body = ["code": 200, "token": token, "data": ["id": 7, "role": role]] }
                else if path.hasSuffix("/userInfo") { body = ["code": 200, "appUser": ["userId": 7, "role": role]] }
                else if path.hasSuffix("/logout") { body = ["code": 200] }
                else { XCTFail("Unexpected synthetic route: \(path)"); throw APIError.notConfigured }
            }
            return (try JSONSerialization.data(withJSONObject: body), 200)
        }
    }
}
