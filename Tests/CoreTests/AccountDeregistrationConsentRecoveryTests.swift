import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class ConsentRecoveryHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    var handler: (URLRequest) throws -> (Data, Int) = { _ in throw URLError(.timedOut) }
    var afterSend: ((URLRequest) -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        afterSend?(request)
        return try handler(request)
    }
}
@MainActor private final class ConsentRecoveryJournal: ComplianceJournaling {
    let isDurable = true
    var rows: [CompliancePendingOperation] = []
    var failRead = false, failBegin = false, failResolve = false, retainOnResolve = false
    var begins = 0, resolves = 0
    func pending(scope: String, operation: String) throws -> CompliancePendingOperation? {
        if failRead { throw ComplianceFailure.malformed }
        let matches = rows.filter { $0.scope == scope && $0.operation == operation }
        guard matches.count <= 1 else { throw ComplianceFailure.malformed }
        return matches.first
    }
    func begin(_ operation: CompliancePendingOperation) throws {
        begins += 1
        if failBegin { throw ComplianceFailure.unavailable }
        guard try pending(scope: operation.scope, operation: operation.operation) == nil else { throw ComplianceFailure.unresolved }
        rows.append(operation)
    }
    func resolve(scope: String, operation: String) throws {
        resolves += 1
        if failResolve { throw ComplianceFailure.unavailable }
        if !retainOnResolve { rows.removeAll { $0.scope == scope && $0.operation == operation } }
    }
}
@MainActor private final class ConsentRecoveryAuth: AuthChannelServing {
    var smsCalls = 0
    func sendSMSCode(phone: String) async throws { smsCalls += 1 }
    func loginWithPhone(phone: String, code: String) async throws -> LoginResult { throw ComplianceFailure.unavailable }
    func loginWithApple(identityToken: String) async throws -> LoginResult { throw ComplianceFailure.unavailable }
    func currentAccount(token: String) async throws -> Account { throw ComplianceFailure.unavailable }
}
@MainActor private final class ConsentRecoveryEffects: ComplianceRoamEffects {
    func stopTracking() async throws {}
    func clearMapPrivacy() async throws {}
    func invalidateMapPrivacyCaches() {}
}
@MainActor private final class ConsentRecoveryFixture {
    nonisolated static let requestID = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa"
    let http = ConsentRecoveryHTTP(), journal = ConsentRecoveryJournal(), auth = ConsentRecoveryAuth()
    var session: ComplianceSession? = .init(accountID: 7, epoch: 1, market: "CN", namespace: "consent-fixture")
    var context: RuntimeDependencyContext
    var approved = true
    var client: AccountDeregistrationOriginalClient?
    lazy var service = AccountComplianceService(configuration: try! APIConfiguration(baseURL: context.baseURL), transport: http,
        journal: journal, current: { self.session }, token: { "synthetic-test-token" },
        deregistrationOriginal: { self.client })
    lazy var coordinator = AccountComplianceCoordinator(service: service, auth: auth, effects: ConsentRecoveryEffects(),
        current: { self.session }, invalidateSession: { _ in XCTFail("No real session invalidation in consent tests") })
    init() throws {
        let actor = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "consent-fixture", token: "synthetic-test-token")
        context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://consent.example.test")!, role: "player", session: actor)
        try replaceClient()
        http.handler = { request in
            if request.url!.path.hasSuffix("/status") { return try Self.envelope(["status": "NORMAL"]) }
            if request.url!.path.hasSuffix("/precheck") {
                return try Self.envelope(["status": "ELIGIBLE", "verificationMethod": "SMS", "impact": Self.impact])
            }
            let fields = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]
            return try Self.envelope(Self.ack(requestID: fields["requestId"]!))
        }
    }
    func replaceClient() throws {
        let endpoint = try OperationEndpointApproval(baseURL: context.baseURL, namespace: context.session.namespace,
            accountID: context.session.accountID, paths: AccountDeregistrationOriginalClient.readPaths.union(AccountDeregistrationOriginalClient.writePaths))
        let approval = try AccountDeregistrationOriginalApproval(endpoint: endpoint, writes: true, legalApproved: true, issuanceID: UUID())
        let captured = context
        client = AccountDeregistrationOriginalClient(context: captured, approval: approval, transport: http,
            current: { self.context }, stillApproved: { self.approved }, onUnauthorized: {})
    }
    nonisolated static var impact: [String: Any] {
        ["schemaVersion": 1, "actorId": 7, "revision": String(repeating: "a", count: 64),
         "items": [["key": "fixture", "value": "0", "source": "synthetic", "effect": "synthetic"]], "unknownCoverage": []]
    }
    nonisolated static func ack(requestID: String = ConsentRecoveryFixture.requestID) -> [String: Any] {
        ["requestId": requestID, "docType": "account_cancellation_notice", "docVersion": "displayed-fixture-v3",
         "scene": "account_cancel", "eventType": "AGREE", "occurredAt": 123]
    }
    nonisolated static func envelope(_ object: Any, code: Int = 200) throws -> (Data, Int) {
        (try JSONSerialization.data(withJSONObject: ["code": code, "data": object], options: .sortedKeys), 200)
    }
    func pending(requestID: String = ConsentRecoveryFixture.requestID, operation: String = ComplianceSubject.cancellation.operation) -> CompliancePendingOperation {
        .init(scope: session!.journalScope, operation: operation, requestID: requestID, epoch: session!.epoch)
    }
    func consent(version: String? = "displayed-fixture-v3", whileCurrent: () -> Bool = { true }) async throws -> ComplianceConsent {
        try await service.consent(.cancellation, event: .agree, requestID: Self.requestID, session: session!,
                                  expectedConsentVersion: version, whileCurrent: whileCurrent)
    }
    func agree() async {
        await coordinator.precheckAndAgree(documentRead: true, explicitAgreement: true, expectedConsentVersion: "displayed-fixture-v3")
    }
}

