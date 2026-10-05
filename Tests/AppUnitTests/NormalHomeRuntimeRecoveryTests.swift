import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// Synthetic requests through the normal composition, never a production approval.
@MainActor final class NormalHomeRuntimeRecoveryTests: XCTestCase {
    private let endpoint = "https://example.com/native"
    private let bundle = "test.questify.normal-home"
    private let realm = "synthetic-home-readiness"
    private var build: RegionalLaunchConfiguration.BuildMetadata {
        .init(market: "CN", baseURL: endpoint, bundleIdentifier: bundle, realm: realm)
    }
    private func deployment(home: Bool = true, details: Bool = true, auth: Bool = true) throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: endpoint, approvedBaseURLs: [.china: [endpoint]],
            verifiedCapabilities: auth ? [.domesticChinaPhone] : [], bundleIdentifier: bundle, realm: realm,
            reads: home ? [.homeAndSearch] : [], contentDetails: details ? .activityAndTopic : nil)
    }
    private func root(_ wire: Wire, _ vault: Vault, _ deployment: ReviewedAppDeployment?,
                      build: RegionalLaunchConfiguration.BuildMetadata? = nil) -> AppCompositionRoot {
        let suite = "normal-home-recovery-" + UUID().uuidString, defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return RegionalLaunchConfiguration.makeComposition(reviewed: deployment, build: build ?? self.build,
            storage: .init(defaults: defaults, tokenStore: { scope in vault.scope = scope; return vault }), makeTransport: { wire })
    }
    private func signIn(_ session: AppSession, wire: Wire) async {
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, wire.accountID)
        XCTAssertTrue(session.authChannels.state.signedIn)
    }
    func testUnconfiguredLaunchNeverReadsVaultOrDispatches() async throws {
        let wire = Wire(), vault = Vault(); vault.token = "synthetic-7"
        let session = root(wire, vault, nil).makeSession()
        await session.bootstrap()
        XCTAssertEqual(session.homeReadAvailability, .deploymentMissing)
        XCTAssertFalse(session.homeFeedReader.isConfigured)
        XCTAssertEqual(vault.reads, 0); XCTAssertNil(vault.scope); XCTAssertTrue(wire.requests.isEmpty)
        XCTAssertNil(RegionalLaunchConfiguration.composition.reviewed)
    }
    func testReviewedBuildRejectsWrongMarketEndpointBundleAndRealmBeforeVaultUse() async throws {
        let cases: [(RegionalLaunchConfiguration.BuildMetadata, RegionalLaunchConfiguration.ValidationIssue)] = [
            (.init(market: nil, baseURL: endpoint, bundleIdentifier: bundle, realm: realm), .marketMissingOrUnsupported),
            (.init(market: "XX", baseURL: endpoint, bundleIdentifier: bundle, realm: realm), .marketMissingOrUnsupported),
            (.init(market: "US", baseURL: endpoint, bundleIdentifier: bundle, realm: realm), .marketMismatch),
            (.init(market: "CN", baseURL: nil, bundleIdentifier: bundle, realm: realm), .endpointMismatch),
            (.init(market: "CN", baseURL: endpoint + "/other", bundleIdentifier: bundle, realm: realm), .endpointMismatch),
            (.init(market: "CN", baseURL: endpoint, bundleIdentifier: nil, realm: realm), .storageScopeMismatch),
            (.init(market: "CN", baseURL: endpoint, bundleIdentifier: bundle + ".other", realm: realm), .storageScopeMismatch),
            (.init(market: "CN", baseURL: endpoint, bundleIdentifier: bundle, realm: nil), .storageScopeMismatch),
            (.init(market: "CN", baseURL: endpoint, bundleIdentifier: bundle, realm: "other"), .storageScopeMismatch)
        ]
        for (metadata, issue) in cases {
            let deployment = try deployment(), wire = Wire(), vault = Vault(); vault.token = "synthetic-7"
            XCTAssertThrowsError(try RegionalLaunchConfiguration.validate(deployment, build: metadata)) {
                XCTAssertEqual($0 as? RegionalLaunchConfiguration.ValidationIssue, issue)
            }
            let session = root(wire, vault, deployment, build: metadata).makeSession()
            await session.bootstrap()
            XCTAssertEqual(session.homeReadAvailability, .buildMismatch)
            XCTAssertFalse(session.isConfigured); XCTAssertNil(session.account)
            XCTAssertEqual(vault.reads, 0); XCTAssertTrue(wire.requests.isEmpty)
        }
    }
    func testNormalRootGuestLoginHomeDetailRoleABAAndLogout() async throws {
        let wire = Wire(), vault = Vault(), deployment = try deployment()
        let container = AppSessionContainer(composition: root(wire, vault, deployment))
        let session = try XCTUnwrap(container.session)
        await session.bootstrap()
        XCTAssertEqual(session.homeReadAvailability, .available)
        XCTAssertEqual(session.contentDetailReadAvailability, .signInRequired)
        _ = try await session.homeFeedReader.categories()
        XCTAssertNil(wire.requests.last?.value(forHTTPHeaderField: "Authorization"))
        await signIn(session, wire: wire)
        XCTAssertEqual(vault.scope, deployment.storageScope); XCTAssertEqual(session.operationalMarket, .china)
        let host = UIHostingController(rootView: SessionRootView(session: session)); host.loadViewIfNeeded()
        let model = HomeFeedModel(); await model.reload(reader: session.homeFeedReader, query: HomeFeedQuery())
        XCTAssertEqual(model.pagination.items.map(\.id), [.topic(31)])
        let detail = try await session.topicReader.topicDetail(id: 31); XCTAssertEqual(detail.id, 31)
        XCTAssertEqual(wire.requests.last?.value(forHTTPHeaderField: "Authorization"), "synthetic-7")
        let old = session.homeFeedReader.scope
        wire.role = "merchant"; await session.refreshOwnAccount()
        wire.role = "player"; await session.refreshOwnAccount()
        XCTAssertNotEqual(session.homeFeedReader.scope, old)
        let signedInScope = session.homeFeedReader.scope
        await session.logout()
        XCTAssertNil(session.account); XCTAssertNil(vault.token)
        XCTAssertNotEqual(session.homeFeedReader.scope, signedInScope)
        XCTAssertEqual(session.contentDetailReadAvailability, .signInRequired)
        let before = wire.requests.filter { $0.url?.path.hasSuffix("/info-to-user") == true }.count
        do { _ = try await session.topicReader.topicDetail(id: 31); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(wire.requests.filter { $0.url?.path.hasSuffix("/info-to-user") == true }.count, before)
        _ = try await session.homeFeedReader.categories()
        XCTAssertNil(wire.requests.last?.value(forHTTPHeaderField: "Authorization"))
    }
    func testHomeAndDetailReadGrantsStayIndependentOfLoginAndMountedService() async throws {
        for home in [false, true] {
            let wire = Wire(), vault = Vault(), session = root(wire, vault, try deployment(home: home, details: !home)).makeSession()
            await signIn(session, wire: wire)
            let before = wire.requests.count
            if home {
                XCTAssertEqual(session.homeReadAvailability, .available)
                XCTAssertTrue(session.topicReader.isConfigured)
                XCTAssertEqual(session.contentDetailReadAvailability, .detailReadNotApproved)
                do { _ = try await session.topicReader.topicDetail(id: 31); XCTFail() }
                catch { XCTAssertEqual(error as? APIError, .notConfigured) }
            } else {
                XCTAssertEqual(session.homeReadAvailability, .homeReadNotApproved)
                XCTAssertEqual(session.contentDetailReadAvailability, .available)
                do { _ = try await session.homeFeedReader.categories(); XCTFail() }
                catch { XCTAssertEqual(error as? APIError, .notConfigured) }
            }
            XCTAssertEqual(wire.requests.count, before)
        }
    }
    func testGuestHomeGrantCannotCreateAuthenticationOrDetailAuthority() async throws {
        let wire = Wire(), vault = Vault(), session = root(wire, vault, try deployment(auth: false)).makeSession()
        _ = try await session.homeFeedReader.categories()
        XCTAssertNil(wire.requests.last?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(session.contentDetailReadAvailability, .signInRequired)
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNil(session.account); XCTAssertNil(vault.token); XCTAssertEqual(wire.requests.count, 1)
    }
    func testOfflineAndValidEmptyHomeRemainDifferentStates() async throws {
        let wire = Wire(), vault = Vault(), session = root(wire, vault, try deployment()).makeSession(), model = HomeFeedModel()
        wire.offline = true; await model.reload(reader: session.homeFeedReader, query: HomeFeedQuery())
        XCTAssertTrue(model.pageFailed); XCTAssertTrue(model.categoryFailed); XCTAssertTrue(model.bannerFailed)
        XCTAssertTrue(model.pagination.items.isEmpty); XCTAssertFalse(model.loading)
        wire.offline = false; wire.empty = true
        await model.reload(reader: session.homeFeedReader, query: HomeFeedQuery())
        XCTAssertFalse(model.pageFailed); XCTAssertFalse(model.categoryFailed); XCTAssertFalse(model.bannerFailed)
        XCTAssertTrue(model.pagination.items.isEmpty); XCTAssertFalse(model.pagination.hasMore)
    }
    func testCurrentHome401ExpiresCurrentOwner() async throws {
        let wire = Wire(), vault = Vault(), session = root(wire, vault, try deployment()).makeSession()
        await signIn(session, wire: wire); wire.categoryStatus = 401
        do { _ = try await session.homeFeedReader.categories(); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertNil(session.account); XCTAssertNil(vault.token)
    }
    func testRetiredDetailSuccessAnd401CannotCrossLogoutAndNextOwner() async throws {
        for unauthorized in [false, true] {
            let wire = Wire(), vault = Vault(), session = root(wire, vault, try deployment()).makeSession()
            await signIn(session, wire: wire); wire.pausePath = "/api/topic/info-to-user"
            let started = expectation(description: "Old detail"); wire.onPaused = { started.fulfill() }
            let task = Task { try await session.topicReader.topicDetail(id: 31) }
            await fulfillment(of: [started], timeout: 2)
            guard wire.hasPending else { task.cancel(); return XCTFail("No pending detail") }
            await session.logout(); wire.accountID = 8; await signIn(session, wire: wire)
            wire.finish(status: unauthorized ? 401 : 200)
            do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(session.account?.id, 8); XCTAssertEqual(vault.token, "synthetic-8")
        }
    }
    func testCompleteGuestAndSignedInAllowedButPartialHomeViewerNeverDispatches() async throws {
        let wire = Wire(), vault = Vault(), composition = root(wire, vault, try deployment())
        let transport = composition.transport()
        typealias Identity = CompositionHTTPTransport.SessionIdentity
        for identity in [Identity(epoch: 1, accountID: nil, role: nil, token: nil),
                         .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7")] {
            transport.current = { identity }; _ = try await transport.send(request(token: identity.token))
            XCTAssertEqual(composition.readAvailability(.home, identity: identity), .available)
        }
        XCTAssertEqual(wire.requests.count, 2)
        for identity in [Identity(epoch: 1, accountID: nil, role: "player", token: nil),
                         .init(epoch: 1, accountID: nil, role: nil, token: "synthetic-7"),
                         .init(epoch: 1, accountID: 7, role: nil, token: "synthetic-7"),
                         .init(epoch: 1, accountID: 7, role: "player", token: nil),
                         .init(epoch: 1, accountID: 0, role: "player", token: "synthetic-7")] {
            transport.current = { identity }
            XCTAssertEqual(composition.readAvailability(.home, identity: identity), .sessionUnavailable)
            do { _ = try await transport.send(request(token: identity.token)); XCTFail() } catch {}
        }
        transport.current = { nil }
        do { _ = try await transport.send(request(token: nil)); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 2)
        transport.current = { .init(epoch: 2, accountID: nil, role: nil, token: nil) }
        do { _ = try await transport.send(request(token: "synthetic-7")); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 2)
        _ = try await transport.send(request(token: nil)); XCTAssertEqual(wire.requests.count, 3)
    }
    func testRoleABACancelsLateHomeSuccessAnd401WithoutExpiringOwner() async throws {
        for unauthorized in [false, true] {
            let wire = Wire(), vault = Vault(), session = root(wire, vault, try deployment()).makeSession()
            await signIn(session, wire: wire); let old = session.homeFeedReader.scope
            wire.pausePath = "/api/category/list"
            let started = expectation(description: "Old Home"); wire.onPaused = { started.fulfill() }
            let task = Task { try await session.homeFeedReader.categories() }
            await fulfillment(of: [started], timeout: 2)
            guard wire.hasPending else { task.cancel(); return XCTFail("No pending Home") }
            wire.role = "merchant"; await session.refreshOwnAccount()
            wire.role = "player"; await session.refreshOwnAccount()
            XCTAssertNotEqual(session.homeFeedReader.scope, old)
            wire.finish(status: unauthorized ? 401 : 200)
            do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.token, "synthetic-7")
            XCTAssertNotEqual(session.errorKey, "auth.expired")
        }
    }
    func testNewViewerReloadClearsLoadedRowsBeforeNewResponse() async throws {
        let wire = Wire(), vault = Vault(), session = root(wire, vault, try deployment()).makeSession(), model = HomeFeedModel()
        await signIn(session, wire: wire)
        await model.reload(reader: session.homeFeedReader, query: HomeFeedQuery())
        XCTAssertEqual(model.pagination.items.map(\.id), [.topic(31)])
        wire.role = "merchant"; await session.refreshOwnAccount(); wire.pausePath = "/api/topic/list"; wire.plainTopicOnly = true
        let started = expectation(description: "New viewer page"); wire.onPaused = { started.fulfill() }
        let task = Task { await model.reload(reader: session.homeFeedReader, query: HomeFeedQuery()) }
        await fulfillment(of: [started], timeout: 2)
        guard wire.hasPending else { task.cancel(); return XCTFail("No pending page") }
        XCTAssertTrue(model.pagination.items.isEmpty); XCTAssertTrue(model.loading)
        wire.finish(); await task.value
        XCTAssertEqual(model.pagination.items.map(\.id), [.topic(41)]); XCTAssertFalse(model.loading)
    }
    private func request(token: String?) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: URL(string: endpoint + "/api/category/list")!, fields: ["parentid": "0"], token: token)
    }
    @MainActor private final class Vault: AppTokenStorage {
        var scope: RegionalSessionStorageScope?, token: String?
        var reads = 0
        func read() throws -> String? { reads += 1; return token }
        func write(_ value: String) throws { token = value }
        func clear() throws { token = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var accountID = 7, role = "player", categoryStatus = 200
        var requests: [URLRequest] = []
        var offline = false, empty = false, plainTopicOnly = false
        var pausePath: String?, onPaused: (() -> Void)?
        private var pending: CheckedContinuation<(Data, Int), Error>?
        private var pendingJSON = "{}"
        var hasPending: Bool { pending != nil }
        func finish(status: Int = 200) { let completion = pending; pending = nil; completion?.resume(returning: (Data(pendingJSON.utf8), status)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); if offline { throw URLError(.notConnectedToInternet) }
            let path = request.url?.path ?? "", json: String
            if path.hasSuffix("/phone") { json = "{\"code\":200,\"token\":\"synthetic-\(accountID)\",\"data\":{\"id\":\(accountID),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/userInfo") { json = "{\"code\":200,\"appUser\":{\"userId\":\(accountID),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/topic/info-to-user") { json = #"{"code":200,"data":{"id":31,"name":"Synthetic detail"}}"# }
            else if path.hasSuffix("/topic/list") { json = empty ? #"{"code":200,"data":{"rows":[]}}"# : "{\"code\":200,\"data\":{\"rows\":[{\"id\":\(role == "merchant" ? 41 : 31),\"name\":\"Synthetic topic\"}]}}" }
            else if path.hasSuffix("/activity/list") { json = #"{"code":200,"data":{"rows":[]}}"# }
            else { json = #"{"code":200,"data":[]}"# }
            if let pausePath, path.hasSuffix(pausePath), !plainTopicOnly || !String(decoding: request.httpBody ?? Data(), as: UTF8.self).contains("is_recommend") {
                pendingJSON = json; return try await withCheckedThrowingContinuation { pending = $0; onPaused?() }
            }
            return (Data(json.utf8), path.hasSuffix("/category/list") ? categoryStatus : 200)
        }
    }
}
