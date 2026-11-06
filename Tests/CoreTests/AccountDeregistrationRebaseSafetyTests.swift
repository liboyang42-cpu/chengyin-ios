import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class C08SafetyWire: HTTPTransport {
    var requests: [URLRequest] = []
    var reply: (URLRequest) throws -> (Data, Int) = { _ in (Data(#"{"code":200,"data":{"status":"NORMAL"}}"#.utf8), 200) }
    var beforeReply: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeReply?(); return try reply(request)
    }
}
@MainActor private final class C08SafetyJournal: ComplianceJournaling {
    let isDurable = true
    var rows: [CompliancePendingOperation] = []
    func pending(scope: String, operation: String) throws -> CompliancePendingOperation? {
        let found = rows.filter { $0.scope == scope && $0.operation == operation }
        guard found.count <= 1 else { throw ComplianceFailure.malformed }; return found.first
    }
    func begin(_ value: CompliancePendingOperation) throws {
        guard try pending(scope: value.scope, operation: value.operation) == nil else { throw ComplianceFailure.unresolved }; rows.append(value)
    }
    func resolve(scope: String, operation: String) throws { rows.removeAll { $0.scope == scope && $0.operation == operation } }
}
@MainActor private final class C08SafetyAuth: AuthChannelServing {
    var sms = 0
    func sendSMSCode(phone: String) async throws { sms += 1 }
    func loginWithPhone(phone: String, code: String) async throws -> LoginResult { throw ComplianceFailure.unavailable }
    func loginWithApple(identityToken: String) async throws -> LoginResult { throw ComplianceFailure.unavailable }
    func currentAccount(token: String) async throws -> Account { throw ComplianceFailure.unavailable }
}
@MainActor private final class C08SafetyEffects: ComplianceRoamEffects {
    func stopTracking() async throws {}
    func clearMapPrivacy() async throws {}
    func invalidateMapPrivacyCaches() {}
}
@MainActor private final class C08SafetyFixture {
    let wire = C08SafetyWire(), journal = C08SafetyJournal(), auth = C08SafetyAuth()
    let url = URL(string: "https://c08.example.test/native")!
    var context: RuntimeDependencyContext
    var session: ComplianceSession? = .init(accountID: 7, epoch: 2, market: "CN", namespace: "fixture")
    var active = true, unauthorized = 0, logout = 0
    var client: AccountDeregistrationOriginalClient!
    lazy var service = AccountComplianceService(configuration: try! APIConfiguration(baseURL: url), transport: wire,
        journal: journal, current: { self.session }, token: { self.context.session.token }, deregistrationOriginal: { self.client })
    lazy var coordinator = AccountComplianceCoordinator(service: service, auth: auth, effects: C08SafetyEffects(),
        current: { self.session }, invalidateSession: { _ in self.logout += 1 })
    init(scoped: Bool = false, writes: Bool = false) throws {
        context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://c08.example.test/native")!, role: "player",
            session: try .init(accountID: 7, epoch: 2, namespace: "fixture", token: "synthetic-token", role: "player"))
        let approval = try AccountDeregistrationOriginalApproval(endpoint: .init(baseURL: url, namespace: "fixture", accountID: 7,
            paths: AccountDeregistrationOriginalClient.readPaths.union(writes ? AccountDeregistrationOriginalClient.writePaths : [])), writes: writes, legalApproved: writes, issuanceID: UUID())
        let captured = context
        let transport: any HTTPTransport = scoped ? AccountDeregistrationScopedTransport(context: captured, approval: approval,
            underlying: wire, current: { self.context }, stillApproved: { self.active }) : wire
        client = AccountDeregistrationOriginalClient(context: captured, approval: approval, transport: transport,
            current: { self.context }, stillApproved: { self.active }, onUnauthorized: { self.unauthorized += 1 })
    }
    func replaceContext(account: Int = 7, epoch: UInt64 = 2, role: String = "player", sessionRole: String = "player", token: String = "synthetic-token", namespace: String = "fixture", base: String? = nil) throws {
        context = RuntimeDependencyContext(market: .china, baseURL: base.flatMap(URL.init(string:)) ?? url, role: role,
            session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token, role: sessionRole))
    }
    static var impact: [String: Any] {
        ["schemaVersion": 1, "actorId": 7, "revision": String(repeating: "a", count: 64),
         "items": [["key": "BALANCE", "value": "0", "source": "synthetic-ledger", "effect": "synthetic-effect"]], "unknownCoverage": []]
    }
    func prepareOriginalJourney(verification: String = "SMS", loseApplyResponse: Bool = false) {
        var applied = false
        wire.reply = { request in
            var data: [String: Any]
            switch request.url!.lastPathComponent {
            case "status": data = ["status": applied ? "PENDING" : "NORMAL"]
            case "precheck": data = ["status": "ELIGIBLE", "verificationMethod": verification, "impact": Self.impact]
            case "consents":
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
                data = ["requestId": body["requestId"]!, "docType": "account_cancellation_notice", "scene": "account_cancel", "eventType": "AGREE", "docVersion": "synthetic-v1"]
            case "result":
                let id = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.first!.value!
                data = ["receiptVersion": 1, "actorId": 7, "requestId": id, "outcome": applied ? "ACCEPTED" : "UNKNOWN"]
                if applied {
                    data.merge(["applicationId": 9, "appliedAt": 1, "executeAfterAtAcceptance": 2, "recordedAt": 3, "impactAtConfirmation": Self.impact]) { _, new in new }
                }
            case "apply":
                let pending = try self.journal.pending(scope: self.session!.journalScope, operation: "deregister")
                XCTAssertNotNil(pending, "Durable original intent must exist before dispatch")
                XCTAssertEqual(pending?.deregistrationImpactRevision, String(repeating: "a", count: 64))
                applied = true
                if loseApplyResponse { throw URLError(.timedOut) }
                data = [:]
            default: XCTFail("Unexpected path"); throw ComplianceFailure.unavailable
            }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
        }
    }
    func reachReview() async {
        await coordinator.load()
        await coordinator.precheckAndAgree(documentRead: true, explicitAgreement: true, expectedConsentVersion: "synthetic-v1")
        await coordinator.sendSMS(phone: "13800000000", explicitlyRequested: true)
        coordinator.prepareReview(code: "123456")
    }
    func originalIntent() -> CompliancePendingOperation {
        .init(scope: session!.journalScope, operation: "deregister", requestID: "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa", epoch: 1,
              deregistrationRealm: url.absoluteString, deregistrationOriginalVersion: 1)
    }
}

