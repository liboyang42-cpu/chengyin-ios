import Foundation
import XCTest
@testable import Questify

@MainActor private final class SupportReadHostVault: AppTokenStorage {
    var value: String? = "synthetic-support-host-token"
    func read() throws -> String? { value }
    func write(_ value: String) throws { self.value = value }
    func clear() throws { value = nil }
}
@MainActor private final class SupportReadHostWire: HTTPTransport {
    var requests: [URLRequest] = []
    var role = "player", status = 200
    var after: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.lastPathComponent == "userInfo" { return (Data("{\"code\":200,\"appUser\":{\"userId\":7,\"role\":\"\(role)\"}}".utf8),200) }
        after?()
        return (Data(#"{"code":200,"data":{"list":[{"ticket_no":"CS20261021-000123","requester_role":"PLAYER","category":"ACCOUNT","subject":"Synthetic subject","status":"OPEN","version":1}],"has_more":false,"next_cursor":1}}"#.utf8),status)
    }
}
@MainActor private final class SupportReadHostFixture {
    let wire = SupportReadHostWire(), vault = SupportReadHostVault()
    let root: AppCompositionRoot
    let suite = "support-read-host-" + UUID().uuidString
    let defaults: UserDefaults
    init() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: "https://support-host.example.test/native", approvedBaseURLs: [.china:["https://support-host.example.test/native"]], verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.support.read." + UUID().uuidString.lowercased(), realm: "synthetic")
        let wire = wire, vault = vault
        root = .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
    }
    func boot() async -> AppSession { let s = root.makeSession(); await s.bootstrap(); wire.requests = []; return s }
    func approve(_ session: AppSession, capabilities: Set<SupportTicketReadCapability> = [.history,.detail,.timeline]) throws -> SupportTicketReadApproval {
        let a = try SupportTicketReadApproval(context: XCTUnwrap(session.supportTicketReadIdentity.context), expiresAt: Date().addingTimeInterval(600), capabilities: capabilities)
        try root.supportTicketReadSelection.replace(with: a); return a
    }
    func cleanup() { root.supportTicketReadSelection.revoke(); defaults.removePersistentDomain(forName: suite) }
}
@MainActor final class SupportTicketR463HostTests: XCTestCase {
    private func fixture() throws -> SupportReadHostFixture { let f = try SupportReadHostFixture(); addTeardownBlock { @MainActor in f.cleanup() }; return f }
    func testNormalDefaultNilNeverCreatesReaderOrRequest() async throws {
        let f = try fixture(), s = await f.boot(); XCTAssertNil(s.makeSupportTicketReadReader()); XCTAssertNil(s.supportTicketReadIdentity.approvalRevision); XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testNormalRootStandaloneReadUsesOnlyR463POSTList() async throws {
        let f = try fixture(), s = await f.boot(); _ = try f.approve(s)
        let reader = try XCTUnwrap(s.makeSupportTicketReadReader()), result = try await reader.history()
        XCTAssertEqual(result.list.first?.subject, "Synthetic subject"); XCTAssertEqual(f.wire.requests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(f.wire.requests.first?.url?.path, "/native/api/support/tickets/list")
    }
    func testWithdrawalClearsEveryOpenFlowAndQueuedRead() async throws {
        let f = try fixture(), s = await f.boot(); _ = try f.approve(s)
        let a = try XCTUnwrap(s.makeSupportTicketReadReader()).makeCoordinator(), b = try XCTUnwrap(s.makeSupportTicketReadReader()).makeCoordinator()
        let av = a.begin(), bv = b.begin(); await a.loadHistory(try XCTUnwrap(a.capture(av))); await b.loadHistory(try XCTUnwrap(b.capture(bv)))
        let queued = try XCTUnwrap(a.capture(av)); f.root.supportTicketReadSelection.revoke(); f.wire.requests = []
        await a.loadHistory(queued); XCTAssertTrue(a.tickets.isEmpty); XCTAssertTrue(b.tickets.isEmpty); XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertNil(s.makeSupportTicketReadReader())
    }
    func testReplacementAllowsNewReaderButNeverReusesOldIssuance() async throws {
        let f = try fixture(), s = await f.boot(), old = try f.approve(s), reader = try XCTUnwrap(s.makeSupportTicketReadReader())
        _ = try f.approve(s); XCTAssertFalse(reader.isCurrent); XCTAssertThrowsError(try f.root.supportTicketReadSelection.replace(with: old))
        let new = try XCTUnwrap(s.makeSupportTicketReadReader()); _ = try await new.history(); XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testRoleChangeRetiresOldViewAndNewExplicitLeaseCanRead() async throws {
        let f = try fixture(), s = await f.boot(); _ = try f.approve(s)
        let identity = s.supportTicketReadIdentity, reader = try XCTUnwrap(s.makeSupportTicketReadReader()), flow = reader.makeCoordinator(), visit = flow.begin()
        await flow.loadHistory(try XCTUnwrap(flow.capture(visit)))
        f.wire.role = "merchant"; await s.refreshOwnAccount(); f.wire.requests = []
        XCTAssertNotEqual(s.supportTicketReadIdentity, identity); XCTAssertFalse(reader.isCurrent); XCTAssertTrue(flow.tickets.isEmpty); XCTAssertNil(s.makeSupportTicketReadReader())
        _ = try f.approve(s); _ = try await XCTUnwrap(s.makeSupportTicketReadReader()).history(); XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testCurrent403OnlyRevokesReadLeaseNotAccount() async throws {
        let f = try fixture(), s = await f.boot(); _ = try f.approve(s); let reader = try XCTUnwrap(s.makeSupportTicketReadReader()); f.wire.status = 403
        do { _ = try await reader.history(); XCTFail() } catch { }
        XCTAssertNil(s.makeSupportTicketReadReader()); XCTAssertEqual(s.account?.id, 7); XCTAssertEqual(f.vault.value, "synthetic-support-host-token")
    }
    func testStale401CannotRevokeReplacementOrLogOut() async throws {
        let f = try fixture(), s = await f.boot(), old = try f.approve(s), reader = try XCTUnwrap(s.makeSupportTicketReadReader())
        var replacement: SupportTicketReadApproval?
        f.wire.status = 401; f.wire.after = { replacement = try? f.approve(s) }
        do { _ = try await reader.history(); XCTFail() } catch { }
        XCTAssertFalse(old.revoked); XCTAssertNotNil(replacement); XCTAssertFalse(replacement?.revoked ?? true); XCTAssertEqual(s.account?.id, 7)
    }
    func testReadGrantDoesNotPermitRequestRecoveryOrWriterRoute() async throws {
        let f = try fixture(), s = await f.boot(), approval = try f.approve(s)
        let host = f.root.transport(), c = approval.context
        host.current = { .init(epoch: c.session.epoch, accountID: 7, role: "player", token: c.session.token, viewerRevision: 1) }
        let transport = try XCTUnwrap(host.makeSupportTicketReadTransport(context: c, approval: approval, currentRuntime: { c }, stillSelected: { true }))
        for path in ["api/support/tickets", "api/support/tickets/request", "api/support/tickets/reply", "api/support/tickets/attachments/bytes"] {
            var r = URLRequest(url: c.baseURL.appendingPathComponent(path)); r.httpMethod = "POST"; r.httpShouldHandleCookies = false; r.httpBody = Data(#"{"cursor":0}"#.utf8)
            for (k,v) in ["Accept":"application/json","Content-Type":"application/json","Authorization":c.session.token,"Cache-Control":"no-store","Pragma":"no-cache"] { r.setValue(v, forHTTPHeaderField: k) }
            do { _ = try await transport.send(r); XCTFail() } catch { }
        }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testDedicatedTransportRejectsChangedViewerRevision() async throws {
        let f = try fixture(), s = await f.boot(), approval = try f.approve(s), host = f.root.transport(), c = approval.context
        var identity = CompositionHTTPTransport.SessionIdentity(epoch: c.session.epoch, accountID: 7, role: "player", token: c.session.token, viewerRevision: 1); host.current = { identity }
        let t = try XCTUnwrap(host.makeSupportTicketReadTransport(context: c, approval: approval, currentRuntime: { c }, stillSelected: { true }))
        identity = .init(epoch: c.session.epoch, accountID: 7, role: "player", token: c.session.token, viewerRevision: 2)
        var r = URLRequest(url: c.baseURL.appendingPathComponent("api/support/tickets/list")); r.httpMethod = "POST"; r.httpShouldHandleCookies = false; r.httpBody = Data(#"{"cursor":0}"#.utf8)
        for (k,v) in ["Accept":"application/json","Content-Type":"application/json","Authorization":c.session.token,"Cache-Control":"no-store","Pragma":"no-cache"] { r.setValue(v, forHTTPHeaderField: k) }
        do { _ = try await t.send(r); XCTFail() } catch { }; XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testReadDoesNotPersistDraftsOrCredentialsOrRecordingConsent() async throws {
        let f = try fixture(), s = await f.boot(); _ = try f.approve(s)
        let before = f.defaults.dictionaryRepresentation(), token = f.vault.value
        _ = try await XCTUnwrap(s.makeSupportTicketReadReader()).history()
        XCTAssertTrue(NSDictionary(dictionary: before).isEqual(to: f.defaults.dictionaryRepresentation())); XCTAssertEqual(f.vault.value, token); XCTAssertFalse(UsageConsentPolicy.liveRecordingApproved)
    }
}
