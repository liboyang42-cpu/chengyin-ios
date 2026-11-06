import Foundation
import XCTest
@testable import Questify

@MainActor private final class ScoreReadHostVault: AppTokenStorage {
    var value: String? = "synthetic-score-host"
    func read() throws -> String? { value }
    func write(_ value: String) throws { self.value = value }
    func clear() throws { value = nil }
}
@MainActor private final class ScoreReadHostWire: HTTPTransport {
    var requests: [URLRequest] = []
    var role = "player"
    var status = 200
    var after: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.lastPathComponent == "userInfo" {
            return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8), 200)
        }
        defer { after?() }
        let body: String
        switch request.url?.lastPathComponent {
        case "mine": body = #"{"rows":[{"id":1,"sessionId":2,"topicId":3,"kind":"appeal","status":"open","topicName":"Synthetic"}],"total":1}"#
        case "reputation": body = #"{"status":"restricted"}"#
        default: body = #"{"sessionId":"2","topicId":"3","totalCenti":"9007199254740993","appeals":[{"id":"1","memberId":"7","sessionId":"2","status":1}],"disputes":[]}"#
        }
        return (Data("{\"code\":200,\"data\":\(body)}".utf8), status)
    }
}
@MainActor private final class ScoreReadHostFixture {
    let wire = ScoreReadHostWire(), vault = ScoreReadHostVault()
    let root: AppCompositionRoot
    let suite = "score-read-host-" + UUID().uuidString
    let defaults: UserDefaults
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://score-host.example.test/native",
            approvedBaseURLs: [.china: ["https://score-host.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.score.read." + UUID().uuidString.lowercased(), realm: "synthetic")
        let wire = wire, vault = vault
        root = .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
    }
    func boot() async -> AppSession { let session = root.makeSession(); await session.bootstrap(); wire.requests = []; return session }
    func approve(_ session: AppSession, caps: Set<MemberScoreReadCapability> = [.list, .sessionDetail, .reputation]) throws -> MemberScoreListApproval {
        let value = try MemberScoreListApproval(context: XCTUnwrap(session.memberScoreReadIdentity.context), expiresAt: Date().addingTimeInterval(600), capabilities: caps)
        try root.memberScoreReadSelection.replace(with: value); return value
    }
    func cleanup() { root.memberScoreReadSelection.revoke(); defaults.removePersistentDomain(forName: suite) }
}