/// Synthetic local sources only. No runtime grant, credential, or business operation is exercised here.
@MainActor final class AccountDeregistrationRebaseSafetyTests: XCTestCase {
    func testLateRevokedHTTPAndBusiness401NeverInvokeUnauthorized() async throws {
        for scoped in [false, true] { for status in [401, 200] {
            let f = try C08SafetyFixture(scoped: scoped)
            f.wire.beforeReply = { f.active = false }
            f.wire.reply = { _ in (Data(#"{"code":401,"data":null}"#.utf8), status) }
            do { _ = try await f.client.status(session: f.session!); XCTFail() } catch {}
            XCTAssertEqual(f.unauthorized, 0); XCTAssertEqual(f.wire.requests.count, 1)
        } }
    }
    func testCurrentHTTPAndBusiness401StillInvokeUnauthorizedOnce() async throws {
        for status in [401, 200] {
            let f = try C08SafetyFixture(scoped: true)
            f.wire.reply = { _ in (Data(#"{"code":401,"data":null}"#.utf8), status) }
            do { _ = try await f.client.status(session: f.session!); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .unauthorized) }
            XCTAssertEqual(f.unauthorized, 1)
        }
    }
    func testCancelledLate401DoesNotInvokeUnauthorized() async throws {
        let f = try C08SafetyFixture()
        var task: Task<Void, Never>?
        f.wire.beforeReply = { task?.cancel() }
        f.wire.reply = { _ in (Data(), 401) }
        task = Task { do { _ = try await f.client.status(session: f.session!); XCTFail() } catch {} }
        await task?.value
        XCTAssertEqual(f.unauthorized, 0); XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testIdentityAndRealmChangesBeforeResponseRejectEven401() async throws {
        for change in ["account", "epoch", "role", "sessionRole", "token", "namespace", "origin"] {
            let f = try C08SafetyFixture()
            f.wire.beforeReply = {
                switch change {
                case "account": try! f.replaceContext(account: 8)
                case "epoch": try! f.replaceContext(epoch: 3)
                case "role": try! f.replaceContext(role: "merchant", sessionRole: "merchant")
                case "sessionRole": try! f.replaceContext(sessionRole: "merchant")
                case "token": try! f.replaceContext(token: "another-synthetic-token")
                case "namespace": try! f.replaceContext(namespace: "other")
                default: try! f.replaceContext(base: "https://other.example.test/native")
                }
            }
            f.wire.reply = { _ in (Data(), 401) }
            do { _ = try await f.client.status(session: f.session!); XCTFail(change) } catch {}
            XCTAssertEqual(f.unauthorized, 0, change)
        }
    }
    func testReadOnlyApprovalDoesNotEnablePrecheckConsentApplyOrCancelRoute() async throws {
        let f = try C08SafetyFixture(scoped: true)
        do { _ = try await f.client.precheck(session: f.session!); XCTFail() } catch {}
        for path in ["api/user/deregister/apply", "api/user/deregister/cancel", "api/compliance/consents"] {
            var request = URLRequest(url: f.url.appendingPathComponent(path)); request.httpMethod = "POST"
            request.httpShouldHandleCookies = false; request.setValue("synthetic-token", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            XCTAssertFalse(AccountDeregistrationOriginalClient.accepts(request, context: f.context, approval: f.client.approval))
        }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }
    func testAcceptedOriginalAndCurrentCompletedShowTerminalWithoutDeletingOriginalJournal() async throws {
        let f = try C08SafetyFixture(); let intent = f.originalIntent(); f.journal.rows = [intent]
        f.wire.reply = { request in
            let data: [String: Any] = request.url!.path.hasSuffix("/result")
                ? ["receiptVersion": 1, "actorId": 7, "requestId": intent.requestID, "outcome": "ACCEPTED", "applicationId": 9,
                   "appliedAt": 1, "executeAfterAtAcceptance": 2, "recordedAt": 3]
                : ["status": "COMPLETED", "executeAfter": "2026-11-01T12:00:00Z"]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
        }
        await f.coordinator.load()
        XCTAssertEqual(f.coordinator.state.step, .completed)
        XCTAssertTrue(f.coordinator.state.originalApplication?.accepted == true)
        XCTAssertEqual(f.journal.rows, [intent]); XCTAssertEqual(f.logout, 0)
        XCTAssertEqual(f.wire.requests.map(\.httpMethod), ["GET", "GET"])
    }
    func testOldPresentationCloseDoesNotInvalidateNewOwner() throws {
        let f = try C08SafetyFixture(); let old = f.coordinator.beginDeregistrationPresentation()
        let new = f.coordinator.beginDeregistrationPresentation()
        let intent = try XCTUnwrap(f.coordinator.captureDeregistrationIntent(new))
        f.coordinator.pauseDeregistrationPresentation(old)
        XCTAssertTrue(f.coordinator.ownsDeregistrationPresentation(new))
        XCTAssertTrue(f.coordinator.isCurrentDeregistrationIntent(intent))
        XCTAssertFalse(f.coordinator.resumeDeregistrationPresentation(old))
    }
    func testPausedQueuedReadNeverSendsAndResumeRequiresNewIntent() async throws {
        let f = try C08SafetyFixture(); let owner = f.coordinator.beginDeregistrationPresentation()
        let old = try XCTUnwrap(f.coordinator.captureDeregistrationIntent(owner))
        f.coordinator.pauseDeregistrationPresentation(owner)
        await f.coordinator.load(intent: old)
        XCTAssertTrue(f.wire.requests.isEmpty)
        XCTAssertTrue(f.coordinator.resumeDeregistrationPresentation(owner))
        XCTAssertFalse(f.coordinator.isCurrentDeregistrationIntent(old))
        await f.coordinator.load(intent: try XCTUnwrap(f.coordinator.captureDeregistrationIntent(owner)))
        XCTAssertEqual(f.wire.requests.count, 1)
    }
    func testRefreshInvalidatesPreviouslyCapturedCancelConfirmation() async throws {
        let f = try C08SafetyFixture(); f.wire.reply = { _ in (Data(#"{"code":200,"data":{"status":"PENDING"}}"#.utf8), 200) }
        let owner = f.coordinator.beginDeregistrationPresentation()
        await f.coordinator.load(intent: try XCTUnwrap(f.coordinator.captureDeregistrationIntent(owner)))
        let oldConfirmation = try XCTUnwrap(f.coordinator.captureDeregistrationIntent(owner))
        await f.coordinator.load(intent: oldConfirmation)
        await f.coordinator.cancel(explicitlyConfirmed: true, intent: oldConfirmation)
        XCTAssertEqual(f.wire.requests.count, 2); XCTAssertTrue(f.wire.requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertTrue(f.journal.rows.isEmpty)
    }
    func testRetiredIntentCannotSendSMSApplyOrAgree() async throws {
        let f = try C08SafetyFixture(); let owner = f.coordinator.beginDeregistrationPresentation()
        let intent = try XCTUnwrap(f.coordinator.captureDeregistrationIntent(owner)); f.coordinator.invalidate()
        await f.coordinator.precheckAndAgree(documentRead: true, explicitAgreement: true, expectedConsentVersion: "v1", intent: intent)
        await f.coordinator.sendSMS(phone: "13800000000", explicitlyRequested: true, intent: intent)
        await f.coordinator.apply(explicitlyConfirmed: true, intent: intent)
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertEqual(f.auth.sms, 0); XCTAssertEqual(f.logout, 0)
    }
    func testChangedAccountCannotResumeOldPresentation() throws {
        let f = try C08SafetyFixture(); let owner = f.coordinator.beginDeregistrationPresentation()
        f.coordinator.pauseDeregistrationPresentation(owner)
        f.session = .init(accountID: 8, epoch: 3, market: "CN", namespace: "fixture")
        XCTAssertFalse(f.coordinator.resumeDeregistrationPresentation(owner)); XCTAssertNil(f.coordinator.captureDeregistrationIntent(owner))
    }
    func testNilOriginalSourceKeepsDefaultServiceClosed() async throws {
        let f = try C08SafetyFixture(); f.client = nil
        await f.coordinator.load()
        XCTAssertEqual(f.coordinator.state.error, "compliance.unavailable")
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertTrue(f.journal.rows.isEmpty)
    }
    func testLegacyJournalDecodesWithoutInventingOriginalMetadata() throws {
        let raw = #"{"scope":"fixture|CN|7","operation":"deregister","requestID":"old-reference","epoch":1}"#
        let row = try JSONDecoder().decode(CompliancePendingOperation.self, from: Data(raw.utf8))
        XCTAssertNil(row.deregistrationRealm); XCTAssertNil(row.deregistrationOriginalVersion); XCTAssertNil(row.deregistrationImpactRevision)
    }
    func testDuplicatedDurableRowsFailClosed() throws {
        let f = try C08SafetyFixture(), url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let row = f.originalIntent(); try JSONEncoder().encode([row, row]).write(to: url)
        let journal = ComplianceFileJournal(url: url)
        XCTAssertTrue(journal.isDurable)
        XCTAssertThrowsError(try journal.pending(scope: row.scope, operation: row.operation))
    }
    func testFullOriginalJourneyPersistsSameUUIDAndSeparatesAcceptedFromCompletion() async throws {
        let f = try C08SafetyFixture(scoped: true, writes: true); f.prepareOriginalJourney()
        await f.reachReview(); XCTAssertEqual(f.coordinator.state.step, .review)
        await f.coordinator.apply(explicitlyConfirmed: true)
        XCTAssertEqual(f.coordinator.state.step, .freshLogin); XCTAssertEqual(f.auth.sms, 1); XCTAssertEqual(f.logout, 1)
        let intent = try XCTUnwrap(f.journal.rows.first)
        XCTAssertEqual(f.journal.rows.count, 1); XCTAssertEqual(intent.operation, "deregister")
        let paths = f.wire.requests.map { $0.url!.lastPathComponent }
        XCTAssertEqual(paths, ["status", "precheck", "consents", "result", "apply", "result", "status"])
        let requests = f.wire.requests.filter { $0.url!.lastPathComponent == "result" }
        XCTAssertTrue(requests.allSatisfy { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems == [.init(name: "requestId", value: intent.requestID)] })
        let application = try XCTUnwrap(f.wire.requests.first { $0.url!.lastPathComponent == "apply" })
        XCTAssertEqual(application.value(forHTTPHeaderField: "X-Account-Deregistration-Original"), "1")
        XCTAssertTrue(String(decoding: application.httpBody!, as: UTF8.self).contains(intent.requestID))
        let calls = f.wire.requests.count; await f.coordinator.apply(explicitlyConfirmed: true)
        XCTAssertEqual(f.wire.requests.count, calls)
    }
    func testLostOriginalApplyResponseKeepsUUIDAndOnlyRecoversByGETAfterFreshLogin() async throws {
        let f = try C08SafetyFixture(writes: true); f.prepareOriginalJourney(loseApplyResponse: true)
        await f.reachReview(); await f.coordinator.apply(explicitlyConfirmed: true)
        XCTAssertEqual(f.coordinator.state.step, .unknown); let intent = try XCTUnwrap(f.journal.rows.first)
        XCTAssertEqual(f.wire.requests.filter { $0.url!.lastPathComponent == "apply" }.count, 1)
        f.session = .init(accountID: 7, epoch: 3, market: "CN", namespace: "fixture"); try f.replaceContext(epoch: 3)
        let captured = f.context, approval = f.client.approval
        f.client = AccountDeregistrationOriginalClient(context: captured, approval: approval, transport: f.wire,
            current: { f.context }, stillApproved: { f.active }, onUnauthorized: { f.unauthorized += 1 })
        f.coordinator.invalidate(); let count = f.wire.requests.count; await f.coordinator.load()
        XCTAssertEqual(f.coordinator.state.step, .pending); XCTAssertEqual(f.coordinator.state.originalApplicationRequestID, intent.requestID)
        XCTAssertEqual(f.journal.rows, [intent]); XCTAssertEqual(f.wire.requests.dropFirst(count).map(\.httpMethod), ["GET", "GET"])
        await f.coordinator.cancel(explicitlyConfirmed: true)
        XCTAssertFalse(f.wire.requests.contains { $0.url!.lastPathComponent == "cancel" })
        XCTAssertEqual(f.journal.rows, [intent]) // Original apply approval never authorizes cancel.
    }
    func testOriginalNonSMSVerificationStopsBeforeConsentAndSMS() async throws {
        for verification in ["WECHAT", "UNAVAILABLE"] {
            let f = try C08SafetyFixture(writes: true); f.prepareOriginalJourney(verification: verification)
            await f.reachReview(); await f.coordinator.apply(explicitlyConfirmed: true)
            XCTAssertEqual(f.coordinator.state.step, .verificationUnavailable)
            XCTAssertEqual(f.wire.requests.map { $0.url!.lastPathComponent }, ["status", "precheck"])
            XCTAssertEqual(f.auth.sms, 0); XCTAssertTrue(f.journal.rows.isEmpty)
        }
    }
    func testUnconfirmedOrForeignImpactCannotRecordConsent() async throws {
        for field in ["actor", "coverage", "revision"] {
            let f = try C08SafetyFixture(writes: true)
            f.wire.reply = { request in
                var impact = C08SafetyFixture.impact
                if field == "actor" { impact["actorId"] = 8 }
                if field == "coverage" { impact["unknownCoverage"] = ["unconfirmed-fixture"] }
                if field == "revision" { impact["revision"] = "bad" }
                let data: [String: Any] = request.url!.lastPathComponent == "status" ? ["status": "NORMAL"] : ["status": "ELIGIBLE", "impact": impact]
                return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
            }
            await f.reachReview(); XCTAssertEqual(f.coordinator.state.step, .blocked)
            XCTAssertEqual(f.auth.sms, 0); XCTAssertTrue(f.journal.rows.isEmpty)
            XCTAssertFalse(f.wire.requests.contains { $0.url!.lastPathComponent == "consents" })
        }
    }

}
