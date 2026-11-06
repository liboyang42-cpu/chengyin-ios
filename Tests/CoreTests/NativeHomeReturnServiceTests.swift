import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *) @MainActor final class NativeHomeReturnServiceTests: XCTestCase {
    final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var response: ((URLRequest) throws -> (Data, Int))?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            return try response?(request) ?? (Data("{\"code\":200,\"data\":null}".utf8), 200)
        }
    }
    func context(account: Int = 7, realm: String = "synthetic", role: String = "player", epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        try .init(market: .china, baseURL: URL(string: "https://example.test/native")!, role: role,
            session: .init(accountID: account, epoch: epoch, namespace: realm, token: "synthetic-token", role: role))
    }
    func envelope(_ data: Any) throws -> (Data, Int) {
        (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
    }
    func check() throws -> NativeHomeReturnCheck {
        let home = try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data("{\"version\":3,\"status\":\"ACTIVE\",\"changedAt\":1,\"effectiveAt\":1,\"label\":\"Synthetic\",\"latitude\":12,\"longitude\":45,\"datum\":\"WGS84\"}".utf8))
        let now = Date(timeIntervalSince1970: 1_000_000)
        return try .preflight(home: home, status: .measured(.init(latitude: 12.1234567, longitude: -45.7654321, accuracyMeters: 5.1234561, capturedAt: now)),
            policy: .init(policyVersion: "synthetic", maxAccuracyMeters: 50, maxFixAgeSeconds: 30, dwellSeconds: 10, serverTimeMillis: 1_000_000_000),
            scope: .run(runId: "42", resourceType: "sys.hp"), now: now, expectedAccountVersion: 4, challengeId: "challenge-1")
    }
    func testSixExactRoutesWithAuthNoStoreAndNoCallerIdentityOrClientReward() async throws {
        let grant = try NativeHomeReturnApproval(context: context(), expiresAt: Date().addingTimeInterval(600)), wire = Wire()
        let service = NativeHomeReturnService(approval: grant, transport: wire, current: { grant.context }, selected: { _ in grant })
        wire.response = { request in
            switch request.url!.lastPathComponent {
            case "policy": return try self.envelope(["policyVersion": "synthetic", "maxAccuracyMeters": 50, "maxFixAgeSeconds": 30, "dwellSeconds": 10, "serverTimeMillis": 1_000_000_000])
            case "runs": return try self.envelope(["runs": [], "truncated": false, "nextBeforeRunId": NSNull()])
            case "account": return try self.envelope(["resourceType": "sys.hp", "scopeType": "RUN", "scopeId": "42", "current": 2, "maximum": 5, "version": 4])
            case "verify":
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                let wireText = try XCTUnwrap(String(data: XCTUnwrap(request.httpBody), encoding: .utf8))
                XCTAssertTrue(wireText.contains("\"latitude\":12.123457"))
                XCTAssertTrue(wireText.contains("\"longitude\":-45.765432"))
                XCTAssertTrue(wireText.contains("\"accuracyMeters\":5.123457"))
                XCTAssertEqual(Set(body.keys), ["requestId", "homeVersion", "expectedAccountVersion", "scopeType", "scopeId", "resourceType", "policyVersion", "latitude", "longitude", "datum", "accuracyMeters", "capturedAtMillis", "challengeId"])
                return try self.envelope(["requestId": body["requestId"]!, "decision": "VERIFIED", "proofId": "proof-1", "homeVersion": 3, "accountVersion": 4, "expiresAtMillis": 1_000_060_000])
            case "restore":
                let body = try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: XCTUnwrap(request.httpBody))
                return try self.envelope(["requestId": body.requestId, "proofId": body.proofId, "decision": "RESTORED", "current": 5, "maximum": 5, "accountVersion": 5])
            case "receipt": return (Data("{\"code\":200,\"msg\":\"success\"}".utf8), 200)
            default: XCTFail("Unexpected route"); return (Data(), 500)
            }
        }
        _ = try await service.policy(); _ = try await service.runs(beforeRunId: "100")
        _ = try await service.account(for: .run(runId: "42", resourceType: "sys.hp"))
        let check = try check(), verification = try await service.verify(check)
        let proof = try verification.proof(for: check)
        let request = try NativeHomeRestoreRequest(proof: proof, currentHomeVersion: 3, expectedAccountVersion: 4,
            deviceNow: Date(timeIntervalSince1970: 1_000_000), serverOffset: 0)
        _ = try await service.restore(request)
        let missing = try await service.restoreReceipt(for: request); XCTAssertNil(missing)
        XCTAssertEqual(wire.requests.map { $0.url!.lastPathComponent }, ["policy", "runs", "account", "verify", "restore", "receipt"])
        XCTAssertEqual(wire.requests.map(\.httpMethod), ["GET", "GET", "GET", "POST", "POST", "GET"])
        XCTAssertEqual(wire.requests[1].url?.query, "beforeRunId=100"); XCTAssertEqual(wire.requests[2].url?.query, "runId=42")
        for request in wire.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "no-store")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Pragma"), "no-cache")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertTrue(request.url!.path.hasPrefix("/native/api/native/home/return/"))
        }
    }
    func testOwnerRealmRoleEpochAndRevokedReplacementGrantBlockBeforeAndAfterHTTP() async throws {
        let original = try context(), grant = try NativeHomeReturnApproval(context: original, expiresAt: Date().addingTimeInterval(600)), wire = Wire()
        var live: RuntimeDependencyContext? = original
        var selected: NativeHomeReturnApproval? = grant
        let service = NativeHomeReturnService(approval: grant, transport: wire, current: { live }, selected: { _ in selected })
        for alternate in [try context(account: 8), try context(realm: "other"), try context(role: "merchant"), try context(epoch: 2)] {
            live = alternate
            do { _ = try await service.runs(); XCTFail() } catch {}
        }
        XCTAssertTrue(wire.requests.isEmpty)
        live = original; selected = try NativeHomeReturnApproval(context: original, expiresAt: Date().addingTimeInterval(600))
        do { _ = try await service.runs(); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
        selected = grant
        wire.response = { _ in grant.revoke(); return try self.envelope(["runs": [], "truncated": false]) }
        do { _ = try await service.runs(); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 1); XCTAssertFalse(service.isCurrent())
    }
    func testFixedBackendErrorsAreSanitizedAndMissingDataReceiptIsNotAnError() async throws {
        let grant = try NativeHomeReturnApproval(context: context(), expiresAt: Date().addingTimeInterval(600)), wire = Wire()
        let service = NativeHomeReturnService(approval: grant, transport: wire, current: { grant.context }, selected: { _ in grant })
        for (code, message, expected) in [(400, "HOME_RUN_UNAVAILABLE", NativeHomeReturnFailure.runUnavailable),
            (400, "HOME_RETURN_CHALLENGE_EXPIRED", .proofExpired), (403, "HOME_RETURN_NOT_APPROVED", .disabled),
            (400, "INVALID_HOME_FIX", .invalid), (500, "untrusted arbitrary server detail", .network)] {
            wire.response = { _ in (try JSONSerialization.data(withJSONObject: ["code": code, "msg": message]), code) }
            do { _ = try await service.policy(); XCTFail() } catch { XCTAssertEqual(error as? NativeHomeReturnFailure, expected) }
        }
    }
    func testInvalidScopeCursorAndMalformedNullableEnvelopeFailClosed() async throws {
        let grant = try NativeHomeReturnApproval(context: context(), expiresAt: Date().addingTimeInterval(600)), wire = Wire()
        let service = NativeHomeReturnService(approval: grant, transport: wire, current: { grant.context }, selected: { _ in grant })
        do { _ = try await service.account(for: .global(resourceType: "sys.hp")); XCTFail() } catch {}
        do { _ = try await service.runs(beforeRunId: "00042"); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
        wire.response = { _ in (Data("{\"code\":200}".utf8), 200) }
        do { _ = try await service.policy(); XCTFail() } catch {}
    }
    func testSessionRoleMismatchCannotCreateGrantOrPassCurrentFence() async throws {
        let original = try context(), wire = Wire()
        let mismatched = RuntimeDependencyContext(market: original.market, baseURL: original.baseURL,
            role: original.role, session: try .init(accountID: 7, epoch: 1, namespace: "synthetic",
                token: "synthetic-token", role: "merchant"))
        XCTAssertThrowsError(try NativeHomeReturnApproval(context: mismatched, expiresAt: Date().addingTimeInterval(600)))
        let grant = try NativeHomeReturnApproval(context: original, expiresAt: Date().addingTimeInterval(600))
        XCTAssertFalse(grant.matches(mismatched))
        let service = NativeHomeReturnService(approval: grant, transport: wire, current: { mismatched }, selected: { _ in grant })
        do { _ = try await service.runs(); XCTFail() } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }

}
