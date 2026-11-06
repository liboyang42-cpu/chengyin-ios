import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// NOT_RUN. Real Service/Transport/Coordinator over in-memory bytes and journal; no OS location or Keychain.
/// Synthetic approval and location status exist only inside these unexecuted tests, not production configuration.
@available(macOS 14.0, *) @MainActor final class NativeHomeVerificationWireBoundaryJourneyTests: XCTestCase {
    @MainActor private final class Clock { var now = Date(timeIntervalSince1970: 1_000_000) }
    private static let scope = NativeHomeResourceScope.run(runId: "42", resourceType: "sys.hp")
    private static func policy(_ now: Date) -> NativeHomeReturnPolicy {
        .init(policyVersion: "synthetic", maxAccuracyMeters: 20, maxFixAgeSeconds: 30, dwellSeconds: 10,
              serverTimeMillis: Int64(now.timeIntervalSince1970 * 1000))
    }
    private static func home(_ version: Int64 = 3) throws -> PrivateHomeSnapshot {
        try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data("{\"version\":\(version),\"status\":\"ACTIVE\",\"changedAt\":1,\"effectiveAt\":1,\"label\":\"Synthetic\",\"latitude\":12,\"longitude\":45,\"datum\":\"WGS84\"}".utf8))
    }
    private static func dwell(_ body: [String: Any], challenge: String = "challenge-original") -> [String: Any] {
        ["requestId": body["requestId"]!, "decision": "DWELL_REQUIRED", "proofId": NSNull(),
         "homeVersion": body["homeVersion"]!, "expiresAtMillis": NSNull(), "retryAfterSeconds": 10,
         "challengeId": challenge, "accountVersion": body["expectedAccountVersion"]!]
    }
    private static func verified(_ body: [String: Any], now: Date) -> [String: Any] {
        ["requestId": body["requestId"]!, "decision": "VERIFIED", "proofId": "proof-original",
         "homeVersion": body["homeVersion"]!, "expiresAtMillis": Int64((now.timeIntervalSince1970 + 60) * 1000),
         "retryAfterSeconds": NSNull(), "challengeId": NSNull(), "accountVersion": body["expectedAccountVersion"]!]
    }
    @MainActor private final class Wire: HTTPTransport {
        let clock: Clock
        var requests: [URLRequest] = [], restores: [NativeHomeRestoreRequest] = []
        var checks: [[String: Any]] = []
        var receipts: [String: [String: Any]] = [:]
        var reply: (([String: Any]) throws -> [String: Any])?
        var loseNextRestore = false
        var accountVersion: Int64 = 4, current: Int64 = 2
        var afterVerify: (() -> Void)?
        var policyVersion = "synthetic", challengeID = "challenge-original"
        init(_ clock: Clock) { self.clock = clock }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let value: Any
            switch request.url?.lastPathComponent {
            case "policy":
                value = ["policyVersion": policyVersion, "maxAccuracyMeters": 20, "maxFixAgeSeconds": 30,
                         "dwellSeconds": 10, "serverTimeMillis": Int64(clock.now.timeIntervalSince1970 * 1000)]
            case "account":
                value = ["resourceType": "sys.hp", "scopeType": "RUN", "scopeId": "42", "current": current, "maximum": 5, "version": accountVersion]
            case "verify":
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                checks.append(body)
                if let reply { value = try reply(body) }
                else if body["challengeId"] == nil { value = NativeHomeVerificationWireBoundaryJourneyTests.dwell(body, challenge: challengeID) }
                else { value = NativeHomeVerificationWireBoundaryJourneyTests.verified(body, now: clock.now) }
                afterVerify?()
            case "restore":
                let original = try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: XCTUnwrap(request.httpBody))
                restores.append(original)
                if receipts[original.requestId] == nil {
                    accountVersion += 1; current = 5
                    receipts[original.requestId] = ["requestId": original.requestId, "proofId": original.proofId,
                        "decision": "RESTORED", "current": current, "maximum": 5, "accountVersion": accountVersion, "retryAfterSeconds": NSNull()]
                }
                if loseNextRestore { loseNextRestore = false; throw NativeHomeReturnFailure.network }
                value = try XCTUnwrap(receipts[original.requestId])
            case "receipt":
                let id = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? ""
                if let receipt = receipts[id] { value = receipt } else { value = NSNull() }
            default: XCTFail("Unexpected route"); throw NativeHomeReturnFailure.invalid
            }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": value]), 200)
        }
    }
    @MainActor private final class Journal: NativeHomeReturnSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: NativeHomeRestoreRequest?
        var saves = 0, clears = 0
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() throws -> NativeHomeRestoreRequest? { value }
        func save(_ request: NativeHomeRestoreRequest) throws {
            guard value == nil || value == request else { throw NativeHomeReturnFailure.storageUnavailable }
            value = request; saves += 1
        }
        func clear(matching request: NativeHomeRestoreRequest) throws {
            guard value == request else { throw NativeHomeReturnFailure.storageUnavailable }
            value = nil; clears += 1
        }
    }
    @MainActor private final class Fixture {
        let clock: Clock, wire: Wire, grant: NativeHomeReturnApproval, journal: Journal, service: NativeHomeReturnService
        var samples = 0
        init() throws {
            let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token", role: "player")
            let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test")!, role: "player", session: owner)
            let grant = try NativeHomeReturnApproval(context: context, expiresAt: Date().addingTimeInterval(600))
            let clock = Clock(), wire = Wire(clock)
            let transport = NativeHomeReturnTransport(approval: grant, underlying: wire, current: { grant.context }, selected: { _ in grant })
            self.clock = clock; self.wire = wire; self.grant = grant; journal = Journal(owner)
            service = NativeHomeReturnService(approval: grant, transport: transport, current: { grant.context }, selected: { _ in grant })
        }
        func model(enabled: Bool = true) -> NativeHomeReturnCoordinator {
            .init(scope: NativeHomeVerificationWireBoundaryJourneyTests.scope, service: service, journal: journal, owner: grant.context.session,
                enabled: enabled, location: {
                    self.samples += 1
                    return .measured(try! .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: self.clock.now))
                }, locationAuthorized: { true }, isCurrent: { self.service.isCurrent() }, now: { self.clock.now })
        }
    }
    private func published(_ id: String, accuracy: Double = 20, age: Double = 30,
                           dwell: Double = 10, serverTime: Int64 = 1_000_000_000) -> NativeHomeReturnPolicy {
        .init(policyVersion: id, maxAccuracyMeters: accuracy, maxFixAgeSeconds: age,
              dwellSeconds: dwell, serverTimeMillis: serverTime)
    }
    private func check(_ f: Fixture, challenge: String? = nil, policy: String = "synthetic") throws -> NativeHomeReturnCheck {
        try .preflight(home: Self.home(), status: .measured(.init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: f.clock.now)),
            policy: published(policy), scope: Self.scope, now: f.clock.now,
            requestId: "verify-original", expectedAccountVersion: 4, challengeId: challenge)
    }
    private func reachProof(_ f: Fixture, _ model: NativeHomeReturnCoordinator) async throws {
        await model.load(); await model.checkIn(home: try Self.home())
        XCTAssertEqual(model.phase, .dwelling); XCTAssertNil(f.journal.value); XCTAssertTrue(f.wire.restores.isEmpty)
        f.clock.now.addTimeInterval(10); await model.checkIn(home: try Self.home())
        XCTAssertEqual(model.phase, .verified); XCTAssertTrue(model.canRestore)
    }

    func testOriginalPolicyTokenAlphabetAndOneTo64ByteBoundaryRemainAccepted() throws {
        for id in ["p", ".", "_", "-", ":", "Policy_1.2:CN-v3", String(repeating: "p", count: 64)] {
            XCTAssertNoThrow(try published(id).validate())
        }
    }

    func testLabelLikePolicyValuesCannotBecomeUsableNativePolicy() throws {
        for id in ["", " ", "policy v1", "policy/v1", "政策", "policyé", "policy\n", String(repeating: "p", count: 65)] {
            XCTAssertThrowsError(try published(id).validate()) { XCTAssertEqual($0 as? NativeHomeReturnFailure, .invalid) }
        }
    }

    func testNumericPolicySafetyChecksAreNotReplacedByTokenValidation() throws {
        for value in [published("p", accuracy: 0), published("p", accuracy: .infinity),
                      published("p", age: 0), published("p", age: .nan), published("p", dwell: -1),
                      published("p", dwell: .infinity), published("p", serverTime: 0)] {
            XCTAssertThrowsError(try value.validate()) { XCTAssertEqual($0 as? NativeHomeReturnFailure, .invalid) }
        }
        XCTAssertNoThrow(try published("p", dwell: 0).validate())
    }

    func testNilAndExistingValidChallengeIdentifiersRemainAcceptedByPreflight() throws {
        let f = try Fixture()
        let values: [String?] = [nil, "c", "12a34567-89ab-4cde-8f01-23456789abcd", String(repeating: "c", count: 64)]
        for id in values {
            XCTAssertEqual(try check(f, challenge: id).challengeId, id)
        }
    }

    func testPreflightRejectsOversizeChallengeWithoutRelaxingExistingCharacterRules() throws {
        let f = try Fixture()
        for id in [String(repeating: "c", count: 65), String(repeating: "c", count: 96), "", ".c", "challenge/id", "challengeé", "challenge\n"] {
            XCTAssertThrowsError(try check(f, challenge: id)) { XCTAssertEqual($0 as? NativeHomeReturnFailure, .invalid) }
        }
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertNil(f.journal.value)
    }

    func testDwellResponseCannotStageAChallengeTheFinalTransportCannotSend() throws {
        let f = try Fixture(), original = try check(f)
        for count in [65, 96] {
            let response = NativeHomeReturnVerification(requestId: original.requestId, decision: .dwellRequired,
                proofId: nil, homeVersion: 3, expiresAtMillis: nil, retryAfterSeconds: 10,
                challengeId: String(repeating: "c", count: count), accountVersion: 4)
            XCTAssertThrowsError(try response.proof(for: original)) { XCTAssertEqual($0 as? NativeHomeReturnFailure, .invalid) }
        }
        let valid = NativeHomeReturnVerification(requestId: original.requestId, decision: .dwellRequired,
            proofId: nil, homeVersion: 3, expiresAtMillis: nil, retryAfterSeconds: 10,
            challengeId: String(repeating: "c", count: 64), accountVersion: 4)
        XCTAssertThrowsError(try valid.proof(for: original)) { XCTAssertEqual($0 as? NativeHomeReturnFailure, .dwellRequired(retryAfterSeconds: 10)) }
    }

    func testInvalidPublishedPolicyStopsBeforeAccountReadSamplingOrVerification() async throws {
        for id in ["policy space", "政策", "policy/path", String(repeating: "p", count: 65)] {
            let f = try Fixture(), model = f.model(); f.wire.policyVersion = id
            await model.load(); await model.checkIn(home: try Self.home()); await model.confirmRestore(home: try Self.home())
            XCTAssertEqual(model.phase, .unavailable); XCTAssertEqual(model.failure, .invalid); XCTAssertNil(model.account)
            XCTAssertEqual(f.wire.requests.map { $0.url?.lastPathComponent }, ["policy"])
            XCTAssertEqual(f.samples, 0); XCTAssertTrue(f.wire.checks.isEmpty); XCTAssertTrue(f.wire.restores.isEmpty)
            XCTAssertNil(f.journal.value); XCTAssertEqual(f.journal.saves, 0)
        }
    }

    func testCorrectedPolicyRequiresExplicitRefreshThenManualCheckAndSeparateConfirmation() async throws {
        let f = try Fixture(), model = f.model(); f.wire.policyVersion = "invalid policy"
        await model.load(); XCTAssertEqual(model.phase, .unavailable)
        f.wire.policyVersion = "."; await model.load()
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(f.samples, 0); XCTAssertTrue(f.wire.checks.isEmpty)
        await model.checkIn(home: try Self.home()); XCTAssertEqual(model.phase, .dwelling)
        XCTAssertEqual(f.wire.checks.first?["policyVersion"] as? String, ".")
        f.clock.now.addTimeInterval(10); await model.checkIn(home: try Self.home())
        XCTAssertEqual(model.phase, .verified); XCTAssertNil(f.journal.value); XCTAssertTrue(f.wire.restores.isEmpty)
        await model.confirmRestore(home: try Self.home())
        XCTAssertEqual(model.decision, .restored); XCTAssertEqual(model.account?.version, 5); XCTAssertEqual(f.journal.clears, 1)
    }

    func testOversizeDwellIsDiscardedAndNextExplicitCheckStartsWithoutThatChallenge() async throws {
        for count in [65, 96] {
            let f = try Fixture(), model = f.model(); f.wire.challengeID = String(repeating: "c", count: count)
            await model.load(); await model.checkIn(home: try Self.home())
            XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.failure, .invalid); XCTAssertNil(model.retryAfterSeconds)
            XCTAssertFalse(model.canRestore); await model.confirmRestore(home: try Self.home())
            XCTAssertNil(f.journal.value); XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertEqual(f.journal.saves, 0)
            f.wire.challengeID = "valid-challenge"; await model.checkIn(home: try Self.home())
            XCTAssertNil(f.wire.checks[1]["challengeId"]); XCTAssertEqual(model.phase, .dwelling)
            XCTAssertEqual(f.samples, 2); XCTAssertTrue(f.wire.restores.isEmpty)
        }
    }

    func testExact64BytePolicyAndChallengeCompleteRealRequestAndReceiptJourney() async throws {
        let f = try Fixture(), model = f.model()
        f.wire.policyVersion = String(repeating: "p", count: 64); f.wire.challengeID = String(repeating: "c", count: 64)
        try await reachProof(f, model)
        XCTAssertNil(f.wire.checks[0]["challengeId"])
        XCTAssertEqual(f.wire.checks[1]["challengeId"] as? String, f.wire.challengeID)
        XCTAssertTrue(f.wire.checks.allSatisfy { $0["policyVersion"] as? String == f.wire.policyVersion })
        XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertNil(f.journal.value)
        await model.confirmRestore(home: try Self.home())
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.decision, .restored); XCTAssertEqual(model.account?.version, 5)
        XCTAssertEqual(f.wire.restores.count, 1); XCTAssertEqual(f.journal.saves, 1); XCTAssertEqual(f.journal.clears, 1)
        XCTAssertEqual(f.samples, 2)
    }

    func testRepeatedValidDwellContinuationKeepsExactOriginalChallengeBeforeProof() async throws {
        let f = try Fixture(), model = f.model(); f.wire.challengeID = String(repeating: "c", count: 64)
        await model.load(); await model.checkIn(home: try Self.home())
        f.wire.reply = { Self.dwell($0, challenge: f.wire.challengeID) }
        await model.checkIn(home: try Self.home()); XCTAssertEqual(model.phase, .dwelling)
        XCTAssertEqual(f.wire.checks[1]["challengeId"] as? String, f.wire.challengeID)
        f.wire.reply = nil; f.clock.now.addTimeInterval(10); await model.checkIn(home: try Self.home())
        XCTAssertEqual(model.phase, .verified); XCTAssertEqual(f.wire.checks[2]["challengeId"] as? String, f.wire.challengeID)
        XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertNil(f.journal.value)
    }

    func testInvalidPolicyCannotUnlockOriginalUnknownAndDoesNotPreventOriginalReceiptRecovery() async throws {
        let f = try Fixture(), first = f.model(); try await reachProof(f, first)
        f.wire.loseNextRestore = true; await first.confirmRestore(home: try Self.home())
        let original = try XCTUnwrap(f.journal.value); XCTAssertEqual(first.phase, .unknown); first.invalidate()
        f.wire.policyVersion = "invalid policy"; let resumed = f.model(); await resumed.load()
        XCTAssertEqual(resumed.phase, .unknown); XCTAssertEqual(resumed.failure, .invalid); XCTAssertTrue(resumed.hasPendingRestore)
        XCTAssertEqual(f.journal.value, original); XCTAssertEqual(f.wire.restores, [original]); XCTAssertFalse(resumed.canCheckIn)
        await resumed.readBack()
        XCTAssertNil(f.journal.value); XCTAssertEqual(resumed.decision, .restored); XCTAssertNil(resumed.account)
        XCTAssertEqual(resumed.phase, .unavailable); XCTAssertTrue(resumed.requiresAccountReadback)
        XCTAssertEqual(f.wire.restores, [original]); XCTAssertEqual(f.journal.saves, 1); XCTAssertEqual(f.journal.clears, 1)
        f.wire.policyVersion = "synthetic"; await resumed.load()
        XCTAssertEqual(resumed.account?.version, 5); XCTAssertEqual(resumed.phase, .ready); XCTAssertEqual(f.wire.restores, [original])
    }

    func testRevocationAndDisabledDefaultAreNotBypassedByValidBoundaryTokens() async throws {
        let f = try Fixture(), disabled = f.model(enabled: false)
        f.wire.policyVersion = String(repeating: "p", count: 64); f.wire.challengeID = String(repeating: "c", count: 64)
        await disabled.load(); await disabled.checkIn(home: try Self.home())
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertEqual(f.samples, 0)
        let model = f.model(); await model.load(); await model.checkIn(home: try Self.home())
        f.wire.afterVerify = { f.grant.revoke() }; await model.checkIn(home: try Self.home())
        await model.confirmRestore(home: try Self.home())
        XCTAssertEqual(model.phase, .invalidated); XCTAssertNil(f.journal.value); XCTAssertTrue(f.wire.restores.isEmpty)
    }
}
