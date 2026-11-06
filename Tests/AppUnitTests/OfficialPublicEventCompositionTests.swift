import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor private final class OfficialPublicHostVault: AppTokenStorage {
    var value: String?
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token }
    func clear() throws { value = nil }
}
@MainActor private final class OfficialPublicHostWire: HTTPTransport {
    var requests: [URLRequest] = []
    var role = "player"
    var code = 200
    var empty = false
    var failNext = false
    var pause = false
    var onPause: (() -> Void)?
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    private var pendingReply: (Data, Int)?
    var isPaused: Bool { continuation != nil }
    func finish() {
        guard let continuation, let pendingReply else { return }
        self.continuation = nil; self.pendingReply = nil; pause = false
        continuation.resume(returning: pendingReply)
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.lastPathComponent == "userInfo" {
            return (Data("{\"code\":200,\"appUser\":{\"id\":7,\"role\":\"\(role)\"}}".utf8), 200)
        }
        if failNext { failNext = false; throw URLError(.notConnectedToInternet) }
        let event = #"{"id":71,"title":"Synthetic public event","status":3,"activityEnd":1783297800000}"#
        let value = request.url?.lastPathComponent == "71" ? event : (empty ? "[]" : "[\(event)]")
        let reply = (Data("{\"code\":\(code),\"data\":\(value)}".utf8), 200)
        if pause {
            pendingReply = reply
            return try await withCheckedThrowingContinuation { continuation = $0; onPause?() }
        }
        return reply
    }
}

@MainActor final class OfficialPublicEventCompositionTests: XCTestCase {
    private func root(_ wire: OfficialPublicHostWire, vault: OfficialPublicHostVault? = nil,
                      reads: Set<ReviewedAppDeployment.ReadGrant> = [.officialPublicEventCatalogAndDetail],
                      market: RegionalMarket = .china) throws -> AppCompositionRoot {
        let vault = vault ?? OfficialPublicHostVault()
        let suite = "official-public-host-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: market, baseURL: "https://example.test/native",
            approvedBaseURLs: [market: ["https://example.test/native"]], verifiedCapabilities: [],
            bundleIdentifier: "test.questify.official-public", realm: "synthetic", reads: reads)
        return AppCompositionRoot(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
    }
    private func selectSyntheticSource(_ root: AppCompositionRoot) throws -> OfficialPublicEventReadSource {
        let reviewed = try XCTUnwrap(root.reviewed), api = try XCTUnwrap(reviewed.regional.apiConfiguration)
        let source = try OfficialPublicEventReadSource(baseURL: api.baseURL, namespace: reviewed.storageScope.service)
        root.officialPublicEventReadSelection.select(source)
        return source
    }
    private func service(_ root: AppCompositionRoot, transport: CompositionHTTPTransport) throws -> OfficialEventService {
        OfficialEventService(configuration: try XCTUnwrap(root.reviewed?.regional.apiConfiguration), transport: transport)
    }
    private func guest(_ root: AppCompositionRoot) -> CompositionHTTPTransport {
        let transport = root.transport()
        transport.current = { .init(epoch: 1, accountID: nil, role: nil, token: nil) }
        return transport
    }

