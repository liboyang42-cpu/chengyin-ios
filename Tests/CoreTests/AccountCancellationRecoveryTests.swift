import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class CancellationRecoveryHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    var responses: [String?]
    var afterSend: ((Int) -> Void)?
    var pauseAtRequest: Int?
    var continuation: CheckedContinuation<Void, Never>?
    init(_ responses: [String?]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        afterSend?(requests.count)
        if pauseAtRequest == requests.count { await withCheckedContinuation { continuation = $0 } }
        guard !responses.isEmpty, let response = responses.removeFirst() else { throw URLError(.timedOut) }
        return (Data(response.utf8), 200)
    }
}
@MainActor private final class CancellationRecoveryContext {
    var session: ComplianceSession? = .init(accountID: 71, epoch: 2, market: "CN", namespace: "fixture")
    var visible = true
}
@MainActor private final class CancellationRecoveryAuth: AuthChannelServing {
    func sendSMSCode(phone: String) async throws { throw ComplianceFailure.unavailable }
    func loginWithPhone(phone: String, code: String) async throws -> LoginResult { throw ComplianceFailure.unavailable }
    func loginWithApple(identityToken: String) async throws -> LoginResult { throw ComplianceFailure.unavailable }
    func currentAccount(token: String) async throws -> Account { throw ComplianceFailure.unavailable }
}
@MainActor private final class CancellationRecoveryEffects: ComplianceRoamEffects {
    func stopTracking() async throws { XCTFail("Cancellation must not operate roam tracking") }
    func clearMapPrivacy() async throws { XCTFail("Cancellation must not operate map privacy") }
    func invalidateMapPrivacyCaches() { XCTFail("Cancellation must not operate map privacy") }
}

@MainActor final class AccountCancellationRecoveryTests: XCTestCase {
    private func response(_ status: String) -> String {
        #"{"code":200,"data":{"status":"\#(status)","executeAfter":"server-date","blockers":[]}}"#
    }
    private func build(_ fake: CancellationRecoveryHTTP, context: CancellationRecoveryContext,
                       url: URL? = nil, enabled: Bool = true) throws -> (AccountComplianceService, ComplianceFileJournal, URL) {
        let location = url ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("operations.json")
        let journal = ComplianceFileJournal(url: location)
        let service = AccountComplianceService(configuration: try APIConfiguration(baseURL: URL(string: "https://fixture.example")!),
            transport: fake, journal: journal, current: { context.session }, token: { "synthetic-token" },
            readsEnabled: enabled, writesEnabled: enabled, legalApproved: { _, _ in false })
        return (service, journal, location)
    }
    private func seed(_ journal: ComplianceFileJournal, session: ComplianceSession, cancellation: Bool = true) throws {
        try journal.begin(.init(scope: session.journalScope, operation: "deregister", requestID: "original-application", epoch: 1))
        if cancellation { try journal.begin(.init(scope: session.journalScope, operation: "deregisterCancel", requestID: "original-cancellation", epoch: session.epoch)) }
    }
    private func coordinator(_ service: AccountComplianceService, context: CancellationRecoveryContext) -> AccountComplianceCoordinator {
        AccountComplianceCoordinator(service: service, auth: CancellationRecoveryAuth(), effects: CancellationRecoveryEffects(),
            current: { context.session }, invalidateSession: { _ in XCTFail("Cancellation must not expire the new session") })
    }
    private func assertCancelPending(_ journal: ComplianceFileJournal, session: ComplianceSession,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertNotNil(try journal.pending(scope: session.journalScope, operation: "deregisterCancel"), file: file, line: line)
    }