/// Isolated synthetic sources only; none of these tests authorizes a runtime endpoint.
@MainActor final class AccountDeregistrationConsentRecoveryTests: XCTestCase {
    func testOriginalACKConfirmsWithoutInventedFieldsOrLatest() async throws {
        let f = try ConsentRecoveryFixture()
        let application = f.pending(operation: "deregister"); f.journal.rows = [application]
        let receipt = try await f.consent()
        XCTAssertEqual(receipt.docVersion, "displayed-fixture-v3")
        XCTAssertEqual(f.journal.rows, [application]); XCTAssertEqual(f.journal.resolves, 1)
        XCTAssertEqual(f.http.requests.count, 1)
        let request = try XCTUnwrap(f.http.requests.first)
        XCTAssertEqual(request.url?.path, "/api/compliance/consents")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(Set(body.keys), ["docType", "scene", "eventType", "requestId"])
        XCTAssertEqual(body["requestId"], ConsentRecoveryFixture.requestID)
        XCTAssertNil(receipt.occurredAt) // Date metadata is not a confirmation key.
    }
    func testNullScopesAndArbitraryDateMetadataDoNotChangeIdentity() async throws {
        for date in [NSNull(), "unparsed-date", 123, ["unparsed": true]] as [Any] {
            let f = try ConsentRecoveryFixture()
            var ack = ConsentRecoveryFixture.ack(); ack["scopeType"] = NSNull(); ack["scopeId"] = NSNull(); ack["occurredAt"] = date
            f.http.handler = { _ in try ConsentRecoveryFixture.envelope(ack) }
            _ = try await f.consent(); XCTAssertTrue(f.journal.rows.isEmpty)
        }
    }
    func testEveryMissingMandatoryFieldRetainsUnknown() async throws {
        for field in ["requestId", "docType", "docVersion", "scene", "eventType"] {
            let f = try ConsentRecoveryFixture(); var ack = ConsentRecoveryFixture.ack(); ack.removeValue(forKey: field)
            f.http.handler = { _ in try ConsentRecoveryFixture.envelope(ack) }
            do { _ = try await f.consent(); XCTFail(field) } catch {}
            XCTAssertEqual(f.journal.rows.count, 1, field); XCTAssertEqual(f.journal.resolves, 0, field)
            XCTAssertEqual(f.http.requests.count, 1, field)
        }
    }
    func testEveryMismatchedIdentityRetainsUnknown() async throws {
        for (field, wrong) in [("requestId", UUID().uuidString.lowercased()), ("docType", "privacy_policy"),
                               ("docVersion", "other-version"), ("docVersion", ""), ("scene", "roam_location"), ("eventType", "REVOKE")] {
            let f = try ConsentRecoveryFixture(); var ack = ConsentRecoveryFixture.ack(); ack[field] = wrong
            f.http.handler = { _ in try ConsentRecoveryFixture.envelope(ack) }
            do { _ = try await f.consent(); XCTFail(field) } catch {}
            XCTAssertEqual(f.journal.rows.count, 1, field); XCTAssertEqual(f.journal.resolves, 0, field)
        }
    }
    func testNonNullScopeOfAnyTypeRejectsEvenZeroOrEmpty() async throws {
        for field in ["scopeType", "scopeId"] {
            for wrong in ["", "MERCHANT", 0, -1, 7, "0", false, ["unexpected": true]] as [Any] {
                let f = try ConsentRecoveryFixture(); var ack = ConsentRecoveryFixture.ack(); ack[field] = wrong
                f.http.handler = { _ in try ConsentRecoveryFixture.envelope(ack) }
                do { _ = try await f.consent(); XCTFail(field) } catch {}
                XCTAssertEqual(f.journal.rows.count, 1); XCTAssertEqual(f.journal.resolves, 0)
            }
        }
    }
    func testVersionComparisonUsesExactDisplayedBytes() async throws {
        let f = try ConsentRecoveryFixture(); var ack = ConsentRecoveryFixture.ack(); ack["docVersion"] = "e\u{301}"
        f.http.handler = { _ in try ConsentRecoveryFixture.envelope(ack) }
        do { _ = try await f.consent(version: "\u{e9}"); XCTFail() } catch {}
        XCTAssertEqual(f.journal.rows.count, 1)
    }
    func testMissingOrEmptyFrozenVersionAndInvalidUUIDSendNothing() async throws {
        for version in [nil, "", " \n"] as [String?] {
            let f = try ConsentRecoveryFixture()
            do { _ = try await f.consent(version: version); XCTFail() } catch {}
            XCTAssertEqual(f.journal.begins, 0); XCTAssertTrue(f.http.requests.isEmpty)
            do { _ = try await f.client!.consent(requestID: ConsentRecoveryFixture.requestID, session: f.session!); XCTFail() } catch {}
            XCTAssertTrue(f.http.requests.isEmpty)
        }
        let f = try ConsentRecoveryFixture()
        do { _ = try await f.service.consent(.cancellation, event: .agree, requestID: "INVALID", session: f.session!, expectedConsentVersion: "shown"); XCTFail() } catch {}
        XCTAssertTrue(f.http.requests.isEmpty); XCTAssertEqual(f.journal.begins, 0)
    }
    func testOldGenericSignaturesKeepSignupRoamAndMerchantProtocol() async throws {
        for subject in [ComplianceSubject.signup, .roamLocation, .merchantOnsite(authoritativeMerchantID: 41)] {
            let f = try ConsentRecoveryFixture()
            let event: ComplianceEvent = subject == .roamLocation ? .revoke : .agree
            f.http.handler = { request in
                if request.url!.path.hasSuffix("/latest") {
                    var record = try subject.fields(); record["eventType"] = event.rawValue
                    return try ConsentRecoveryFixture.envelope(record)
                }
                return try ConsentRecoveryFixture.envelope([:] as [String: String])
            }
            let generic = AccountComplianceService(configuration: try APIConfiguration(baseURL: f.context.baseURL),
                transport: f.http, journal: f.journal, current: { f.session }, token: { "synthetic-test-token" },
                readsEnabled: true, writesEnabled: true, legalApproved: { _, _ in true }, authoritativeMerchantID: { 41 },
                deregistrationOriginal: { f.client })
            let result = try await generic.consent(subject, event: event, requestID: "legacy-fixture", session: f.session!)
            XCTAssertTrue(result.matches(subject, event: event))
            XCTAssertEqual(f.http.requests.count, 2); XCTAssertTrue(f.journal.rows.isEmpty)
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(f.http.requests[0].httpBody)) as? [String: Any])
            XCTAssertNil(fields["docVersion"]); XCTAssertEqual(fields["requestId"] as? String, "legacy-fixture")
        }
    }
    func testMalformedEnvelopeAndBusinessOrHTTPFailureKeepPending() async throws {
        let replies: [(Data, Int)] = [
            (Data(#"{"code":200,"data":null}"#.utf8), 200), (Data(#"{"code":200}"#.utf8), 200),
            (Data(#"{"code":"200","data":{}}"#.utf8), 200), (Data(#"{"code":409,"data":{}}"#.utf8), 200),
            (Data(#"{"code":200,"data":{}}"#.utf8), 500), (Data("not-json".utf8), 200)]
        for reply in replies {
            let f = try ConsentRecoveryFixture(); f.http.handler = { _ in reply }
            do { _ = try await f.consent(); XCTFail() } catch {}
            XCTAssertEqual(f.journal.rows.count, 1); XCTAssertEqual(f.journal.resolves, 0)
        }
    }
    func testLostReplyBlocksReplacementAndReadProjectionSendsNothing() async throws {
        let f = try ConsentRecoveryFixture(); f.http.handler = { _ in throw URLError(.timedOut) }
        do { _ = try await f.consent(); XCTFail() } catch {}
        let intent = try XCTUnwrap(f.journal.rows.first)
        XCTAssertEqual(try f.service.readDeregistrationConsent(session: f.session!), .unknown(requestID: intent.requestID))
        do { _ = try await f.service.consent(.cancellation, event: .agree, requestID: UUID().uuidString.lowercased(), session: f.session!, expectedConsentVersion: "shown"); XCTFail() } catch {}
        XCTAssertEqual(f.http.requests.count, 1); XCTAssertEqual(f.journal.rows, [intent]); XCTAssertEqual(f.journal.begins, 1)
    }
    func testBeginAndReadFailureNeverPost() async throws {
        for failRead in [false, true] {
            let f = try ConsentRecoveryFixture(); f.journal.failRead = failRead; f.journal.failBegin = !failRead
            do { _ = try await f.consent(); XCTFail() } catch {}
            XCTAssertTrue(f.http.requests.isEmpty); XCTAssertEqual(f.journal.resolves, 0)
            XCTAssertEqual(try f.service.readDeregistrationConsent(session: f.session!), failRead ? .unavailable : .none)
        }
    }
    func testResolveFailureOrNoOpNeverReportsConfirmation() async throws {
        for retain in [false, true] {
            let f = try ConsentRecoveryFixture(); f.journal.failResolve = !retain; f.journal.retainOnResolve = retain
            do { _ = try await f.consent(); XCTFail() } catch {}
            XCTAssertEqual(f.journal.rows.count, 1); XCTAssertEqual(f.http.requests.count, 1)
        }
    }
    func testPendingIntentReplacementIsNeverResolvedByLateACK() async throws {
        let f = try ConsentRecoveryFixture(); let replacement = f.pending(requestID: UUID().uuidString.lowercased())
        f.http.afterSend = { _ in f.journal.rows = [replacement] }
        do { _ = try await f.consent(); XCTFail() } catch {}
        XCTAssertEqual(f.journal.rows, [replacement]); XCTAssertEqual(f.journal.resolves, 0)
    }
    func testAccountNamespaceMarketAndEpochChangeRejectLateACK() async throws {
        for next in [ComplianceSession(accountID: 8, epoch: 1, market: "CN", namespace: "consent-fixture"),
                     .init(accountID: 7, epoch: 1, market: "CN", namespace: "other"),
                     .init(accountID: 7, epoch: 1, market: "US", namespace: "consent-fixture"),
                     .init(accountID: 7, epoch: 2, market: "CN", namespace: "consent-fixture")] {
            let f = try ConsentRecoveryFixture(); f.http.afterSend = { _ in f.session = next }
            do { _ = try await f.consent(); XCTFail() } catch {}
            XCTAssertEqual(f.journal.rows.count, 1); XCTAssertEqual(f.journal.resolves, 0)
        }
    }
    func testRealmRevocationReplacementAndGenerationRejectLateACK() async throws {
        for change in 0..<4 {
            let f = try ConsentRecoveryFixture(); var current = true
            f.http.afterSend = { _ in
                switch change {
                case 0: f.context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://other.example.test")!, role: "player", session: f.context.session)
                case 1: f.approved = false
                case 2: try! f.replaceClient()
                default: current = false
                }
            }
            do { _ = try await f.consent(whileCurrent: { current }); XCTFail() } catch {}
            XCTAssertEqual(f.journal.rows.count, 1); XCTAssertEqual(f.journal.resolves, 0)
        }
    }
    func testTaskCancellationDuringOriginalPOSTRetainsPending() async throws {
        let f = try ConsentRecoveryFixture()
        var work: Task<ComplianceConsent, Error>!
        f.http.afterSend = { _ in work.cancel() }
        work = Task { try await f.consent() }
        do { _ = try await work.value; XCTFail() } catch {}
        XCTAssertEqual(f.journal.rows.count, 1); XCTAssertEqual(f.journal.resolves, 0)
        XCTAssertEqual(f.http.requests.count, 1)
    }
    func testProjectionSeparatesUnreadNoneUnknownUnavailableAndOwnerScopes() throws {
        let f = try ConsentRecoveryFixture()
        XCTAssertEqual(ComplianceState().localCancellationConsent, .unread)
        XCTAssertEqual(try f.service.readDeregistrationConsent(session: f.session!), .none)
        let intent = f.pending(); f.journal.rows = [intent]
        XCTAssertEqual(try f.service.readDeregistrationConsent(session: f.session!), .unknown(requestID: intent.requestID))
        for next in [ComplianceSession(accountID: 8, epoch: 1, market: "CN", namespace: "consent-fixture"),
                     .init(accountID: 7, epoch: 1, market: "US", namespace: "consent-fixture"),
                     .init(accountID: 7, epoch: 1, market: "CN", namespace: "other")] {
            f.session = next; XCTAssertEqual(try f.service.readDeregistrationConsent(session: next), .none)
        }
        f.session = .init(accountID: 7, epoch: 2, market: "CN", namespace: "consent-fixture")
        XCTAssertEqual(try f.service.readDeregistrationConsent(session: f.session!), .unknown(requestID: intent.requestID))
        f.journal.rows.append(intent)
        XCTAssertEqual(try f.service.readDeregistrationConsent(session: f.session!), .unavailable)
        XCTAssertTrue(f.http.requests.isEmpty); XCTAssertEqual(f.journal.resolves, 0)
    }
    func testColdServiceReadsDurableOldJournalWithoutUpgradeOrTransport() throws {
        let f = try ConsentRecoveryFixture()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("synthetic-consent.json")
        let first = ComplianceFileJournal(url: url); let intent = f.pending()
        try first.begin(intent)
        let originalBytes = try Data(contentsOf: url)
        let restored = AccountComplianceService(configuration: try APIConfiguration(baseURL: f.context.baseURL), transport: f.http,
            journal: ComplianceFileJournal(url: url), current: { f.session }, token: { "synthetic-test-token" })
        XCTAssertEqual(try restored.readDeregistrationConsent(session: f.session!), .unknown(requestID: intent.requestID))
        XCTAssertEqual(try Data(contentsOf: url), originalBytes); XCTAssertTrue(f.http.requests.isEmpty)
        try Data("corrupt".utf8).write(to: url)
        XCTAssertEqual(try restored.readDeregistrationConsent(session: f.session!), .unavailable)
        XCTAssertEqual(try Data(contentsOf: url), Data("corrupt".utf8))
    }
    func testLatestAgreeAndNormalOrPendingCurrentNeverSettleLocalConsent() async throws {
        for status in ["NORMAL", "PENDING"] {
            let f = try ConsentRecoveryFixture(); let intent = f.pending(); f.journal.rows = [intent]
            f.http.handler = { request in
                if request.url!.path.hasSuffix("/latest") {
                    var ack = ConsentRecoveryFixture.ack(requestID: UUID().uuidString.lowercased()); ack.removeValue(forKey: "occurredAt")
                    return try ConsentRecoveryFixture.envelope(ack)
                }
                return try ConsentRecoveryFixture.envelope(["status": status])
            }
            let reader = AccountComplianceService(configuration: try APIConfiguration(baseURL: f.context.baseURL),
                transport: f.http, journal: f.journal, current: { f.session }, token: { "synthetic-test-token" },
                readsEnabled: true, deregistrationOriginal: { f.client })
            _ = try await reader.latest(.cancellation, session: f.session!)
            let count = f.http.requests.count
            do { _ = try await reader.reconcileConsent(.cancellation, event: .agree, session: f.session!); XCTFail() } catch {}
            XCTAssertEqual(f.http.requests.count, count)
            await f.coordinator.load()
            XCTAssertEqual(f.coordinator.state.status?.status, status)
            XCTAssertEqual(f.coordinator.state.localCancellationConsent, .unknown(requestID: intent.requestID))
            XCTAssertEqual(f.journal.rows, [intent]); XCTAssertEqual(f.journal.resolves, 0)
            await f.agree(); XCTAssertEqual(f.http.requests.count, count + 1)
        }
    }
    func testOriginalApplicationGuardRejectsPendingOrUnreadableConsentWithoutNewKey() async throws {
        for unreadable in [false, true] {
            let f = try ConsentRecoveryFixture(); let intent = f.pending(); f.journal.rows = [intent]; f.journal.failRead = unreadable
            let impact = try JSONDecoder().decode(AccountDeregistrationImpact.self, from: JSONSerialization.data(withJSONObject: ConsentRecoveryFixture.impact))
            do { _ = try await f.service.apply(smscode: "123456", requestID: UUID().uuidString.lowercased(), session: f.session!, impact: impact); XCTFail() } catch {}
            XCTAssertEqual(f.journal.rows, [intent]); XCTAssertEqual(f.journal.begins, 0); XCTAssertTrue(f.http.requests.isEmpty)
        }
    }
    func testCoordinatorOnlyConfirmedOriginalACKEnablesSMS() async throws {
        let f = try ConsentRecoveryFixture(); await f.coordinator.load(); await f.agree()
        XCTAssertEqual(f.coordinator.state.step, .verify)
        XCTAssertEqual(f.coordinator.state.localCancellationConsent, .none)
        await f.coordinator.sendSMS(phone: "13800000000", explicitlyRequested: true)
        XCTAssertEqual(f.auth.smsCalls, 1)
        XCTAssertEqual(f.http.requests.filter { $0.url!.path == "/api/compliance/consents" }.count, 1)
        XCTAssertFalse(f.http.requests.contains { $0.url!.path.hasSuffix("/latest") })
    }
    func testCoordinatorTimeoutMismatchAndResolveFailureShowUnknownAndNoSMS() async throws {
        for failure in 0..<3 {
            let f = try ConsentRecoveryFixture(); await f.coordinator.load()
            let original = f.http.handler
            f.http.handler = { request in
                if request.url!.path == "/api/compliance/consents" {
                    if failure == 0 { throw URLError(.timedOut) }
                    if failure == 1 { var ack = ConsentRecoveryFixture.ack(); ack["docVersion"] = "drift"; return try ConsentRecoveryFixture.envelope(ack) }
                }
                return try original(request)
            }
            f.journal.failResolve = failure == 2
            await f.agree()
            XCTAssertNotNil(f.coordinator.state.localCancellationConsent.requestID)
            XCTAssertNotEqual(f.coordinator.state.step, .verify)
            await f.coordinator.sendSMS(phone: "13800000000", explicitlyRequested: true)
            XCTAssertEqual(f.auth.smsCalls, 0)
            let count = f.http.requests.count
            f.coordinator.invalidate(); XCTAssertEqual(f.coordinator.state.localCancellationConsent, .unread)
            await f.coordinator.load()
            XCTAssertNotNil(f.coordinator.state.localCancellationConsent.requestID)
            XCTAssertEqual(f.http.requests.count, count + 1)
            await f.agree(); XCTAssertEqual(f.http.requests.count, count + 1)
        }
    }
    func testCloseOrGrantReplacementDuringACKLeavesJournalAndClearsPresentation() async throws {
        for replace in [false, true] {
            let f = try ConsentRecoveryFixture(); await f.coordinator.load()
            f.http.afterSend = { request in
                if request.url!.path == "/api/compliance/consents" {
                    if replace { try! f.replaceClient() } else { f.coordinator.invalidate() }
                }
            }
            await f.agree()
            XCTAssertEqual(f.coordinator.state.localCancellationConsent, .unread)
            XCTAssertEqual(f.coordinator.state.step, .idle)
            XCTAssertEqual(f.journal.rows.count, 1); XCTAssertEqual(f.journal.resolves, 0)
        }
    }
    func testAccountSwitchDuringLoadClearsLocalHintAndLateCurrentStatus() async throws {
        let f = try ConsentRecoveryFixture(); f.journal.rows = [f.pending()]
        f.http.afterSend = { _ in f.session = .init(accountID: 8, epoch: 2, market: "CN", namespace: "consent-fixture") }
        await f.coordinator.load()
        XCTAssertEqual(f.coordinator.state.localCancellationConsent, .unread)
        XCTAssertEqual(f.coordinator.state.step, .idle); XCTAssertNil(f.coordinator.state.status)
        XCTAssertEqual(f.journal.rows.count, 1); XCTAssertEqual(f.journal.resolves, 0)
    }
    func testPrecheckGrantReplacementCannotStartConsentWithNewIssuance() async throws {
        let f = try ConsentRecoveryFixture(); await f.coordinator.load()
        f.http.afterSend = { request in if request.url!.path.hasSuffix("/precheck") { try! f.replaceClient() } }
        await f.agree()
        XCTAssertEqual(f.coordinator.state.localCancellationConsent, .unread)
        XCTAssertEqual(f.journal.begins, 0)
        XCTAssertFalse(f.http.requests.contains { $0.url!.path == "/api/compliance/consents" })
    }
    func testUnavailableLocalReadRemainsVisibleEvenWhenCurrentGETCannotRun() async throws {
        let f = try ConsentRecoveryFixture(); f.journal.failRead = true
        await f.coordinator.load()
        XCTAssertEqual(f.coordinator.state.localCancellationConsent, .unavailable)
        await f.agree(); XCTAssertTrue(f.http.requests.isEmpty)
        f.journal.failRead = false; await f.coordinator.load()
        XCTAssertEqual(f.coordinator.state.localCancellationConsent, .none)
    }
}
