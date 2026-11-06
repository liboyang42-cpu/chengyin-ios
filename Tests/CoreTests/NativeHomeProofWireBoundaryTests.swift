import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// NOT_RUN. Real value/service/transport/coordinator contracts with synthetic bytes only.
/// No network, OS Keychain, location or production grant operation.
@available(macOS 14.0, *) @MainActor final class NativeHomeProofWireBoundaryTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_000_000)
    private static let scope = NativeHomeResourceScope.run(runId: "42", resourceType: "sys.hp")
    private static func home() throws -> PrivateHomeSnapshot {
        try JSONDecoder().decode(PrivateHomeSnapshot.self, from: Data(#"{"version":3,"status":"ACTIVE","changedAt":1,"effectiveAt":1,"label":"Synthetic","latitude":12,"longitude":45,"datum":"WGS84"}"#.utf8))
    }
    private func check() throws -> NativeHomeReturnCheck {
        try .preflight(home: Self.home(), status: .measured(.init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: Self.now)),
            policy: .init(policyVersion: "synthetic", maxAccuracyMeters: 20, maxFixAgeSeconds: 30, dwellSeconds: 0, serverTimeMillis: 1_000_000_000),
            scope: Self.scope, now: Self.now, requestId: "verify-original", expectedAccountVersion: 4)
    }
    private func proof(_ id: String) throws -> NativeHomeReturnProof {
        try .init(proofId: id, homeVersion: 3, scope: Self.scope, expiresAtMillis: 1_000_060_000, for: check())
    }
    private static func rawRequest(_ proof: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["requestId": "restore-original", "proofId": proof,
            "homeVersion": 3, "expectedAccountVersion": 4, "scopeType": "RUN", "scopeId": "42", "resourceType": "sys.hp"], options: [.sortedKeys])
    }
    @MainActor private final class Journal: NativeHomeReturnSecureJournaling {
        let scope: PrivateHomeJournalScope
        var bytes: Data?
        var saves = 0, clears = 0
        init(_ owner: PlayExperienceSession) { scope = .init(owner: owner) }
        func read() throws -> NativeHomeRestoreRequest? {
            guard let bytes else { return nil }
            do { return try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: bytes) }
            catch { throw NativeHomeReturnFailure.storageUnavailable }
        }
        func save(_ request: NativeHomeRestoreRequest) throws {
            let existing = try read()
            guard existing == nil || existing == request else { throw NativeHomeReturnFailure.storageUnavailable }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            bytes = try encoder.encode(request); saves += 1
        }
        func clear(matching request: NativeHomeRestoreRequest) throws {
            guard try read() == request else { throw NativeHomeReturnFailure.storageUnavailable }
            bytes = nil; clears += 1
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        var proofID = "proof-original"
        var requests: [URLRequest] = [], originals: [NativeHomeRestoreRequest] = []
        var committed: NativeHomeRestoreRequest?
        var loseNext = false
        var version: Int64 = 4
        var current: Int64 = 2
        private func receipt(_ request: NativeHomeRestoreRequest) -> [String: Any] {
            ["requestId": request.requestId, "proofId": request.proofId, "decision": "RESTORED",
             "current": 5, "maximum": 5, "accountVersion": 5, "retryAfterSeconds": NSNull()]
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let data: Any
            switch request.url?.lastPathComponent {
            case "policy": data = ["policyVersion": "synthetic", "maxAccuracyMeters": 20, "maxFixAgeSeconds": 30, "dwellSeconds": 0, "serverTimeMillis": 1_000_000_000]
            case "account": data = ["resourceType": "sys.hp", "scopeType": "RUN", "scopeId": "42", "current": current, "maximum": 5, "version": version]
            case "verify":
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                data = ["requestId": body["requestId"]!, "proofId": proofID, "decision": "VERIFIED", "homeVersion": 3,
                    "expiresAtMillis": 1_000_060_000, "retryAfterSeconds": NSNull(), "challengeId": NSNull(), "accountVersion": 4]
            case "restore":
                let original = try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: XCTUnwrap(request.httpBody))
                originals.append(original)
                if let committed { XCTAssertEqual(committed, original) } else { committed = original; current = 5; version = 5 }
                if loseNext { loseNext = false; throw NativeHomeReturnFailure.network }
                data = receipt(original)
            case "receipt":
                if let committed { data = receipt(committed) } else { data = NSNull() }
            default: throw NativeHomeReturnFailure.invalid
            }
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
        }
    }
    @MainActor private final class Fixture {
        let grant: NativeHomeReturnApproval, wire: Wire, journal: Journal, service: NativeHomeReturnService, transport: NativeHomeReturnTransport
        var samples = 0
        init() throws {
            let owner = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token", role: "player")
            let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://example.test")!, role: "player", session: owner)
            let grant = try NativeHomeReturnApproval(context: context, expiresAt: Date().addingTimeInterval(600)), wire = Wire()
            let transport = NativeHomeReturnTransport(approval: grant, underlying: wire, current: { grant.context }, selected: { _ in grant })
            self.grant = grant; self.wire = wire; self.transport = transport; journal = Journal(owner)
            service = NativeHomeReturnService(approval: grant, transport: transport, current: { grant.context }, selected: { _ in grant })
        }
        func model(enabled: Bool = true) -> NativeHomeReturnCoordinator {
            .init(scope: NativeHomeProofWireBoundaryTests.scope, service: service, journal: journal, owner: grant.context.session,
                enabled: enabled, location: {
                    self.samples += 1
                    return .measured(try! .init(latitude: 12, longitude: 45, accuracyMeters: 5, capturedAt: NativeHomeProofWireBoundaryTests.now))
                }, locationAuthorized: { true }, isCurrent: { self.service.isCurrent() }, now: { NativeHomeProofWireBoundaryTests.now })
        }
    }

    func testOriginalProofAndExact64ByteBoundaryRemainConstructible() throws {
        for id in ["p", "12a34567-89ab-4cde-8f01-23456789abcd", String(repeating: "p", count: 64)] {
            let value = try proof(id); XCTAssertEqual(value.proofId, id)
            let request = try NativeHomeRestoreRequest(proof: value, currentHomeVersion: 3, expectedAccountVersion: 4,
                deviceNow: Self.now, serverOffset: 0, requestId: "restore-original")
            XCTAssertNoThrow(try request.validateNative())
        }
    }

    func testProofCannotExceedTheOriginalServer64ByteContract() throws {
        for count in [65, 95, 96, 97] {
            XCTAssertThrowsError(try proof(String(repeating: "p", count: count))) { XCTAssertEqual($0 as? NativeHomeReturnFailure, .invalid) }
        }
    }

    func testExistingIdentifierCharacterAndEmptyChecksAreNotRelaxed() throws {
        for id in ["", "proof/id", "proof\n", "proofé", ".proof"] {
            XCTAssertThrowsError(try proof(id)) { XCTAssertEqual($0 as? NativeHomeReturnFailure, .invalid) }
        }
    }

    func testRestoreDecoderRejectsOversizeProofBeforeJournalAdoption() throws {
        for count in [65, 96, 97] {
            XCTAssertThrowsError(try JSONDecoder().decode(NativeHomeRestoreRequest.self,
                from: Self.rawRequest(String(repeating: "p", count: count)))) { XCTAssertEqual($0 as? NativeHomeReturnFailure, .invalid) }
        }
    }

    func testValidPersistedRequestRoundTripsWithoutChangingIdentityOrAddingLocation() throws {
        for count in [1, 36, 64] {
            let original = try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: Self.rawRequest(String(repeating: "p", count: count)))
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let bytes = try encoder.encode(original)
            XCTAssertEqual(try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: bytes), original)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(Set(object.keys), ["requestId", "proofId", "homeVersion", "expectedAccountVersion", "scopeType", "scopeId", "resourceType"])
        }
    }

    func testExact64ByteRequestPassesRealFinalTransportAndOriginalReceiptValidation() async throws {
        let f = try Fixture(), id = String(repeating: "p", count: 64)
        let request = try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: Self.rawRequest(id))
        let receipt = try await f.service.restore(request)
        XCTAssertEqual(receipt.proofId, id); XCTAssertEqual(receipt.decision, .restored); XCTAssertEqual(f.wire.originals, [request])
    }

    func testFinalTransportStillRejectsManualOversizeBodyWithoutDispatching() async throws {
        let f = try Fixture()
        var request = URLRequest(url: f.grant.context.baseURL.appendingPathComponent(NativeHomeReturnService.path + "/restore"))
        request.httpMethod = "POST"; request.httpBody = try Self.rawRequest(String(repeating: "p", count: 65))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control"); request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.setValue(f.grant.context.session.token, forHTTPHeaderField: "Authorization")
        do { _ = try await f.transport.send(request); XCTFail() }
        catch { XCTAssertEqual(error as? NativeHomeReturnFailure, .disabled) }
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertNil(f.journal.bytes)
    }

    func testOversizeVerifiedResponseNeverBecomesProofOrDurableUnknown() async throws {
        for count in [65, 96] {
            let f = try Fixture(), model = f.model(); f.wire.proofID = String(repeating: "p", count: count)
            await model.load(); await model.checkIn(home: try Self.home())
            XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.failure, .invalid); XCTAssertFalse(model.canRestore)
            await model.confirmRestore(home: try Self.home())
            XCTAssertNil(f.journal.bytes); XCTAssertEqual(f.journal.saves, 0); XCTAssertTrue(f.wire.originals.isEmpty)
            XCTAssertFalse(model.hasPendingRestore); XCTAssertEqual(f.samples, 1)
        }
    }

    func testExact64ByteProofCompletesOnlyAfterSeparateExplicitConfirmation() async throws {
        let f = try Fixture(), model = f.model(); f.wire.proofID = String(repeating: "p", count: 64)
        await model.load(); await model.checkIn(home: try Self.home())
        XCTAssertEqual(model.phase, .verified); XCTAssertTrue(model.canRestore); XCTAssertNil(f.journal.bytes); XCTAssertTrue(f.wire.originals.isEmpty)
        await model.confirmRestore(home: try Self.home())
        XCTAssertEqual(model.decision, .restored); XCTAssertEqual(model.account?.version, 5)
        XCTAssertEqual(f.journal.saves, 1); XCTAssertEqual(f.journal.clears, 1); XCTAssertEqual(f.wire.originals.count, 1)
        XCTAssertEqual(f.wire.originals.first?.proofId, String(repeating: "p", count: 64))
    }

    func testRejectedProofRequiresNewExplicitVerificationAndCannotAutoRestore() async throws {
        let f = try Fixture(), model = f.model(); f.wire.proofID = String(repeating: "p", count: 65)
        await model.load(); await model.checkIn(home: try Self.home()); XCTAssertFalse(model.canRestore)
        f.wire.proofID = "valid-original"; await model.confirmRestore(home: try Self.home())
        XCTAssertTrue(f.wire.originals.isEmpty); XCTAssertEqual(f.journal.saves, 0)
        await model.checkIn(home: try Self.home()); XCTAssertTrue(model.canRestore)
        await model.confirmRestore(home: try Self.home())
        XCTAssertEqual(f.wire.originals.count, 1); XCTAssertEqual(f.wire.originals.first?.proofId, "valid-original")
        XCTAssertEqual(f.samples, 2)
    }

    func testValidBoundaryLostRestoreRetainsOriginalAcrossModelRecreationAndReceiptRead() async throws {
        let f = try Fixture(), first = f.model(); f.wire.proofID = String(repeating: "p", count: 64)
        await first.load(); await first.checkIn(home: try Self.home())
        f.wire.loseNext = true; await first.confirmRestore(home: try Self.home())
        let saved = try XCTUnwrap(f.journal.bytes), original = try JSONDecoder().decode(NativeHomeRestoreRequest.self, from: saved)
        XCTAssertEqual(first.phase, .unknown); first.invalidate()
        let resumed = f.model(); await resumed.load()
        XCTAssertEqual(resumed.phase, .unknown); XCTAssertEqual(f.journal.bytes, saved); XCTAssertEqual(f.wire.originals, [original])
        await resumed.readBack()
        XCTAssertNil(f.journal.bytes); XCTAssertEqual(resumed.decision, .restored); XCTAssertEqual(f.wire.originals, [original])
        XCTAssertEqual(f.samples, 1); XCTAssertEqual(f.journal.saves, 1); XCTAssertEqual(f.journal.clears, 1)
    }

    func testHistoricalOversizeJournalRemainsIntactAndBlockedWithoutAutomaticRepair() async throws {
        for count in [65, 96] {
            let f = try Fixture(), model = f.model(), original = try Self.rawRequest(String(repeating: "p", count: count))
            f.journal.bytes = original
            await model.load(); await model.load(); await model.retryExact(); await model.readBack()
            XCTAssertEqual(model.phase, .blocked); XCTAssertEqual(model.failure, .storageUnavailable)
            XCTAssertFalse(model.canCheckIn); XCTAssertFalse(model.canRetryExact); XCTAssertFalse(model.canRestore)
            XCTAssertEqual(f.journal.bytes, original); XCTAssertEqual(f.journal.saves, 0); XCTAssertEqual(f.journal.clears, 0)
            XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertEqual(f.samples, 0)
        }
    }

    func testDisabledOrRevokedModelDoesNotUseAValidProofToExpandAuthority() async throws {
        let f = try Fixture(), disabled = f.model(enabled: false)
        await disabled.load(); await disabled.checkIn(home: try Self.home())
        XCTAssertTrue(f.wire.requests.isEmpty); XCTAssertEqual(f.samples, 0)
        let model = f.model(); await model.load(); await model.checkIn(home: try Self.home())
        f.grant.revoke(); await model.confirmRestore(home: try Self.home())
        XCTAssertEqual(model.phase, .invalidated); XCTAssertNil(f.journal.bytes); XCTAssertTrue(f.wire.originals.isEmpty)
    }
}
