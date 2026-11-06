import XCTest
@testable import QuestifyCore

/// Synthetic coordinator flow definitions only. No backend, location, Keychain or grant. NOT_RUN.
@available(macOS 14.0, *) @MainActor final class NativeHomeAccountReadbackFenceTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private final class Journal: NativeHomeReturnSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: NativeHomeRestoreRequest?
        var failRead = false, failClear = false
        var saves = 0, clears = 0
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() throws -> NativeHomeRestoreRequest? {
            if failRead { throw NativeHomeReturnFailure.storageUnavailable }; return value
        }
        func save(_ request: NativeHomeRestoreRequest) throws {
            guard value == nil || value == request else { throw NativeHomeReturnFailure.storageUnavailable }
            value = request; saves += 1
        }
        func clear(matching request: NativeHomeRestoreRequest) throws {
            guard !failClear, value == request else { throw NativeHomeReturnFailure.storageUnavailable }
            value = nil; clears += 1
        }
    }
    private final class Service: NativeHomeReturnServing {
        var version: Int64 = 4, current: Int64 = 2, maximum: Int64 = 5
        var wrongScope = false, policyMissing = false, failAccount = false, loseResponse = false
        var decision: NativeHomeRestoreReceipt.Decision = .restored
        var receiptVersion: Int64?, afterRestoreVersion: Int64?
        var reads = 0, policyReads = 0, receiptReads = 0
        var checks: [NativeHomeReturnCheck] = [], requests: [NativeHomeRestoreRequest] = []
        var receipts: [String: NativeHomeRestoreReceipt] = [:]
        var afterAccount: (() -> Void)?
        func policy() async throws -> NativeHomeReturnPolicy? {
            policyReads += 1
            return policyMissing ? nil : .init(policyVersion: "synthetic", maxAccuracyMeters: 20, maxFixAgeSeconds: 30,
                dwellSeconds: 0, serverTimeMillis: 1_000_000_000)
        }
        func account(for scope: NativeHomeResourceScope) async throws -> NativeHomeResourceAccount {
            reads += 1
            if failAccount { throw NativeHomeReturnFailure.network }
            let value = NativeHomeResourceAccount(resourceType: "sys.hp", scopeType: "RUN", scopeId: wrongScope ? "999" : scope.wire["scopeId"],
                current: current, maximum: maximum, version: version)
            afterAccount?(); return value
        }
        func verify(_ check: NativeHomeReturnCheck) async throws -> NativeHomeReturnVerification {
            checks.append(check)
            return .init(requestId: check.requestId, decision: .verified, proofId: "synthetic-proof",
                homeVersion: check.homeVersion, expiresAtMillis: 1_000_060_000, retryAfterSeconds: nil,
                accountVersion: check.expectedAccountVersion)
        }
        func restore(_ request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt {
            requests.append(request)
            if receipts[request.requestId] == nil {
                let storedVersion = receiptVersion ?? (decision == .restored ? request.expectedAccountVersion + 1 : request.expectedAccountVersion)
                let successful = decision == .restored || decision == .alreadyAtMax
                receipts[request.requestId] = .init(requestId: request.requestId, proofId: request.proofId, decision: decision,
                    current: successful ? 5 : 2, maximum: 5, accountVersion: storedVersion, retryAfterSeconds: decision == .cooldown ? 1 : nil)
                version = afterRestoreVersion ?? storedVersion; current = successful ? 5 : 2
            }
            if loseResponse { loseResponse = false; throw NativeHomeReturnFailure.network }
            return receipts[request.requestId]!
        }
        func restoreReceipt(for request: NativeHomeRestoreRequest) async throws -> NativeHomeRestoreReceipt? {
            receiptReads += 1; return receipts[request.requestId]
        }
    }
    private func owner(_ id: Int = 7) throws -> PlayExperienceSession {
        try .init(accountID: id, epoch: 1, namespace: "synthetic", token: "synthetic-token")
    }
    private func home() throws -> PrivateHomeSnapshot {
        try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(#"{"version":3,"status":"ACTIVE","changedAt":1,"effectiveAt":1,"label":"Synthetic","latitude":12,"longitude":45,"datum":"WGS84"}"#.utf8))
    }
    private func model(_ service: Service, _ journal: Journal, owner: PlayExperienceSession? = nil, run: String = "42",
                       enabled: Bool = true, current: @escaping () -> Bool = { true }) throws -> NativeHomeReturnCoordinator {
        let actualOwner = try owner ?? self.owner()
        return NativeHomeReturnCoordinator(scope: .run(runId: run, resourceType: "sys.hp"), service: service, journal: journal,
            owner: actualOwner, enabled: enabled,
            location: { .measured(try! .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: Self.now)) },
            locationAuthorized: { true }, isCurrent: current, now: { Self.now })
    }
    private func verify(_ model: NativeHomeReturnCoordinator) async throws {
        await model.load(); await model.checkIn(home: try home()); XCTAssertEqual(model.phase, .verified)
    }
    private func blocked(_ model: NativeHomeReturnCoordinator, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(model.phase, .unavailable, file: file, line: line)
        XCTAssertNil(model.account, file: file, line: line)
        XCTAssertFalse(model.canCheckIn, file: file, line: line); XCTAssertFalse(model.canRestore, file: file, line: line)
    }

    func testLaterReadCannotRegressAnAlreadyValidatedCurrentVersionBeforeAnyWrite() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        await model.load(); XCTAssertEqual(model.account?.version, 4)
        service.version = 3; await model.load(); blocked(model)
        await model.checkIn(home: try home()); await model.confirmRestore(home: try home())
        XCTAssertTrue(service.checks.isEmpty); XCTAssertTrue(service.requests.isEmpty); XCTAssertEqual(journal.saves, 0)
    }

    func testReceiptFloorSurvivesTheFirstSuccessfulAutomaticReadback() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        try await verify(model); await model.confirmRestore(home: try home())
        XCTAssertEqual(model.account?.version, 5); XCTAssertEqual(model.decision, .restored); XCTAssertNil(journal.value)
        service.version = 4; service.current = 2; await model.load(); blocked(model)
        XCTAssertEqual(model.decision, .restored); XCTAssertEqual(service.requests.count, 1); XCTAssertEqual(journal.clears, 1)
        await model.retryExact(); XCTAssertEqual(service.requests.count, 1)
    }

    func testNewerCurrentReadRaisesTheFloorInsteadOfKeepingOnlyTheReceiptVersion() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        try await verify(model); await model.confirmRestore(home: try home())
        service.version = 8; service.current = 1; await model.load()
        XCTAssertEqual(model.account?.version, 8); XCTAssertEqual(model.account?.current, 1)
        service.version = 7; await model.load(); blocked(model)
        service.version = 8; await model.load(); XCTAssertTrue(model.canCheckIn); XCTAssertNil(model.failure)
        XCTAssertEqual(model.account?.current, 1); XCTAssertEqual(service.requests.count, 1)
    }

    func testEqualOrNewerManualReadsRecoverWithoutSamplingOrReplaying() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        await model.load(); service.version = 2; await model.load(); blocked(model)
        service.version = 4; await model.load(); XCTAssertEqual(model.phase, .ready)
        service.version = 6; await model.load(); XCTAssertEqual(model.account?.version, 6)
        service.version = 5; await model.load(); blocked(model)
        XCTAssertTrue(service.checks.isEmpty); XCTAssertTrue(service.requests.isEmpty); XCTAssertNil(journal.value)
    }

    func testSameVersionDoesNotInventBalanceEqualityOrUseAnOldCachedBalance() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        await model.load(); XCTAssertEqual(model.account?.current, 2)
        service.current = 1; await model.load()
        XCTAssertEqual(model.account?.version, 4); XCTAssertEqual(model.account?.current, 1); XCTAssertTrue(model.canCheckIn)
    }

    func testUnknownReceiptCannotLowerTheNewerCurrentVersionObservedWhilePending() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        try await verify(model); service.loseResponse = true; await model.confirmRestore(home: try home())
        let original = try XCTUnwrap(journal.value)
        service.version = 8; service.current = 1; await model.load()
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(model.account?.version, 8); XCTAssertEqual(journal.value, original)
        service.version = 5; service.current = 5; await model.readBack()
        blocked(model); XCTAssertEqual(model.decision, .restored); XCTAssertTrue(model.requiresAccountReadback)
        XCTAssertNil(journal.value); XCTAssertEqual(service.requests, [original]); XCTAssertEqual(journal.clears, 1)
        service.version = 8; service.current = 1; await model.load()
        XCTAssertEqual(model.account?.version, 8); XCTAssertEqual(model.account?.current, 1); XCTAssertTrue(model.canCheckIn)
    }

    func testOriginalDenialCanClearItsJournalButCannotDowngradeTheKnownCurrentVersion() async throws {
        for decision in [NativeHomeRestoreReceipt.Decision.proofExpired, .proofConsumed, .staleHome, .proofUnavailable, .runUnavailable, .versionConflict] {
            let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
            try await verify(model); service.decision = decision
            let originalVersion: Int64 = decision == .versionConflict ? 5 : 4
            service.receiptVersion = originalVersion; service.loseResponse = true
            await model.confirmRestore(home: try home()); XCTAssertEqual(model.phase, .unknown)
            service.version = 8; await model.load(); XCTAssertEqual(model.account?.version, 8)
            service.version = originalVersion; await model.readBack(); blocked(model)
            XCTAssertEqual(model.decision, decision); XCTAssertNil(journal.value); XCTAssertTrue(model.requiresAccountReadback)
            service.version = 8; await model.load(); XCTAssertEqual(model.account?.version, 8)
            XCTAssertEqual(model.failure, service.receipts.values.first?.failure)
            XCTAssertEqual(service.requests.count, 1); XCTAssertEqual(journal.clears, 1)
        }
    }

    func testAlreadyFullAndCooldownKeepTheirExistingTerminalVersions() async throws {
        for decision in [NativeHomeRestoreReceipt.Decision.alreadyAtMax, .cooldown] {
            let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
            service.decision = decision; try await verify(model); await model.confirmRestore(home: try home())
            XCTAssertEqual(model.decision, decision); XCTAssertEqual(model.account?.version, 4); XCTAssertNil(journal.value)
            service.version = 3; await model.load(); blocked(model)
            XCTAssertEqual(service.requests.count, 1)
        }
    }

    func testScopeMismatchCannotPoisonTheFloorWithAnUnrelatedHighVersion() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        await model.load(); service.wrongScope = true; service.version = 900; await model.load(); blocked(model)
        service.wrongScope = false; service.version = 5; await model.load()
        XCTAssertEqual(model.account?.version, 5); XCTAssertTrue(model.canCheckIn)
    }

    func testInvalidAccountShapeCannotRaiseTheFloor() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        await model.load(); service.version = 900; service.current = 6; await model.load(); blocked(model)
        service.current = 2; service.version = 5; await model.load(); XCTAssertEqual(model.account?.version, 5)
    }

    func testPolicyAndNetworkFailuresDoNotResetKnownVersions() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        await model.load(); service.policyMissing = true; await model.load(); blocked(model)
        service.policyMissing = false; service.failAccount = true; await model.load(); blocked(model)
        service.failAccount = false; service.version = 3; await model.load(); blocked(model)
        service.version = 4; await model.load(); XCTAssertTrue(model.canCheckIn)
    }

    func testStorageFailureDoesNotForgetThePreviousValidCurrentRead() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        await model.load(); journal.failRead = true; await model.load(); XCTAssertEqual(model.phase, .blocked)
        journal.failRead = false; service.version = 3; await model.load(); blocked(model)
        service.version = 4; await model.load(); XCTAssertEqual(model.phase, .ready)
    }

    func testInvalidReceiptDoesNotRaiseTheFloorOrClearTheOriginalJournal() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        try await verify(model); service.receiptVersion = 900; service.afterRestoreVersion = 4
        await model.confirmRestore(home: try home())
        let original = try XCTUnwrap(journal.value)
        XCTAssertEqual(model.phase, .unknown); XCTAssertNil(model.decision); XCTAssertEqual(journal.clears, 0)
        service.version = 5; await model.load(); XCTAssertEqual(model.account?.version, 5); XCTAssertEqual(model.phase, .unknown)
        service.receipts[original.requestId] = .init(requestId: original.requestId, proofId: original.proofId, decision: .restored,
            current: 5, maximum: 5, accountVersion: 5, retryAfterSeconds: nil)
        await model.readBack(); XCTAssertNil(journal.value); XCTAssertEqual(model.account?.version, 5); XCTAssertEqual(service.requests.count, 1)
    }

    func testFailedTerminalClearRetainsUnknownAndDoesNotReplaceTheOriginalRequest() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        try await verify(model); journal.failClear = true; await model.confirmRestore(home: try home())
        let original = try XCTUnwrap(journal.value)
        service.version = 8; await model.load(); XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(model.account?.version, 8)
        journal.failClear = false; service.version = 5; await model.readBack(); blocked(model)
        XCTAssertNil(journal.value); XCTAssertEqual(model.decision, .restored); XCTAssertEqual(service.requests, [original])
    }

    func testWireMaximumUsesInt64OrderingWithoutDoubleRounding() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        service.version = 9_007_199_254_740_991; await model.load()
        XCTAssertEqual(model.account?.version, 9_007_199_254_740_991)
        service.version -= 1; await model.load(); blocked(model)
        service.version += 1; await model.load(); XCTAssertTrue(model.canCheckIn)
    }

    func testInvalidationAndDifferentOwnerOrRunDoNotShareAnInMemoryFloor() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        service.version = 8; await model.load(); model.invalidate(); service.version = 1; await model.load()
        XCTAssertEqual(model.phase, .invalidated); XCTAssertNil(model.account)
        let otherOwner = try owner(8), otherJournal = Journal(otherOwner)
        let other = try self.model(service, otherJournal, owner: otherOwner, run: "99")
        await other.load(); XCTAssertEqual(other.account?.version, 1); XCTAssertEqual(other.phase, .ready)
    }

    func testNewInstanceDoesNotClaimPersistenceOfThePreviousInMemoryFloor() async throws {
        let service = Service(), journal = Journal(try owner()), first = try model(service, journal)
        service.version = 8; await first.load(); first.invalidate()
        let reopened = try model(service, journal); service.version = 1; await reopened.load()
        XCTAssertEqual(reopened.account?.version, 1); XCTAssertTrue(reopened.canCheckIn)
        XCTAssertNil(journal.value); XCTAssertTrue(service.requests.isEmpty)
    }

    func testRevocationDuringAccountReadCannotPublishTheNewValue() async throws {
        var current = true
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal, current: { current })
        await model.load(); service.version = 9; service.afterAccount = { current = false }
        await model.load(); XCTAssertEqual(model.phase, .invalidated); XCTAssertNil(model.account); XCTAssertFalse(model.canCheckIn)
        XCTAssertTrue(service.requests.isEmpty)
    }

    func testDefaultOffStillMakesNoReadsOrWrites() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal, enabled: false)
        await model.load(); await model.checkIn(home: try home()); await model.confirmRestore(home: try home())
        XCTAssertEqual(model.phase, .disabled); XCTAssertEqual(service.policyReads, 0); XCTAssertEqual(service.reads, 0)
        XCTAssertTrue(service.checks.isEmpty); XCTAssertTrue(service.requests.isEmpty); XCTAssertEqual(journal.saves, 0)
    }

    func testValidReadClearsTransientErrorButRestoresOnlyTheKnownTerminalFailure() async throws {
        for decision in [NativeHomeRestoreReceipt.Decision.restored, .alreadyAtMax, .cooldown, .proofExpired] {
            let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
            service.decision = decision; try await verify(model); await model.confirmRestore(home: try home())
            let receipt = try XCTUnwrap(service.receipts.values.first)
            service.failAccount = true; await model.load(); blocked(model); XCTAssertEqual(model.failure, .network)
            service.failAccount = false; await model.load()
            XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.decision, decision)
            XCTAssertEqual(model.failure, receipt.failure); XCTAssertFalse(model.requiresAccountReadback)
            XCTAssertEqual(service.requests.count, 1); XCTAssertNil(journal.value)
        }
    }

    func testNewVerificationDoesNotInheritThePreviousTerminalDenial() async throws {
        let service = Service(), journal = Journal(try owner()), model = try model(service, journal)
        service.decision = .proofExpired; try await verify(model); await model.confirmRestore(home: try home())
        XCTAssertEqual(model.failure, .proofExpired)
        await model.checkIn(home: try home()); XCTAssertEqual(model.phase, .verified); XCTAssertNil(model.decision); XCTAssertNil(model.failure)
        service.failAccount = true; await model.load(); blocked(model)
        service.failAccount = false; await model.load(); XCTAssertNil(model.decision); XCTAssertNil(model.failure)
    }
}