    func testOnlyExplicitPendingIsCancellableEvenWhenDateRemains() throws {
        for status in ["NORMAL", "CANCELLED", "COMPLETED", "FAILED", "WAITING", "UNKNOWN"] {
            let value = try JSONDecoder().decode(ComplianceDeregistration.self, from: Data("{\"status\":\"\(status)\",\"executeAfter\":\"server-date\"}".utf8))
            XCTAssertFalse(value.pending, status)
            XCTAssertEqual(value.completed, status == "COMPLETED")
            XCTAssertEqual(value.cancellationConfirmed, status == "CANCELLED")
        }
        let pending = try JSONDecoder().decode(ComplianceDeregistration.self, from: Data(#"{"status":"PENDING"}"#.utf8))
        XCTAssertTrue(pending.pending)
    }
    func testCancelUsesBackendCancelledResponseAndFreshStatus() async throws {
        let context = CancellationRecoveryContext(); let session = context.session!
        let fake = CancellationRecoveryHTTP([response("PENDING"), response("CANCELLED"), response("CANCELLED")])
        let (service, journal, _) = try build(fake, context: context); try seed(journal, session: session, cancellation: false)
        let result = try await service.cancel(session: session)
        XCTAssertTrue(result.cancellationConfirmed)
        XCTAssertNil(try journal.pending(scope: session.journalScope, operation: "deregisterCancel"))
        XCTAssertNil(try journal.pending(scope: session.journalScope, operation: "deregister"))
        XCTAssertEqual(fake.requests.map(\.httpMethod), ["GET", "POST", "GET"])
        XCTAssertEqual(fake.requests.map { $0.url!.path }, ["/api/user/deregister/status", "/api/user/deregister/cancel", "/api/user/deregister/status"])
    }
    func testNormalCancelResponseNeverClaimsCancellationSucceeded() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([response("PENDING"), response("NORMAL")])
        let (service, journal, _) = try build(fake, context: context)
        do { _ = try await service.cancel(session: context.session!); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .readbackMismatch) }
        try assertCancelPending(journal, session: context.session!)
    }
    func testPendingReadbackAfterCancelledResponsePreservesIntent() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([response("PENDING"), response("CANCELLED"), response("PENDING")])
        let (service, journal, _) = try build(fake, context: context)
        do { _ = try await service.cancel(session: context.session!); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .readbackMismatch) }
        try assertCancelPending(journal, session: context.session!)
    }
    func testLostCancelResponseSurvivesRecreationThenReadsOnly() async throws {
        let context = CancellationRecoveryContext(); let session = context.session!
        let fake = CancellationRecoveryHTTP([response("PENDING"), nil]); let (service, journal, url) = try build(fake, context: context)
        try seed(journal, session: session, cancellation: false)
        do { _ = try await service.cancel(session: session); XCTFail() } catch { }
        try assertCancelPending(journal, session: session)
        let recoveredHTTP = CancellationRecoveryHTTP([response("CANCELLED")])
        let (recreated, recoveredJournal, _) = try build(recoveredHTTP, context: context, url: url)
        let result = try await recreated.recoverDeregistrationStatus(session: session)
        XCTAssertTrue(result.cancellationConfirmed)
        XCTAssertEqual(recoveredHTTP.requests.map(\.httpMethod), ["GET"])
        XCTAssertNil(try recoveredJournal.pending(scope: session.journalScope, operation: "deregisterCancel"))
        XCTAssertNil(try recoveredJournal.pending(scope: session.journalScope, operation: "deregister"))
    }
    func testNormalPendingCompletedFailedAndUnknownKeepOriginalCancel() async throws {
        for status in ["NORMAL", "PENDING", "COMPLETED", "FAILED", "WAITING", "UNKNOWN"] {
            let context = CancellationRecoveryContext(); let session = context.session!
            let fake = CancellationRecoveryHTTP([response(status)]); let (service, journal, _) = try build(fake, context: context)
            try seed(journal, session: session)
            let result = try await service.recoverDeregistrationStatus(session: session)
            XCTAssertEqual(result.status, status)
            XCTAssertEqual(try journal.pending(scope: session.journalScope, operation: "deregisterCancel")?.requestID, "original-cancellation")
            XCTAssertNotNil(try journal.pending(scope: session.journalScope, operation: "deregister"))
            XCTAssertEqual(fake.requests.map(\.httpMethod), ["GET"])
        }
    }
    func testPendingCancelCannotDispatchAgain() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([])
        let (service, journal, _) = try build(fake, context: context); try seed(journal, session: context.session!)
        do { _ = try await service.cancel(session: context.session!); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .unresolved) }
        XCTAssertTrue(fake.requests.isEmpty)
    }
    func testFailedRecoveryReadRetainsIntentForAnotherRead() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([nil, response("CANCELLED")])
        let (service, journal, _) = try build(fake, context: context); try seed(journal, session: context.session!)
        do { _ = try await service.recoverDeregistrationStatus(session: context.session!); XCTFail() } catch { }
        try assertCancelPending(journal, session: context.session!)
        _ = try await service.recoverDeregistrationStatus(session: context.session!)
        XCTAssertEqual(fake.requests.map(\.httpMethod), ["GET", "GET"])
        XCTAssertNil(try journal.pending(scope: context.session!.journalScope, operation: "deregisterCancel"))
    }
    func testAccountSwitchDuringRecoveryCannotResolveOldJournal() async throws {
        let context = CancellationRecoveryContext(); let original = context.session!
        let fake = CancellationRecoveryHTTP([response("CANCELLED")]); let (service, journal, _) = try build(fake, context: context)
        try seed(journal, session: original)
        fake.afterSend = { _ in context.session = .init(accountID: 72, epoch: 3, market: "CN", namespace: "fixture") }
        do { _ = try await service.recoverDeregistrationStatus(session: original); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .staleSession) }
        try assertCancelPending(journal, session: original)
    }
    func testCloseDuringPreflightDoesNotDispatchCancel() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([response("PENDING")])
        let (service, journal, _) = try build(fake, context: context)
        fake.afterSend = { _ in context.visible = false }
        do { _ = try await service.cancel(session: context.session!, whileCurrent: { context.visible }); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .staleSession) }
        XCTAssertEqual(fake.requests.map(\.httpMethod), ["GET"])
        XCTAssertNil(try journal.pending(scope: context.session!.journalScope, operation: "deregisterCancel"))
    }
    func testCloseDuringCancelResponseKeepsPendingAndSkipsReadback() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([response("PENDING"), response("CANCELLED")])
        let (service, journal, _) = try build(fake, context: context)
        fake.afterSend = { count in if count == 2 { context.visible = false } }
        do { _ = try await service.cancel(session: context.session!, whileCurrent: { context.visible }); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .staleSession) }
        try assertCancelPending(journal, session: context.session!)
        XCTAssertEqual(fake.requests.map(\.httpMethod), ["GET", "POST"])
    }
    func testCloseDuringCancellationReadbackCannotResolveJournal() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([response("PENDING"), response("CANCELLED"), response("CANCELLED")])
        let (service, journal, _) = try build(fake, context: context)
        fake.afterSend = { count in if count == 3 { context.visible = false } }
        do { _ = try await service.cancel(session: context.session!, whileCurrent: { context.visible }); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .staleSession) }
        try assertCancelPending(journal, session: context.session!)
    }
    func testCoordinatorCloseDuringRecoveryDoesNotResolveOrShowOldResult() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([response("CANCELLED")])
        let (service, journal, _) = try build(fake, context: context); try seed(journal, session: context.session!)
        let model = coordinator(service, context: context)
        fake.afterSend = { _ in model.invalidate() }
        await model.load()
        XCTAssertEqual(model.state.step, .idle); XCTAssertNil(model.state.status)
        try assertCancelPending(journal, session: context.session!)
    }
    func testCoordinatorCloseDuringCancelPreflightNeverPosts() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([response("PENDING"), response("PENDING")])
        let (service, _, _) = try build(fake, context: context); let model = coordinator(service, context: context)
        await model.load()
        fake.afterSend = { _ in model.invalidate() }
        await model.cancel(explicitlyConfirmed: true)
        XCTAssertEqual(model.state.step, .idle)
        XCTAssertEqual(fake.requests.map(\.httpMethod), ["GET", "GET"])
    }
    func testCoordinatorUnknownCancelRefreshRecoversWithoutRepost() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([response("PENDING"), response("PENDING"), nil, response("CANCELLED")])
        let (service, journal, _) = try build(fake, context: context); let model = coordinator(service, context: context)
        await model.load(); await model.cancel(explicitlyConfirmed: true)
        XCTAssertEqual(model.state.step, .unknown)
        await model.cancel(explicitlyConfirmed: true)
        XCTAssertEqual(fake.requests.count, 3)
        await model.load()
        XCTAssertEqual(model.state.step, .notice); XCTAssertEqual(model.state.status?.status, "CANCELLED")
        XCTAssertNil(try journal.pending(scope: context.session!.journalScope, operation: "deregisterCancel"))
        XCTAssertEqual(fake.requests.map(\.httpMethod), ["GET", "GET", "POST", "GET"])
    }
    func testCoordinatorPendingUnknownCancellationHasNoCancelAction() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([response("PENDING")])
        let (service, journal, _) = try build(fake, context: context); try seed(journal, session: context.session!)
        let model = coordinator(service, context: context); await model.load()
        XCTAssertEqual(model.state.step, .unknown)
        await model.cancel(explicitlyConfirmed: true)
        XCTAssertEqual(fake.requests.count, 1)
    }
    func testCompletedAccountHasTerminalPresentationNotCancel() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([response("COMPLETED")])
        let (service, _, _) = try build(fake, context: context); let model = coordinator(service, context: context)
        await model.load(); XCTAssertEqual(model.state.step, .completed)
        await model.cancel(explicitlyConfirmed: true)
        XCTAssertEqual(fake.requests.map(\.httpMethod), ["GET"])
    }
    func testSameEpochPendingApplicationRequiresFreshLogin() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([response("PENDING")])
        let (service, journal, _) = try build(fake, context: context); let session = context.session!
        try journal.begin(.init(scope: session.journalScope, operation: "deregister", requestID: "original-application", epoch: session.epoch))
        let model = coordinator(service, context: context); await model.load()
        XCTAssertEqual(model.state.step, .freshLogin)
        await model.cancel(explicitlyConfirmed: true)
        XCTAssertEqual(fake.requests.count, 1)
    }
    func testDefiniteBusinessRejectionClearsOnlyCancelLock() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([response("PENDING"), #"{"code":409,"msg":"state changed"}"#])
        let (service, journal, _) = try build(fake, context: context); try seed(journal, session: context.session!, cancellation: false)
        do { _ = try await service.cancel(session: context.session!); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .rejected("state changed")) }
        XCTAssertNil(try journal.pending(scope: context.session!.journalScope, operation: "deregisterCancel"))
        XCTAssertNotNil(try journal.pending(scope: context.session!.journalScope, operation: "deregister"))
    }
    func testCloseDuringBusinessRejectionCannotResolveCancelLock() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([response("PENDING"), #"{"code":409,"msg":"state changed"}"#])
        let (service, journal, _) = try build(fake, context: context)
        fake.afterSend = { count in if count == 2 { context.visible = false } }
        do { _ = try await service.cancel(session: context.session!, whileCurrent: { context.visible }); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .staleSession) }
        try assertCancelPending(journal, session: context.session!)
    }
    func testReadGateOffPreservesJournalAndDoesNotSend() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([])
        let (service, journal, _) = try build(fake, context: context, enabled: false); try seed(journal, session: context.session!)
        do { _ = try await service.recoverDeregistrationStatus(session: context.session!); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .unavailable) }
        try assertCancelPending(journal, session: context.session!)
        XCTAssertTrue(fake.requests.isEmpty)
    }
    func testCorruptJournalDoesNotDispatchRecoveryOrResetIntent() async throws {
        let context = CancellationRecoveryContext(); let fake = CancellationRecoveryHTTP([])
        let (service, _, url) = try build(fake, context: context)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("invalid-journal".utf8).write(to: url)
        do { _ = try await service.recoverDeregistrationStatus(session: context.session!); XCTFail() } catch { }
        XCTAssertTrue(fake.requests.isEmpty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "invalid-journal")
    }

    func testRecoveryDoesNotClearApplicationCreatedWhileReadWasInFlight() async throws {
        let context = CancellationRecoveryContext(); let session = context.session!
        let fake = CancellationRecoveryHTTP([response("CANCELLED")]); let (service, journal, _) = try build(fake, context: context)
        try journal.begin(.init(scope: session.journalScope, operation: "deregisterCancel", requestID: "original-cancellation", epoch: 2))
        fake.afterSend = { _ in try! journal.begin(.init(scope: session.journalScope, operation: "deregister", requestID: "new-application", epoch: 3)) }
        do { _ = try await service.recoverDeregistrationStatus(session: session); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .unresolved) }
        XCTAssertEqual(try journal.pending(scope: session.journalScope, operation: "deregister")?.requestID, "new-application")
        try assertCancelPending(journal, session: session)
    }
    func testRecoveryDoesNotClearReplacementCancellation() async throws {
        let context = CancellationRecoveryContext(); let session = context.session!
        let fake = CancellationRecoveryHTTP([response("CANCELLED")]); let (service, journal, _) = try build(fake, context: context)
        try seed(journal, session: session)
        fake.afterSend = { _ in
            try! journal.resolve(scope: session.journalScope, operation: "deregisterCancel")
            try! journal.begin(.init(scope: session.journalScope, operation: "deregisterCancel", requestID: "replacement-cancellation", epoch: 3))
        }
        do { _ = try await service.recoverDeregistrationStatus(session: session); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .unresolved) }
        XCTAssertEqual(try journal.pending(scope: session.journalScope, operation: "deregisterCancel")?.requestID, "replacement-cancellation")
        XCTAssertNotNil(try journal.pending(scope: session.journalScope, operation: "deregister"))
    }
    func testApplicationReplacementDuringCancelPreflightDoesNotPost() async throws {
        let context = CancellationRecoveryContext(); let session = context.session!
        let fake = CancellationRecoveryHTTP([response("PENDING")]); let (service, journal, _) = try build(fake, context: context)
        fake.afterSend = { _ in try! journal.begin(.init(scope: session.journalScope, operation: "deregister", requestID: "new-application", epoch: 3)) }
        do { _ = try await service.cancel(session: session); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .unresolved) }
        XCTAssertEqual(fake.requests.map(\.httpMethod), ["GET"])
        XCTAssertEqual(try journal.pending(scope: session.journalScope, operation: "deregister")?.requestID, "new-application")
    }
    func testApplicationReplacementDuringCancelReadbackIsRetained() async throws {
        let context = CancellationRecoveryContext(); let session = context.session!
        let fake = CancellationRecoveryHTTP([response("PENDING"), response("CANCELLED"), response("CANCELLED")])
        let (service, journal, _) = try build(fake, context: context); try seed(journal, session: session, cancellation: false)
        fake.afterSend = { count in
            if count == 3 {
                try! journal.resolve(scope: session.journalScope, operation: "deregister")
                try! journal.begin(.init(scope: session.journalScope, operation: "deregister", requestID: "new-application", epoch: 3))
            }
        }
        do { _ = try await service.cancel(session: session); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .unresolved) }
        XCTAssertEqual(try journal.pending(scope: session.journalScope, operation: "deregister")?.requestID, "new-application")
        try assertCancelPending(journal, session: session)
    }
    func testConcurrentCancelIsBlockedDuringPreflight() async throws {
        let context = CancellationRecoveryContext(); let session = context.session!
        let fake = CancellationRecoveryHTTP([response("PENDING"), response("CANCELLED"), response("CANCELLED")])
        fake.pauseAtRequest = 1
        let (service, _, _) = try build(fake, context: context)
        let first = Task { try await service.cancel(session: session) }
        while fake.continuation == nil { await Task.yield() }
        do { _ = try await service.cancel(session: session); XCTFail() }
        catch { XCTAssertEqual(error as? ComplianceFailure, .busy) }
        XCTAssertEqual(fake.requests.count, 1)
        fake.continuation?.resume(); fake.continuation = nil
        _ = try await first.value
        XCTAssertEqual(fake.requests.map(\.httpMethod), ["GET", "POST", "GET"])
    }
}
