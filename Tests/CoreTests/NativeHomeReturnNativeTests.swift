import XCTest
@testable import QuestifyCore

/// Synthetic values only. No OS location, Keychain or backend access.
@available(macOS 14.0, *) @MainActor final class NativeHomeReturnNativeTests: XCTestCase {
    final class Clock { var date = Date(timeIntervalSince1970: 1_000_000) }
    final class Journal: NativeHomeReturnSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: NativeHomeRestoreRequest?
        var failRead = false, failSave = false, failClear = false
        var afterSave: (() -> Void)?
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() throws -> NativeHomeRestoreRequest? { if failRead { throw NativeHomeReturnFailure.storageUnavailable }; return value }
        func save(_ request: NativeHomeRestoreRequest) throws {
            if failSave || (value != nil && value != request) { throw NativeHomeReturnFailure.storageUnavailable }
            value = request; afterSave?()
        }
        func clear(matching request: NativeHomeRestoreRequest) throws {
            guard !failClear, value == request else { throw NativeHomeReturnFailure.storageUnavailable }; value = nil
        }
    }
    final class Service: NativeHomeReturnRunServing {
        let clock: Clock
        var requests: [NativeHomeRestoreRequest] = [], checks: [NativeHomeReturnCheck] = []
        var policyReads = 0, accountReads = 0, receiptReads = 0
        var current: Int64 = 2, version: Int64 = 4
        var lost = false, noReceipt = false, accountFails = false, corruptVerification = false
        var noDwell = false
        var policyResponseDelay: TimeInterval = 0
        var receipts: [String: NativeHomeRestoreReceipt] = [:]
        var pages: [NativeHomeReturnRuns] = []
        var cursors: [String?] = []
        init(_ clock: Clock) { self.clock = clock }
        func policy() async throws -> NativeHomeReturnPolicy? {
            policyReads += 1
            let serverTime = Int64(clock.date.timeIntervalSince1970 * 1000)
            clock.date.addTimeInterval(policyResponseDelay)
            return .init(policyVersion: "synthetic", maxAccuracyMeters: 50, maxFixAgeSeconds: 30,
                         dwellSeconds: 10, serverTimeMillis: serverTime)
        }
        func runs(beforeRunId: String?) async throws -> NativeHomeReturnRuns {
            cursors.append(beforeRunId)
            return pages.isEmpty ? .init(runs: [], truncated: false, nextBeforeRunId: nil) : pages.removeFirst()
        }
        func account(for scope: NativeHomeResourceScope) async throws -> NativeHomeResourceAccount {
            accountReads += 1
            if accountFails { throw NativeHomeReturnFailure.runUnavailable }
            return .init(resourceType: "sys.hp", scopeType: "RUN", scopeId: scope.wire["scopeId"], current: current, maximum: 5, version: version)
        }
        func verify(_ check: NativeHomeReturnCheck) async throws -> NativeHomeReturnVerification {
            checks.append(check)
            if !noDwell && check.challengeId == nil {
                return .init(requestId: check.requestId, decision: .dwellRequired, proofId: nil, homeVersion: check.homeVersion,
                    expiresAtMillis: nil, retryAfterSeconds: 10, challengeId: "challenge-1")
            }
            return .init(requestId: check.requestId, decision: .verified, proofId: "proof-1", homeVersion: check.homeVersion,
                expiresAtMillis: Int64((clock.date.timeIntervalSince1970 + 60) * 1000), retryAfterSeconds: nil,
                accountVersion: corruptVerification ? version + 1 : version)
        }
        func restore(_ request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt {
            requests.append(request)
            if receipts[request.requestId] == nil {
                current = 5; version += 1
                receipts[request.requestId] = .init(requestId: request.requestId, proofId: request.proofId,
                    decision: .restored, current: current, maximum: 5, accountVersion: version, retryAfterSeconds: nil)
            }
            if lost { lost = false; throw NativeHomeReturnFailure.network }
            return receipts[request.requestId]!
        }
        func restoreReceipt(for request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt? {
            receiptReads += 1; return noReceipt ? nil : receipts[request.requestId]
        }
    }
    func owner(_ id: Int = 7, realm: String = "synthetic") throws -> PlayExperienceSession {
        try .init(accountID: id, epoch: 1, namespace: realm, token: "synthetic-token")
    }
    func home(_ version: Int64 = 3) throws -> PrivateHomeSnapshot {
        try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data("{\"version\":\(version),\"status\":\"ACTIVE\",\"changedAt\":1,\"effectiveAt\":1,\"label\":\"Synthetic\",\"latitude\":12,\"longitude\":45,\"datum\":\"WGS84\"}".utf8))
    }
    func model(_ service: Service, _ journal: Journal?, enabled: Bool = true,
               current: @escaping () -> Bool = { true }, sample: (() async -> NativeHomeReturnLocationStatus)? = nil) throws -> NativeHomeReturnCoordinator {
        NativeHomeReturnCoordinator(scope: .run(runId: "42", resourceType: "sys.hp"), service: service, journal: journal,
            owner: try owner(), enabled: enabled,
            location: sample ?? { .measured(try! .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: service.clock.date)) },
            locationAuthorized: { true }, isCurrent: current, now: { service.clock.date })
    }
    func verified(_ model: NativeHomeReturnCoordinator) async throws {
        await model.load(); await model.checkIn(home: try home())
        if model.phase == .dwelling { await model.checkIn(home: try home()) }
        XCTAssertEqual(model.phase, .verified)
    }
    func testProductionDefaultOffAndJournalMandatoryBeforeAnyRead() async throws {
        let service = Service(Clock()), journal = Journal(try owner())
        let disabled = try model(service, journal, enabled: false), missing = try model(service, nil)
        await disabled.load(); await missing.load()
        XCTAssertEqual(disabled.phase, .disabled); XCTAssertEqual(missing.phase, .disabled); XCTAssertEqual(service.policyReads, 0)
    }
    func testExplicitTwoSamplesThenSeparateConfirmationAndAuthoritativeReadback() async throws {
        let service = Service(Clock()), journal = Journal(try owner()), model = try model(service, journal)
        await model.load(); XCTAssertTrue(service.checks.isEmpty); XCTAssertTrue(service.requests.isEmpty)
        await model.checkIn(home: try home())
        XCTAssertEqual(model.phase, .dwelling); XCTAssertEqual(model.retryAfterSeconds, 10); XCTAssertFalse(model.canRestore)
        XCTAssertNil(journal.value); XCTAssertTrue(service.requests.isEmpty)
        service.clock.date.addTimeInterval(10)
        await model.checkIn(home: try home())
        XCTAssertEqual(service.checks.last?.challengeId, "challenge-1"); XCTAssertEqual(model.phase, .verified)
        XCTAssertTrue(service.requests.isEmpty)
        await model.confirmRestore(home: try home()); await model.confirmRestore(home: try home())
        XCTAssertEqual(service.requests.count, 1); XCTAssertEqual(model.account?.current, 5); XCTAssertEqual(model.account?.version, 5)
        XCTAssertEqual(service.accountReads, 2); XCTAssertNil(journal.value)
    }
    func testLostResponseColdStartDoesNotReplayAndReadbackUsesOriginalRequest() async throws {
        let service = Service(Clock()), journal = Journal(try owner()), model = try model(service, journal)
        try await verified(model); service.lost = true
        await model.confirmRestore(home: try home())
        let original = try XCTUnwrap(journal.value)
        model.invalidate()
        let reopened = try self.model(service, journal); await reopened.load()
        XCTAssertEqual(reopened.phase, .unknown); XCTAssertEqual(service.requests.count, 1); XCTAssertFalse(reopened.canCheckIn)
        service.noReceipt = true; await reopened.readBack()
        XCTAssertEqual(journal.value, original); XCTAssertTrue(reopened.noReceiptYet)
        service.noReceipt = false; await reopened.readBack()
        XCTAssertNil(journal.value); XCTAssertEqual(service.requests.count, 1); XCTAssertEqual(reopened.account?.current, 5)
    }
    func testExactRetryRechecksJournalAndNeverCreatesNewKeyOrProof() async throws {
        let service = Service(Clock()), journal = Journal(try owner()), model = try model(service, journal)
        try await verified(model); service.lost = true; await model.confirmRestore(home: try home())
        let first = try XCTUnwrap(journal.value)
        await model.retryExact()
        XCTAssertEqual(service.requests, [first, first]); XCTAssertEqual(service.version, 5); XCTAssertEqual(service.checks.count, 2)
    }
    func testMissingDurablePendingDoesNotPermitReplay() async throws {
        let service = Service(Clock()), journal = Journal(try owner()), model = try model(service, journal)
        try await verified(model); service.lost = true; await model.confirmRestore(home: try home())
        journal.value = nil; await model.retryExact()
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(model.failure, .storageUnavailable); XCTAssertEqual(service.requests.count, 1)
    }
    func testLockedStorageBlocksBeforeHTTPAndFailedClearRetainsUnknown() async throws {
        let service = Service(Clock()), journal = Journal(try owner()), model = try model(service, journal)
        journal.failRead = true; await model.load(); XCTAssertEqual(model.phase, .blocked); XCTAssertEqual(service.policyReads, 0)
        journal.failRead = false; try await verified(model); journal.failClear = true
        await model.confirmRestore(home: try home())
        XCTAssertNotNil(journal.value); XCTAssertEqual(model.phase, .unknown)
    }
    func testRevocationDuringJournalSaveDoesNotDispatchOrEraseRecord() async throws {
        var valid = true
        let service = Service(Clock()), journal = Journal(try owner()), model = try model(service, journal, current: { valid })
        try await verified(model); journal.afterSave = { valid = false }
        await model.confirmRestore(home: try home())
        XCTAssertEqual(model.phase, .invalidated); XCTAssertNotNil(journal.value); XCTAssertTrue(service.requests.isEmpty)
    }
    func testProofAccountMismatchHomeChangeExpiryAndCancelNeverRestore() async throws {
        let service = Service(Clock()), journal = Journal(try owner()), model = try model(service, journal)
        service.noDwell = true; service.corruptVerification = true
        await model.load(); await model.checkIn(home: try home()); XCTAssertEqual(model.failure, .invalid)
        service.corruptVerification = false; await model.checkIn(home: try home())
        await model.confirmRestore(home: try home(4)); XCTAssertEqual(model.failure, .homeChanged)
        await model.checkIn(home: try home()); service.clock.date.addTimeInterval(61)
        await model.confirmRestore(home: try home()); XCTAssertEqual(model.failure, .proofExpired)
        await model.checkIn(home: try home()); model.cancelVerification(); await model.confirmRestore(home: try home())
        XCTAssertTrue(service.requests.isEmpty); XCTAssertNil(journal.value)
    }
    func testAuthoritativeAccountReadFailureDoesNotShowReceiptBalance() async throws {
        let service = Service(Clock()), journal = Journal(try owner()), model = try model(service, journal)
        try await verified(model); service.accountFails = true; await model.confirmRestore(home: try home())
        XCTAssertNil(model.account); XCTAssertTrue(model.requiresAccountReadback); XCTAssertFalse(model.canCheckIn)
        XCTAssertEqual(model.decision, .restored); XCTAssertNil(journal.value)
        service.accountFails = false; await model.load(); XCTAssertEqual(model.account?.current, 5)
    }
    func testChangedOrDeletedHomeDoesNotBlockOriginalUnknownReceipt() async throws {
        let service = Service(Clock()), journal = Journal(try owner()), model = try model(service, journal)
        try await verified(model); service.lost = true; await model.confirmRestore(home: try home())
        let original = try XCTUnwrap(journal.value)
        service.receipts[original.requestId] = .init(requestId: original.requestId, proofId: original.proofId,
            decision: .staleHome, current: 0, maximum: 0, accountVersion: original.expectedAccountVersion, retryAfterSeconds: nil)
        model.cancelVerification() // home deletion/navigation must not discard the UNKNOWN identity
        await model.checkIn(home: nil); XCTAssertEqual(service.checks.count, 2)
        await model.readBack()
        XCTAssertNil(journal.value); XCTAssertEqual(model.decision, .staleHome); XCTAssertEqual(service.requests.count, 1)
    }
    func testPermissionRevocationBeforeConfirmationDropsProofButNeverUnknown() async throws {
        var authorized = true
        let service = Service(Clock()), journal = Journal(try owner())
        let model = NativeHomeReturnCoordinator(scope: .run(runId: "42", resourceType: "sys.hp"), service: service, journal: journal,
            owner: try owner(), enabled: true,
            location: { .measured(try! .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: service.clock.date)) },
            locationAuthorized: { authorized }, isCurrent: { true }, now: { service.clock.date })
        try await verified(model); authorized = false; await model.confirmRestore(home: try home())
        XCTAssertFalse(model.canRestore); XCTAssertEqual(model.failure, .permissionDenied); XCTAssertTrue(service.requests.isEmpty)
        authorized = true; try await verified(model); service.lost = true; await model.confirmRestore(home: try home())
        authorized = false; await model.readBack()
        XCTAssertNil(journal.value); XCTAssertEqual(model.decision, .restored)
    }
    func testSixDecimalQuantizationIsConservativeAndFutureFixHasNoSlack() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let fix = try NativeHomeReturnFix(latitude: 12.1234567, longitude: -45.7654321, accuracyMeters: 5.1234561, capturedAt: now)
        XCTAssertEqual(fix.latitude, 12.123457); XCTAssertEqual(fix.longitude, -45.765432)
        XCTAssertEqual(fix.accuracyMeters, 5.123457); XCTAssertGreaterThanOrEqual(fix.accuracyMeters, 5.1234561)
        XCTAssertEqual(String(describing: fix), "NativeHomeReturnFix[redacted]")
        let policy = NativeHomeReturnPolicy(policyVersion: "synthetic", maxAccuracyMeters: 50, maxFixAgeSeconds: 30,
            dwellSeconds: 10, serverTimeMillis: 1_000_000_000)
        XCTAssertThrowsError(try NativeHomeReturnCheck.preflight(home: home(), status: .fix(accuracyMeters: 5, capturedAt: now.addingTimeInterval(0.01)),
            policy: policy, scope: .run(runId: "42", resourceType: "sys.hp"), now: now))
    }
    func testPolicyResponseLatencyDoesNotRejectFreshSameDeviceSample() async throws {
        let service = Service(Clock()), journal = Journal(try owner()), model = try model(service, journal)
        service.policyResponseDelay = 2; service.noDwell = true
        await model.load(); await model.checkIn(home: try home())
        XCTAssertEqual(service.checks.count, 1); XCTAssertEqual(model.phase, .verified); XCTAssertNil(model.failure)
    }
    func testFractionalOrZeroExplicitDwellAndSelfPlayActivityZeroAreValid() throws {
        for dwell in [0.0, 0.5] {
            let bytes = try JSONSerialization.data(withJSONObject: ["policyVersion": "synthetic", "maxAccuracyMeters": 50,
                "maxFixAgeSeconds": 30, "dwellSeconds": dwell, "serverTimeMillis": 1_000_000_000])
            let policy = try JSONDecoder().decode(NativeHomeReturnPolicy.self, from: bytes)
            try policy.validate(); XCTAssertEqual(policy.dwellSeconds, dwell)
        }
        let run = NativeHomeReturnRun(runId: "42", activityId: "0", topicId: "6", playInstanceId: "existing-self-play", resourceType: "sys.hp", current: 2, maximum: 5, version: 4)
        XCTAssertNoThrow(try run.validate())
    }
    func testNativeScopeAndIncompletePolicyFailClosed() throws {
        for scope in [NativeHomeResourceScope.global(resourceType: "sys.hp"), .theme(themeId: "42", resourceType: "sys.hp"),
                      .run(runId: "theme-42", resourceType: "sys.hp"), .run(runId: "042", resourceType: "sys.hp"), .run(runId: "42", resourceType: "luck")] {
            XCTAssertThrowsError(try scope.validateNative())
        }
        XCTAssertThrowsError(try JSONDecoder().decode(NativeHomeReturnPolicy.self, from: Data("{\"policyVersion\":\"v1\",\"maxAccuracyMeters\":10,\"maxFixAgeSeconds\":30}".utf8)))
    }
    func testRequestPersistenceHasNoLocationAndConsumedProofIsNotSuccess() async throws {
        let service = Service(Clock()), journal = Journal(try owner()), model = try model(service, journal)
        try await verified(model); service.lost = true; await model.confirmRestore(home: try home())
        let request = try XCTUnwrap(journal.value), bytes = try JSONEncoder().encode(request)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(Set(body.keys), ["proofId", "requestId", "homeVersion", "expectedAccountVersion", "scopeType", "scopeId", "resourceType"])
        XCTAssertEqual(try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: bytes), request)
        for decision in [NativeHomeRestoreReceipt.Decision.proofConsumed, .proofUnavailable, .runUnavailable] {
            let receipt = NativeHomeRestoreReceipt(requestId: request.requestId, proofId: request.proofId, decision: decision,
                current: 0, maximum: 0, accountVersion: request.expectedAccountVersion, retryAfterSeconds: nil)
            try receipt.validate(for: request); XCTAssertNotNil(receipt.failure)
        }
    }
    func testPartialRunsUseRealDescendingCursorAndExplicitSelection() async throws {
        let service = Service(Clock()), journal = Journal(try owner())
        let first = NativeHomeReturnRun(runId: "42", activityId: "5", topicId: "6", playInstanceId: "existing-1", resourceType: "sys.hp", current: 2, maximum: 5, version: 4)
        let second = NativeHomeReturnRun(runId: "12", activityId: "7", topicId: "8", playInstanceId: "existing-2", resourceType: "sys.hp", current: 2, maximum: 5, version: 4)
        service.pages = [.init(runs: [first], truncated: true, nextBeforeRunId: "20"), .init(runs: [second], truncated: false, nextBeforeRunId: nil)]
        let selection = NativeHomeReturnSelectionCoordinator(service: service, journal: journal, owner: try owner(), isCurrent: { true },
            makeModel: { scope in NativeHomeReturnCoordinator(scope: scope, service: service, journal: journal, owner: try! self.owner(), enabled: true,
                location: { .denied }, isCurrent: { true }, now: { service.clock.date }) })
        await selection.load(); XCTAssertNil(selection.selected); XCTAssertEqual(service.accountReads, 0)
        await selection.loadMore(); XCTAssertEqual(service.cursors, [nil, "20"]); XCTAssertEqual(selection.runs.map(\.id), ["42", "12"])
        await selection.select(second); XCTAssertEqual(selection.selected?.scope, second.scope); XCTAssertEqual(service.accountReads, 1)
    }
}
