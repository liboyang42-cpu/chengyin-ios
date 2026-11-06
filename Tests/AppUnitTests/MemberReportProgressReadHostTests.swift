import Foundation
import XCTest
@testable import Questify

@MainActor private final class ReportProgressHostVault: AppTokenStorage {
    var value: String? = "synthetic-report-host"
    func read() throws -> String? { value }
    func write(_ value: String) throws { self.value = value }
    func clear() throws { value = nil }
}
@MainActor private final class ReportProgressHostWire: HTTPTransport {
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
        let record = #"{"id":1,"targetType":"COMMENT","targetId":9,"reasonCode":"OTHER","policyVersion":"SYNTHETIC","description":"original","evidenceAssetIds":[],"anonymityPolicy":"SUBJECT_HIDDEN","stage":"INVESTIGATING","version":1,"createTime":"2026-10-28 21:10:00","timeline":[]}"#
        let data: String
        switch request.url?.lastPathComponent {
        case "mine": data = "[\(record)]"
        case "taxonomy": data = #"{"policyVersion":"SYNTHETIC","reasons":[{"code":"OTHER","label":"Source reason"}]}"#
        default: data = record
        }
        return (Data("{\"code\":200,\"data\":\(data)}".utf8), status)
    }
}
@MainActor private final class ReportProgressHostFixture {
    let wire = ReportProgressHostWire(), vault = ReportProgressHostVault()
    let root: AppCompositionRoot
    let suite = "report-progress-host-" + UUID().uuidString
    let defaults: UserDefaults
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://report-host.example.test/native",
            approvedBaseURLs: [.china: ["https://report-host.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.report.progress." + UUID().uuidString.lowercased(), realm: "synthetic")
        let wire = wire, vault = vault
        root = .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
    }
    func boot() async -> AppSession { let session = root.makeSession(); await session.bootstrap(); wire.requests = []; return session }
    func approve(_ session: AppSession, caps: Set<MemberReportProgressCapability> = [.history, .detail, .taxonomy]) throws -> MemberReportProgressApproval {
        let value = try MemberReportProgressApproval(context: XCTUnwrap(session.memberReportProgressIdentity.context), expiresAt: Date().addingTimeInterval(600), capabilities: caps)
        try root.memberReportProgressSelection.replace(with: value); return value
    }
    func cleanup() { root.memberReportProgressSelection.revoke(); defaults.removePersistentDomain(forName: suite) }
}
@MainActor final class MemberReportProgressReadHostTests: XCTestCase {
    private func fixture() throws -> ReportProgressHostFixture {
        let f = try ReportProgressHostFixture(); addTeardownBlock { @MainActor in f.cleanup() }; return f
    }
    func testNormalRootHasNoHistorySourceAndDoesNotRequestPermission() async throws {
        let f = try fixture(), session = await f.boot()
        XCTAssertNil(session.memberReportProgressIdentity.approvalRevision); XCTAssertNil(session.makeMemberReportProgressReader())
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertFalse(UsageConsentPolicy.liveRecordingApproved)
    }
    func testNormalHostReadsRealHistoryDetailAndTaxonomyWithoutQueryOrBody() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let reader = try XCTUnwrap(session.makeMemberReportProgressReader()), flow = reader.makeCoordinator(), owner = flow.beginHistory()
        await flow.loadHistory(intent: try XCTUnwrap(flow.capture(owner)))
        let record = try XCTUnwrap(flow.records.first), selected = try XCTUnwrap(flow.select(record, intent: try XCTUnwrap(flow.capture(owner))))
        let detail = selected.reader.makeCoordinator(), detailOwner = detail.beginDetail(selected.record)
        flow.end(owner); await detail.loadDetail(intent: try XCTUnwrap(detail.capture(detailOwner)))
        XCTAssertEqual(detail.detail?.id, 1); XCTAssertEqual(detail.reasonLabel(for: record), "Source reason")
        XCTAssertEqual(f.wire.requests.map { $0.url?.lastPathComponent }, ["mine", "taxonomy", "1", "taxonomy"])
        XCTAssertTrue(f.wire.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil && URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.query == nil })
    }
    func testHistoryOnlySourceDoesNotBorrowMetadataOrDetail() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session, caps: [.history])
        let reader = try XCTUnwrap(session.makeMemberReportProgressReader()), flow = reader.makeCoordinator(), owner = flow.beginHistory()
        await flow.loadHistory(intent: try XCTUnwrap(flow.capture(owner))); XCTAssertEqual(f.wire.requests.count, 1)
        XCTAssertNil(flow.select(try XCTUnwrap(flow.records.first), intent: try XCTUnwrap(flow.capture(owner))))
    }
    func testSourceWithdrawalClearsListAndQueuedRequestSynchronously() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let reader = try XCTUnwrap(session.makeMemberReportProgressReader()), flow = reader.makeCoordinator(), owner = flow.beginHistory()
        await flow.loadHistory(intent: try XCTUnwrap(flow.capture(owner))); let queued = try XCTUnwrap(flow.capture(owner))
        f.root.memberReportProgressSelection.revoke(); f.wire.requests = []
        XCTAssertTrue(flow.records.isEmpty); XCTAssertFalse(flow.loaded); XCTAssertNil(session.makeMemberReportProgressReader())
        await flow.loadHistory(intent: queued); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testReplacementCannotReuseOldLeaseOrOldSelection() async throws {
        let f = try fixture(), session = await f.boot(), first = try f.approve(session)
        let old = try XCTUnwrap(session.makeMemberReportProgressReader()), flow = old.makeCoordinator(), owner = flow.beginHistory()
        await flow.loadHistory(intent: try XCTUnwrap(flow.capture(owner))); let record = try XCTUnwrap(flow.records.first), queued = try XCTUnwrap(flow.capture(owner))
        _ = try f.approve(session); f.wire.requests = []
        XCTAssertFalse(old.isCurrent); XCTAssertNil(flow.select(record, intent: queued)); XCTAssertTrue(flow.records.isEmpty)
        XCTAssertThrowsError(try f.root.memberReportProgressSelection.replace(with: first))
        XCTAssertNotNil(session.makeMemberReportProgressReader()); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testRoleRefreshClearsListAndPushedDetailBeforeViewCallbacks() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let reader = try XCTUnwrap(session.makeMemberReportProgressReader()), history = reader.makeCoordinator(), owner = history.beginHistory()
        await history.loadHistory(intent: try XCTUnwrap(history.capture(owner)))
        let detail = reader.makeCoordinator(), detailOwner = detail.beginDetail(try XCTUnwrap(history.records.first))
        await detail.loadDetail(intent: try XCTUnwrap(detail.capture(detailOwner))); XCTAssertNotNil(detail.detail)
        let before = session.memberReportProgressIdentity; f.wire.role = "merchant"; await session.refreshOwnAccount(); f.wire.requests = []
        XCTAssertNotEqual(session.memberReportProgressIdentity, before); XCTAssertTrue(history.records.isEmpty); XCTAssertNil(detail.detail); XCTAssertNil(detail.detailRecord)
        XCTAssertNil(session.makeMemberReportProgressReader()); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testLateRevoked401DoesNotExpireCurrentAccountOrCredential() async throws {
        let f = try fixture(), session = await f.boot(), approval = try f.approve(session)
        let reader = try XCTUnwrap(session.makeMemberReportProgressReader()), flow = reader.makeCoordinator(), owner = flow.beginHistory()
        f.wire.status = 401; f.wire.after = { f.root.memberReportProgressSelection.revoke() }
        await flow.loadHistory(intent: try XCTUnwrap(flow.capture(owner)))
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(f.vault.value, "synthetic-report-host")
        XCTAssertFalse(approval.accessDenied); XCTAssertTrue(flow.records.isEmpty)
    }
    func testObserved403ClearsEveryClientWithoutChangingAccount() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let a = try XCTUnwrap(session.makeMemberReportProgressReader()), b = try XCTUnwrap(session.makeMemberReportProgressReader())
        let first = a.makeCoordinator(), owner = first.beginHistory(); await first.loadHistory(intent: try XCTUnwrap(first.capture(owner)))
        let other = b.makeCoordinator(), detailOwner = other.beginDetail(try XCTUnwrap(first.records.first))
        await other.loadDetail(intent: try XCTUnwrap(other.capture(detailOwner))); f.wire.status = 403
        do { _ = try await a.history(); XCTFail() } catch { }
        XCTAssertTrue(first.records.isEmpty); XCTAssertNil(other.detail); XCTAssertNil(other.detailRecord)
        XCTAssertNil(session.makeMemberReportProgressReader()); XCTAssertEqual(session.account?.id, 7)
    }
    func testDedicatedTransportAlsoFencesCompositionViewerRevision() async throws {
        let f = try fixture(), session = await f.boot(), approval = try f.approve(session)
        let context = approval.context, host = f.root.transport()
        var viewer = CompositionHTTPTransport.SessionIdentity(epoch: context.session.epoch, accountID: 7, role: "player", token: context.session.token, viewerRevision: 1)
        host.current = { viewer }
        let transport = try XCTUnwrap(host.makeMemberReportProgressTransport(context: context, approval: approval, currentRuntime: { context }, stillSelected: { true }))
        viewer = .init(epoch: context.session.epoch, accountID: 7, role: "player", token: context.session.token, viewerRevision: 2)
        var request = URLRequest(url: context.baseURL.appendingPathComponent("api/community-trust/reports/mine")); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        do { _ = try await transport.send(request); XCTFail() } catch { }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testGenericTransportCannotBorrowDedicatedReportSource() async throws {
        let f = try fixture(), session = await f.boot(), approval = try f.approve(session)
        let host = f.root.transport(), context = approval.context
        host.current = { .init(epoch: context.session.epoch, accountID: 7, role: "player", token: context.session.token, viewerRevision: 1) }
        var request = URLRequest(url: context.baseURL.appendingPathComponent("api/community-trust/reports/mine")); request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        request.setValue(context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        do { _ = try await host.send(request); XCTFail() } catch { }; XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testUnreviewedDeploymentCannotMakeReadTransport() throws {
        let f = try fixture(), context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://report-host.example.test/native")!, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-report-host", role: "player"))
        let approval = try MemberReportProgressApproval(context: context, expiresAt: Date().addingTimeInterval(600))
        let empty = AppCompositionRoot(makeTransport: { f.wire }), host = empty.transport()
        host.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-report-host", viewerRevision: 1) }
        XCTAssertNil(host.makeMemberReportProgressTransport(context: context, approval: approval, currentRuntime: { context }, stillSelected: { true }))
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testReadOnlyJourneyDoesNotChangePreferencesCredentialOrRecordingPermission() async throws {
        let f = try fixture(), session = await f.boot(); _ = try f.approve(session)
        let before = f.defaults.dictionaryRepresentation(), token = f.vault.value
        let reader = try XCTUnwrap(session.makeMemberReportProgressReader()), records = try await reader.history()
        _ = try await reader.detail(for: XCTUnwrap(records.first)); _ = try await reader.taxonomy()
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: f.defaults.dictionaryRepresentation())); XCTAssertEqual(f.vault.value, token)
        XCTAssertFalse(UsageConsentPolicy.liveRecordingApproved)
    }
}
