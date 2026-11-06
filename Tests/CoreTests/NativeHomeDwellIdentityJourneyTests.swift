import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// NOT_RUN. Real Service/Transport/Coordinator over in-memory bytes and journal; no OS location or Keychain.
/// Synthetic approval and location status exist only inside these unexecuted tests, not production configuration.
@available(macOS 14.0, *) @MainActor final class NativeHomeDwellIdentityJourneyTests: XCTestCase {
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
        init(_ clock: Clock) { self.clock = clock }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let value: Any
            switch request.url?.lastPathComponent {
            case "policy":
                value = ["policyVersion": "synthetic", "maxAccuracyMeters": 20, "maxFixAgeSeconds": 30,
                         "dwellSeconds": 10, "serverTimeMillis": Int64(clock.now.timeIntervalSince1970 * 1000)]
            case "account":
                value = ["resourceType": "sys.hp", "scopeType": "RUN", "scopeId": "42", "current": current, "maximum": 5, "version": accountVersion]
            case "verify":
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                checks.append(body)
                if let reply { value = try reply(body) }
                else if body["challengeId"] == nil { value = NativeHomeDwellIdentityJourneyTests.dwell(body) }
                else { value = NativeHomeDwellIdentityJourneyTests.verified(body, now: clock.now) }
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
            .init(scope: NativeHomeDwellIdentityJourneyTests.scope, service: service, journal: journal, owner: grant.context.session,
                enabled: enabled, location: {
                    self.samples += 1
                    return .measured(try! .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: self.clock.now))
                }, locationAuthorized: { true }, isCurrent: { self.service.isCurrent() }, now: { self.clock.now })
        }
    }
    private func check(_ f: Fixture, challenge: String? = nil) throws -> NativeHomeReturnCheck {
        try .preflight(home: Self.home(), status: .measured(.init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: f.clock.now)),
            policy: Self.policy(f.clock.now), scope: Self.scope, now: f.clock.now,
            requestId: "verify-original", expectedAccountVersion: 4, challengeId: challenge)
    }
    private func rejects(_ f: Fixture, challenge: String? = nil) async throws {
        do { _ = try await f.service.verify(check(f, challenge: challenge)); XCTFail("Mismatched dwell identity must fail") }
        catch { XCTAssertEqual(error as? NativeHomeReturnFailure, .invalid) }
        XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertNil(f.journal.value)
    }
    private func reachProof(_ f: Fixture, _ model: NativeHomeReturnCoordinator) async throws {
        await model.load(); await model.checkIn(home: try Self.home())
        XCTAssertEqual(model.phase, .dwelling); XCTAssertFalse(model.canRestore)
        f.clock.now.addTimeInterval(10); await model.checkIn(home: try Self.home())
        XCTAssertEqual(model.phase, .verified); XCTAssertTrue(model.canRestore)
        XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertNil(f.journal.value)
    }

    func testFirstDwellBindsAccountButIsNotAProofOrARestore() async throws {
        let f = try Fixture(), original = try check(f)
        let response = try await f.service.verify(original)
        XCTAssertEqual(response.accountVersion, 4); XCTAssertEqual(response.challengeId, "challenge-original")
        XCTAssertThrowsError(try response.proof(for: original)) { XCTAssertEqual($0 as? NativeHomeReturnFailure, .dwellRequired(retryAfterSeconds: 10)) }
        XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertEqual(f.journal.saves, 0)
    }

    func testMissingNullAndWrongAccountVersionsCannotStageDwell() async throws {
        for variant in 0..<5 {
            let f = try Fixture()
            f.wire.reply = { body in
                var value = Self.dwell(body)
                switch variant {
                case 0: value.removeValue(forKey: "accountVersion")
                case 1: value["accountVersion"] = NSNull()
                case 2: value["accountVersion"] = -1
                case 3: value["accountVersion"] = 3
                default: value["accountVersion"] = 5
                }
                return value
            }
            try await rejects(f)
        }
    }

    func testValidContinuationMustReturnTheSameOriginalChallenge() async throws {
        let f = try Fixture(); f.wire.reply = { Self.dwell($0) }
        let original = try check(f, challenge: "challenge-original"), response = try await f.service.verify(original)
        XCTAssertEqual(response.challengeId, original.challengeId); XCTAssertEqual(response.accountVersion, 4)
        XCTAssertThrowsError(try response.proof(for: original)) { XCTAssertEqual($0 as? NativeHomeReturnFailure, .dwellRequired(retryAfterSeconds: 10)) }
    }

    func testMissingNullOrReplacedContinuationChallengeFailsAtServiceBoundary() async throws {
        for variant in 0..<4 {
            let f = try Fixture()
            f.wire.reply = { body in
                var value = Self.dwell(body)
                switch variant {
                case 0: value.removeValue(forKey: "challengeId")
                case 1: value["challengeId"] = NSNull()
                case 2: value["challengeId"] = ""
                default: value["challengeId"] = "another-valid-challenge"
                }
                return value
            }
            try await rejects(f, challenge: "challenge-original")
        }
    }

    func testInitialChallengeRemainsServerSelectedWithoutInventedClientIdentifier() async throws {
        let f = try Fixture(); f.wire.reply = { Self.dwell($0, challenge: "server-issued-other-id") }
        let original = try check(f), response = try await f.service.verify(original)
        XCTAssertNil(original.challengeId); XCTAssertEqual(response.challengeId, "server-issued-other-id")
        XCTAssertThrowsError(try response.proof(for: original)) { XCTAssertEqual($0 as? NativeHomeReturnFailure, .dwellRequired(retryAfterSeconds: 10)) }
    }

    func testExistingVerifiedAccountIdentityCheckIsStillEnforced() async throws {
        let f = try Fixture()
        f.wire.reply = { body in var value = Self.verified(body, now: f.clock.now); value["accountVersion"] = 5; return value }
        try await rejects(f, challenge: "challenge-original")
    }

    func testTransportFreeOptionalAccountContractDoesNotBecomeANativeBypass() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let original = try NativeHomeReturnCheck.preflight(home: Self.home(), status: .fix(accuracyMeters: 5, capturedAt: now),
            policy: Self.policy(now), scope: Self.scope, now: now, requestId: "offline-optional")
        let response = NativeHomeReturnVerification(requestId: original.requestId, decision: .dwellRequired, proofId: nil,
            homeVersion: 3, expiresAtMillis: nil, retryAfterSeconds: 10, challengeId: "challenge-original", accountVersion: nil)
        XCTAssertNoThrow(try response.validateIdentity(for: original))
        XCTAssertThrowsError(try response.proof(for: original)) { XCTAssertEqual($0 as? NativeHomeReturnFailure, .dwellRequired(retryAfterSeconds: 10)) }
        // Native still rejects absent version even with a measured fix; no legacy-value bypass.
        let f = try Fixture()
        for status in [NativeHomeReturnLocationStatus.fix(accuracyMeters: 5, capturedAt: now),
                       .measured(try .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: now))] {
            let incomplete = try NativeHomeReturnCheck.preflight(home: Self.home(), status: status,
                policy: Self.policy(now), scope: Self.scope, now: now)
            do { _ = try await f.service.verify(incomplete); XCTFail() }
            catch { XCTAssertEqual(error as? NativeHomeReturnFailure, .invalid) }
        }
        XCTAssertTrue(f.wire.requests.isEmpty)
    }

    func testInvalidDwellAccountNeverReachesConfirmationOrSecureJournal() async throws {
        let f = try Fixture(), model = f.model()
        f.wire.reply = { body in var value = Self.dwell(body); value.removeValue(forKey: "accountVersion"); return value }
        await model.load(); await model.checkIn(home: try Self.home())
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.failure, .invalid); XCTAssertNil(model.retryAfterSeconds)
        XCTAssertFalse(model.canRestore); await model.confirmRestore(home: try Self.home())
        XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertNil(f.journal.value); XCTAssertEqual(f.journal.saves, 0)
    }

    func testReplacedContinuationIsDiscardedAndNextExplicitCheckStartsWithoutIt() async throws {
        let f = try Fixture(), model = f.model()
        await model.load(); await model.checkIn(home: try Self.home()); XCTAssertEqual(model.phase, .dwelling)
        f.wire.reply = { Self.dwell($0, challenge: "replacement") }
        await model.checkIn(home: try Self.home())
        XCTAssertEqual(f.wire.checks[1]["challengeId"] as? String, "challenge-original")
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.failure, .invalid); XCTAssertNil(model.retryAfterSeconds)
        f.wire.reply = nil; await model.checkIn(home: try Self.home())
        XCTAssertNil(f.wire.checks[2]["challengeId"]); XCTAssertEqual(model.phase, .dwelling)
        XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertNil(f.journal.value)
    }

    func testOriginalDwellProofAndSeparateExplicitRestoreCompleteWithCurrentReadback() async throws {
        let f = try Fixture(), model = f.model(); try await reachProof(f, model)
        XCTAssertEqual(f.samples, 2); XCTAssertNil(f.wire.checks[0]["challengeId"])
        XCTAssertEqual(f.wire.checks[1]["challengeId"] as? String, "challenge-original")
        XCTAssertNotEqual(f.wire.checks[0]["requestId"] as? String, f.wire.checks[1]["requestId"] as? String)
        await model.confirmRestore(home: try Self.home()); await model.confirmRestore(home: try Self.home())
        XCTAssertEqual(f.wire.restores.count, 1); XCTAssertEqual(f.journal.saves, 1); XCTAssertEqual(f.journal.clears, 1)
        XCTAssertNil(f.journal.value); XCTAssertEqual(model.decision, .restored); XCTAssertEqual(model.account?.version, 5)
        XCTAssertEqual(model.account?.current, 5); XCTAssertEqual(model.phase, .ready)
    }

    func testLostRestoreAfterDwellSurvivesModelRecreationWithoutNewSamplesOrReplay() async throws {
        let f = try Fixture(), first = f.model(); try await reachProof(f, first)
        f.wire.loseNextRestore = true; await first.confirmRestore(home: try Self.home())
        let original = try XCTUnwrap(f.journal.value); XCTAssertEqual(first.phase, .unknown)
        first.invalidate(); let resumed = f.model(); await resumed.load()
        XCTAssertEqual(resumed.phase, .unknown); XCTAssertEqual(f.journal.value, original)
        XCTAssertEqual(f.samples, 2); XCTAssertEqual(f.wire.checks.count, 2); XCTAssertEqual(f.wire.restores, [original])
        await resumed.readBack()
        XCTAssertNil(f.journal.value); XCTAssertEqual(f.journal.clears, 1); XCTAssertEqual(resumed.decision, .restored)
        XCTAssertEqual(f.wire.restores, [original]); XCTAssertEqual(f.samples, 2)
    }

    func testCancellingDwellDropsOnlyEphemeralChallengeAndDoesNotWrite() async throws {
        let f = try Fixture(), model = f.model()
        await model.load(); await model.checkIn(home: try Self.home()); model.cancelVerification()
        XCTAssertEqual(model.phase, .ready); XCTAssertNil(model.retryAfterSeconds); XCTAssertFalse(model.canRestore)
        await model.checkIn(home: try Self.home())
        XCTAssertNil(f.wire.checks[1]["challengeId"]); XCTAssertEqual(model.phase, .dwelling)
        XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertEqual(f.journal.saves, 0)
    }

    func testHomeChangeStartsANewCheckInsteadOfReusingTheOldChallenge() async throws {
        let f = try Fixture(), model = f.model()
        await model.load(); await model.checkIn(home: try Self.home())
        await model.checkIn(home: try Self.home(4))
        XCTAssertNil(f.wire.checks[1]["challengeId"]); XCTAssertEqual(f.wire.checks[1]["homeVersion"] as? Int, 4)
        XCTAssertEqual(model.phase, .dwelling); XCTAssertTrue(f.wire.restores.isEmpty)
    }

    func testOriginalDenialShapeNeverStagesChallengeOrProof() async throws {
        let f = try Fixture(), model = f.model()
        f.wire.reply = { body in
            var value = Self.dwell(body); value["decision"] = "OUT_OF_RADIUS"
            value["challengeId"] = NSNull(); value["retryAfterSeconds"] = NSNull(); return value
        }
        await model.load(); await model.checkIn(home: try Self.home())
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.failure, .outOfRadius); XCTAssertFalse(model.canRestore)
        XCTAssertNil(f.journal.value); XCTAssertTrue(f.wire.restores.isEmpty)
    }

    func testGrantRevocationDuringDwellReplyCannotPublishAChallenge() async throws {
        let f = try Fixture(), model = f.model(); await model.load()
        f.wire.afterVerify = { f.grant.revoke() }; await model.checkIn(home: try Self.home())
        XCTAssertEqual(model.phase, .invalidated); XCTAssertFalse(model.canRestore); XCTAssertNil(model.retryAfterSeconds)
        XCTAssertNil(f.journal.value); XCTAssertTrue(f.wire.restores.isEmpty)
    }

    func testDefaultDisabledModelNeverSamplesOrVerifies() async throws {
        let f = try Fixture(), model = f.model(enabled: false)
        await model.load(); await model.checkIn(home: try Self.home())
        XCTAssertEqual(model.phase, .disabled); XCTAssertEqual(f.samples, 0); XCTAssertTrue(f.wire.requests.isEmpty)
    }
}
