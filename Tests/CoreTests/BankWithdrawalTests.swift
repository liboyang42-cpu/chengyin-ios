import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class BankSyntheticTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var handler: (URLRequest) async throws -> (Data, Int) = { _ in throw URLError(.timedOut) }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try await handler(request) }
}
@MainActor final class BankWithdrawalTests: XCTestCase {
    private let base = URL(string: "https://example.com")!
    private func session() -> BankWithdrawalSession { .init(scope: .init(namespace: "synthetic", accountID: 7, epoch: UUID()), token: "SYNTHETIC_AUTH") }
    private func draft() -> BankWithdrawalDraft {
        var value = BankWithdrawalDraft(); value.amount = "12.30"; value.realname = "SYNTHETIC_NAME"
        value.bankName = "SYNTHETIC_BANK"; value.bankAccount = "SYNTHETIC_ACCOUNT_1234"; value.mobilephone = "SYNTHETIC_PHONE_5678"; return value
    }
    private func consent(_ session: BankWithdrawalSession, version: String = "synthetic-v1", event: String = "AGREE") throws -> BankWithdrawalConsentEvidence {
        let data = Data("{\"docType\":\"bank_account_collection\",\"docVersion\":\"\(version)\",\"scene\":\"withdrawal\",\"eventType\":\"\(event)\"}".utf8)
        return .init(scope: session.scope, currentDocumentVersion: "synthetic-v1", consent: try JSONDecoder().decode(ComplianceConsent.self, from: data))
    }
    private func challenge(_ state: String = "PENDING", amount: String = "12.30", id: Int = 71, seconds: Int = 120, canProceed: Bool = true, risk: String = "WARNING") -> Data {
        let token = state == "PENDING" ? "\"SYNTHETIC_CHALLENGE_TOKEN\"" : "null"
        return Data("{\"code\":200,\"data\":{\"challengeId\":\(id),\"challengeToken\":\(token),\"state\":\"\(state)\",\"serverTime\":\"2026-10-02 12:00:00\",\"expiresAt\":\"2026-10-02 12:02:00\",\"expiresInSeconds\":\(seconds),\"question\":\"Synthetic confirmation?\",\"consequence\":\"Synthetic application reduces available funds.\",\"riskLevel\":\"\(risk)\",\"canProceed\":\(canProceed),\"amount\":\(amount),\"currency\":\"CNY\",\"accountMask\":\"****1234\",\"phoneMask\":\"***5678\",\"safetyMessages\":[\"Synthetic safety notice\"]}}".utf8)
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "BankWithdrawalTests." + UUID().uuidString)! }
    private func adapter(_ transport: BankSyntheticTransport, defaults: UserDefaults, active: @escaping () -> BankWithdrawalSession?, consent: @escaping () -> BankWithdrawalConsentEvidence? = { nil }, enabled: Bool = true, paths: Set<String>? = nil, now: @escaping () -> Date = Date.init) throws -> BankWithdrawalAdapter {
        let current = active()!
        let grant = try OperationEndpointApproval(baseURL: base, namespace: current.scope.namespace, accountID: current.scope.accountID,
            paths: paths ?? ["api/fund/preflight/bank-withdrawal", "api/fund/preflight/71/confirm", "api/fund/preflight/71/reject", "api/withdrawal/create"])
        return BankWithdrawalAdapter(configuration: try .init(baseURL: base), transport: transport,
            journal: OperationDefaultsJournal(defaults: defaults), approval: grant, enableReviewedWrites: enabled,
            consentEvidence: consent, currentSession: active, now: now)
    }
    private func fail<T>(_ block: () async throws -> T, file: StaticString = #filePath, line: UInt = #line) async {
        do { _ = try await block(); XCTFail("Expected fail-closed result", file: file, line: line) } catch {}
    }
    func testBackendInputLimitsDecimalPrecisionAndNoInventedCardFormat() throws {
        XCTAssertEqual(try draft().validatedAmount(), Decimal(string: "12.3"))
        for amount in ["0", "-1", "1.001", "1e2", "NaN", "1,20", "1000000000000", ".1"] {
            var value = draft(); value.amount = amount; XCTAssertThrowsError(try value.validatedAmount())
        }
        var value = draft(); value.realname = String(repeating: "😀", count: 33)
        XCTAssertThrowsError(try value.validatedAmount()) // Java validation counts UTF-16 units.
        value = draft(); value.bankAccount = "ABCD"; value.mobilephone = "phone"
        XCTAssertNoThrow(try value.validatedAmount()) // Client does not invent numeric/issuer eligibility rules.
        value = draft(); value.bankName = " \n"; XCTAssertThrowsError(try value.validatedAmount())
    }
    func testSensitiveDescriptionsAreRedacted() throws {
        let value = draft(); XCTAssertFalse(String(describing: value).contains(value.bankAccount))
        XCTAssertFalse(String(reflecting: value).contains(value.realname))
        XCTAssertFalse(String(reflecting: session()).contains("SYNTHETIC_AUTH"))
    }
    func testPreflightAndCreateUseDifferentExactAmountKeysAndStableID() throws {
        let pre = try draft().fields(requestID: "intent")
        let create = try draft().fields(requestID: "intent", challengeID: 71)
        XCTAssertEqual(Set(pre.keys), ["requestId", "amount", "realname", "bankName", "bankAccount", "mobilephone"])
        XCTAssertEqual(Set(create.keys), ["requestId", "withdrawalAmount", "challengeId", "realname", "bankName", "bankAccount", "mobilephone"])
        XCTAssertEqual(create["requestId"] as? String, pre["requestId"] as? String)
    }
    func testDefaultGateAndMissingConsentNeverDispatch() async throws {
        let current = session(), fake = BankSyntheticTransport()
        let dormant = BankWithdrawalAdapter(configuration: try .init(baseURL: base), transport: fake,
            journal: OperationDefaultsJournal(defaults: defaults()), currentSession: { current })
        let review = try dormant.review(draft())
        await fail { try await dormant.prepare(review) }; XCTAssertTrue(fake.requests.isEmpty)
        let missing = try adapter(fake, defaults: defaults(), active: { current })
        let second = try missing.review(draft()); await fail { try await missing.prepare(second) }
        XCTAssertTrue(fake.requests.isEmpty)
    }
    func testOldRevokedWrongScopeConsentNeverDispatch() async throws {
        let current = session(), fake = BankSyntheticTransport()
        for evidence in [try consent(current, version: "old"), try consent(current, event: "REVOKE"), try consent(session())] {
            let value = try adapter(fake, defaults: defaults(), active: { current }, consent: { evidence })
            let review = try value.review(draft()); await fail { try await value.prepare(review) }
        }
        XCTAssertTrue(fake.requests.isEmpty)
    }
    func testEditAndCancelInvalidateImmutableReview() async throws {
        let current = session(), evidence = try consent(current), fake = BankSyntheticTransport()
        let value = try adapter(fake, defaults: defaults(), active: { current }, consent: { evidence })
        let original = try value.review(draft()); var changed = draft(); changed.amount = "1"
        _ = try value.review(changed); await fail { try await value.prepare(original) }
        let fresh = try value.review(draft()); value.discardLocalInput(); await fail { try await value.prepare(fresh) }
        XCTAssertTrue(fake.requests.isEmpty)
    }
    func testAccountEpochAndTokenChangesFencePreflight() async throws {
        var current = session(); let evidence = try consent(current), fake = BankSyntheticTransport()
        let value = try adapter(fake, defaults: defaults(), active: { current }, consent: { evidence })
        let review = try value.review(draft())
        current = .init(scope: current.scope, token: "CHANGED_TOKEN")
        await fail { try await value.prepare(review) }; XCTAssertTrue(fake.requests.isEmpty)
    }
    func testPrepareDoesNotConfirmOrCreate() async throws {
        let current = session(), evidence = try consent(current), fake = BankSyntheticTransport()
        fake.handler = { _ in (self.challenge(), 200) }
        let value = try adapter(fake, defaults: defaults(), active: { current }, consent: { evidence })
        let review = try value.review(draft()); let proof = try await value.prepare(review)
        XCTAssertEqual(proof.amount, Decimal(string: "12.3")); XCTAssertEqual(proof.currency, "CNY")
        XCTAssertEqual(fake.requests.map { $0.url!.path }, ["/api/fund/preflight/bank-withdrawal"])
        XCTAssertEqual(fake.requests.first?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertFalse(String(reflecting: proof).contains("SYNTHETIC_CHALLENGE_TOKEN"))
    }
    func testSuccessRequiresConfirmedSameChallengeThenPositiveReceipt() async throws {
        let current = session(), evidence = try consent(current), fake = BankSyntheticTransport(), store = defaults()
        fake.handler = { request in
            if request.url!.path.hasSuffix("/confirm") { return (self.challenge("CONFIRMED"), 200) }
            if request.url!.path.hasSuffix("/create") { return (Data(#"{"code":200,"data":301}"#.utf8), 200) }
            return (self.challenge(), 200)
        }
        let value = try adapter(fake, defaults: store, active: { current }, consent: { evidence })
        let review = try value.review(draft()); let proof = try await value.prepare(review)
        let receipt = try await value.submit(proof); XCTAssertEqual(receipt.applicationID, 301)
        XCTAssertFalse(value.hasUnresolvedOutcome)
        let pre = try JSONSerialization.jsonObject(with: fake.requests[0].httpBody!) as! [String: Any]
        let create = try JSONSerialization.jsonObject(with: fake.requests[2].httpBody!) as! [String: Any]
        XCTAssertEqual(pre["requestId"] as? String, create["requestId"] as? String)
        XCTAssertNil(create["amount"]); XCTAssertNotNil(create["withdrawalAmount"])
        await fail { try await value.submit(proof) }; XCTAssertEqual(fake.requests.count, 3)
    }
    func testMissingCreateGrantDoesNotEvenConfirm() async throws {
        let current = session(), evidence = try consent(current), fake = BankSyntheticTransport()
        fake.handler = { _ in (self.challenge(), 200) }
        let value = try adapter(fake, defaults: defaults(), active: { current }, consent: { evidence },
            paths: ["api/fund/preflight/bank-withdrawal", "api/fund/preflight/71/confirm"])
        let review = try value.review(draft()); let proof = try await value.prepare(review)
        await fail { try await value.submit(proof) }; XCTAssertEqual(fake.requests.count, 1)
    }
    func testUnknownConfirmationPersistsAcrossRestartAndCannotResubmit() async throws {
        var current = session(); let first = current, evidence = try consent(current), fake = BankSyntheticTransport(), store = defaults()
        fake.handler = { request in
            if request.url!.path.hasSuffix("bank-withdrawal") { return (self.challenge(), 200) }
            throw URLError(.timedOut)
        }
        let value = try adapter(fake, defaults: store, active: { current }, consent: { evidence })
        let review = try value.review(draft()); let proof = try await value.prepare(review)
        await fail { try await value.submit(proof) }; await fail { try await value.submit(proof) }
        XCTAssertEqual(fake.requests.count, 2)
        current = .init(scope: .init(namespace: first.scope.namespace, accountID: first.scope.accountID, epoch: UUID()), token: "NEW_TOKEN")
        let restarted = try adapter(fake, defaults: store, active: { current }, consent: { evidence })
        XCTAssertThrowsError(try restarted.review(draft())); XCTAssertTrue(restarted.hasUnresolvedOutcome)
        for case let data as Data in store.dictionaryRepresentation().values {
            let text = String(data: data, encoding: .utf8) ?? ""
            for secret in ["SYNTHETIC_NAME", "SYNTHETIC_ACCOUNT", "SYNTHETIC_PHONE", "SYNTHETIC_BANK", "SYNTHETIC_AUTH", "SYNTHETIC_CHALLENGE", "12.30"] { XCTAssertFalse(text.contains(secret)) }
        }
    }
    func testMalformedCreateReceiptRetainsUnknownLock() async throws {
        let current = session(), evidence = try consent(current), fake = BankSyntheticTransport()
        fake.handler = { request in
            if request.url!.path.hasSuffix("/confirm") { return (self.challenge("CONFIRMED"), 200) }
            if request.url!.path.hasSuffix("/create") { return (Data(#"{"code":200,"data":null}"#.utf8), 200) }
            return (self.challenge(), 200)
        }
        let value = try adapter(fake, defaults: defaults(), active: { current }, consent: { evidence })
        let review = try value.review(draft()); let proof = try await value.prepare(review)
        await fail { try await value.submit(proof) }; XCTAssertTrue(value.hasUnresolvedOutcome)
        XCTAssertThrowsError(try value.review(draft()))
    }
    func testBlockedMismatchAndExpiredProofNeverCreate() async throws {
        let current = session(), evidence = try consent(current)
        for payload in [challenge(amount: "99"), challenge(seconds: 0), challenge(canProceed: false), challenge(risk: "BLOCKED")] {
            let fake = BankSyntheticTransport(); fake.handler = { _ in (payload, 200) }
            let value = try adapter(fake, defaults: defaults(), active: { current }, consent: { evidence })
            let review = try value.review(draft()); await fail { try await value.prepare(review) }; XCTAssertEqual(fake.requests.count, 1)
        }
    }
    func testExpiredClockAndConsentRevocationBeforeConfirmNeverDispatch() async throws {
        let current = session(); var evidence: BankWithdrawalConsentEvidence? = try consent(current), date = Date(timeIntervalSince1970: 1000)
        let fake = BankSyntheticTransport(); fake.handler = { _ in (self.challenge(), 200) }
        let value = try adapter(fake, defaults: defaults(), active: { current }, consent: { evidence }, now: { date })
        let review = try value.review(draft()); let proof = try await value.prepare(review)
        evidence = nil; await fail { try await value.submit(proof) }; XCTAssertEqual(fake.requests.count, 1)
        evidence = try consent(current); date = date.addingTimeInterval(121)
        await fail { try await value.submit(proof) }; XCTAssertEqual(fake.requests.count, 1)
    }
    func testSwitchDuringConfirmPreventsCreateAndPreservesLock() async throws {
        var current = session(); let evidence = try consent(current), fake = BankSyntheticTransport()
        fake.handler = { request in
            if request.url!.path.hasSuffix("/confirm") { current = self.session(); return (self.challenge("CONFIRMED"), 200) }
            return (self.challenge(), 200)
        }
        let value = try adapter(fake, defaults: defaults(), active: { current }, consent: { evidence })
        let review = try value.review(draft()); let proof = try await value.prepare(review)
        await fail { try await value.submit(proof) }; XCTAssertEqual(fake.requests.count, 2)
    }
    func testExplicitRejectClearsOnlyAfterMatchedRejectedReceipt() async throws {
        let current = session(), evidence = try consent(current), fake = BankSyntheticTransport()
        fake.handler = { request in (self.challenge(request.url!.path.hasSuffix("/reject") ? "REJECTED" : "PENDING"), 200) }
        let value = try adapter(fake, defaults: defaults(), active: { current }, consent: { evidence })
        let review = try value.review(draft()); let proof = try await value.prepare(review)
        try await value.reject(proof); XCTAssertFalse(value.hasUnresolvedOutcome)
        XCTAssertEqual(fake.requests.count, 2); XCTAssertNoThrow(try value.review(draft()))
    }
    func testHistoryBackendStatusesDoNotInvertRejectedAndPaid() throws {
        for (status, expected) in [(0,"wallet.pendingReview"), (1,"wallet.approved"), (2,"wallet.rejected"), (3,"wallet.paid")] {
            let data = Data("{\"id\":1,\"withdrawalAmount\":12.3,\"status\":\(status)}".utf8)
            XCTAssertEqual(try JSONDecoder().decode(WalletWithdrawalRecord.self, from: data).statusKey, expected)
        }
    }
    func testWrongConfirmedChallengeCannotCreate() async throws {
        let current = session(), evidence = try consent(current), fake = BankSyntheticTransport()
        fake.handler = { request in
            if request.url!.path.hasSuffix("/confirm") { return (self.challenge("CONFIRMED", id: 99), 200) }
            return (self.challenge(risk: "STATIC"), 200)
        }
        let value = try adapter(fake, defaults: defaults(), active: { current }, consent: { evidence })
        let review = try value.review(draft()); let proof = try await value.prepare(review)
        await fail { try await value.submit(proof) }; XCTAssertEqual(fake.requests.count, 2)
        XCTAssertTrue(value.hasUnresolvedOutcome)
    }
    func testClosingPreparedFormClearsInputButDoesNotUnlockUnknownOperation() async throws {
        let current = session(), evidence = try consent(current), fake = BankSyntheticTransport()
        fake.handler = { _ in (self.challenge(), 200) }
        let value = try adapter(fake, defaults: defaults(), active: { current }, consent: { evidence })
        let review = try value.review(draft()); let proof = try await value.prepare(review)
        value.discardLocalInput()
        await fail { try await value.submit(proof) }; XCTAssertEqual(fake.requests.count, 1)
        XCTAssertTrue(value.hasUnresolvedOutcome); XCTAssertThrowsError(try value.review(draft()))
    }
    func testMissingOrMalformedPreflightNeverCreatesAndCannotBeRetried() async throws {
        let current = session(), evidence = try consent(current), fake = BankSyntheticTransport()
        fake.handler = { _ in (Data(#"{"code":200,"data":{}}"#.utf8), 200) }
        let value = try adapter(fake, defaults: defaults(), active: { current }, consent: { evidence })
        let review = try value.review(draft()); await fail { try await value.prepare(review) }
        await fail { try await value.prepare(review) }; XCTAssertEqual(fake.requests.count, 1)
        XCTAssertTrue(value.hasUnresolvedOutcome)
    }

}
