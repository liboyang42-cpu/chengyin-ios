import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class PlayReadCompositionTests: XCTestCase {
    private typealias Identity = CompositionHTTPTransport.SessionIdentity
    private let base = URL(string: "https://play-read.example/native")!
    private let readIssuance = UUID()
    private func deployment(rootRead: Bool = true) throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.questify.play-read", realm: "synthetic",
            reads: rootRead ? [.playNodesAndRouteState] : [])
    }
    private func configuration(_ deployment: ReviewedAppDeployment, reads: Bool = true, accountID: Int = 7,
                               paths: Set<String> = ["api/play/nodes", "api/play/route-state"],
                               extraCapabilities: Set<PlayExperienceCapability> = [],
                               issuance: UUID? = nil) throws -> RuntimeDependencyConfiguration {
        .init(market: .china, endpoints: try .init(baseURL: base, namespace: deployment.storageScope.service,
            accountID: accountID, paths: paths), play: (reads ? Set<PlayExperienceCapability>([.reads]) : []).union(extraCapabilities),
            playReadApprovalID: issuance ?? readIssuance)
    }
    private func root(_ wire: PlayReadWire, rootRead: Bool = true, runtimeRead: Bool = true,
                      accountID: Int = 7, paths: Set<String> = ["api/play/nodes", "api/play/route-state"],
                      approvalActive: @escaping @MainActor () -> Bool = { true },
                      extraCapabilities: Set<PlayExperienceCapability> = [],
                      approvalIssuance: (@MainActor () -> UUID)? = nil) throws -> AppCompositionRoot {
        let deployment = try deployment(rootRead: rootRead)
        let endpoints = try OperationEndpointApproval(baseURL: base, namespace: deployment.storageScope.service, accountID: accountID, paths: paths)
        let stableIssuance = readIssuance
        let capabilities = (runtimeRead ? Set<PlayExperienceCapability>([.reads]) : []).union(extraCapabilities)
        let suite = "play-read-test-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let vault = PlayReadVault()
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }, sessionDependencies: { _ in
                // Production-style selector reconstructs values on each evaluation,
                // but the reviewed authority owns a stable issuance for its lifetime.
                guard approvalActive() else { return .dormant }
                return .init(configuration: .init(market: .china, endpoints: endpoints, play: capabilities,
                    playReadApprovalID: approvalIssuance?() ?? stableIssuance))
            })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(session.account?.id, 7)
    }
    private func request(_ path: String = "api/play/nodes", query: String = "activityId=41", method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: base.absoluteString + "/" + path + "?" + query)!)
        request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("synthetic-7", forHTTPHeaderField: "Authorization")
        return request
    }
    private func direct(_ wire: PlayReadWire) throws -> CompositionHTTPTransport {
        let deployment = try deployment(), config = try configuration(deployment)
        let transport = CompositionHTTPTransport(deployment: deployment, underlying: wire)
        transport.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
        transport.playReadConfiguration = { _ in config }
        return transport
    }
    func testNormalAppSessionBothReadersDispatchExactAuthenticatedBranchReads() async throws {
        let wire = PlayReadWire(), session = try root(wire).makeSession()
        await login(session)
        for scope in [PlaySessionScope.activity(41), .topic(71)] {
            let legacy = session.playReader(for: scope)
            let snapshot = try await legacy.playSession()
            XCTAssertEqual(snapshot.visibleNodes.map(\.id), [1, 2]); XCTAssertTrue(snapshot.isLocked(snapshot.visibleNodes[1]))
            XCTAssertFalse(legacy.canSubmitAnswer); XCTAssertFalse(legacy.supportsAnswerSubmission)
            let rich = try XCTUnwrap(session.playExperience(for: scope)); await rich.load()
            XCTAssertEqual(rich.phase, .ready); XCTAssertEqual(rich.snapshot?.visibleNodes.map(\.id), [1, 2])
            XCTAssertFalse(rich.canWrite)
        }
        XCTAssertEqual(wire.playRequests.count, 8)
        XCTAssertEqual(wire.playRequests.map { $0.url?.lastPathComponent }, Array(repeating: ["nodes", "route-state"], count: 4).flatMap { $0 })
        XCTAssertEqual(wire.playRequests.map { $0.url?.query }, Array(repeating: "activityId=41", count: 4) + Array(repeating: "topicId=71", count: 4))
        XCTAssertTrue(wire.playRequests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && $0.value(forHTTPHeaderField: "Authorization") == "synthetic-7" })
    }
    func testGuestUnconfiguredMissingRootMissingRuntimeAndWrongAccountNeverDispatch() async throws {
        let wire = PlayReadWire(), guest = try root(wire).makeSession()
        _ = PlaySessionView(reader: guest.playReader(for: .activity(41))).body
        await PlayViewModel(reader: guest.playReader(for: .activity(41))).load()
        XCTAssertNil(guest.playReader(for: .activity(41)).identity)
        XCTAssertFalse(guest.playReader(for: .activity(41)).isConfigured)
        let unconfigured = AppCompositionRoot(makeTransport: { wire }).makeSession()
        XCTAssertFalse(unconfigured.playReader(for: .activity(41)).isConfigured)
        XCTAssertNil(unconfigured.playExperience(for: .activity(41)))
        for (rootRead, runtimeRead, account) in [(false, true, 7), (true, false, 7), (true, true, 8)] {
            let session = try root(wire, rootRead: rootRead, runtimeRead: runtimeRead, accountID: account).makeSession()
            await login(session)
            do { _ = try await session.playReader(for: .activity(41)).playSession(); XCTFail() } catch {}
            if let rich = session.playExperience(for: .activity(41)) { await rich.load(); XCTAssertNil(rich.snapshot) }
        }
        do { _ = try await guest.playReader(for: .activity(0)).playSession(); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(wire.playRequests.isEmpty)
    }
    func testIncompleteIdentityWrongMethodQueryScopeAndUnreviewedRoutesFailClosed() async throws {
        let wire = PlayReadWire(), transport = try direct(wire)
        for identity in [Identity(epoch: 1, accountID: nil, role: nil, token: nil),
                         .init(epoch: 1, accountID: 7, role: nil, token: "synthetic-7"),
                         .init(epoch: 1, accountID: nil, role: "player", token: "synthetic-7"),
                         .init(epoch: 1, accountID: 7, role: " ", token: "synthetic-7"),
                         .init(epoch: 1, accountID: 7, role: "player", token: nil)] {
            transport.current = { identity }
            do { _ = try await transport.send(request()); XCTFail() } catch {}
        }
        transport.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7") }
        for query in ["actId=41", "activityId=0", "activityId=01", "activityId=41&topicId=71", "activityId=41&activityId=41", "activityId=%34%31", "activityId=41&nodeId=1"] {
            do { _ = try await transport.send(request(query: query)); XCTFail(query) } catch {}
        }
        for method in ["POST", "PUT", "DELETE", "HEAD"] {
            do { _ = try await transport.send(request(method: method)); XCTFail(method) } catch {}
        }
        for path in ["api/play/ending", "api/play/run-session", "api/play/run-session/list", "api/play/answer", "api/play/leaderboard", "api/play/start", "api/play/nodes/"] {
            do { _ = try await transport.send(request(path)); XCTFail(path) } catch {}
        }
        var body = request(); body.httpBody = Data("x".utf8)
        do { _ = try await transport.send(body); XCTFail() } catch {}
        var wrongToken = request(); wrongToken.setValue("synthetic-other", forHTTPHeaderField: "Authorization")
        do { _ = try await transport.send(wrongToken); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testRootGrantAloneNeverBypassesRuntimeApproval() async throws {
        let wire = PlayReadWire(), transport = CompositionHTTPTransport(deployment: try deployment(), underlying: wire)
        transport.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7") }
        do { _ = try await transport.send(request()); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testRuntimeEndingApprovalStillCannotExpandNormalRootReadFamily() async throws {
        let wire = PlayReadWire(), transport = try direct(wire)
        let config = try configuration(deployment(), paths: ["api/play/nodes", "api/play/route-state", "api/play/ending"])
        transport.playReadConfiguration = { _ in config }
        do { _ = try await transport.send(request("api/play/ending")); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExactEndpointApprovalDoesNotImplyRouteState() async throws {
        let wire = PlayReadWire(), session = try root(wire, paths: ["api/play/nodes"]).makeSession()
        await login(session)
        do { _ = try await session.playReader(for: .activity(41)).playSession(); XCTFail() } catch {}
        XCTAssertEqual(wire.playRequests.map { $0.url?.lastPathComponent }, ["nodes"])
    }
    func testEmptyRegistrationGateMissingPassAndErrorNeverManufactureProgress() async throws {
        let wire = PlayReadWire(), session = try root(wire).makeSession(); await login(session)
        let reader = session.playReader(for: .topic(71)), model = PlayViewModel(reader: reader)
        wire.nodes = #"{"code":200,"data":{"topicId":71,"nodes":[],"registered":true,"playable":true}}"#
        await model.load(); XCTAssertEqual(model.visibleSnapshot?.availability, .empty)
        _ = PlaySessionView(reader: reader).body
        wire.nodes = #"{"code":200,"data":{"topicId":71,"nodes":[{"nodeId":1}],"registered":false,"leadSpectator":true,"playable":true}}"#
        await model.load(); XCTAssertEqual(model.visibleSnapshot?.availability, .registrationRequired)
        XCTAssertEqual(model.visibleSnapshot?.result.leadSpectator, true)
        XCTAssertEqual(model.visibleSnapshot?.result.registered, false)
        wire.nodes = #"{"code":402,"msg":"synthetic missing pass"}"#
        await model.load(); XCTAssertNil(model.visibleSnapshot); XCTAssertEqual(model.visibleIssue?.titleKey, "play.passRequired")
        wire.nodes = #"{"code":500,"msg":"synthetic unavailable"}"#
        await model.load(); XCTAssertNil(model.visibleSnapshot); XCTAssertEqual(model.visibleIssue?.titleKey, "play.loadFailed")
        wire.nodes = "{}"
        await model.load(); XCTAssertNil(model.visibleSnapshot)
    }
    func testCurrentHTTPAndBusiness401ExpireMatchingSessionForBothReaders() async throws {
        for rich in [false, true] {
            for status in [200, 401] {
                let wire = PlayReadWire(), session = try root(wire).makeSession(); await login(session)
                wire.nodes = #"{"code":401}"#; wire.status = status
                if rich { await session.playExperience(for: .activity(41))?.load() }
                else { do { _ = try await session.playReader(for: .activity(41)).playSession(); XCTFail() } catch {} }
                XCTAssertNil(session.account)
            }
        }
    }
    func testLateRoleABASuccessAnd401CannotPopulateOrExpireSameEpochSession() async throws {
        for rich in [false, true] {
            for unauthorized in [false, true] {
                let wire = PlayReadWire(), session = try root(wire).makeSession(); await login(session)
                let reader = session.playReader(for: .activity(41)), model = PlayViewModel(reader: reader)
                let coordinator = try XCTUnwrap(session.playExperience(for: .activity(41)))
                wire.pause = true
                let started = expectation(description: "Play read paused"); wire.onPaused = { started.fulfill() }
                let task = Task { if rich { await coordinator.load() } else { await model.load() } }
                await fulfillment(of: [started], timeout: 2)
                guard wire.hasPending else { task.cancel(); return XCTFail("Read did not reach recorder") }
                let epoch = session.sessionRevision
                wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
                wire.finish(unauthorized: unauthorized); await task.value
                XCTAssertEqual(session.account?.role, "player"); XCTAssertEqual(session.sessionRevision, epoch)
                XCTAssertNil(model.visibleSnapshot); XCTAssertNil(coordinator.snapshot); XCTAssertNil(reader.identity)
                let count = wire.playRequests.count
                do { _ = try await reader.playSession(); XCTFail() } catch {}
                await coordinator.load(); XCTAssertEqual(wire.playRequests.count, count)
                XCTAssertFalse(reader === session.playReader(for: .activity(41)))
                XCTAssertFalse(coordinator === session.playExperience(for: .activity(41)))
            }
        }
    }
    func testLate401AfterLogoutReloginAndCancellationNeverExpiresReplacement() async throws {
        for cancel in [false, true] {
            let wire = PlayReadWire(), session = try root(wire).makeSession(); await login(session)
            let reader = session.playReader(for: .activity(41)); wire.pause = true
            let started = expectation(description: "Read paused"); wire.onPaused = { started.fulfill() }
            let task = Task { try await reader.playSession() }
            await fulfillment(of: [started], timeout: 2)
            guard wire.hasPending else { task.cancel(); return XCTFail("Read did not reach recorder") }
            if cancel { task.cancel() } else { await session.logout(); await login(session) }
            let epoch = session.sessionRevision
            wire.finish(unauthorized: true)
            do { _ = try await task.value; XCTFail() } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
            XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(session.sessionRevision, epoch)
        }
    }
    func testNormalSessionRevocationDropsLateSuccessAnd401ForBothReaders() async throws {
        for rich in [false, true] {
            for unauthorized in [false, true] {
                var approved = true
                let wire = PlayReadWire(), session = try root(wire, approvalActive: { approved }).makeSession()
                await login(session)
                let model = PlayViewModel(reader: session.playReader(for: .activity(41)))
                let coordinator = try XCTUnwrap(session.playExperience(for: .activity(41)))
                wire.pause = true
                let started = expectation(description: "Normal Play read paused")
                wire.onPaused = { started.fulfill() }
                let task = Task { if rich { await coordinator.load() } else { await model.load() } }
                await fulfillment(of: [started], timeout: 2)
                guard wire.hasPending else { task.cancel(); return XCTFail("Read did not reach recorder") }
                approved = false; wire.finish(unauthorized: unauthorized); await task.value
                XCTAssertEqual(session.account?.id, 7)
                XCTAssertNil(model.visibleSnapshot); XCTAssertNil(coordinator.snapshot)
                let count = wire.playRequests.count
                if rich { await coordinator.load() } else { await model.load() }
                XCTAssertEqual(wire.playRequests.count, count)
            }
        }
    }
    func testLoadedSnapshotsAreNotProjectedAfterApprovalRevocation() async throws {
        var approved = true
        let wire = PlayReadWire(), session = try root(wire, approvalActive: { approved }).makeSession()
        await login(session)
        let reader = session.playReader(for: .activity(41)), model = PlayViewModel(reader: reader)
        let coordinator = try XCTUnwrap(session.playExperience(for: .activity(41)))
        await model.load(); await coordinator.load()
        XCTAssertNotNil(model.visibleSnapshot); XCTAssertNotNil(coordinator.snapshot)
        approved = false
        XCTAssertNil(reader.identity); XCTAssertNil(model.visibleSnapshot); XCTAssertNil(coordinator.snapshot)
        XCTAssertFalse(coordinator.hasCurrentMediaSnapshot); XCTAssertFalse(coordinator.canWrite)
        XCTAssertEqual(session.account?.id, 7)
    }
    func testNormalSelectorGrantReissueCannotReviveAnEscapedReader() async throws {
        for rich in [false, true] {
            var issuance = UUID()
            let wire = PlayReadWire(), session = try root(wire, approvalIssuance: { issuance }).makeSession()
            await login(session)
            let reader = session.playReader(for: .activity(41))
            let model = PlayViewModel(reader: reader)
            let coordinator = try XCTUnwrap(session.playExperience(for: .activity(41)))
            wire.pause = true
            let started = expectation(description: "Read paused before grant replacement")
            wire.onPaused = { started.fulfill() }
            let task = Task { if rich { await coordinator.load() } else { await model.load() } }
            await fulfillment(of: [started], timeout: 2)
            guard wire.hasPending else { task.cancel(); return XCTFail("Read did not reach recorder") }
            issuance = UUID(); wire.finish(unauthorized: true); await task.value
            XCTAssertEqual(session.account?.id, 7); XCTAssertNil(model.visibleSnapshot); XCTAssertNil(coordinator.snapshot)
            XCTAssertNil(reader.identity)
            let fresh = session.playReader(for: .activity(41))
            XCTAssertFalse(reader === fresh); _ = try await fresh.playSession()
            let freshCoordinator = try XCTUnwrap(session.playExperience(for: .activity(41)))
            XCTAssertFalse(coordinator === freshCoordinator); await freshCoordinator.load()
            XCTAssertNotNil(freshCoordinator.snapshot)
        }
    }
    func testFreshEntryUsesNewApprovalRatherThanRetainedDormantDependencies() async throws {
        var approved = false
        let wire = PlayReadWire(), session = try root(wire, approvalActive: { approved }).makeSession()
        await login(session)
        let dormant = session.playReader(for: .activity(41)); XCTAssertFalse(dormant.isConfigured)
        approved = true
        let fresh = session.playReader(for: .activity(41)); XCTAssertFalse(fresh === dormant)
        _ = try await fresh.playSession(); XCTAssertNil(dormant.identity)
        let coordinator = try XCTUnwrap(session.playExperience(for: .activity(41))); await coordinator.load()
        XCTAssertNotNil(coordinator.snapshot); XCTAssertFalse(coordinator.canWrite)
    }
    func testMissingExplicitPlayIssuanceCannotDispatch() async throws {
        let wire = PlayReadWire(), transport = try direct(wire), deployment = try deployment()
        let config = RuntimeDependencyConfiguration(market: .china,
            endpoints: try .init(baseURL: base, namespace: deployment.storageScope.service, accountID: 7, paths: ["api/play/nodes"]), play: [.reads])
        transport.playReadConfiguration = { _ in config }
        do { _ = try await transport.send(request()); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testReadOnlyNormalSessionRunAndMutationPathsNeverDispatch() async throws {
        let wire = PlayReadWire(), session = try root(wire, extraCapabilities: [.runPersistence, .classicCompletion, .hints, .leader, .thoughtClaims]).makeSession(); await login(session)
        wire.nodes = String(decoding: PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.classic), as: UTF8.self)
        let coordinator = try XCTUnwrap(session.playExperience(for: .activity(41))); await coordinator.load()
        XCTAssertFalse(coordinator.canWrite); XCTAssertFalse(coordinator.canManageRun)
        coordinator.startRun(now: 10); await coordinator.pauseRun(now: 20, savedAt: 100)
        await coordinator.endRun(now: 30, savedAt: 200); await coordinator.restoreRun()
        await coordinator.requestHint(nodeID: 701, level: nil); await coordinator.performLead(.start)
        await coordinator.claimVisibleThoughts(chapterID: 1); await coordinator.retryExactBranchAfterReadback()
        XCTAssertThrowsError(try coordinator.review(nodeID: 701, evidence: .answer("synthetic")))
        XCTAssertEqual(coordinator.clock.phase, .idle); XCTAssertFalse(coordinator.remoteRunSaveFailed)
        XCTAssertEqual(wire.playRequests.count, 1)
    }
    func testRevokedRuntimeApprovalDropsLate401AtCompositionBoundary() async throws {
        let wire = PlayReadWire(), transport = try direct(wire)
        wire.pause = true
        let started = expectation(description: "Read paused"); wire.onPaused = { started.fulfill() }
        let task = Task { try await transport.send(self.request()) }
        await fulfillment(of: [started], timeout: 2)
        guard wire.hasPending else { task.cancel(); return XCTFail("Read did not reach recorder") }
        transport.playReadConfiguration = { _ in nil }; wire.finish(unauthorized: true)
        do { _ = try await task.value; XCTFail() } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }
}

@MainActor private final class PlayReadVault: AppTokenStorage {
    var value: String?
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token }
    func clear() throws { value = nil }
}
@MainActor private final class PlayReadWire: HTTPTransport {
    var requests: [URLRequest] = []
    var playRequests: [URLRequest] { requests.filter { $0.url?.path.contains("/api/play/") == true } }
    var role = "player", pause = false, status = 200
    static let route = #"{"routeMode":"BRANCH_GRAPH","sessionId":99,"version":1,"status":"ACTIVE","nodeStates":{"1":"PLAYABLE","2":"DISCOVERED_LOCKED","3":"HIDDEN"}}"#
    var nodes = #"{"code":200,"data":{"topicId":71,"registered":true,"playable":true,"nodes":[{"nodeId":1},{"nodeId":2},{"nodeId":3}],"routeState":ROUTE}}"#.replacingOccurrences(of: "ROUTE", with: PlayReadWire.route)
    private var pending: CheckedContinuation<(Data, Int), Error>?
    var onPaused: (() -> Void)?
    var hasPending: Bool { pending != nil }
    func finish(unauthorized: Bool) {
        let continuation = pending; pending = nil; pause = false
        continuation?.resume(returning: (Data((unauthorized ? #"{"code":401}"# : nodes).utf8), 200))
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        switch request.url?.lastPathComponent {
        case "phone": return (Data(#"{"code":200,"token":"synthetic-7"}"#.utf8), 200)
        case "userInfo": return (Data("{\"code\":200,\"appUser\":{\"id\":7,\"role\":\"\(role)\"}}".utf8), 200)
        case "logout": return (Data(#"{"code":200}"#.utf8), 200)
        case "nodes":
            if pause { return try await withCheckedThrowingContinuation { pending = $0; onPaused?() } }
            return (Data(nodes.utf8), status)
        case "route-state": return (Data("{\"code\":200,\"data\":\(Self.route)}".utf8), 200)
        default: XCTFail("Unreviewed request reached recorder"); throw APIError.invalidRequest
        }
    }
}
