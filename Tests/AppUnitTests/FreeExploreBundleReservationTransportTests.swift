import XCTest
@testable import Questify

@MainActor final class FreeExploreBundleReservationTransportTests: XCTestCase {
    func testDefaultNilAuthorizationRejectsPersistedPOST() async throws {
        let r = try Rig(); let adapter = try r.adapter(useDefault: true)
        try r.pending.save(r.command)
        await reject(adapter, try r.request()); XCTAssertTrue(r.write.requests.isEmpty)
        XCTAssertEqual(try r.pending.load(), r.command)
    }
    func testExactPersistedOriginalIsTheOnlyAcceptedBody() async throws {
        let r = try Rig(); try r.pending.save(r.command); let adapter = try r.adapter()
        _ = try await adapter.send(r.request())
        XCTAssertEqual(r.write.requests.count, 1)
        XCTAssertEqual(r.write.requests[0].httpBody, try r.command.wireData())
        XCTAssertEqual(try r.pending.load(), r.command) // transport never acknowledges
    }
    func testMissingOriginalDoesNotPOST() async throws {
        let r = try Rig(); await reject(try r.adapter(), try r.request())
        XCTAssertTrue(r.write.requests.isEmpty)
    }
    func testAlteredKeyTimeUnitOfferAndRegistrationNeverPOST() async throws {
        let r = try Rig(); try r.pending.save(r.command); let adapter = try r.adapter()
        for (key, value) in [("idempotencyKey", "new-key"), ("startAt", "1900000000001"),
                             ("unitId", "18"), ("offerId", "30"), ("registrationId", "42")] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: r.command.wireData()) as? [String: Any])
            if key == "idempotencyKey" { object[key] = value } else { object[key] = Int64(value)! }
            var request = try r.request(); let body = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            request.httpBody = body; request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
            await reject(adapter, request)
        }
        XCTAssertTrue(r.write.requests.isEmpty)
    }
    func testForeignHostQueryRefundAndMethodAreRejected() async throws {
        let r = try Rig(); try r.pending.save(r.command); let adapter = try r.adapter()
        for url in ["https://other.example/api/free-explore/bundle/reservation",
                    "https://example.test/api/free-explore/bundle/reservation?debug=true",
                    "https://example.test/api/free-explore/bundle/order/refund-quote",
                    "https://example.test/api/free-explore/bundle/reservation/1/cancel"] {
            var req = try r.request(); req.url = URL(string: url); await reject(adapter, req)
        }
        var req = try r.request(); req.httpMethod = "PUT"; await reject(adapter, req)
        XCTAssertTrue(r.write.requests.isEmpty)
    }
    func testWrongCredentialAndContentTypeAreRejected() async throws {
        let r = try Rig(); try r.pending.save(r.command); let adapter = try r.adapter()
        var req = try r.request(); req.setValue("other-token", forHTTPHeaderField: "Authorization")
        await reject(adapter, req)
        req = try r.request(); req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        await reject(adapter, req); XCTAssertTrue(r.write.requests.isEmpty)
    }
    func testRevokedGrantBeforeSendKeepsOriginalAndDoesNotPOST() async throws {
        let r = try Rig(); try r.pending.save(r.command); let adapter = try r.adapter()
        r.approval?.revoke(); await reject(adapter, try r.request())
        XCTAssertTrue(r.write.requests.isEmpty); XCTAssertEqual(try r.pending.load(), r.command)
    }
    func testRevocationAfterDispatchRemainsUnknown() async throws {
        let r = try Rig(); try r.pending.save(r.command); let adapter = try r.adapter()
        r.write.onSend = { r.approval?.revoke() }
        do { _ = try await adapter.send(r.request()); XCTFail("revoked late result") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .outcomeUnknown) }
        XCTAssertEqual(r.write.requests.count, 1); XCTAssertEqual(try r.pending.load(), r.command)
    }
    func testSessionChangeAfterDispatchRemainsUnknown() async throws {
        let r = try Rig(); try r.pending.save(r.command); let adapter = try r.adapter()
        r.write.onSend = { r.current = nil }
        do { _ = try await adapter.send(r.request()); XCTFail("stale late result") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .outcomeUnknown) }
        XCTAssertEqual(try r.pending.load(), r.command)
    }
    func testStorageReadFailureNeverUsesFallback() async throws {
        let r = try Rig(); try r.pending.save(r.command); let adapter = try r.adapter()
        r.store.failRead = true; await reject(adapter, try r.request())
        XCTAssertTrue(r.write.requests.isEmpty); XCTAssertEqual(r.store.removes, 0)
    }
    func testGrantForDifferentRegistrationCannotAuthorize() async throws {
        let r = try Rig(); try r.pending.save(r.command)
        r.approval = try FreeExploreBundleReservationApproval(context: r.context,
            registrationID: FreeExploreLaunchID(42), expiresAt: Date().addingTimeInterval(60))
        await reject(try r.adapter(), try r.request()); XCTAssertTrue(r.write.requests.isEmpty)
    }
    func testClosedWriterDelegatesOnlyToExistingReadGate() async throws {
        let r = try Rig(), adapter = try r.adapter(useDefault: true)
        var req = URLRequest(url: URL(string: "https://example.test/api/free-explore/bundle/reservation/receipt?idempotencyKey=original")!)
        req.httpMethod = "GET"; req.setValue(r.context.session.token, forHTTPHeaderField: "Authorization")
        try r.pending.save(r.command)
        _ = try await adapter.send(req)
        XCTAssertEqual(r.read.requests.count, 1); XCTAssertTrue(r.write.requests.isEmpty)
        XCTAssertFalse(adapter.permitsReservationDispatch)
    }
    func testBusinessLoginRequiredRevokesWriterWithoutClearingPending() async throws {
        let r = try Rig(); try r.pending.save(r.command); let adapter = try r.adapter()
        r.write.result = (Data("{\"code\":409,\"businessCode\":\"LOGIN_REQUIRED\"}".utf8), 200)
        _ = try await adapter.send(r.request())
        XCTAssertFalse(adapter.permitsReservationDispatch); XCTAssertEqual(try r.pending.load(), r.command)
    }
    func testWrongDurableOwnerCannotConstructAdapter() throws {
        let r = try Rig()
        let other = try FreeExploreLaunchSession(baseURL: r.context.baseURL, accountID: 8, market: r.context.market.rawValue,
            namespace: r.context.session.namespace, role: "player", epoch: 1, token: "test-token")
        let pending = FreeExploreLaunchPendingStore(storage: r.store, session: other)
        XCTAssertThrowsError(try FreeExploreBundleReservationTransport(context: r.context, registrationID: r.command.registrationId,
            pending: pending, readTransport: r.readGate(), underlying: r.write, current: { r.context }))
    }
    func testRetirementPreventsFurtherPOSTAndKeepsOriginal() async throws {
        let r = try Rig(); try r.pending.save(r.command); let adapter = try r.adapter()
        adapter.retire(); await reject(adapter, try r.request())
        XCTAssertFalse(adapter.permitsReservationDispatch)
        XCTAssertTrue(r.write.requests.isEmpty); XCTAssertEqual(try r.pending.load(), r.command)
    }
    func testLate401FromRetiredIdentityRemainsUnknown() async throws {
        let r = try Rig(); try r.pending.save(r.command); let adapter = try r.adapter()
        r.write.result = (Data("{\"code\":401}".utf8), 401)
        r.write.onSend = { r.current = nil }
        do { _ = try await adapter.send(r.request()); XCTFail("late 401 must not reach new identity") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .outcomeUnknown) }
        XCTAssertEqual(try r.pending.load(), r.command)
    }
    func testReplacementApprovalDoesNotAdoptInflightResult() async throws {
        let r = try Rig(); try r.pending.save(r.command); let adapter = try r.adapter()
        let replacement = try FreeExploreBundleReservationApproval(context: r.context,
            registrationID: r.command.registrationId, expiresAt: Date().addingTimeInterval(60))
        r.write.onSend = { r.approval = replacement }
        do { _ = try await adapter.send(r.request()); XCTFail("replacement is another grant") }
        catch { XCTAssertEqual(error as? FreeExploreLaunchFailure, .outcomeUnknown) }
        XCTAssertEqual(try r.pending.load(), r.command)
    }
    func testInitiallyEmptyRealReadGateRecoversOriginalPOSTThroughService() async throws {
        let r = try Rig(); let gate = try r.readGate()
        XCTAssertNil(try r.pending.load())
        let adapter = try FreeExploreBundleReservationTransport(context: r.context,
            registrationID: r.command.registrationId, pending: r.pending, readTransport: gate,
            underlying: r.write, current: { r.current }, selectApproval: { r.approval })
        let session = try FreeExploreLaunchSession(baseURL: r.context.baseURL, accountID: 7,
            market: r.context.market.rawValue, namespace: "test", role: "player", epoch: 1, token: "synthetic-token")
        let service = FreeExploreLaunchService(session: session, transport: adapter,
            currentSession: { r.current == r.context ? session : nil },
            reservationAllowed: { adapter.permitsReservationDispatch })
        // User confirms after first open; durable original appears after read transport construction.
        try r.pending.save(r.command)
        r.write.result = (Data(), 503)
        do { _ = try await service.reserve(r.command); XCTFail("unknown write must not succeed") } catch {}
        XCTAssertEqual(r.write.requests.count, 1)
        r.approval?.revoke() // write revocation still allows exact authorized read recovery
        let receipt: [String: Any] = ["id": 91, "registrationId": 41, "holderMemberId": 7,
            "unitId": 17, "chapterId": 3, "offerId": 29, "merchantId": 5,
            "startAt": "2030-03-17T00:00:00Z", "status": "BOOKED",
            "idempotencyKey": r.command.idempotencyKey, "requestFingerprint": r.command.fingerprint]
        r.read.result = (try JSONSerialization.data(withJSONObject: ["code": 200, "data": receipt]), 200)
        let recovered = try await service.receipt(r.command)
        XCTAssertEqual(recovered?.idempotencyKey, "original")
        XCTAssertEqual(r.read.requests.count, 1)
        XCTAssertEqual(try r.pending.load(), r.command) // GET alone never acknowledges/removes
        XCTAssertFalse(adapter.permitsReservationDispatch)
    }
    func testArbitraryReceiptKeyCannotUseDynamicReader() async throws {
        let r = try Rig(); let adapter = try r.adapter(); try r.pending.save(r.command)
        var req = r.receiptRequest(); req.url = URL(string: "https://example.test/api/free-explore/bundle/reservation/receipt?idempotencyKey=attacker")!
        await reject(adapter, req); XCTAssertTrue(r.read.requests.isEmpty)
    }
    func testMissingCurrentPendingRevokesOldReceiptRoute() async throws {
        let r = try Rig(); let adapter = try r.adapter(); try r.pending.save(r.command)
        r.store.values.removeAll() // simulate acknowledgement by the owning coordinator
        await reject(adapter, r.receiptRequest()); XCTAssertTrue(r.read.requests.isEmpty)
    }
    func testChangedPendingDuringReadRejectsLateReceipt() async throws {
        let r = try Rig(); let adapter = try r.adapter(); try r.pending.save(r.command)
        r.read.onSend = { r.store.values.removeAll() }
        await reject(adapter, r.receiptRequest()); XCTAssertEqual(r.read.requests.count, 1)
    }
    func testDynamicReadStorageFailureMakesNoRequest() async throws {
        let r = try Rig(); let adapter = try r.adapter(); try r.pending.save(r.command)
        r.store.failRead = true; await reject(adapter, r.receiptRequest())
        XCTAssertTrue(r.read.requests.isEmpty); XCTAssertEqual(r.store.removes, 0)
    }
    func testRetiredRealReadGateBlocksRecoveryDespiteLiveWriter() async throws {
        let r = try Rig(); let gate = try r.readGate()
        let adapter = try FreeExploreBundleReservationTransport(context: r.context,
            registrationID: r.command.registrationId, pending: r.pending, readTransport: gate,
            underlying: r.write, current: { r.current }, selectApproval: { r.approval })
        try r.pending.save(r.command); gate.retire()
        await reject(adapter, r.receiptRequest()); XCTAssertTrue(r.read.requests.isEmpty)
        await reject(adapter, try r.request()); XCTAssertTrue(r.write.requests.isEmpty)
        XCTAssertFalse(adapter.permitsReservationDispatch)
        XCTAssertEqual(try r.pending.load(), r.command)
    }
    func testSnapshotOnlyReaderCannotConstructWriter() throws {
        let r = try Rig()
        let snapshot = FreeExploreBundleReadTransport(context: r.context, registrationID: r.command.registrationId,
            original: nil, underlying: r.read, current: { true }, denied: {})
        XCTAssertThrowsError(try FreeExploreBundleReservationTransport(context: r.context,
            registrationID: r.command.registrationId, pending: r.pending, readTransport: snapshot,
            underlying: r.write, current: { r.current }))
    }
    func testSameOwnerDifferentStoreCannotConstructWriter() throws {
        let r = try Rig()
        let owner = try FreeExploreLaunchSession(baseURL: r.context.baseURL, accountID: 7,
            market: r.context.market.rawValue, namespace: "test", role: "player", epoch: 1, token: "synthetic-token")
        let other = FreeExploreLaunchPendingStore(storage: Store(), session: owner)
        XCTAssertThrowsError(try FreeExploreBundleReservationTransport(context: r.context,
            registrationID: r.command.registrationId, pending: other, readTransport: r.readGate(),
            underlying: r.write, current: { r.current }))
    }
    private func reject(_ adapter: FreeExploreBundleReservationTransport, _ request: URLRequest) async {
        do { _ = try await adapter.send(request); XCTFail("must reject") } catch {}
    }
    private final class Rig {
        let context: RuntimeDependencyContext
        var current: RuntimeDependencyContext?
        var approval: FreeExploreBundleReservationApproval?
        let store = Store(), read = Recorder(), write = Recorder()
        let pending: FreeExploreLaunchPendingStore
        let command: FreeExploreLaunchReservationCommand
        init() throws {
            let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "test", token: "synthetic-token")
            context = .init(market: .china, baseURL: URL(string: "https://example.test")!, role: "player", session: session)
            current = context
            command = try .init(registrationId: FreeExploreLaunchID(41), unitId: FreeExploreLaunchID(17),
                offerId: FreeExploreLaunchID(29), startAt: 1_900_000_000_000, idempotencyKey: "original")
            let owner = try FreeExploreLaunchSession(baseURL: context.baseURL, accountID: 7, market: context.market.rawValue,
                namespace: "test", role: "player", epoch: 1, token: "synthetic-token")
            pending = FreeExploreLaunchPendingStore(storage: store, session: owner)
            approval = try FreeExploreBundleReservationApproval(context: context, registrationID: command.registrationId,
                expiresAt: Date().addingTimeInterval(60))
        }
        func readGate() throws -> FreeExploreBundleReadTransport {
            try .init(context: context, registrationID: command.registrationId, pending: pending,
                underlying: read, current: { [weak self] in guard let self else { return false }; return self.current == self.context }, denied: {})
        }
        func adapter(useDefault: Bool = false) throws -> FreeExploreBundleReservationTransport {
            if useDefault { return try .init(context: context, registrationID: command.registrationId, pending: pending,
                readTransport: readGate(), underlying: write, current: { [weak self] in self?.current }) }
            return try .init(context: context, registrationID: command.registrationId, pending: pending,
                readTransport: readGate(), underlying: write, current: { [weak self] in self?.current },
                selectApproval: { [weak self] in self?.approval })
        }
        func receiptRequest() -> URLRequest {
            var req = URLRequest(url: URL(string: "https://example.test/api/free-explore/bundle/reservation/receipt?idempotencyKey=original")!)
            req.httpMethod = "GET"; req.setValue(context.session.token, forHTTPHeaderField: "Authorization")
            return req
        }
        func request() throws -> URLRequest {
            var req = URLRequest(url: context.baseURL.appendingPathComponent("api/free-explore/bundle/reservation"))
            req.httpMethod = "POST"; req.httpBody = try command.wireData()
            req.setValue(context.session.token, forHTTPHeaderField: "Authorization")
            req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            req.setValue(String(req.httpBody!.count), forHTTPHeaderField: "Content-Length")
            return req
        }
    }
    private final class Store: TemplateAuthoringStorage {
        var values: [String: Data] = [:]
        var failRead = false
        var removes = 0
        func read(_ key: String) throws -> Data? { if failRead { throw FreeExploreLaunchFailure.storageUnavailable }; return values[key] }
        func write(_ data: Data, key: String) throws { values[key] = data }
        func remove(_ key: String) throws { removes += 1; values.removeValue(forKey: key) }
    }
    private final class Recorder: HTTPTransport {
        var requests: [URLRequest] = []
        var onSend: (() -> Void)?
        var result = (Data("{\"code\":200,\"data\":null}".utf8), 200)
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); onSend?(); return result }
    }
}
