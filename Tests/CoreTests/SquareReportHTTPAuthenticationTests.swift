import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class ReportHTTPAuthAccess: SquareReportAccess {
    var identity: SquareGovernanceIdentity? = .init(accountID: 81, epoch: 1, namespace: "http-auth-regression")
    var token: String? = "synthetic-report-token"
    func freshSubject(_ target: SocialActionTarget) async throws -> SocialActionSnapshot {
        try .init(target: target, post: SquareReportFixtures.post(), comment: nil)
    }
}

@MainActor private final class ReportHTTPAuthTransport: SquareReportOfflineTransport {
    let original = SquareReportFixtureTransport()
    var denyAll = false
    var denyPost = false
    var denyReceipt = false
    var body = Data()
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if denyAll || (denyPost && request.httpMethod == "POST") ||
            (denyReceipt && request.url?.path.contains("community-trust/reports/") == true) {
            return (body, 401)
        }
        return try await original.send(request)
    }
}

@MainActor final class SquareReportHTTPAuthenticationTests: XCTestCase {
    private func service(_ transport: ReportHTTPAuthTransport) throws -> SquareReportService {
        .init(offlineConfiguration: try .init(baseURL: URL(string: "https://example.com")!), transport: transport)
    }
    func testHTTP401DoesNotDependOnEnvelopeForReadOrWrite() {
        for body in [Data(), Data("<html>Unauthorized</html>".utf8), Data("{}".utf8), Data("{\"code\":200,\"data\":{}}".utf8)] {
            for mutation in [false, true] {
                XCTAssertThrowsError(try SquareReportService.decode(body, status: 401, mutation: mutation)) {
                    XCTAssertEqual($0 as? SquareReportFailure, .signedOut)
                }
            }
        }
    }
    func testBusiness401AndOtherErrorsKeepOriginalMeaning() {
        XCTAssertThrowsError(try SquareReportService.decode(Data("{\"code\":401}".utf8), status: 200, mutation: false)) {
            XCTAssertEqual($0 as? SquareReportFailure, .signedOut)
        }
        for status in [403, 426, 500] {
            XCTAssertThrowsError(try SquareReportService.decode(Data(), status: status, mutation: true)) {
                XCTAssertEqual($0 as? SquareReportFailure, .unknown)
            }
            XCTAssertThrowsError(try SquareReportService.decode(Data(), status: status, mutation: false)) {
                XCTAssertEqual($0 as? SquareReportFailure, status == 403 ? .rejected(403) : .malformed)
            }
        }
    }
    func testRealPolicyReadReportsSignInWithoutRetrying() async throws {
        let transport = ReportHTTPAuthTransport(); transport.denyAll = true
        transport.body = Data("not-json".utf8)
        do { _ = try await service(transport).policy(token: "synthetic-report-token", check: {}); XCTFail() }
        catch { XCTAssertEqual(error as? SquareReportFailure, .signedOut) }
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.httpMethod, "GET")
    }
    func testPost401PreservesOriginalLockAndCannotResubmitAfterRestart() async throws {
        let transport = ReportHTTPAuthTransport(), access = ReportHTTPAuthAccess()
        let journal = SquareGovernanceJournal.ephemeral(), cases = SquareReportCaseStore.ephemeral()
        let model = SquareReportCoordinator(service: try service(transport), journal: journal, caseStore: cases)
        let target = try SquareReportTarget(post: SquareReportFixtures.post())
        let snapshot = try await model.load(target: target, access: access)
        let review = try model.prepare(snapshot: snapshot, reasonCode: "SPAM", description: "Synthetic facts", access: access)
        transport.denyPost = true
        do { _ = try await model.confirm(review, access: access); XCTFail() }
        catch { XCTAssertEqual(error as? SquareReportFailure, .signedOut) }
        let identity = try XCTUnwrap(access.identity)
        XCTAssertTrue(model.isLocked(target: target, identity: identity))
        XCTAssertNil(model.receipt(target: target, identity: identity))
        XCTAssertNil(try cases.reference(target: target, identity: identity))
        let restarted = SquareReportCoordinator(service: try service(transport), journal: journal, caseStore: cases)
        XCTAssertTrue(restarted.isLocked(target: target, identity: identity))
        do { _ = try await restarted.confirm(review, access: access); XCTFail() }
        catch { XCTAssertEqual(error as? SquareReportFailure, .locked) }
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
    func testDeniedReceiptReadPreservesOriginalCaseAndAccountSwitchStopsRequest() async throws {
        let transport = ReportHTTPAuthTransport(), access = ReportHTTPAuthAccess()
        let cases = SquareReportCaseStore.ephemeral(), journal = SquareGovernanceJournal.ephemeral()
        let model = SquareReportCoordinator(service: try service(transport), journal: journal, caseStore: cases)
        let target = try SquareReportTarget(post: SquareReportFixtures.post())
        let identity = try XCTUnwrap(access.identity)
        cases.record(9901, target: target, identity: identity)
        transport.denyReceipt = true
        do { _ = try await model.recover(target: target, expectedIdentity: identity, access: access); XCTFail() }
        catch { XCTAssertEqual(error as? SquareReportFailure, .signedOut) }
        XCTAssertEqual(try cases.reference(target: target, identity: identity), 9901)
        let count = transport.requests.count
        access.identity = .init(accountID: 82, epoch: 2, namespace: identity.namespace)
        do { _ = try await model.recover(target: target, expectedIdentity: identity, access: access); XCTFail() }
        catch { XCTAssertEqual(error as? SquareReportFailure, .signedOut) }
        XCTAssertEqual(transport.requests.count, count)
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
    }
}
