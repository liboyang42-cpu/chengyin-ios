import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class ClubBadgeScopedTransportTests: XCTestCase {
    final class Wire: HTTPTransport {
        var calls = 0
        var sent: URLRequest?
        var after: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            calls += 1; sent = request; after?()
            return (Data(#"{"code":200,"data":[]}"#.utf8), 200)
        }
    }
    final class Fixture {
        let context: RuntimeDependencyContext
        let wire = Wire()
        let issued: ClubBadgeManagementApproval
        var latest: ClubBadgeManagementApproval?
        var current: RuntimeDependencyContext?
        lazy var scoped = ClubBadgeScopedTransport(context: context, clubID: 7, approval: issued, underlying: wire,
            current: { [weak self] in self?.current }, currentApproval: { [weak self] in self?.latest })
        init(writes: Bool = false) throws {
            context = try WorkshopOwnedTestData.context(); current = context
            let endpoints = try OperationEndpointApproval(baseURL: context.baseURL, namespace: context.session.namespace,
                accountID: context.session.accountID, paths: ClubBadgeManagementRoute.paths)
            issued = try .init(endpoints: endpoints, clubIDs: [7], reviewedPolicyVersion: "synthetic", reads: true, writes: writes)
            latest = issued
        }
        func request(club: Int = 7) throws -> URLRequest {
            var r = URLRequest(url: context.baseURL.appendingPathComponent(ClubBadgeManagementRoute.listPath))
            r.httpMethod = "POST"; r.httpBody = try JSONSerialization.data(withJSONObject: ["id": club])
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.setValue(context.session.token, forHTTPHeaderField: "Authorization")
            r.setValue(String(r.httpBody!.count), forHTTPHeaderField: "Content-Length")
            r.setValue("no-store", forHTTPHeaderField: "Cache-Control"); r.setValue("no-cache", forHTTPHeaderField: "Pragma")
            r.httpShouldHandleCookies = false; r.cachePolicy = .reloadIgnoringLocalCacheData
            return r
        }
    }
    func testOriginalServiceEmitsAcceptedBoundedReadShape() async throws {
        let f = try Fixture()
        let service = ClubBadgeManagementService(context: f.context, clubID: 7, transport: f.scoped,
            current: { f.current }, approval: { _ in f.latest })
        let badges = try await service.badges()
        XCTAssertTrue(badges.isEmpty)
        XCTAssertEqual(f.wire.calls, 1); XCTAssertEqual(f.wire.sent?.httpShouldHandleCookies, false)
    }
    func testDifferentClubIsRejectedBeforeTransport() async throws {
        let f = try Fixture()
        do { _ = try await f.scoped.send(f.request(club: 8)); XCTFail("Wrong club") } catch { }
        XCTAssertEqual(f.wire.calls, 0)
    }
    func testCookieTokenAndFramingOverridesAreRejected() async throws {
        for key in ["Cookie", "Authorization", "Transfer-Encoding", "Content-Length"] {
            let f = try Fixture(); var r = try f.request(); r.setValue("invalid", forHTTPHeaderField: key)
            do { _ = try await f.scoped.send(r); XCTFail("Unexpected header accepted") } catch { }
            XCTAssertEqual(f.wire.calls, 0)
        }
    }
    func testContextWithdrawalSuppressesLateResult() async throws {
        let f = try Fixture(); f.wire.after = { f.current = nil }
        do { _ = try await f.scoped.send(f.request()); XCTFail("Retired response") } catch { }
        XCTAssertEqual(f.wire.calls, 1)
    }
    func testSameFieldsNewGrantCannotResurrectOldTransport() async throws {
        let f = try Fixture()
        f.latest = try .init(endpoints: f.issued.endpoints, clubIDs: [7], reviewedPolicyVersion: "synthetic", reads: true)
        do { _ = try await f.scoped.send(f.request()); XCTFail("New grant is a new lifetime") } catch { }
        XCTAssertEqual(f.wire.calls, 0)
    }
    func testReadOnlyApprovalCannotAuthorizeCreate() async throws {
        let f = try Fixture(); var r = try f.request()
        let fields: [String: Any] = ["clubId": 7, "badgeName": "Trail"]
        r.url = f.context.baseURL.appendingPathComponent(ClubBadgeManagementRoute.createPath)
        r.httpBody = try JSONSerialization.data(withJSONObject: fields)
        r.setValue(String(r.httpBody!.count), forHTTPHeaderField: "Content-Length")
        r.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: ClubBadgeManagementRoute.requestHeader)
        r.setValue(try ClubBadgeManagementRoute.sourceHash(operation: "CREATE", fields: fields), forHTTPHeaderField: ClubBadgeManagementRoute.sourceHeader)
        do { _ = try await f.scoped.send(r); XCTFail("Read grant cannot write") } catch { }
        XCTAssertEqual(f.wire.calls, 0)
    }
}
