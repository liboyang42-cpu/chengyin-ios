import XCTest
import Foundation
@testable import Questify

/// Authored offline integration coverage for the composition proposal.
/// Memory transport/journal only; no live endpoint, secure draft write, or grant installation.
@MainActor final class TemplateOriginalRequestCompositionTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var beforeReply: (() -> Void)?
        var account = 7, role = "player"
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let path = request.url!.path
            if path.hasSuffix("/phone") { return (Data("{\"code\":200,\"token\":\"synthetic-\(account)\",\"data\":{\"id\":\(account),\"role\":\"\(role)\"}}".utf8), 200) }
            if path.hasSuffix("/userInfo") { return (Data("{\"code\":200,\"appUser\":{\"userId\":\(account),\"role\":\"\(role)\"}}".utf8), 200) }
            beforeReply?()
            let body = try XCTUnwrap(request.httpBody)
            let query = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let receipt: [String: Any] = ["protocolVersion": try XCTUnwrap(query["protocolVersion"]),
                "requestId": try XCTUnwrap(query["requestId"]), "payloadSHA256": try XCTUnwrap(query["payloadSHA256"]),
                "state": "COMMITTED", "originalResult": ["memberTemplateId": 42]]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": receipt]), 200)
        }
    }
    private final class Storage: TemplateAuthoringStorage {
        var values: [String: Data] = [:]
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws { values[key] = data }
        func remove(_ key: String) throws { values.removeValue(forKey: key) }
    }
    private final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ token: String) throws { self.token = token }
        func clear() throws { token = nil }
    }
    private final class Scope {
        var runtime: RuntimeDependencyContext?
        var viewer: CompositionHTTPTransport.SessionIdentity?
        var read: OperationEndpointApproval?
        var write: OperationEndpointApproval?
    }
    private struct Fixture {
        let outer: CompositionHTTPTransport
        let wire: Wire
        let scope: Scope
        let context: RuntimeDependencyContext
        let author: TemplateAuthoringSession
    }
    private func deployment() throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.original-template", realm: "synthetic")
    }
    private func fixture(read: Bool = true, write: Bool = false) throws -> Fixture {
        let d = try deployment(), wire = Wire(), scope = Scope()
        let player = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: d.storageScope.service, token: "synthetic-7", role: "player")
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player", session: player)
        let author = try TemplateAuthoringSession(accountID: 7, namespace: player.namespace, epoch: 1, authorizationRevision: "player")
        scope.runtime = context; scope.viewer = .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1)
        if read { scope.read = try .init(baseURL: base, namespace: player.namespace, accountID: 7, paths: [TemplateAuthoringRequestReceipt.readPath]) }
        if write { scope.write = try .init(baseURL: base, namespace: player.namespace, accountID: 7, paths: [TemplateAuthoringRequestReceipt.submitPath, "api/template/draft"]) }
        let outer = CompositionHTTPTransport(deployment: d, underlying: wire); outer.current = { scope.viewer }
        return .init(outer: outer, wire: wire, scope: scope, context: context, author: author)
    }
    private func service(_ f: Fixture, outer: CompositionHTTPTransport? = nil, context: RuntimeDependencyContext? = nil,
                         author: TemplateAuthoringSession? = nil) -> TemplateAuthoringRequestHTTPService? {
        (outer ?? f.outer).makeTemplateAuthoringRequestService(context: context ?? f.context, session: author ?? f.author,
            readApproval: f.scope.read, submitApproval: f.scope.write, currentRuntime: { f.scope.runtime },
            currentReadApproval: { f.scope.read }, currentSubmitApproval: { f.scope.write })
    }
    private func original() throws -> TemplateAuthoringRequestReceipt.Submit {
        try .init(id: UUID(), command: .init(request: TemplateAuthoringContract.request(.init(title: "Original draft"), intent: .saveDraft)))
    }
    func testCompositionSelectorsAndDedicatedFactoryDefaultToNil() throws {
        let f = try fixture(read: false), root = AppCompositionRoot()
        XCTAssertNil(root.templateAuthoringOriginalReadApproval(f.context)); XCTAssertNil(root.templateAuthoringOriginalSubmitApproval(f.context))
        XCTAssertNil(service(f)); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testWrongContextAndWrongAuthorAreRejectedBeforeTransport() throws {
        let f = try fixture()
        let foreign = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://other.test/native")!, role: "player", session: f.context.session)
        XCTAssertNil(service(f, context: foreign))
        let changed = try TemplateAuthoringSession(accountID: 8, namespace: f.author.namespace, epoch: 1, authorizationRevision: "player")
        XCTAssertNil(service(f, author: changed))
        f.scope.viewer = .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7")
        XCTAssertNil(service(f)); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testWrongReadGrantNeverDispatches() async throws {
        let f = try fixture()
        f.scope.read = try .init(baseURL: base, namespace: f.author.namespace, accountID: 8, paths: [TemplateAuthoringRequestReceipt.readPath])
        let reader = try XCTUnwrap(service(f)); XCTAssertFalse(reader.canRead)
        do { _ = try await reader.read(original(), session: f.author); XCTFail("Wrong owner grant") } catch {}
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testReadOnlyFactoryRecoversDurableOriginalWithoutAuthorizingAnyWriter() async throws {
        let f = try fixture(), reader = try XCTUnwrap(service(f)), storage = Storage(), store = TemplateAuthoringLocalStore(storage: storage)
        let envelope = try original(), request = try XCTUnwrap(envelope.command?.descriptor), identity = TemplateAuthoringIdentity()
        var pending = TemplateAuthoringPending(operationID: try XCTUnwrap(UUID(uuidString: envelope.requestId)), ownerKey: f.author.ownerKey,
            identity: identity, request: request, createdAt: Date())
        pending.serverRequest = envelope
        try store.save(.init(title: "Original draft"), session: f.author, identity: identity); try store.savePending(pending, session: f.author)
        let coordinator = TemplateAuthoringCoordinator(store: store, requestService: reader, currentSession: { f.author })
        coordinator.open(); XCTAssertFalse(coordinator.canSubmit); XCTAssertTrue(coordinator.canReadOriginalRequest)
        await coordinator.readOriginalRequest()
        XCTAssertEqual(coordinator.savedDraft?.memberTemplateID.rawValue, 42); XCTAssertEqual(coordinator.pending?.serverRequest, envelope)
        XCTAssertEqual(f.wire.requests.map { $0.url!.path }, ["/native/api/template/author-requests/read"])
        XCTAssertFalse(reader.canSubmit(path: "/api/template/draft")); XCTAssertFalse(reader.canSubmit(path: "/api/template/publish"))
    }
    func testDedicatedFactoryDoesNotWidenGenericTransport() async throws {
        let f = try fixture(), value = try original()
        let request = try OperationAdapterHTTP.json(configuration: .init(baseURL: base), path: TemplateAuthoringRequestReceipt.readPath,
            body: JSONEncoder().encode(TemplateAuthoringRequestReceipt.Read(value)), token: "synthetic-7")
        do { _ = try await f.outer.send(request); XCTFail("Generic route should remain denied") } catch {}
        XCTAssertTrue(f.wire.requests.isEmpty)
        _ = try await XCTUnwrap(service(f)).read(value, session: f.author)
        XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testAccountTokenRoleAndViewerChangesRejectLateResult() async throws {
        for transition in ["account", "token", "role", "viewer"] {
            let f = try fixture(), reader = try XCTUnwrap(service(f))
            f.wire.beforeReply = {
                switch transition {
                case "account": f.scope.viewer = .init(epoch: 1, accountID: 8, role: "player", token: "synthetic-7", viewerRevision: 1)
                case "token": f.scope.viewer = .init(epoch: 1, accountID: 7, role: "player", token: "rotated-token", viewerRevision: 1)
                case "role": f.scope.viewer = .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7", viewerRevision: 1)
                default: f.scope.viewer = .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 3)
                }
            }
            do { _ = try await reader.read(original(), session: f.author); XCTFail(transition) } catch {}
            XCTAssertEqual(f.wire.requests.count, 1)
        }
    }
    func testRuntimeRevocationAndGrantRevocationRejectLateResult() async throws {
        for runtime in [true, false] {
            let f = try fixture(), reader = try XCTUnwrap(service(f))
            f.wire.beforeReply = { if runtime { f.scope.runtime = nil } else { f.scope.read = nil } }
            do { _ = try await reader.read(original(), session: f.author); XCTFail("Revoked result") } catch {}
            XCTAssertEqual(f.wire.requests.count, 1); XCTAssertFalse(reader.canRead)
        }
    }
    func testReplacingUnderlyingPreservesContextFenceAndUsesOnlyReplacement() async throws {
        let f = try fixture(), replacement = Wire(), clone = f.outer.replacingUnderlying(replacement)
        let reader = try XCTUnwrap(service(f, outer: clone))
        _ = try await reader.read(original(), session: f.author)
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertEqual(replacement.requests.count, 1)
        f.scope.viewer = nil
        do { _ = try await reader.read(original(), session: f.author); XCTFail("Retired viewer") } catch {}
        XCTAssertEqual(replacement.requests.count, 1)
    }
    private func appSession(_ wire: Wire, read: Bool) throws -> AppSession {
        let suite = "template-original-app-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)), vault = Vault()
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        var root = AppCompositionRoot(deployment: .reviewed(try deployment()), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
        if read {
            root.templateAuthoringOriginalReadApproval = { context in
                try? .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID,
                    paths: [TemplateAuthoringRequestReceipt.readPath])
            }
        }
        return root.makeSession()
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    func testNormalSessionKeepsEditorAndShelfWritersDisabledForNilAndReadOnlyGrants() async throws {
        for read in [false, true] {
            let wire = Wire(), session = try appSession(wire, read: read); await login(session); wire.requests = []
            let editor = session.templateAuthoringEditor()
            XCTAssertFalse(editor.canSubmit); XCTAssertFalse(session.templateShelfCoordinator().canSubmit)
            XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testRetainedEditorReusesSameScopeAndIsReplacedAfterRoleABA() async throws {
        let wire = Wire(), session = try appSession(wire, read: true); await login(session)
        let editor = session.templateAuthoringEditor(); editor.change(.init(title: "Retained local draft"))
        XCTAssertTrue(editor === session.templateAuthoringEditor())
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
        let returned = session.templateAuthoringEditor()
        XCTAssertFalse(editor === returned); XCTAssertFalse(returned.canSubmit)
        XCTAssertNil(editor.session)
    }
}
