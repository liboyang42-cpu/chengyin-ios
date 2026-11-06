import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// NOT_RUN. Real coordinator/service/final transport over fake wire, permission queries and journal.
/// No OS provider, location request, Keychain, production grant or actual server is used.
@available(macOS 14.0, *) @MainActor final class NativeHomeCheckInAuthorizationJourneyTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private static let scope = NativeHomeResourceScope.run(runId: "42", resourceType: "sys.hp")
    private static func home() throws -> PrivateHomeSnapshot {
        try JSONDecoder().decode(PrivateHomeSnapshot.self,
            from: Data(#"{"version":3,"status":"ACTIVE","label":"Synthetic","latitude":12,"longitude":45,"datum":"WGS84","changedAt":1,"effectiveAt":1}"#.utf8))
    }
    @MainActor private final class Pause {
        let entered: XCTestExpectation
        private var continuation: CheckedContinuation<Void, Never>?
        init(_ entered: XCTestExpectation) { self.entered = entered }
        func wait() async { await withCheckedContinuation { continuation = $0; entered.fulfill() } }
        func resume() { let old = continuation; continuation = nil; old?.resume() }
    }
    @MainActor private final class Journal: NativeHomeReturnSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: NativeHomeRestoreRequest?
        var saves = 0, clears = 0
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() -> NativeHomeRestoreRequest? { value }
        func save(_ request: NativeHomeRestoreRequest) throws {
            guard value == nil || value == request else { throw NativeHomeReturnFailure.storageUnavailable }
            saves += 1; value = request
        }
        func clear(matching request: NativeHomeRestoreRequest) throws {
            guard value == request else { throw NativeHomeReturnFailure.storageUnavailable }
            clears += 1; value = nil
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], checks: [[String: Any]] = [], restores: [NativeHomeRestoreRequest] = []
        var receipts: [String: [String: Any]] = [:]
        var verifyPause: Pause?
        var dwell = false, loseWrite = false
        var version = 4, current = 2
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let value: Any
            switch request.url?.lastPathComponent {
            case "policy":
                value = ["policyVersion": "synthetic", "maxAccuracyMeters": 20, "maxFixAgeSeconds": 30,
                         "dwellSeconds": dwell ? 10 : 0, "serverTimeMillis": 1_000_000_000]
            case "account":
                value = ["resourceType": "sys.hp", "scopeType": "RUN", "scopeId": "42", "current": current, "maximum": 5, "version": version]
            case "verify":
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                checks.append(body)
                if dwell {
                    value = ["requestId": body["requestId"]!, "decision": "DWELL_REQUIRED", "proofId": NSNull(),
                             "homeVersion": body["homeVersion"]!, "expiresAtMillis": NSNull(), "retryAfterSeconds": 10,
                             "challengeId": "challenge-original", "accountVersion": body["expectedAccountVersion"]!]
                } else {
                    value = ["requestId": body["requestId"]!, "decision": "VERIFIED", "proofId": "proof-original",
                             "homeVersion": body["homeVersion"]!, "expiresAtMillis": 1_000_060_000, "retryAfterSeconds": NSNull(),
                             "challengeId": NSNull(), "accountVersion": body["expectedAccountVersion"]!]
                }
                if let pause = verifyPause { verifyPause = nil; await pause.wait() }
            case "restore":
                let original = try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: XCTUnwrap(request.httpBody))
                restores.append(original)
                if receipts[original.requestId] == nil {
                    version += 1; current = 5
                    receipts[original.requestId] = ["requestId": original.requestId, "proofId": original.proofId,
                        "decision": "RESTORED", "current": current, "maximum": 5, "accountVersion": version, "retryAfterSeconds": NSNull()]
                }
                if loseWrite { loseWrite = false; throw NativeHomeReturnFailure.unknown }
                value = try XCTUnwrap(receipts[original.requestId])
            case "receipt":
                let url = try XCTUnwrap(request.url)
                let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? ""
                if let receipt = receipts[id] { value = receipt } else { value = NSNull() }
            default: throw NativeHomeReturnFailure.invalid
            }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": value]), 200)
        }
    }
    @MainActor private final class Fixture {
        let grant: NativeHomeReturnApproval, service: NativeHomeReturnService, journal: Journal, wire: Wire
        var permission = true, foreground = true, services = true
        var samples = 0, stops = 0
        var samplePause: Pause?
        var afterSample: (() -> Void)?
        var status: NativeHomeReturnLocationStatus
        var authorized: Bool { permission && foreground && services }
        init() throws {
            let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic-check-in", token: "synthetic-token", role: "player")
            let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://check-in.example.test")!, role: "player", session: owner)
            let grant = try NativeHomeReturnApproval(context: context, expiresAt: Date().addingTimeInterval(600)), wire = Wire()
            let transport = NativeHomeReturnTransport(approval: grant, underlying: wire, current: { grant.context }, selected: { _ in grant })
            self.grant = grant; self.wire = wire; journal = Journal(owner)
            service = NativeHomeReturnService(approval: grant, transport: transport, current: { grant.context }, selected: { _ in grant })
            status = .measured(try .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: NativeHomeCheckInAuthorizationJourneyTests.now))
        }
        func sample() async -> NativeHomeReturnLocationStatus {
            samples += 1
            if let pause = samplePause { samplePause = nil; await pause.wait() }
            afterSample?(); return status
        }
        func model(enabled: Bool = true) -> NativeHomeReturnCoordinator {
            .init(scope: NativeHomeCheckInAuthorizationJourneyTests.scope, service: service, journal: journal, owner: grant.context.session,
                enabled: enabled, location: { await self.sample() }, stopLocation: { self.stops += 1 },
                locationAuthorized: { self.authorized }, isCurrent: { self.service.isCurrent() }, now: { NativeHomeCheckInAuthorizationJourneyTests.now })
        }
    }
    private func discarded(_ model: NativeHomeReturnCoordinator, _ f: Fixture, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.phase, .ready, file: file, line: line); XCTAssertFalse(model.canRestore, file: file, line: line)
        XCTAssertNil(model.retryAfterSeconds, file: file, line: line); XCTAssertFalse(model.hasPendingRestore, file: file, line: line)
        XCTAssertEqual(f.journal.saves, 0, file: file, line: line); XCTAssertEqual(f.journal.clears, 0, file: file, line: line)
        XCTAssertTrue(f.wire.restores.isEmpty, file: file, line: line)
    }

    func testUnchangedAuthorizedFlowRequiresSeparateConfirmationThenCurrentRead() async throws {
        let f = try Fixture(), model = f.model(); await model.load(); let home = try Self.home()
        XCTAssertEqual(f.samples, 0); await model.checkIn(home: home)
        XCTAssertEqual(model.phase, .verified); XCTAssertTrue(model.canRestore)
        XCTAssertEqual(f.wire.checks.count, 1); XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertEqual(f.journal.saves, 0)
        await model.confirmRestore(home: home)
        XCTAssertEqual(model.decision, .restored); XCTAssertEqual(model.account?.version, 5)
        XCTAssertEqual(f.journal.saves, 1); XCTAssertEqual(f.journal.clears, 1); XCTAssertNil(f.journal.value)
    }
    func testPermissionRevokedAfterAdapterResultCannotForwardMeasuredFix() async throws {
        let f = try Fixture(), model = f.model(); await model.load()
        f.afterSample = { f.permission = false }
        await model.checkIn(home: try Self.home()); discarded(model, f)
        XCTAssertEqual(model.failure, .permissionDenied); XCTAssertEqual(f.samples, 1); XCTAssertTrue(f.wire.checks.isEmpty)
    }
    func testForegroundOrServicesLossAtConsumerResumptionStopsVerify() async throws {
        for foreground in [false, true] {
            let f = try Fixture(), model = f.model(); await model.load()
            f.afterSample = { if foreground { f.foreground = false } else { f.services = false } }
            await model.checkIn(home: try Self.home()); discarded(model, f)
            XCTAssertEqual(model.failure, .permissionDenied); XCTAssertTrue(f.wire.checks.isEmpty)
        }
    }
    func testExplicitUnavailableSampleReasonsRemainDistinctBeforeAuthorizationFallback() async throws {
        let cases: [(NativeHomeReturnLocationStatus, NativeHomeReturnFailure)] = [
            (.servicesOff, .locationOff), (.denied, .permissionDenied), (.notDetermined, .permissionDenied)]
        for pair in cases {
            let f = try Fixture(), model = f.model(); f.permission = false; f.status = pair.0
            await model.load(); await model.checkIn(home: try Self.home()); discarded(model, f)
            XCTAssertEqual(model.failure, pair.1); XCTAssertTrue(f.wire.checks.isEmpty)
        }
    }
    func testDefaultFalseAuthorizationClosureCannotTurnMeasuredStatusIntoPermission() async throws {
        let f = try Fixture()
        let model = NativeHomeReturnCoordinator(scope: Self.scope, service: f.service, journal: f.journal, owner: f.grant.context.session,
            enabled: true, location: { await f.sample() }, isCurrent: { f.service.isCurrent() }, now: { Self.now })
        await model.load(); await model.checkIn(home: try Self.home()); discarded(model, f)
        XCTAssertEqual(model.failure, .permissionDenied); XCTAssertTrue(f.wire.checks.isEmpty)
    }
    func testLateVerifiedResponseAfterRevocationCannotStageProofOrRestore() async throws {
        let f = try Fixture(), model = f.model(); await model.load(); let home = try Self.home()
        let paused = expectation(description: "Synthetic verify already dispatched"), pause = Pause(paused)
        f.wire.verifyPause = pause
        let task = Task { await model.checkIn(home: home) }
        await fulfillment(of: [paused], timeout: 1); f.permission = false; pause.resume(); await task.value
        discarded(model, f); XCTAssertEqual(model.failure, .permissionDenied); XCTAssertEqual(f.wire.checks.count, 1)
        f.permission = true; XCTAssertFalse(model.canRestore); await model.confirmRestore(home: home)
        XCTAssertTrue(f.wire.restores.isEmpty)
        await model.checkIn(home: home); XCTAssertEqual(model.phase, .verified); XCTAssertEqual(f.wire.checks.count, 2)
        XCTAssertNotEqual(f.wire.checks[0]["requestId"] as? String, f.wire.checks[1]["requestId"] as? String)
    }
    func testLateDwellResponseAfterForegroundLossCannotRetainChallenge() async throws {
        let f = try Fixture(), model = f.model(); f.wire.dwell = true; await model.load(); let home = try Self.home()
        let paused = expectation(description: "Synthetic dwell response waits"), pause = Pause(paused)
        f.wire.verifyPause = pause
        let task = Task { await model.checkIn(home: home) }
        await fulfillment(of: [paused], timeout: 1); f.foreground = false; pause.resume(); await task.value
        discarded(model, f); XCTAssertEqual(model.failure, .permissionDenied)
        f.foreground = true; await model.checkIn(home: home)
        XCTAssertEqual(model.phase, .dwelling); XCTAssertEqual(f.wire.checks.count, 2)
        XCTAssertNil(f.wire.checks[1]["challengeId"])
    }
    func testTaskCancelledWhileSamplerIgnoresCancellationNeverDispatchesVerify() async throws {
        let f = try Fixture(), model = f.model(); await model.load(); let home = try Self.home()
        let paused = expectation(description: "Synthetic sampler waits"), pause = Pause(paused)
        f.samplePause = pause
        let task = Task { await model.checkIn(home: home) }
        await fulfillment(of: [paused], timeout: 1); task.cancel(); pause.resume(); await task.value
        discarded(model, f); XCTAssertTrue(f.wire.checks.isEmpty); XCTAssertGreaterThan(f.stops, 0)
    }
    func testTaskCancelledAfterVerifyDispatchDoesNotStageOrRepeatAnything() async throws {
        let f = try Fixture(), model = f.model(); await model.load(); let home = try Self.home()
        let paused = expectation(description: "Verify dispatched before task cancellation"), pause = Pause(paused)
        f.wire.verifyPause = pause
        let task = Task { await model.checkIn(home: home) }
        await fulfillment(of: [paused], timeout: 1); task.cancel(); pause.resume(); await task.value
        discarded(model, f); XCTAssertEqual(f.wire.checks.count, 1); XCTAssertGreaterThan(f.stops, 0)
        XCTAssertNil(model.failure) // Cancellation is not manufactured as a network denial or success.
    }
    func testAlreadyCancelledCheckInDoesNotStartAnotherSampleOrDiscardStagedProof() async throws {
        let f = try Fixture(), model = f.model(); await model.load(); let home = try Self.home()
        await model.checkIn(home: home); XCTAssertEqual(model.phase, .verified)
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; await model.checkIn(home: home) }
        await task.value
        XCTAssertEqual(f.samples, 1); XCTAssertEqual(f.wire.checks.count, 1); XCTAssertTrue(model.canRestore)
        XCTAssertEqual(f.journal.saves, 0)
    }
    func testNavigationCancellationAndGrantRevocationStillFenceLateVerify() async throws {
        for revoke in [false, true] {
            let f = try Fixture(), model = f.model(); await model.load(); let home = try Self.home()
            let paused = expectation(description: "Verify waits across lifecycle change"), pause = Pause(paused)
            f.wire.verifyPause = pause
            let task = Task { await model.checkIn(home: home) }
            await fulfillment(of: [paused], timeout: 1)
            if revoke { f.grant.revoke() } else { model.cancelVerification() }
            pause.resume(); await task.value
            XCTAssertEqual(model.phase, revoke ? .invalidated : .ready); XCTAssertFalse(model.canRestore)
            XCTAssertEqual(f.journal.saves, 0); XCTAssertEqual(f.journal.clears, 0); XCTAssertTrue(f.wire.restores.isEmpty)
        }
    }
    private func lostOriginal(_ f: Fixture, _ model: NativeHomeReturnCoordinator) async throws -> NativeHomeRestoreRequest {
        let home = try Self.home(); await model.load(); await model.checkIn(home: home)
        f.wire.loseWrite = true; await model.confirmRestore(home: home)
        XCTAssertEqual(model.phase, .unknown); return try XCTUnwrap(f.journal.value)
    }
    func testUnknownReceiptReadRemainsPossibleAfterLocationPermissionIsGone() async throws {
        let f = try Fixture(), model = f.model(); let original = try await lostOriginal(f, model)
        f.permission = false; f.foreground = false; let samples = f.samples
        await model.checkIn(home: try Self.home())
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(f.journal.value, original)
        await model.readBack()
        XCTAssertEqual(model.decision, .restored); XCTAssertEqual(model.account?.version, 5)
        XCTAssertNil(f.journal.value); XCTAssertEqual(f.samples, samples); XCTAssertEqual(f.wire.restores, [original])
    }
    func testOriginalExactRetryDoesNotRequireNewLocationOrEraseUnknownEarly() async throws {
        let f = try Fixture(), model = f.model(); let original = try await lostOriginal(f, model)
        f.permission = false; let samples = f.samples
        await model.retryExact()
        XCTAssertEqual(f.wire.restores, [original, original]); XCTAssertEqual(f.samples, samples)
        XCTAssertEqual(model.decision, .restored); XCTAssertNil(f.journal.value); XCTAssertEqual(f.journal.clears, 1)
    }
    func testDefaultOffStillPerformsNoReadsSamplesOrWrites() async throws {
        let f = try Fixture(), model = f.model(enabled: false)
        await model.load(); await model.checkIn(home: try Self.home()); await model.confirmRestore(home: try Self.home())
        XCTAssertEqual(model.phase, .disabled); XCTAssertEqual(f.samples, 0); XCTAssertTrue(f.wire.requests.isEmpty)
        XCTAssertEqual(f.journal.saves, 0); XCTAssertEqual(f.journal.clears, 0)
    }
}