@MainActor final class MemberScoreAppealReadHostTests: XCTestCase {
    private func fixture() throws -> ScoreReadHostFixture {
        let f = try ScoreReadHostFixture(); addTeardownBlock { @MainActor in f.cleanup() }; return f
    }
    func testNormalRootStartsWithoutAnyScoreOrReputationSource() async throws {
        let f = try fixture(), session = await f.boot()
        XCTAssertNil(session.memberScoreReadIdentity.approvalRevision); XCTAssertNil(session.makeMemberScoreAppealListClient())
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertFalse(UsageConsentPolicy.liveRecordingApproved)
    }
    func testNormalHostListReputationAndOriginalDetailUseOnlyGET() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let client = try XCTUnwrap(session.makeMemberScoreAppealListClient()), list = client.makeCoordinator(), owner = list.beginList()
        await list.loadList(intent: try XCTUnwrap(list.capture(owner))); XCTAssertEqual(list.reputation, .restricted)
        let row = try XCTUnwrap(list.rows.first), selected = try XCTUnwrap(list.select(row, intent: try XCTUnwrap(list.capture(owner))))
        let detail = selected.client.makeCoordinator(), detailOwner = detail.beginDetail(row)
        list.end(owner); await detail.loadDetail(intent: try XCTUnwrap(detail.capture(detailOwner)))
        XCTAssertEqual(detail.detail?.totalCenti, 9007199254740993)
        XCTAssertEqual(f.wire.requests.map(\.httpMethod), ["GET", "GET", "GET"])
        XCTAssertTrue(f.wire.requests.allSatisfy { $0.httpBody == nil })
    }
    func testListOnlyGrantDoesNotBorrowReputationOrDetail() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session, caps: [.list])
        let client = try XCTUnwrap(session.makeMemberScoreAppealListClient()), flow = client.makeCoordinator(), owner = flow.beginList()
        await flow.loadList(intent: try XCTUnwrap(flow.capture(owner)))
        XCTAssertEqual(f.wire.requests.count, 1); XCTAssertNil(flow.reputation); XCTAssertTrue(flow.reputationUnavailable)
        XCTAssertNil(flow.select(try XCTUnwrap(flow.rows.first), intent: try XCTUnwrap(flow.capture(owner))))
    }
    func testRevocationSynchronouslyRetiresEveryReadPresentation() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let client = try XCTUnwrap(session.makeMemberScoreAppealListClient()), flow = client.makeCoordinator(), owner = flow.beginList()
        await flow.loadList(intent: try XCTUnwrap(flow.capture(owner))); let queued = try XCTUnwrap(flow.capture(owner))
        f.root.memberScoreReadSelection.revoke(); f.wire.requests = []
        XCTAssertTrue(flow.rows.isEmpty); XCTAssertNil(flow.reputation); XCTAssertFalse(flow.loaded)
        await flow.loadList(intent: queued); XCTAssertTrue(f.wire.requests.isEmpty)
        XCTAssertNil(session.makeMemberScoreAppealListClient())
    }
    func testReplacementCannotReuseOldIssuanceOrOldSelection() async throws {
        let f = try fixture(), session = await f.boot(), first = try f.approve(session)
        let old = try XCTUnwrap(session.makeMemberScoreAppealListClient()), flow = old.makeCoordinator(), owner = flow.beginList()
        await flow.loadList(intent: try XCTUnwrap(flow.capture(owner))); let row = try XCTUnwrap(flow.rows.first), queued = try XCTUnwrap(flow.capture(owner))
        _ = try f.approve(session); f.wire.requests = []
        XCTAssertNil(flow.select(row, intent: queued)); XCTAssertFalse(old.isCurrent)
        XCTAssertThrowsError(try f.root.memberScoreReadSelection.replace(with: first))
        XCTAssertNotNil(session.makeMemberScoreAppealListClient()); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testRoleRefreshHidesCachedRowsBeforeUILifecycleCallback() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let client = try XCTUnwrap(session.makeMemberScoreAppealListClient()), flow = client.makeCoordinator(), owner = flow.beginList()
        await flow.loadList(intent: try XCTUnwrap(flow.capture(owner))); let queued = try XCTUnwrap(flow.capture(owner))
        let oldIdentity = session.memberScoreReadIdentity; f.wire.role = "merchant"; await session.refreshOwnAccount(); f.wire.requests = []
        XCTAssertNotEqual(session.memberScoreReadIdentity, oldIdentity); XCTAssertTrue(flow.rows.isEmpty); XCTAssertNil(flow.reputation)
        await flow.loadList(intent: queued); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testLateRevoked401DoesNotExpireCurrentAccount() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let client = try XCTUnwrap(session.makeMemberScoreAppealListClient()), flow = client.makeCoordinator(), owner = flow.beginList()
        f.wire.status = 401; f.wire.after = { f.root.memberScoreReadSelection.revoke() }
        await flow.loadList(intent: try XCTUnwrap(flow.capture(owner)))
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(f.vault.value, "synthetic-score-host"); XCTAssertTrue(flow.rows.isEmpty)
    }
    func testDedicatedTransportRequiresCapturedViewerRevision() async throws {
        let f = try fixture(), session = await f.boot(), approval = try f.approve(session)
        let context = approval.context, host = f.root.transport()
        var viewer = CompositionHTTPTransport.SessionIdentity(epoch: context.session.epoch, accountID: 7, role: "player", token: context.session.token, viewerRevision: 1)
        host.current = { viewer }
        let transport = try XCTUnwrap(host.makeMemberScoreReadTransport(context: context, approval: approval, currentRuntime: { context }, stillSelected: { true }))
        viewer = .init(epoch: context.session.epoch, accountID: 7, role: "player", token: context.session.token, viewerRevision: 3)
        var request = URLRequest(url: context.baseURL.appendingPathComponent("api/member/reputation")); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        do { _ = try await transport.send(request); XCTFail() } catch { }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testGenericTransportCannotBorrowDedicatedScoreGrant() async throws {
        let f = try fixture(), session = await f.boot(), approval = try f.approve(session)
        let host = f.root.transport(), context = approval.context
        host.current = { .init(epoch: context.session.epoch, accountID: 7, role: "player", token: context.session.token, viewerRevision: 1) }
        var request = URLRequest(url: context.baseURL.appendingPathComponent("api/member/reputation")); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        do { _ = try await host.send(request); XCTFail() } catch { }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testUnreviewedDeploymentCannotConstructReadTransport() throws {
        let f = try fixture(), context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://score-host.example.test/native")!, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-score-host", role: "player"))
        let approval = try MemberScoreListApproval(context: context, expiresAt: Date().addingTimeInterval(600))
        let empty = AppCompositionRoot(makeTransport: { f.wire }), host = empty.transport()
        host.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-score-host", viewerRevision: 1) }
        XCTAssertNil(host.makeMemberScoreReadTransport(context: context, approval: approval, currentRuntime: { context }, stillSelected: { true }))
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testReadDoesNotChangeConsentChoiceOrOriginalPendingState() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let before = f.defaults.dictionaryRepresentation(), token = f.vault.value
        let client = try XCTUnwrap(session.makeMemberScoreAppealListClient()); _ = try await client.list(); _ = try await client.reputation()
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: f.defaults.dictionaryRepresentation())); XCTAssertEqual(f.vault.value, token)
        XCTAssertFalse(UsageConsentPolicy.liveRecordingApproved)
    }
}
