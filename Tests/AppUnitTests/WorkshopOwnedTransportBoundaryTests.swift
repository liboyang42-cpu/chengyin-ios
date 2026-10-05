import XCTest
@testable import Questify

@MainActor final class WorkshopOwnedTransportBoundaryTests: XCTestCase {
    private let base = URL(string: "https://example.com/native")!
    private func deployment() throws -> ReviewedAppDeployment {
        try .init(market: .china, baseURL: base.absoluteString, approvedBaseURLs: [.china: [base.absoluteString]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.workshop.transport", realm: "synthetic")
    }
    private func request(_ suffix: String = "list", body: String = "") -> URLRequest {
        var r = URLRequest(url: base.appendingPathComponent("api/workshop/owned/" + suffix))
        r.httpMethod = "POST"; r.httpBody = Data(body.utf8); r.setValue("synthetic", forHTTPHeaderField: "Authorization")
        r.setValue(String(body.utf8.count), forHTTPHeaderField: "Content-Length")
        r.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        r.cachePolicy = .reloadIgnoringLocalCacheData; r.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        r.setValue("no-cache", forHTTPHeaderField: "Pragma"); return r
    }
    private func context(_ d: ReviewedAppDeployment) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: d.storageScope.service, token: "synthetic"))
    }
    func testExactReadRoutesOnlyAndNoOwnerOverrideOrPackageThroughReadApproval() async throws {
        let d = try deployment(), wire = Wire(), grant = try WorkshopOwnedReadApproval(context: context(d), expiresAt: .distantFuture)
        let transport = CompositionHTTPTransport(deployment: d, underlying: wire, workshopOwnedReadApproval: { _ in grant })
        transport.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic") }
        _ = try await transport.send(request()); _ = try await transport.send(request("detail", body: "claim_id=claim:A_1-9"))
        XCTAssertEqual(wire.calls, 2)
        var invalid = [request(body: "owner=7"), request("detail"), request("detail", body: "claim_id=a&owner=7"),
            request("detail", body: "claim_id=a&claim_id=b"), request("detail", body: "claim_id=%61"),
            request("detail", body: "claim_id=" + String(repeating: "a", count: 129)),
            request("package"), request("claim"), request("install"), request("purchase")]
        var q = request(); q.url = URL(string: q.url!.absoluteString + "?owner=7"); invalid.append(q)
        q = request(); q.httpMethod = "GET"; invalid.append(q)
        q = request(); q.setValue("1", forHTTPHeaderField: "Content-Length"); invalid.append(q)
        q = request(); q.setValue(nil, forHTTPHeaderField: "Content-Length"); invalid.append(q)
        q = request(); q.setValue("application/json", forHTTPHeaderField: "Content-Type"); invalid.append(q)
        q = request(); q.setValue(nil, forHTTPHeaderField: "Cache-Control"); invalid.append(q)
        q = request(); q.url = URL(string: "https://other.example.com/native/api/workshop/owned/list"); invalid.append(q)
        q = request(); q.url = URL(string: base.absoluteString + "/api/workshop/owned/list/"); invalid.append(q)
        for r in invalid {
            XCTAssertNil(WorkshopOwnedReadRoute(request: r, baseURL: base))
            do { _ = try await transport.send(r); XCTFail("Unexpected request passed: \(r.url!)") }
            catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        }
        XCTAssertEqual(wire.calls, 2)
    }
    func testDefaultsAndPartialIdentityNeverForwardEvenCanonicalRoute() async throws {
        let d = try deployment(), wire = Wire(), grant = try WorkshopOwnedReadApproval(context: context(d), expiresAt: .distantFuture)
        let defaults = CompositionHTTPTransport(deployment: d, underlying: wire)
        defaults.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic") }
        do { _ = try await defaults.send(request()); XCTFail("No approval") } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let transport = CompositionHTTPTransport(deployment: d, underlying: wire, workshopOwnedReadApproval: { _ in grant })
        for identity in [CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: nil, role: nil, token: nil),
                         .init(epoch: 1, accountID: 7, role: nil, token: "synthetic"),
                         .init(epoch: 1, accountID: 7, role: "player", token: nil),
                         .init(epoch: 1, accountID: 8, role: "player", token: "synthetic"),
                         .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic")] {
            transport.current = { identity }
            do { _ = try await transport.send(request()); XCTFail("Mismatched viewer") } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        }
        XCTAssertEqual(wire.calls, 0)
    }
    func testCloneKeepsGrantAndRevocationFence() async throws {
        let d = try deployment(), original = Wire(), replacement = Wire()
        var grant: WorkshopOwnedReadApproval? = try .init(context: context(d), expiresAt: .distantFuture)
        let root = CompositionHTTPTransport(deployment: d, underlying: original, workshopOwnedReadApproval: { _ in grant })
        root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic") }
        let copied = root.replacingUnderlying(replacement)
        _ = try await copied.send(request())
        grant = nil
        do { _ = try await copied.send(request()); XCTFail("Revoked copied transport") } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(original.calls, 0); XCTAssertEqual(replacement.calls, 1)
    }
    @MainActor private final class Wire: HTTPTransport {
        var calls = 0
        func send(_ request: URLRequest) async throws -> (Data, Int) { calls += 1; return (Data(), 200) }
    }
}
