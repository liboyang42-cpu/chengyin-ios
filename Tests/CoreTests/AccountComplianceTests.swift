import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class ComplianceHTTPFake: HTTPTransport {
    var requests: [URLRequest] = []
    var responses: [String]
    var afterSend: (() -> Void)?
    init(_ responses: [String]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); afterSend?()
        guard !responses.isEmpty else { throw URLError(.timedOut) }
        return (Data(responses.removeFirst().utf8), 200)
    }
}
@MainActor private final class ComplianceTestContext {
    var session: ComplianceSession? = .init(accountID: 7, epoch: 1, market: "CN", namespace: "test")
    var merchantID: Int? = 41
}
@MainActor final class AccountComplianceTests: XCTestCase {
    private func build(_ fake: ComplianceHTTPFake, context: ComplianceTestContext, enabled: Bool = true) throws -> (AccountComplianceService, ComplianceFileJournal, URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("journal.json")
        let journal = ComplianceFileJournal(url: url)
        let service = AccountComplianceService(configuration: try APIConfiguration(baseURL: URL(string: "https://fixture.example")!), transport: fake, journal: journal, current: { context.session }, token: { "synthetic-test-token" }, readsEnabled: enabled, writesEnabled: enabled, legalApproved: { _, _ in enabled }, authoritativeMerchantID: { context.merchantID })
        return (service, journal, url)
    }
    func testMissingLatestIsNormalNoConsent() async throws {
        let context = ComplianceTestContext(); let fake = ComplianceHTTPFake([#"{"code":200}"#]); let (service, _, _) = try build(fake, context: context)
        let result = try await service.latest(.signup, session: context.session!)
        XCTAssertNil(result); XCTAssertEqual(fake.requests.first?.url?.path, "/api/compliance/consents/latest")
    }
    func testExactMerchantWriteReadbackAndNoClientVersion() async throws {
        let context = ComplianceTestContext(); let fake = ComplianceHTTPFake([#"{"code":200}"#, #"{"code":200,"data":{"docType":"merchant_onsite_data_sharing","scene":"merchant_redeem","scopeType":"MERCHANT","scopeId":41,"eventType":"AGREE","docVersion":"server-only"}}"#])
        let (service, journal, _) = try build(fake, context: context); let subject = ComplianceSubject.merchantOnsite(authoritativeMerchantID: 41)
        let record = try await service.consent(subject, event: .agree, requestID: "fixture", session: context.session!)
        XCTAssertTrue(record.matches(subject, event: .agree)); XCTAssertNil(try journal.pending(scope: context.session!.journalScope, operation: subject.operation))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: fake.requests[0].httpBody!) as? [String: Any])
        XCTAssertNil(json["docVersion"]); XCTAssertEqual(json["scopeId"] as? Int, 41)
    }
    func testMismatchLocksAcrossJournalRecreationAndPreventsRetry() async throws {
        let context = ComplianceTestContext(); let fake = ComplianceHTTPFake([#"{"code":200}"#, #"{"code":200,"data":{"docType":"privacy_policy","scene":"roam_location","eventType":"AGREE"}}"#])
        let (service, _, url) = try build(fake, context: context)
        do { _ = try await service.consent(.roamLocation, event: .revoke, requestID: "fixture", session: context.session!); XCTFail() } catch { XCTAssertEqual(error as? ComplianceFailure, .readbackMismatch) }
        XCTAssertNotNil(try ComplianceFileJournal(url: url).pending(scope: context.session!.journalScope, operation: ComplianceSubject.roamLocation.operation))
        do { _ = try await service.consent(.roamLocation, event: .revoke, requestID: "new", session: context.session!); XCTFail() } catch { XCTAssertEqual(error as? ComplianceFailure, .unresolved) }
        XCTAssertEqual(fake.requests.count, 2)
    }
    func testScopeChangeDuringReadbackIsRejected() async throws {
        let context = ComplianceTestContext(); let session = context.session!; let fake = ComplianceHTTPFake([#"{"code":200}"#]); let (service, _, _) = try build(fake, context: context)
        fake.afterSend = { context.merchantID = 42 }
        do { _ = try await service.consent(.merchantOnsite(authoritativeMerchantID: 41), event: .agree, requestID: "fixture", session: session); XCTFail() } catch { XCTAssertEqual(error as? ComplianceFailure, .staleSession) }
        XCTAssertEqual(fake.requests.count, 1)
    }
    func testSessionChangeDiscardsResponseAndRetainsLock() async throws {
        let context = ComplianceTestContext(); let session = context.session!; let fake = ComplianceHTTPFake([#"{"code":200}"#]); let (service, journal, _) = try build(fake, context: context)
        fake.afterSend = { context.session = .init(accountID: 8, epoch: 2, market: "CN", namespace: "test") }
        do { _ = try await service.consent(.roamLocation, event: .revoke, requestID: "fixture", session: session); XCTFail() } catch { XCTAssertEqual(error as? ComplianceFailure, .staleSession) }
        XCTAssertNotNil(try journal.pending(scope: session.journalScope, operation: ComplianceSubject.roamLocation.operation))
    }
    func testDefaultsSendNothing() async throws {
        let context = ComplianceTestContext(); let fake = ComplianceHTTPFake([]); let (service, _, _) = try build(fake, context: context, enabled: false)
        do { _ = try await service.status(session: context.session!); XCTFail() } catch { XCTAssertEqual(error as? ComplianceFailure, .unavailable) }
        XCTAssertTrue(fake.requests.isEmpty)
    }
    func testDeregisterUsesMultipartAndSameEpochCannotCancel() async throws {
        let context = ComplianceTestContext(); let fake = ComplianceHTTPFake([#"{"code":200,"data":{"status":"WAITING","executeAfter":"server-date","blockers":[]}}"#]); let (service, _, _) = try build(fake, context: context)
        let result = try await service.apply(smscode: "123456", requestID: "fixture", session: context.session!)
        XCTAssertTrue(result.pending); XCTAssertTrue(fake.requests[0].value(forHTTPHeaderField: "Content-Type")!.contains("multipart/form-data"))
        let body = String(data: fake.requests[0].httpBody!, encoding: .utf8)!
        XCTAssertTrue(body.contains("name=\"smscode\"")); XCTAssertTrue(body.contains("name=\"requestId\""))
        do { _ = try await service.cancel(session: context.session!); XCTFail() } catch { XCTAssertEqual(error as? ComplianceFailure, .staleSession) }
        XCTAssertEqual(fake.requests.count, 1)
    }
    func testBlockedAndUnknownNeverEligible() throws {
        let blocked = try JSONDecoder().decode(ComplianceDeregistration.self, from: Data(#"{"status":"BLOCKED","blockers":["server reason"]}"#.utf8))
        XCTAssertTrue(blocked.blocked); XCTAssertFalse(blocked.eligible); XCTAssertEqual(blocked.blockers, ["server reason"])
        let unknown = try JSONDecoder().decode(ComplianceDeregistration.self, from: Data("{}".utf8))
        XCTAssertFalse(unknown.eligible); XCTAssertFalse(unknown.pending); XCTAssertEqual(unknown.status, "UNKNOWN")
    }
    func testMarketingWrongOwnerNeverConfirms() async throws {
        let context = ComplianceTestContext(); let row = try JSONDecoder().decode(ComplianceMarketingConsent.self, from: Data(#"{"merchantRowId":41,"merchantOwnerMemberId":7,"inAppOptedIn":false,"couponOptedIn":false}"#.utf8))
        let fake = ComplianceHTTPFake([#"{"code":200}"#, #"{"code":200,"data":[{"merchantRowId":41,"merchantOwnerMemberId":8,"inAppOptedIn":true,"couponOptedIn":false}]}"#]); let (service, _, _) = try build(fake, context: context)
        do { _ = try await service.setMarketing(row, channel: .inApp, optedIn: true, requestID: "fixture", session: context.session!); XCTFail() } catch { XCTAssertEqual(error as? ComplianceFailure, .readbackMismatch) }
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: fake.requests[0].httpBody!) as? [String: Any])
        XCTAssertEqual(body["merchantOwnerMemberId"] as? Int, 7); XCTAssertEqual(body["channel"] as? String, "IN_APP")
    }
}

@MainActor private final class ComplianceAuthFake: AuthChannelServing {
    var smsCalls = 0
    var failSMS = false
    func sendSMSCode(phone: String) async throws { smsCalls += 1; if failSMS { throw ComplianceFailure.rejected("SMS failed") } }
    func loginWithPhone(phone: String, code: String) async throws -> LoginResult { throw ComplianceFailure.unavailable }
    func loginWithApple(identityToken: String) async throws -> LoginResult { throw ComplianceFailure.unavailable }
    func currentAccount(token: String) async throws -> Account { throw ComplianceFailure.unavailable }
}
@MainActor private final class ComplianceEffectsFake: ComplianceRoamEffects {
    var calls: [String] = []
    var failStop = false
    var failClear = false
    func stopTracking() async throws { calls.append("stop"); if failStop { throw ComplianceFailure.unavailable } }
    func clearMapPrivacy() async throws { calls.append("clear"); if failClear { throw ComplianceFailure.unavailable } }
    func invalidateMapPrivacyCaches() { calls.append("invalidate") }
}
extension AccountComplianceTests {
    func testConsentRejectionDoesNotReachSMS() async throws {
        let context = ComplianceTestContext(); let fake = ComplianceHTTPFake([#"{"code":200,"data":{"status":"NORMAL"}}"#, #"{"code":200,"data":{"status":"ELIGIBLE"}}"#, #"{"code":409,"msg":"consent failed"}"#]); let (service, _, _) = try build(fake, context: context)
        let auth = ComplianceAuthFake(); let coordinator = AccountComplianceCoordinator(service: service, auth: auth, effects: ComplianceEffectsFake(), current: { context.session }, invalidateSession: { _ in XCTFail() })
        await coordinator.load(); await coordinator.precheckAndAgree(documentRead: true, explicitAgreement: true)
        await coordinator.sendSMS(phone: "13800000000", explicitlyRequested: true)
        XCTAssertEqual(auth.smsCalls, 0); XCTAssertNotEqual(coordinator.state.step, .verify)
    }
    func testSMSFailureAndAcceptedApplyInvalidateOriginalSession() async throws {
        let context = ComplianceTestContext(); let original = context.session!
        let fake = ComplianceHTTPFake([#"{"code":200,"data":{"status":"NORMAL"}}"#, #"{"code":200,"data":{"status":"ELIGIBLE"}}"#, #"{"code":200}"#, #"{"code":200,"data":{"docType":"account_cancellation_notice","scene":"account_cancel","eventType":"AGREE"}}"#, #"{"code":200,"data":{"status":"WAITING","executeAfter":"server-date"}}"#]); let (service, _, _) = try build(fake, context: context)
        let auth = ComplianceAuthFake(); var invalidated: ComplianceSession?
        let coordinator = AccountComplianceCoordinator(service: service, auth: auth, effects: ComplianceEffectsFake(), current: { context.session }, invalidateSession: { invalidated = $0; context.session = nil })
        await coordinator.load(); await coordinator.precheckAndAgree(documentRead: true, explicitAgreement: true)
        auth.failSMS = true; await coordinator.sendSMS(phone: "13800000000", explicitlyRequested: true)
        XCTAssertFalse(coordinator.state.smsSent)
        coordinator.prepareReview(code: "123456"); XCTAssertEqual(coordinator.state.step, .verify)
        auth.failSMS = false; await coordinator.sendSMS(phone: "13800000000", explicitlyRequested: true)
        coordinator.prepareReview(code: "123456"); await coordinator.apply(explicitlyConfirmed: true)
        XCTAssertEqual(invalidated, original); XCTAssertEqual(coordinator.state.step, .freshLogin)
    }
    func testRoamPartialFailureResumesWithoutSecondWrite() async throws {
        let context = ComplianceTestContext(); let fake = ComplianceHTTPFake([#"{"code":200}"#, #"{"code":200}"#, #"{"code":200,"data":{"docType":"privacy_policy","scene":"roam_location","eventType":"REVOKE"}}"#]); let (service, _, _) = try build(fake, context: context)
        let effects = ComplianceEffectsFake(); effects.failStop = true
        let coordinator = AccountComplianceCoordinator(service: service, auth: ComplianceAuthFake(), effects: effects, current: { context.session }, invalidateSession: { _ in })
        await coordinator.revokeRoam(explicitlyConfirmed: true)
        XCTAssertEqual(coordinator.state.roamCleanup, .serverConfirmed); XCTAssertEqual(effects.calls, ["stop"])
        effects.failStop = false; effects.failClear = true; await coordinator.revokeRoam(explicitlyConfirmed: true)
        XCTAssertEqual(coordinator.state.roamCleanup, .trackingStopped); XCTAssertEqual(effects.calls, ["stop", "stop", "clear", "invalidate"])
        effects.failClear = false; await coordinator.revokeRoam(explicitlyConfirmed: true)
        XCTAssertEqual(coordinator.state.roamCleanup, .complete); XCTAssertEqual(fake.requests.count, 3)
    }
    func testFreshLoginAllowsCancelWithStatusReadback() async throws {
        let context = ComplianceTestContext(); let fake = ComplianceHTTPFake([#"{"code":200,"data":{"status":"WAITING","executeAfter":"server-date"}}"#, #"{"code":200,"data":{"status":"WAITING","executeAfter":"server-date"}}"#, #"{"code":200,"data":{"status":"NORMAL"}}"#, #"{"code":200,"data":{"status":"NORMAL"}}"#]); let (service, journal, _) = try build(fake, context: context)
        _ = try await service.apply(smscode: "123456", requestID: "fixture", session: context.session!)
        context.session = .init(accountID: 7, epoch: 2, market: "CN", namespace: "test")
        let result = try await service.cancel(session: context.session!)
        XCTAssertEqual(result.status, "NORMAL"); XCTAssertNil(try journal.pending(scope: context.session!.journalScope, operation: "deregister"))
        XCTAssertEqual(fake.requests.map { $0.url!.path }, ["/api/user/deregister/apply", "/api/user/deregister/status", "/api/user/deregister/cancel", "/api/user/deregister/status"])
    }
}
