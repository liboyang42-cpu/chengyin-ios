import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// NOT_RUN. Real native service/transport/selection/coordinator, synthetic HTTP and journal only.
/// A seam throwing after a write is a fault model, not a claim about any observed Keychain failure.
@available(macOS 14.0, *) @MainActor final class NativeHomeSaveFailureRecoveryJourneyTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private static let scope = NativeHomeResourceScope.run(runId: "42", resourceType: "sys.hp")
    private static func home() throws -> PrivateHomeSnapshot {
        try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(#"{"version":3,"status":"ACTIVE","changedAt":1,"effectiveAt":1,"label":"Synthetic","latitude":12,"longitude":45,"datum":"WGS84"}"#.utf8))
    }
    @MainActor private final class Journal: NativeHomeReturnSecureJournaling {
        let scope: PrivateHomeJournalScope
        var value: NativeHomeRestoreRequest?
        var attempted: [NativeHomeRestoreRequest] = [], cleared: [NativeHomeRestoreRequest] = []
        var writeBeforeFailure = true, failSave = true, failRead = false, failClear = false
        var afterSaveFailure: (() -> Void)?
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() throws -> NativeHomeRestoreRequest? {
            if failRead { throw NativeHomeReturnFailure.storageUnavailable }; return value
        }
        func save(_ request: NativeHomeRestoreRequest) throws {
            attempted.append(request)
            guard value == nil || value == request else { throw NativeHomeReturnFailure.storageUnavailable }
            if !failSave || writeBeforeFailure { value = request }
            if failSave { afterSaveFailure?(); throw NativeHomeReturnFailure.storageUnavailable }
        }
        func clear(matching request: NativeHomeRestoreRequest) throws {
            guard !failClear, value == request else { throw NativeHomeReturnFailure.storageUnavailable }
            cleared.append(request); value = nil
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], restores: [NativeHomeRestoreRequest] = [], receiptIDs: [String] = []
        var committed: NativeHomeRestoreRequest?, overrideReceipt: [String: Any]?
        var loseNextRestore = false, failAccount = false
        var current: Int64 = 2, version: Int64 = 4
        var runs = 0, verifies = 0
        func commit(_ request: NativeHomeRestoreRequest) { committed = request; current = 5; version = 5 }
        private func receipt(_ request: NativeHomeRestoreRequest) -> [String: Any] {
            ["requestId": request.requestId, "proofId": request.proofId, "decision": "RESTORED",
             "current": 5, "maximum": 5, "accountVersion": 5, "retryAfterSeconds": NSNull()]
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let data: Any
            switch request.url?.lastPathComponent {
            case "runs":
                runs += 1
                data = ["runs": [["runId": "42", "activityId": "5", "topicId": "6", "playInstanceId": "synthetic-run", "resourceType": "sys.hp", "current": 2, "maximum": 5, "version": 4]], "truncated": false, "nextBeforeRunId": NSNull()]
            case "policy": data = ["policyVersion": "synthetic", "maxAccuracyMeters": 20, "maxFixAgeSeconds": 30, "dwellSeconds": 0, "serverTimeMillis": 1_000_000_000]
            case "account":
                if failAccount { throw NativeHomeReturnFailure.network }
                data = ["resourceType": "sys.hp", "scopeType": "RUN", "scopeId": "42", "current": current, "maximum": 5, "version": version]
            case "verify":
                verifies += 1
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                data = ["requestId": body["requestId"]!, "proofId": "proof-original", "decision": "VERIFIED", "homeVersion": 3,
                        "expiresAtMillis": 1_000_060_000, "retryAfterSeconds": NSNull(), "challengeId": NSNull(), "accountVersion": 4]
            case "restore":
                let original = try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: XCTUnwrap(request.httpBody))
                restores.append(original)
                if let committed { XCTAssertEqual(committed, original) } else { commit(original) }
                if loseNextRestore { loseNextRestore = false; throw NativeHomeReturnFailure.network }
                data = receipt(original)
            case "receipt":
                let id = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value)
                receiptIDs.append(id)
                if let overrideReceipt { data = overrideReceipt }
                else if let committed, committed.requestId == id { data = receipt(committed) }
                else { data = NSNull() }
            default: throw NativeHomeReturnFailure.invalid
            }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
        }
    }
    @MainActor private final class Fixture {
        let grant: NativeHomeReturnApproval, wire: Wire, journal: Journal, service: NativeHomeReturnService
        var samples = 0, made: [NativeHomeReturnCoordinator] = []
        lazy var selection = NativeHomeReturnSelectionCoordinator(service: service, journal: journal, owner: grant.context.session,
            isCurrent: { [unowned self] in self.service.isCurrent() }, makeModel: { [unowned self] scope in self.model(scope: scope) })
        init() throws {
            let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token", role: "player")
            let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test")!, role: "player", session: owner)
            let grant = try NativeHomeReturnApproval(context: context, expiresAt: Date().addingTimeInterval(600)), wire = Wire()
            self.grant = grant; self.wire = wire; journal = Journal(owner)
            let transport = NativeHomeReturnTransport(approval: grant, underlying: wire, current: { grant.context }, selected: { _ in grant })
            service = NativeHomeReturnService(approval: grant, transport: transport, current: { grant.context }, selected: { _ in grant })
        }
        func model(scope: NativeHomeResourceScope = NativeHomeSaveFailureRecoveryJourneyTests.scope, enabled: Bool = true) -> NativeHomeReturnCoordinator {
            let model = NativeHomeReturnCoordinator(scope: scope, service: service, journal: journal, owner: grant.context.session,
                enabled: enabled, location: {
                    self.samples += 1
                    return .measured(try! .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: NativeHomeSaveFailureRecoveryJourneyTests.now))
                }, locationAuthorized: { true }, isCurrent: { self.service.isCurrent() }, now: { NativeHomeSaveFailureRecoveryJourneyTests.now })
            made.append(model); return model
        }
    }
    private func verify(_ model: NativeHomeReturnCoordinator) async throws {
        await model.load(); await model.checkIn(home: try Self.home()); XCTAssertEqual(model.phase, .verified)
    }
    private func failSave(_ f: Fixture, _ model: NativeHomeReturnCoordinator) async throws -> NativeHomeRestoreRequest {
        try await verify(model); await model.confirmRestore(home: try Self.home())
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(model.failure, .storageUnavailable)
        XCTAssertTrue(model.hasPendingRestore); XCTAssertFalse(model.canCheckIn); XCTAssertFalse(model.canRestore)
        XCTAssertNil(model.decision); XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertEqual(f.journal.attempted.count, 1)
        return try XCTUnwrap(f.journal.attempted.first)
    }
    private func replacement(_ original: NativeHomeRestoreRequest, field: String, value: Any) throws -> NativeHomeRestoreRequest {
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object[field] = value
        return try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testThrowingSaveRetainsOriginalAndDoesNotDispatchOrClear() async throws {
        let f = try Fixture(), model = f.model(), original = try await failSave(f, model)
        XCTAssertEqual(f.journal.value, original); XCTAssertTrue(f.journal.cleared.isEmpty)
        await model.confirmRestore(home: try Self.home()); await model.checkIn(home: try Self.home()); model.cancelVerification()
        XCTAssertEqual(f.journal.attempted, [original]); XCTAssertTrue(f.wire.restores.isEmpty)
        XCTAssertEqual(f.samples, 1); XCTAssertEqual(model.phase, .unknown)
    }

    func testSavedOriginalRefreshDoesNotAutomaticallyRestoreOrMintIdentity() async throws {
        let f = try Fixture(), model = f.model(), original = try await failSave(f, model)
        for _ in 0..<3 { await model.load(); XCTAssertEqual(model.phase, .unknown) }
        XCTAssertEqual(f.journal.value, original); XCTAssertEqual(f.journal.attempted, [original])
        XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertTrue(f.wire.receiptIDs.isEmpty); XCTAssertEqual(f.samples, 1)
    }

    func testUnprovenEmptySlotDoesNotUnlockOrReinsertTheAttempt() async throws {
        let f = try Fixture(), model = f.model(); f.journal.writeBeforeFailure = false
        let original = try await failSave(f, model), reads = f.wire.requests.count
        await model.load(); await model.retryExact(); await model.confirmRestore(home: try Self.home())
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(model.failure, .storageUnavailable)
        XCTAssertNil(f.journal.value); XCTAssertEqual(f.journal.attempted, [original]); XCTAssertTrue(f.journal.cleared.isEmpty)
        XCTAssertEqual(f.wire.requests.count, reads); XCTAssertTrue(f.wire.restores.isEmpty)
    }

    func testDisappearingSavedSlotCannotUnlockOriginal() async throws {
        let f = try Fixture(), model = f.model(), original = try await failSave(f, model)
        f.journal.value = nil; await model.load(); await model.retryExact()
        XCTAssertEqual(model.phase, .unknown); XCTAssertTrue(model.hasPendingRestore)
        XCTAssertEqual(model.failure, .storageUnavailable); XCTAssertEqual(f.journal.attempted, [original]); XCTAssertTrue(f.wire.restores.isEmpty)
    }

    func testReplacedIdentityFieldsCannotBeAdoptedOrDispatched() async throws {
        let changes: [(String, Any)] = [("requestId", "replacement-original"), ("proofId", "other-proof"),
            ("homeVersion", 4), ("expectedAccountVersion", 5), ("scopeId", "77")]
        for (field, value) in changes {
            let f = try Fixture(), model = f.model(), original = try await failSave(f, model)
            let other = try replacement(original, field: field, value: value); f.journal.value = other
            let reads = f.wire.requests.count
            await model.load(); await model.retryExact()
            XCTAssertEqual(model.phase, .unknown); XCTAssertTrue(model.hasPendingRestore); XCTAssertEqual(model.scope, Self.scope)
            XCTAssertEqual(f.journal.value, other); XCTAssertEqual(f.journal.attempted, [original]); XCTAssertTrue(f.journal.cleared.isEmpty)
            XCTAssertEqual(f.wire.requests.count, reads); XCTAssertTrue(f.wire.restores.isEmpty)
        }
    }

    func testUnavailableJournalReadRetainsIdentityUntilExplicitOriginalRetry() async throws {
        let f = try Fixture(), model = f.model(), original = try await failSave(f, model)
        f.journal.failRead = true; await model.load(); await model.retryExact()
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(model.failure, .storageUnavailable); XCTAssertTrue(f.wire.restores.isEmpty)
        f.journal.failRead = false; await model.load(); XCTAssertTrue(f.wire.restores.isEmpty)
        await model.retryExact()
        XCTAssertEqual(f.wire.restores, [original]); XCTAssertEqual(model.decision, .restored)
        XCTAssertEqual(model.account?.version, 5); XCTAssertEqual(f.journal.cleared, [original]); XCTAssertEqual(f.journal.attempted, [original])
    }

    func testExplicitRetryUsesOriginalAndLostResponseCanRecoverWithoutSecondWrite() async throws {
        let f = try Fixture(), model = f.model(), original = try await failSave(f, model)
        f.wire.loseNextRestore = true; await model.retryExact()
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(f.journal.value, original); XCTAssertEqual(f.wire.restores, [original])
        await model.readBack()
        XCTAssertEqual(f.wire.restores, [original]); XCTAssertEqual(f.wire.receiptIDs, [original.requestId])
        XCTAssertNil(f.journal.value); XCTAssertEqual(model.decision, .restored); XCTAssertEqual(model.account?.current, 5)
        XCTAssertEqual(f.journal.attempted, [original]); XCTAssertEqual(f.samples, 1)
    }

    func testAbsentReceiptAfterSaveFailureIsNotPermissionToClearOrResend() async throws {
        let f = try Fixture(), model = f.model(), original = try await failSave(f, model)
        await model.readBack()
        XCTAssertTrue(model.noReceiptYet); XCTAssertEqual(model.phase, .unknown); XCTAssertNil(model.decision)
        XCTAssertEqual(f.journal.value, original); XCTAssertTrue(f.journal.cleared.isEmpty); XCTAssertTrue(f.wire.restores.isEmpty)
        XCTAssertEqual(f.wire.receiptIDs, [original.requestId])
    }

    func testForeignReceiptCannotSettleOriginalAfterSaveFailure() async throws {
        let f = try Fixture(), model = f.model(), original = try await failSave(f, model)
        f.wire.overrideReceipt = ["requestId": "unrelated-request", "proofId": original.proofId,
            "decision": "RESTORED", "current": 5, "maximum": 5, "accountVersion": 5]
        await model.readBack()
        XCTAssertEqual(model.phase, .unknown); XCTAssertNil(model.decision); XCTAssertEqual(f.journal.value, original)
        XCTAssertTrue(f.journal.cleared.isEmpty); XCTAssertTrue(f.wire.restores.isEmpty)
    }

    func testMatchingReceiptCannotClearAReplacementEvenIfOriginalWasCommittedElsewhere() async throws {
        let f = try Fixture(), model = f.model(), original = try await failSave(f, model)
        let other = try replacement(original, field: "requestId", value: "replacement-original")
        f.journal.value = other; f.wire.commit(original); await model.readBack()
        XCTAssertEqual(model.phase, .unknown); XCTAssertNil(model.decision); XCTAssertEqual(f.journal.value, other)
        XCTAssertTrue(f.journal.cleared.isEmpty); XCTAssertTrue(f.wire.restores.isEmpty)
        f.journal.value = original; await model.readBack()
        XCTAssertNil(f.journal.value); XCTAssertEqual(model.decision, .restored); XCTAssertEqual(model.account?.version, 5)
        XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertEqual(f.journal.cleared, [original])
    }

    func testTerminalClearFailureStaysUnknownAndCurrentReadFailureNeverUsesReceiptBalance() async throws {
        let f = try Fixture(), model = f.model(), original = try await failSave(f, model)
        f.journal.failClear = true; await model.retryExact()
        XCTAssertEqual(model.phase, .unknown); XCTAssertNil(model.decision); XCTAssertEqual(f.journal.value, original)
        f.journal.failClear = false; f.wire.failAccount = true; await model.readBack()
        XCTAssertEqual(model.decision, .restored); XCTAssertNil(model.account); XCTAssertTrue(model.requiresAccountReadback)
        XCTAssertEqual(model.phase, .unavailable); XCTAssertNil(f.journal.value); XCTAssertEqual(f.wire.restores, [original])
        f.wire.failAccount = false; await model.load()
        XCTAssertEqual(model.account?.version, 5); XCTAssertEqual(model.phase, .ready); XCTAssertEqual(f.wire.restores, [original])
    }

    func testSelectionRefreshPreservesTheFailedSaveOwnerInsteadOfRebuildingIt() async throws {
        for missing in [false, true] {
            let f = try Fixture(); await f.selection.load()
            let run = try XCTUnwrap(f.selection.runs.first); await f.selection.select(run)
            let model = try XCTUnwrap(f.selection.selected), original = try await failSave(f, model)
            if missing { f.journal.value = nil }
            else { f.journal.value = try replacement(original, field: "scopeId", value: "77") }
            await f.selection.load(); await f.selection.select(run)
            XCTAssertTrue(f.selection.selected === model); XCTAssertEqual(f.made.count, 1); XCTAssertEqual(f.wire.runs, 1)
            XCTAssertFalse(f.selection.canSelect); XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(model.scope, Self.scope)
            XCTAssertEqual(f.journal.attempted, [original]); XCTAssertTrue(f.wire.restores.isEmpty); XCTAssertTrue(f.journal.cleared.isEmpty)
        }
    }

    func testColdRecreationRecoversOnlyTheActuallyPersistedOriginalWithoutReplay() async throws {
        let f = try Fixture(), first = f.model(), original = try await failSave(f, first)
        first.invalidate(); let resumed = f.model(); await resumed.load()
        XCTAssertEqual(resumed.phase, .unknown); XCTAssertTrue(resumed.hasPendingRestore)
        XCTAssertEqual(f.journal.value, original); XCTAssertTrue(f.wire.restores.isEmpty)
        await resumed.readBack(); XCTAssertTrue(resumed.noReceiptYet); XCTAssertEqual(f.journal.value, original)
        await resumed.retryExact()
        XCTAssertEqual(f.wire.restores, [original]); XCTAssertEqual(resumed.decision, .restored); XCTAssertNil(f.journal.value)
        XCTAssertEqual(f.journal.attempted, [original]); XCTAssertEqual(f.samples, 1)
    }

    func testScopeRevocationDuringSaveFailureDoesNotResurrectInMemoryPending() async throws {
        let f = try Fixture(), model = f.model(); try await verify(model)
        f.journal.afterSaveFailure = { f.grant.revoke() }
        await model.confirmRestore(home: try Self.home()); await model.load(); await model.retryExact(); await model.readBack()
        XCTAssertEqual(model.phase, .invalidated); XCTAssertFalse(model.hasPendingRestore); XCTAssertNil(model.account)
        XCTAssertNotNil(f.journal.value); XCTAssertTrue(f.journal.cleared.isEmpty); XCTAssertTrue(f.wire.restores.isEmpty)
        XCTAssertTrue(f.wire.receiptIDs.isEmpty)
    }

    func testSuccessfulSavePathStillRequiresSeparateConfirmationAndReadsCurrentAccount() async throws {
        let f = try Fixture(), model = f.model(); f.journal.failSave = false
        try await verify(model); XCTAssertTrue(f.journal.attempted.isEmpty); XCTAssertTrue(f.wire.restores.isEmpty)
        await model.confirmRestore(home: try Self.home())
        let original = try XCTUnwrap(f.journal.attempted.first)
        XCTAssertEqual(f.wire.restores, [original]); XCTAssertEqual(f.journal.cleared, [original]); XCTAssertNil(f.journal.value)
        XCTAssertEqual(model.decision, .restored); XCTAssertEqual(model.account?.version, 5); XCTAssertEqual(model.phase, .ready)
    }

    func testDefaultDisabledModelDoesNotInvokeJournalOrTransport() async throws {
        let f = try Fixture(), model = f.model(enabled: false)
        await model.load(); await model.checkIn(home: try Self.home()); await model.confirmRestore(home: try Self.home())
        await model.retryExact(); await model.readBack()
        XCTAssertEqual(model.phase, .disabled); XCTAssertTrue(f.journal.attempted.isEmpty); XCTAssertTrue(f.wire.requests.isEmpty)
        XCTAssertEqual(f.samples, 0); XCTAssertFalse(model.hasPendingRestore)
    }
}
