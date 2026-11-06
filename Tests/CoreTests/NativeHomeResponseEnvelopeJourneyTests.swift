import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// NOT_RUN. Raw response bytes exercise the real native service; all transport and storage stay in memory.
@available(macOS 14.0, *) @MainActor final class NativeHomeResponseEnvelopeJourneyTests: XCTestCase {
    private static let routes = ["policy", "runs", "account", "verify", "restore", "receipt"]
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private static func payload(_ route: String) -> String {
        switch route {
        case "policy": return #"{"policyVersion":"synthetic","maxAccuracyMeters":20,"maxFixAgeSeconds":30,"dwellSeconds":0,"serverTimeMillis":1000000000}"#
        case "runs": return #"{"runs":[],"truncated":false,"nextBeforeRunId":null}"#
        case "account": return #"{"resourceType":"sys.hp","scopeType":"RUN","scopeId":"42","current":2,"maximum":5,"version":5}"#
        case "verify": return #"{"requestId":"verify-original","decision":"VERIFIED","proofId":"synthetic-proof","homeVersion":3,"expiresAtMillis":1000060000,"accountVersion":4}"#
        default: return #"{"requestId":"restore-original","proofId":"synthetic-proof","decision":"RESTORED","current":5,"maximum":5,"accountVersion":5}"#
        }
    }
    private static func envelope(_ payload: String) -> String { "{\"code\":200,\"data\":\(payload),\"msg\":\"success\"}" }
    @MainActor private final class Wire: HTTPTransport {
        var sent: [URLRequest] = []
        var bodies: [String: Data] = [:], statuses: [String: Int] = [:]
        var afterSend: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            sent.append(request); afterSend?()
            let route = request.url?.lastPathComponent ?? ""
            return (bodies[route] ?? Data(NativeHomeResponseEnvelopeJourneyTests.envelope(NativeHomeResponseEnvelopeJourneyTests.payload(route)).utf8), statuses[route] ?? 200)
        }
    }
    @MainActor private final class Journal: NativeHomeReturnSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: NativeHomeRestoreRequest?
        var clears = 0, saves = 0
        init(_ owner: PlayExperienceSession, _ request: NativeHomeRestoreRequest) { scope = .init(owner: owner); value = request }
        func read() throws -> NativeHomeRestoreRequest? { value }
        func save(_ request: NativeHomeRestoreRequest) throws {
            guard value == nil || value == request else { throw NativeHomeReturnFailure.storageUnavailable }; value = request; saves += 1
        }
        func clear(matching request: NativeHomeRestoreRequest) throws {
            guard value == request else { throw NativeHomeReturnFailure.storageUnavailable }; value = nil; clears += 1
        }
    }
    @MainActor private final class Fixture {
        let grant: NativeHomeReturnApproval, wire: Wire, service: NativeHomeReturnService
        init() throws {
            let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token", role: "player")
            let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test/native")!, role: "player", session: owner)
            let grant = try NativeHomeReturnApproval(context: context, expiresAt: Date().addingTimeInterval(600)), wire = Wire()
            self.grant = grant; self.wire = wire
            let transport = NativeHomeReturnTransport(approval: grant, underlying: wire, current: { grant.context }, selected: { _ in grant })
            service = NativeHomeReturnService(approval: grant, transport: transport, current: { grant.context }, selected: { _ in grant })
        }
        func model(_ journal: Journal) -> NativeHomeReturnCoordinator {
            NativeHomeReturnCoordinator(scope: .run(runId: "42", resourceType: "sys.hp"), service: service, journal: journal,
                owner: grant.context.session, enabled: true, location: { XCTFail("Recovery must not sample"); return .denied },
                isCurrent: { self.service.isCurrent() }, now: { NativeHomeResponseEnvelopeJourneyTests.now })
        }
    }
    private func request() throws -> NativeHomeRestoreRequest {
        try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: Data(#"{"proofId":"synthetic-proof","requestId":"restore-original","homeVersion":3,"expectedAccountVersion":4,"scopeType":"RUN","scopeId":"42","resourceType":"sys.hp"}"#.utf8))
    }
    private func check() throws -> NativeHomeReturnCheck {
        let home = try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(#"{"version":3,"status":"ACTIVE","changedAt":1,"effectiveAt":1,"label":"Synthetic","latitude":12,"longitude":45,"datum":"WGS84"}"#.utf8))
        return try .preflight(home: home, status: .measured(.init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: Self.now)),
            policy: .init(policyVersion: "synthetic", maxAccuracyMeters: 20, maxFixAgeSeconds: 30, dwellSeconds: 0, serverTimeMillis: 1_000_000_000),
            scope: .run(runId: "42", resourceType: "sys.hp"), now: Self.now, requestId: "verify-original", expectedAccountVersion: 4)
    }
    private func perform(_ route: String, _ f: Fixture) async throws {
        switch route {
        case "policy": _ = try await f.service.policy()
        case "runs": _ = try await f.service.runs()
        case "account": _ = try await f.service.account(for: .run(runId: "42", resourceType: "sys.hp"))
        case "verify": _ = try await f.service.verify(check())
        case "restore": _ = try await f.service.restore(request())
        default: _ = try await f.service.restoreReceipt(for: request())
        }
    }
    private func rejects(_ route: String, bytes: Data, expected: NativeHomeReturnFailure = .invalid) async throws {
        let f = try Fixture(); f.wire.bodies[route] = bytes
        do { try await perform(route, f); XCTFail("Ambiguous envelope must fail before typed success") }
        catch { XCTAssertEqual(error as? NativeHomeReturnFailure, expected) }
        XCTAssertEqual(f.wire.sent.count, 1)
    }

    func testAllSixOriginalSuccessfulEnvelopesRemainReadable() async throws {
        let f = try Fixture()
        for route in Self.routes { try await perform(route, f) }
        XCTAssertEqual(f.wire.sent.compactMap { $0.url?.lastPathComponent }, Self.routes)
    }

    func testRepeatedCodeCannotBeCollapsedOnAnyNativeRoute() async throws {
        for route in Self.routes {
            for code in [200, 403] {
                let raw = "{\"code\":200,\"code\":\(code),\"data\":\(Self.payload(route))}"
                try await rejects(route, bytes: Data(raw.utf8))
            }
        }
    }

    func testRepeatedDataIncludingIdenticalValuesCannotBecomeAReceipt() async throws {
        for route in ["verify", "restore", "receipt"] {
            let value = Self.payload(route)
            try await rejects(route, bytes: Data("{\"code\":200,\"data\":\(value),\"data\":\(value)}".utf8))
        }
    }

    func testAllOriginalReceiptIdentityAndDecisionFieldsRejectDuplicateDeclarations() async throws {
        let fields = [#""requestId":"restore-original""#, #""proofId":"synthetic-proof""#, #""decision":"RESTORED""#,
            #""current":5"#, #""maximum":5"#, #""accountVersion":5"#]
        for field in fields {
            let payload = Self.payload("receipt").replacingOccurrences(of: field, with: field + "," + field)
            try await rejects("receipt", bytes: Data(Self.envelope(payload).utf8))
        }
    }

    func testEscapedAliasesOfCodeAndRequestIdentityAreStillDuplicates() async throws {
        let payload = Self.payload("receipt")
        try await rejects("receipt", bytes: Data("{\"code\":200,\"\\u0063ode\":200,\"data\":\(payload)}".utf8))
        let aliased = payload.replacingOccurrences(of: #""requestId":"restore-original""#,
            with: #""requestId":"restore-original","\u0072equestId":"restore-original""#)
        try await rejects("receipt", bytes: Data(Self.envelope(aliased).utf8))
    }

    func testDuplicateInsideIgnoredNestedExtensionIsNotHiddenByTypedDecoding() async throws {
        let raw = Self.envelope(String(Self.payload("receipt").dropLast()) + #", "future":{"items":[{"state":true,"state":false}]}}"#)
        try await rejects("receipt", bytes: Data(raw.utf8))
    }

    func testValidUnknownNestedFieldsNumbersAndUnicodeArePreservedAsCompatibleInput() async throws {
        let f = try Fixture()
        let payload = String(Self.payload("receipt").dropLast()) + #", "future":{"text":"位置仅为测试","items":[null,true,false,123456789012345678901234567890,1.1234567890123456789]}}"#
        f.wire.bodies["receipt"] = Data(Self.envelope(payload).utf8)
        let receipt = try await f.service.restoreReceipt(for: request()); XCTAssertEqual(receipt?.decision, .restored)
    }

    func testOneEscapedFieldNameIsNotRejectedOrReserialized() async throws {
        let f = try Fixture()
        let payload = Self.payload("receipt").replacingOccurrences(of: "requestId", with: "\\u0072equestId")
        f.wire.bodies["receipt"] = Data(Self.envelope(payload).utf8)
        let receipt = try await f.service.restoreReceipt(for: request()); XCTAssertEqual(receipt?.requestId, "restore-original")
    }

    func testMissingAndNullReceiptRemainAbsenceRatherThanSuccessOrFailure() async throws {
        for raw in [#"{"code":200,"msg":"success"}"#, #"{"code":200,"data":null}"#] {
            let f = try Fixture(); f.wire.bodies["receipt"] = Data(raw.utf8)
            let receipt = try await f.service.restoreReceipt(for: request()); XCTAssertNil(receipt)
        }
    }

    func testNonObjectTrailingAndTruncatedDocumentsFailClosed() async throws {
        for raw in ["[]", "null", "[{}]", Self.envelope(Self.payload("receipt")) + "{}", "{\"code\":200,\"data\":"] {
            try await rejects("receipt", bytes: Data(raw.utf8))
        }
    }

    func testInvalidUtf8CannotBeReplacedBeforeIdentityDecoding() async throws {
        var bytes = Data(Self.envelope(Self.payload("receipt")).utf8); bytes.append(0xff)
        try await rejects("receipt", bytes: bytes)
    }

    func testExistingResponseSizeLimitStillRunsBeforeTheParser() async throws {
        let base = Self.envelope(Self.payload("receipt")), f = try Fixture()
        let boundary = Data((base + String(repeating: " ", count: 65_536 - base.utf8.count)).utf8)
        f.wire.bodies["receipt"] = boundary
        let receipt = try await f.service.restoreReceipt(for: request()); XCTAssertEqual(receipt?.decision, .restored)
        try await rejects("receipt", bytes: boundary + Data([32]), expected: .network)
    }

    func testSharedDepthAndPathologicalExponentLimitsBoundUnknownExtensions() async throws {
        let tooDeep = String(Self.payload("receipt").dropLast()) + ",\"future\":" + String(repeating: "[", count: 129) + "null" + String(repeating: "]", count: 129) + "}"
        try await rejects("receipt", bytes: Data(Self.envelope(tooDeep).utf8))
        let exponent = String(Self.payload("receipt").dropLast()) + ",\"future\":1e1000000000}"
        try await rejects("receipt", bytes: Data(Self.envelope(exponent).utf8))
        let f = try Fixture()
        let bounded = String(Self.payload("receipt").dropLast()) + ",\"future\":" + String(repeating: "[", count: 64) + "null" + String(repeating: "]", count: 64) + "}"
        f.wire.bodies["receipt"] = Data(Self.envelope(bounded).utf8)
        let receipt = try await f.service.restoreReceipt(for: request()); XCTAssertEqual(receipt?.decision, .restored)
    }

    func testHttpAuthorizationFailureStillWinsBeforeBodyParsing() async throws {
        for status in [401, 403] {
            let f = try Fixture(); f.wire.statuses["receipt"] = status; f.wire.bodies["receipt"] = Data([0xff])
            do { _ = try await f.service.restoreReceipt(for: request()); XCTFail() }
            catch { XCTAssertEqual(error as? NativeHomeReturnFailure, .disabled) }
        }
    }

    func testOriginalBusinessAndHttpReasonMappingsStayUnchanged() async throws {
        for (status, code, message, expected) in [(200, 409, "HOME_RETURN_VERSION_CONFLICT", NativeHomeReturnFailure.runUnavailable),
                (400, 400, "INVALID_HOME_RETURN_REQUEST", .invalid), (503, 503, "HOME_RETURN_UNAVAILABLE", .network)] {
            let f = try Fixture(); f.wire.statuses["receipt"] = status
            f.wire.bodies["receipt"] = try JSONSerialization.data(withJSONObject: ["code": code, "msg": message])
            do { _ = try await f.service.restoreReceipt(for: request()); XCTFail() }
            catch { XCTAssertEqual(error as? NativeHomeReturnFailure, expected) }
        }
    }

    func testRevokedOwnerCheckStillRunsBeforeTheSuccessfulBodyPreflight() async throws {
        let f = try Fixture(); f.wire.afterSend = { f.grant.revoke() }
        f.wire.bodies["receipt"] = Data(#"{"code":200,"code":200}"#.utf8)
        do { _ = try await f.service.restoreReceipt(for: request()); XCTFail() }
        catch { XCTAssertEqual(error as? NativeHomeReturnFailure, .disabled) }
        XCTAssertEqual(f.wire.sent.count, 1)
    }

    func testAmbiguousOriginalGetCannotClearRecoveryButLaterValidReceiptCan() async throws {
        let f = try Fixture(), original = try request(), journal = Journal(f.grant.context.session, original), model = f.model(journal)
        await model.load(); XCTAssertEqual(model.phase, .unknown)
        let payload = Self.payload("receipt").replacingOccurrences(of: #""decision":"RESTORED""#, with: #""decision":"RESTORED","decision":"RESTORED""#)
        f.wire.bodies["receipt"] = Data(Self.envelope(payload).utf8)
        await model.readBack()
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(journal.value, original); XCTAssertEqual(journal.clears, 0); XCTAssertNil(model.decision)
        XCTAssertEqual(f.wire.sent.filter { $0.url?.lastPathComponent == "restore" }.count, 0)
        f.wire.bodies["receipt"] = nil; await model.readBack()
        XCTAssertNil(journal.value); XCTAssertEqual(journal.clears, 1); XCTAssertEqual(model.decision, .restored)
        XCTAssertEqual(model.account?.current, 2); XCTAssertEqual(model.account?.version, 5)
        XCTAssertEqual(journal.saves, 0); XCTAssertEqual(f.wire.sent.filter { $0.url?.lastPathComponent == "restore" }.count, 0)
    }

    func testAmbiguousExactRetryResponseDoesNotChangeTheOriginalRequestOrAutoRetry() async throws {
        let f = try Fixture(), original = try request(), journal = Journal(f.grant.context.session, original), model = f.model(journal)
        await model.load()
        let value = Self.payload("restore")
        f.wire.bodies["restore"] = Data("{\"code\":200,\"data\":\(value),\"data\":\(value)}".utf8)
        await model.retryExact()
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(journal.value, original); XCTAssertEqual(journal.clears, 0); XCTAssertNil(model.decision)
        let writes = f.wire.sent.filter { $0.url?.lastPathComponent == "restore" }
        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: XCTUnwrap(writes.first?.httpBody)), original)
        XCTAssertEqual(journal.saves, 0)
    }
}