    func testIndependentGrantAndSourceRemainSeparatelyDefaultClosed() async throws {
        let grantSets: [Set<ReviewedAppDeployment.ReadGrant>] = [[], [.homeAndSearch], [.officialPublicEventCatalogAndDetail]]
        for grants in grantSets {
            let wire = OfficialPublicHostWire(), root = try self.root(wire, reads: grants)
            XCTAssertNil(root.officialPublicEventReadSelection.source)
            let session = root.makeSession()
            do { _ = try await session.officialEventReader.events(city: nil); XCTFail("No source was selected") }
            catch { XCTAssertEqual(error as? APIError, .notConfigured) }
            XCTAssertTrue(wire.requests.isEmpty)
        }
        let wire = OfficialPublicHostWire(), root = try self.root(wire, reads: [.homeAndSearch])
        _ = try selectSyntheticSource(root)
        do { _ = try await root.makeSession().officialEventReader.events(city: nil); XCTFail("homeAndSearch was expanded") }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty)
    }

    func testNormalGuestReaderListCardDetailEmptyFailureAndExplicitRetryUseOriginalGETs() async throws {
        let wire = OfficialPublicHostWire(), root = try self.root(wire)
        _ = try selectSyntheticSource(root)
        let session = root.makeSession()
        let rows = try await session.officialEventReader.events(city: nil)
        let event = try XCTUnwrap(rows.first)
        let host = UIHostingController(rootView: OfficialEventCard(event: event))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        let detail = try await session.officialEventReader.detail(id: event.id)
        XCTAssertEqual(detail.id, 71)
        wire.empty = true
        let empty = try await session.officialEventReader.events(city: nil)
        XCTAssertTrue(empty.isEmpty)
        wire.failNext = true
        do { _ = try await session.officialEventReader.detail(id: 71); XCTFail() }
        catch { XCTAssertEqual(OfficialDetailLoadFailure(error), .network) }
        let recovered = try await session.officialEventReader.detail(id: 71)
        XCTAssertEqual(recovered.id, 71)
        wire.code = 404
        do { _ = try await session.officialEventReader.detail(id: 71); XCTFail() }
        catch { XCTAssertEqual(error as? OfficialReadFailure, .unavailable) }
        XCTAssertEqual(wire.requests.count, 6)
        XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && $0.value(forHTTPHeaderField: "Authorization") == nil })
        XCTAssertNil(session.account)
    }

    func testCanonicalCityIsPassedVerbatimWithoutGrantingPrivateRoutes() async throws {
        let wire = OfficialPublicHostWire(), root = try self.root(wire)
        _ = try selectSyntheticSource(root)
        let transport = guest(root), service = try self.service(root, transport: transport)
        _ = try await service.events(city: "Example & town/城")
        let url = try XCTUnwrap(wire.requests.first?.url)
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems, [.init(name: "city", value: "Example & town/城")])
        transport.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7") }
        let paths = ["api/official/my-events", "api/official/v2/party-inbox", "api/official/can-publish",
                     "api/official/my-published", "api/official/broadcast/71/stats", "api/official/active-for-roam",
                     "api/official/events/71/signup", "api/official/events/071", "api/official/events/71/"]
        for path in paths {
            var request = URLRequest(url: URL(string: "https://example.test/native")!.appendingPathComponent(path))
            request.httpMethod = "GET"; request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("synthetic-7", forHTTPHeaderField: "Authorization")
            do { _ = try await transport.send(request); XCTFail(path) }
            catch { XCTAssertEqual(error as? APIError, .notConfigured, path) }
        }
        XCTAssertEqual(wire.requests.count, 1)
    }

    func testUSRevokedRemovedAndForeignSourceNeverReachWire() async throws {
        for state in ["US", "revoked", "removed", "origin", "namespace"] {
            let wire = OfficialPublicHostWire(), root = try self.root(wire, market: state == "US" ? .unitedStates : .china)
            let source = try selectSyntheticSource(root)
            switch state {
            case "revoked": source.revoke()
            case "removed": root.officialPublicEventReadSelection.select(nil)
            case "origin": root.officialPublicEventReadSelection.select(try .init(baseURL: URL(string: "https://foreign.test/native")!, namespace: source.namespace))
            case "namespace": root.officialPublicEventReadSelection.select(try .init(baseURL: source.baseURL, namespace: "foreign"))
            default: break
            }
            do { _ = try await root.makeSession().officialEventReader.events(city: nil); XCTFail(state) }
            catch { XCTAssertEqual(error as? APIError, .notConfigured, state) }
            XCTAssertTrue(wire.requests.isEmpty)
        }
    }

    func testIncompleteViewerOrMismatchedSentTokenCannotBecomeAnonymous() async throws {
        let viewers: [CompositionHTTPTransport.SessionIdentity] = [
            .init(epoch: 1, accountID: nil, role: "player", token: nil),
            .init(epoch: 1, accountID: nil, role: nil, token: "synthetic-7"),
            .init(epoch: 1, accountID: 7, role: nil, token: "synthetic-7"),
            .init(epoch: 1, accountID: 7, role: "player", token: nil),
            .init(epoch: 1, accountID: 7, role: "", token: "synthetic-7")]
        for viewer in viewers {
            let wire = OfficialPublicHostWire(), root = try self.root(wire)
            _ = try selectSyntheticSource(root)
            let transport = root.transport(); transport.current = { viewer }
            do { _ = try await service(root, transport: transport).events(city: nil, token: viewer.token); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .notConfigured) }
            XCTAssertTrue(wire.requests.isEmpty)
        }
        let wire = OfficialPublicHostWire(), root = try self.root(wire)
        _ = try selectSyntheticSource(root)
        let transport = root.transport()
        transport.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7") }
        for token in [nil, "synthetic-other"] as [String?] {
            do { _ = try await service(root, transport: transport).events(city: nil, token: token); XCTFail() }
            catch { XCTAssertTrue(error is CancellationError) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }

    func testLateSuccessAnd401CannotCrossAnyIdentityOrSourceLifetime() async throws {
        for code in [200, 401] {
            for change in ["account", "role", "epoch", "token", "viewerABA", "revoked", "removed", "replaced", "sourceABA", "cancelled"] {
                let wire = OfficialPublicHostWire(), root = try self.root(wire)
                let source = try selectSyntheticSource(root), transport = root.transport()
                var viewer = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1)
                transport.current = { viewer }; wire.pause = true; wire.code = code
                let started = expectation(description: "Original public GET admitted")
                wire.onPause = { started.fulfill() }
                let service = try self.service(root, transport: transport)
                let pending = Task { try await service.events(city: nil, token: "synthetic-7") }
                await fulfillment(of: [started], timeout: 2)
                guard wire.isPaused else { pending.cancel(); wire.finish(); XCTFail(change); return }
                switch change {
                case "account": viewer = .init(epoch: 1, accountID: 8, role: "player", token: "synthetic-7", viewerRevision: 1)
                case "role": viewer = .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7", viewerRevision: 1)
                case "epoch": viewer = .init(epoch: 2, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1)
                case "token": viewer = .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-8", viewerRevision: 1)
                case "viewerABA": viewer = .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 3)
                case "revoked": source.revoke()
                case "removed": root.officialPublicEventReadSelection.select(nil)
                case "replaced": _ = try selectSyntheticSource(root)
                case "sourceABA": root.officialPublicEventReadSelection.select(nil); root.officialPublicEventReadSelection.select(source)
                default: pending.cancel()
                }
                wire.finish()
                do { _ = try await pending.value; XCTFail(change) }
                catch { XCTAssertTrue(error is CancellationError, "\(code):\(change)") }
                XCTAssertEqual(wire.requests.count, 1)
            }
        }
    }

    func testExistingTransportClonesObserveRemovalReselectionAndRevocation() async throws {
        let wire = OfficialPublicHostWire(), unused = OfficialPublicHostWire(), root = try self.root(unused)
        let source = try selectSyntheticSource(root), original = guest(root)
        let clone = original.replacingUnderlying(wire).replacingUnderlying(wire)
        let service = try self.service(root, transport: clone)
        _ = try await service.events(city: nil)
        root.officialPublicEventReadSelection.select(nil)
        do { _ = try await service.events(city: nil); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        root.officialPublicEventReadSelection.select(source)
        _ = try await service.detail(id: 71)
        source.revoke()
        do { _ = try await service.events(city: nil); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(wire.requests.count, 2); XCTAssertTrue(unused.requests.isEmpty)
    }

    func testNormalSessionRoleRoundTripChangesReaderScopeAndRejectsOld401() async throws {
        let wire = OfficialPublicHostWire(), vault = OfficialPublicHostVault(); vault.value = "synthetic-7"
        let root = try self.root(wire, vault: vault)
        _ = try selectSyntheticSource(root)
        let session = root.makeSession(); await session.bootstrap()
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(session.account?.effectiveRole, "player")
        let originalScope = session.officialEventReader.scope
        wire.pause = true; wire.code = 401
        let started = expectation(description: "Old official read waits through role refresh")
        wire.onPause = { started.fulfill() }
        let pending = Task { try await session.officialEventReader.events(city: nil) }
        await fulfillment(of: [started], timeout: 2)
        guard wire.isPaused else { pending.cancel(); wire.finish(); XCTFail(); return }
        wire.role = "merchant"; await session.refreshOwnAccount()
        wire.role = "player"; await session.refreshOwnAccount()
        XCTAssertNotEqual(session.officialEventReader.scope, originalScope)
        wire.finish()
        do { _ = try await pending.value; XCTFail("Old 401 reached current session") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.value, "synthetic-7")
        wire.code = 200
        _ = try await session.officialEventReader.detail(id: 71)
        XCTAssertEqual(wire.requests.last?.value(forHTTPHeaderField: "Authorization"), "synthetic-7")
    }

    func testNormalGuestReaderRekeysOnSourceRemovalRoundTripAndCanExplicitlyRetry() async throws {
        let wire = OfficialPublicHostWire(), root = try self.root(wire)
        let source = try selectSyntheticSource(root), session = root.makeSession()
        let first = session.officialEventReader.scope
        root.officialPublicEventReadSelection.select(nil)
        root.officialPublicEventReadSelection.select(source)
        XCTAssertNotEqual(session.officialEventReader.scope, first)
        _ = try await session.officialEventReader.events(city: nil)
        source.revoke()
        let revoked = session.officialEventReader.scope
        do { _ = try await session.officialEventReader.detail(id: 71); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        _ = try selectSyntheticSource(root)
        XCTAssertNotEqual(session.officialEventReader.scope, revoked)
        let restored = try await session.officialEventReader.detail(id: 71)
        XCTAssertEqual(restored.id, 71); XCTAssertEqual(wire.requests.count, 2)
    }
}
