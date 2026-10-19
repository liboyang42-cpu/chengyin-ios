import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class DeregisterHTTPFake: HTTPTransport {
    var requests: [URLRequest] = []
    var responses: [String]
    init(_ responses: [String]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.timedOut) }
        return (Data(responses.removeFirst().utf8), 200)
    }
}
@MainActor private final class DeregisterAuthFake: AuthChannelServing {
    var smsCalls = 0
    func sendSMSCode(phone: String) async throws { smsCalls += 1 }
    func loginWithPhone(phone: String, code: String) async throws -> LoginResult { throw ComplianceFailure.unavailable }
    func loginWithApple(identityToken: String) async throws -> LoginResult { throw ComplianceFailure.unavailable }
    func currentAccount(token: String) async throws -> Account { throw ComplianceFailure.unavailable }
}
@MainActor private final class DeregisterEffectsFake: ComplianceRoamEffects {
    func stopTracking() async throws {}
    func clearMapPrivacy() async throws {}
    func invalidateMapPrivacyCaches() {}
}

/// Mini-program utils/deregister-flow.js status and verification-method parity.
@MainActor final class AccountDeregistrationParityTests: XCTestCase {
    private var session: ComplianceSession? = .init(accountID: 7, epoch: 1, market: "CN", namespace: "deregister-parity")

    private func coordinator(_ fake: DeregisterHTTPFake, auth: DeregisterAuthFake = DeregisterAuthFake()) throws -> AccountComplianceCoordinator {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("journal.json")
        let service = AccountComplianceService(configuration: try APIConfiguration(baseURL: URL(string: "https://fixture.example")!), transport: fake,
                                               journal: ComplianceFileJournal(url: url), current: { [unowned self] in self.session }, token: { "synthetic-test-token" },
                                               readsEnabled: true, writesEnabled: true, legalApproved: { _, _ in true }, authoritativeMerchantID: { nil })
        return AccountComplianceCoordinator(service: service, auth: auth, effects: DeregisterEffectsFake(), current: { [unowned self] in self.session }, invalidateSession: { _ in })
    }

    private func decode(_ json: String) throws -> ComplianceDeregistration {
        try JSONDecoder().decode(ComplianceDeregistration.self, from: Data(json.utf8))
    }

    func testCancelledAndFailedReturnToPrecheckLikeNormal() async throws {
        for status in ["NORMAL", "CANCELLED", "FAILED"] {
            let value = try coordinator(DeregisterHTTPFake([#"{"code":200,"data":{"status":"\#(status)"}}"#]))
            await value.load()
            XCTAssertEqual(value.state.step, .notice, status)
        }
        let unknown = try coordinator(DeregisterHTTPFake([#"{"code":200,"data":{"status":"INVENTED"}}"#]))
        await unknown.load()
        XCTAssertEqual(unknown.state.step, .unknown)
    }

    func testPendingWithoutExecuteAfterIsStillPending() throws {
        XCTAssertTrue(try decode(#"{"status":"PENDING"}"#).pending)
        XCTAssertTrue(try decode(#"{"status":"WAITING","executeAfter":"2026-10-26T03:00:00.000+08:00"}"#).pending)
        XCTAssertFalse(try decode(#"{"status":"CANCELLED","executeAfter":"2026-10-26T03:00:00.000+08:00"}"#).pending)
        XCTAssertFalse(try decode(#"{"status":"NORMAL"}"#).pending)
    }

    func testVerificationMethodDecodesAndOnlySMSOrLegacyAbsentIsUsable() throws {
        XCTAssertTrue(try decode(#"{"status":"ELIGIBLE"}"#).verificationAvailableOnThisDevice)
        XCTAssertTrue(try decode(#"{"status":"ELIGIBLE","verificationMethod":"SMS"}"#).verificationAvailableOnThisDevice)
        XCTAssertFalse(try decode(#"{"status":"ELIGIBLE","verificationMethod":"WECHAT"}"#).verificationAvailableOnThisDevice)
        XCTAssertFalse(try decode(#"{"status":"ELIGIBLE","verificationMethod":"UNAVAILABLE"}"#).verificationAvailableOnThisDevice)
        XCTAssertFalse(try decode(#"{"status":"ELIGIBLE","verificationMethod":7}"#).verificationAvailableOnThisDevice)
        XCTAssertTrue(try decode(#"{"status":"ELIGIBLE","verificationMethod":null}"#).verificationAvailableOnThisDevice)
    }

    func testWeChatOrUnavailableVerificationRecordsNoConsentAndSendsNoSMS() async throws {
        for method in ["WECHAT", "UNAVAILABLE"] {
            let fake = DeregisterHTTPFake([#"{"code":200,"data":{"status":"NORMAL"}}"#, #"{"code":200,"data":{"status":"ELIGIBLE","blockers":[],"verificationMethod":"\#(method)"}}"#])
            let auth = DeregisterAuthFake(); let value = try coordinator(fake, auth: auth)
            await value.load(); await value.precheckAndAgree(documentRead: true, explicitAgreement: true)
            XCTAssertEqual(value.state.step, .verificationUnavailable, method)
            XCTAssertEqual(value.state.status?.verificationMethod, method)
            await value.sendSMS(phone: "10000000000", explicitlyRequested: true)
            XCTAssertEqual(auth.smsCalls, 0)
            XCTAssertEqual(fake.requests.map { $0.url!.path }, ["/api/user/deregister/status", "/api/user/deregister/precheck"])
        }
    }

    func testRecheckFromVerificationUnavailableReadsStatusAgain() async throws {
        let fake = DeregisterHTTPFake([#"{"code":200,"data":{"status":"NORMAL"}}"#, #"{"code":200,"data":{"status":"ELIGIBLE","verificationMethod":"WECHAT"}}"#, #"{"code":200,"data":{"status":"NORMAL"}}"#])
        let value = try coordinator(fake)
        await value.load(); await value.precheckAndAgree(documentRead: true, explicitAgreement: true)
        await value.load()
        XCTAssertEqual(value.state.step, .notice)
    }
}
