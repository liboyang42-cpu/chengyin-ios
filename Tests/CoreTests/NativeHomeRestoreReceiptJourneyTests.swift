import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// NOT_RUN. Real service/transport/coordinator objects over an in-memory wire; no URLSession, GPS or Keychain.
@available(macOS 14.0, *) @MainActor final class NativeHomeRestoreReceiptJourneyTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
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
    @MainActor private final class Wire: HTTPTransport {
        var sent: [URLRequest] = []
        var original: NativeHomeRestoreRequest?
        var receiptVersion: Int64 = 4, accountVersion: Int64 = 4
        var decision: NativeHomeRestoreReceipt.Decision = .versionConflict
        var loseWrite = false, noReceipt = false
        var responseRequestID: String?, responseProofID: String?
        func count(_ suffix: String) -> Int { sent.filter { $0.url?.lastPathComponent == suffix }.count }
        private func envelope(_ value: Any) throws -> (Data, Int) {
            (try JSONSerialization.data(withJSONObject: ["code": 200, "data": value]), 200)
        }
        private func receipt() throws -> (Data, Int) {
            let request = try XCTUnwrap(original)
            return try envelope(["requestId": responseRequestID ?? request.requestId, "proofId": responseProofID ?? request.proofId,
                "decision": decision.rawValue, "current": decision == .restored || decision == .alreadyAtMax ? 5 : 2,
                "maximum": 5, "accountVersion": receiptVersion])
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            sent.append(request)
            switch request.url?.lastPathComponent {
            case "policy": return try envelope(["policyVersion": "synthetic", "maxAccuracyMeters": 20,
                "maxFixAgeSeconds": 30, "dwellSeconds": 0, "serverTimeMillis": 1_000_000_000])
            case "account": return try envelope(["resourceType": "sys.hp", "scopeType": "RUN", "scopeId": "42",
                "current": 2, "maximum": 5, "version": accountVersion])
            case "verify":
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                return try envelope(["requestId": body["requestId"]!, "decision": "VERIFIED", "proofId": "synthetic-proof",
                    "homeVersion": 3, "accountVersion": body["expectedAccountVersion"]!, "expiresAtMillis": 1_000_060_000])
            case "restore":
                let value = try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: XCTUnwrap(request.httpBody))
                if let original { XCTAssertEqual(value, original) } else { original = value }
                if loseWrite { loseWrite = false; throw NativeHomeReturnFailure.network }
                return try receipt()
            case "receipt":
                let requestID = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value
                XCTAssertEqual(requestID, original?.requestId)
                if noReceipt { return (Data(#"{"code":200,"msg":"success"}"#.utf8), 200) }
                return try receipt()
            default: throw NativeHomeReturnFailure.invalid
            }
        }
    }
    @MainActor private final class Fixture {
        let grant: NativeHomeReturnApproval
        let wire: Wire
        let journal: Journal
        let service: NativeHomeReturnService
        var samples = 0
        init() throws {
            let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token", role: "player")
            let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test/native")!, role: "player", session: owner)
            let grant = try NativeHomeReturnApproval(context: context, expiresAt: Date().addingTimeInterval(600))
            let wire = Wire()
            self.grant = grant; self.wire = wire; journal = Journal(owner)
            let transport = NativeHomeReturnTransport(approval: grant, underlying: wire, current: { grant.context }, selected: { _ in grant })
            service = NativeHomeReturnService(approval: grant, transport: transport, current: { grant.context }, selected: { _ in grant })
        }
        func model(enabled: Bool = true) -> NativeHomeReturnCoordinator {
            NativeHomeReturnCoordinator(scope: .run(runId: "42", resourceType: "sys.hp"), service: service, journal: journal,
                owner: grant.context.session, enabled: enabled,
                location: { self.samples += 1; return .measured(try! .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: NativeHomeRestoreReceiptJourneyTests.now)) },
                locationAuthorized: { true }, isCurrent: { self.service.isCurrent() }, now: { NativeHomeRestoreReceiptJourneyTests.now })
        }
    }
    private func home() throws -> PrivateHomeSnapshot {
        try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(#"{"version":3,"status":"ACTIVE","changedAt":1,"effectiveAt":1,"label":"Synthetic","latitude":12,"longitude":45,"datum":"WGS84"}"#.utf8))
    }
    private func request(expected: Int64 = 4) throws -> NativeHomeRestoreRequest {
        try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: Data("{\"proofId\":\"synthetic-proof\",\"requestId\":\"restore-original\",\"homeVersion\":3,\"expectedAccountVersion\":\(expected),\"scopeType\":\"RUN\",\"scopeId\":\"42\",\"resourceType\":\"sys.hp\"}".utf8))
    }
    private func receipt(_ request: NativeHomeRestoreRequest, _ decision: NativeHomeRestoreReceipt.Decision = .versionConflict,
                         version: Int64, current: Int64 = 2, maximum: Int64 = 5, retry: Int? = nil) -> NativeHomeRestoreReceipt {
        .init(requestId: request.requestId, proofId: request.proofId, decision: decision,
              current: current, maximum: maximum, accountVersion: version, retryAfterSeconds: retry)
    }
    private func invalid(_ operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Invalid original receipt must be rejected") }
        catch { XCTAssertEqual(error as? NativeHomeReturnFailure, .invalid) }
    }
    private func stage(_ model: NativeHomeReturnCoordinator) async throws {
        await model.load(); await model.checkIn(home: try home()); XCTAssertEqual(model.phase, .verified)
    }
    private func unknown(_ model: NativeHomeReturnCoordinator, _ f: Fixture) {
        XCTAssertEqual(model.phase, .unknown); XCTAssertTrue(model.hasPendingRestore); XCTAssertNotNil(f.journal.value)
        XCTAssertNil(model.decision); XCTAssertFalse(model.canRestore); XCTAssertFalse(model.canCheckIn); XCTAssertEqual(f.journal.clears, 0)
    }

    func testEqualVersionConflictViolatesTheOriginalReceiptContract() throws {
        let request = try request()
        XCTAssertThrowsError(try receipt(request, version: 4).validate(for: request)) { XCTAssertEqual($0 as? NativeHomeReturnFailure, .invalid) }
    }

    func testDifferentLowerAndHigherVersionsRemainValidOriginalConflicts() throws {
        let request = try request()
        for version in [Int64(0), 3, 5, 9_007_199_254_740_991] {
            let value = receipt(request, version: version)
            XCTAssertNoThrow(try value.validate(for: request)); XCTAssertEqual(value.failure, .unknown)
        }
    }

    func testConflictStillRejectsRetryAndOutOfWireRangeVersions() throws {
        let request = try request()
        XCTAssertThrowsError(try receipt(request, version: 5, retry: 1).validate(for: request))
        for version in [Int64(-1), 9_007_199_254_740_992] { XCTAssertThrowsError(try receipt(request, version: version).validate(for: request)) }
        let maximum = try self.request(expected: 9_007_199_254_740_991)
        XCTAssertThrowsError(try receipt(maximum, version: maximum.expectedAccountVersion).validate(for: maximum))
        XCTAssertNoThrow(try receipt(maximum, version: maximum.expectedAccountVersion - 1).validate(for: maximum))
    }

    func testExistingSuccessAndCooldownRelationsRemainExact() throws {
        let request = try request()
        XCTAssertNoThrow(try receipt(request, .restored, version: 5, current: 5).validate(for: request))
        XCTAssertNoThrow(try receipt(request, .alreadyAtMax, version: 4, current: 5).validate(for: request))
        XCTAssertNoThrow(try receipt(request, .cooldown, version: 4, retry: 1).validate(for: request))
        XCTAssertThrowsError(try receipt(request, .restored, version: 4, current: 5).validate(for: request))
        XCTAssertThrowsError(try receipt(request, .alreadyAtMax, version: 5, current: 5).validate(for: request))
        XCTAssertThrowsError(try receipt(request, .cooldown, version: 5, retry: 1).validate(for: request))
    }

    func testHistoricalDenialsRetainTheirOriginalPermittedVersionSemantics() throws {
        let request = try request()
        for decision in [NativeHomeRestoreReceipt.Decision.proofConsumed, .staleHome, .proofExpired, .runUnavailable, .proofUnavailable] {
            for version in [Int64(0), 4, 5] {
                let value = receipt(request, decision, version: version, current: 0, maximum: 0)
                XCTAssertNoThrow(try value.validate(for: request)); XCTAssertNotNil(value.failure)
            }
        }
    }

    func testRealServiceRejectsContradictoryWriteAndOriginalReceiptGet() async throws {
        let f = try Fixture(), request = try request()
        await invalid { _ = try await f.service.restore(request) }
        await invalid { _ = try await f.service.restoreReceipt(for: request) }
        XCTAssertEqual(f.wire.count("restore"), 1); XCTAssertEqual(f.wire.count("receipt"), 1)
        XCTAssertEqual(f.wire.original, request)
    }

    func testRealServiceAcceptsBothDirectionsOfActualConflictWithoutClaimingSuccess() async throws {
        for version in [Int64(3), 5] {
            let f = try Fixture(), request = try request(); f.wire.receiptVersion = version
            let written = try await f.service.restore(request), read = try await f.service.restoreReceipt(for: request)
            XCTAssertEqual(written, read); XCTAssertEqual(written.decision, .versionConflict); XCTAssertEqual(written.failure, .unknown)
        }
    }

    func testContradictoryInitialWriteCannotClearJournalOrAutomaticallyRefresh() async throws {
        let f = try Fixture(), model = f.model(); try await stage(model)
        await model.confirmRestore(home: try home()); unknown(model, f)
        XCTAssertEqual(f.wire.count("restore"), 1); XCTAssertEqual(f.wire.count("account"), 1)
        XCTAssertEqual(f.journal.value, f.wire.original); XCTAssertEqual(f.journal.saves, 1); XCTAssertEqual(f.samples, 1)
        await model.confirmRestore(home: try home()); XCTAssertEqual(f.wire.count("restore"), 1)
    }

    func testContradictoryOriginalGetRetainsUnknownAfterLostWriteResponse() async throws {
        let f = try Fixture(), model = f.model(); try await stage(model); f.wire.loseWrite = true
        await model.confirmRestore(home: try home()); let original = try XCTUnwrap(f.journal.value)
        await model.readBack(); unknown(model, f)
        XCTAssertEqual(f.journal.value, original); XCTAssertEqual(f.wire.count("restore"), 1); XCTAssertEqual(f.wire.count("receipt"), 1)
        XCTAssertEqual(f.wire.count("account"), 1); XCTAssertEqual(f.samples, 1)
    }

    func testColdStartReadsTheOriginalRequestWithoutReissuingIt() async throws {
        let f = try Fixture(), first = f.model(); try await stage(first)
        await first.confirmRestore(home: try home()); let original = try XCTUnwrap(f.journal.value); first.invalidate()
        let reopened = f.model(); await reopened.load(); unknown(reopened, f)
        await reopened.readBack(); unknown(reopened, f)
        XCTAssertEqual(f.wire.count("restore"), 1); XCTAssertEqual(f.journal.value, original); XCTAssertEqual(f.journal.saves, 1)
        XCTAssertEqual(f.samples, 1)
    }

    func testLaterValidOriginalReceiptClearsOnlyThatRequestAndReadsCurrentState() async throws {
        let f = try Fixture(), model = f.model(); try await stage(model)
        await model.confirmRestore(home: try home()); let original = try XCTUnwrap(f.journal.value)
        await model.readBack(); unknown(model, f)
        f.wire.receiptVersion = 5; f.wire.accountVersion = 5; await model.readBack()
        XCTAssertNil(f.journal.value); XCTAssertEqual(f.journal.clears, 1); XCTAssertEqual(model.decision, .versionConflict)
        XCTAssertEqual(model.account?.version, 5); XCTAssertEqual(model.account?.current, 2); XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.failure, .unknown); XCTAssertEqual(f.wire.original, original); XCTAssertEqual(f.wire.count("restore"), 1)
        XCTAssertEqual(f.wire.count("account"), 2); XCTAssertEqual(f.samples, 1)
    }

    func testExplicitExactRetryReusesIdenticalBytesAndDoesNotGenerateAnotherProof() async throws {
        let f = try Fixture(), model = f.model(); try await stage(model)
        await model.confirmRestore(home: try home()); let original = try XCTUnwrap(f.journal.value)
        f.wire.receiptVersion = 5; f.wire.accountVersion = 5; await model.retryExact()
        let writes = f.wire.sent.filter { $0.url?.lastPathComponent == "restore" }
        XCTAssertEqual(writes.count, 2); XCTAssertEqual(writes[0].httpBody, writes[1].httpBody)
        XCTAssertEqual(f.wire.original, original); XCTAssertEqual(f.journal.saves, 1); XCTAssertEqual(f.journal.clears, 1)
        XCTAssertEqual(f.wire.count("verify"), 1); XCTAssertEqual(f.samples, 1); XCTAssertEqual(model.decision, .versionConflict)
    }

    func testAbsentReceiptIsStillUnknownAndNeverClearsOrResends() async throws {
        let f = try Fixture(), model = f.model(); try await stage(model)
        await model.confirmRestore(home: try home()); f.wire.noReceipt = true; await model.readBack()
        unknown(model, f); XCTAssertTrue(model.noReceiptYet); XCTAssertEqual(f.wire.count("restore"), 1); XCTAssertEqual(f.journal.saves, 1)
    }

    func testValidDifferentVersionDoesNotExcuseWrongRequestOrProofIdentity() async throws {
        for wrongRequest in [true, false] {
            let f = try Fixture(), request = try request(); f.wire.original = request; f.wire.receiptVersion = 5
            if wrongRequest { f.wire.responseRequestID = "other-original-request" } else { f.wire.responseProofID = "other-proof" }
            await invalid { _ = try await f.service.restoreReceipt(for: request) }
        }
    }

    func testRevokedApprovalPreventsReceiptReadBeforeTheSyntheticTransport() async throws {
        let f = try Fixture(), request = try request(); f.wire.original = request; f.grant.revoke()
        do { _ = try await f.service.restoreReceipt(for: request); XCTFail("Revoked approval must not read") }
        catch { XCTAssertEqual(error as? NativeHomeReturnFailure, .disabled) }
        XCTAssertTrue(f.wire.sent.isEmpty)
    }

    func testDefaultOffCoordinatorStillDoesNotSampleOrReachTheSyntheticWire() async throws {
        let f = try Fixture(), model = f.model(enabled: false)
        await model.load(); await model.checkIn(home: try home()); await model.confirmRestore(home: try home())
        XCTAssertEqual(model.phase, .disabled); XCTAssertTrue(f.wire.sent.isEmpty); XCTAssertEqual(f.samples, 0); XCTAssertNil(f.journal.value)
    }
}
