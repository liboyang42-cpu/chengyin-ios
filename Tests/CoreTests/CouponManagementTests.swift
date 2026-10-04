import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class CouponManagementTests: XCTestCase {
    final class Fake: CouponManagementTransport, CouponPublisherAuthorizing {
        var isSynthetic = true
        var requests: [CouponManagementRequest] = []
        var list = CouponManagementSyntheticFixtures.published
        var response = Data(#"{"code":200,"msg":"Synthetic acknowledgement"}"#.utf8)
        var status = 200
        var fail = false
        var permission = CouponPublisherPermission(revision: "role-1", mayPublish: true)
        var afterPermission: (() -> Void)?
        var onSend: (() -> Void)?
        func freshPermission(session: CouponManagementSession) async throws -> CouponPublisherPermission { afterPermission?(); return permission }
        func send(_ request: CouponManagementRequest, session: CouponManagementSession) async throws -> (Data, Int) {
            requests.append(request); onSend?()
            if request.mutates { if fail { throw URLError(.timedOut) }; return (response, status) }
            return (list, 200)
        }
    }
    final class MemoryLocks: CouponManagementLocking {
        var items: [String: CouponManagementPending] = [:]
        var failWrites = false
        func pending(ownerKey: String, resource: String) throws -> CouponManagementPending? { items[ownerKey + resource] }
        func acquire(_ pending: CouponManagementPending) throws {
            guard !failWrites else { throw CouponManagementError.storage }
            let key = pending.ownerKey + pending.resource
            guard items[key] == nil else { throw CouponManagementError.locked }; items[key] = pending
        }
        func release(_ pending: CouponManagementPending) throws { items.removeValue(forKey: pending.ownerKey + pending.resource) }
    }
    func session(_ epoch: UInt64 = 1, account: Int = 1) throws -> CouponManagementSession { try .init(accountID: account, namespace: "synthetic", epoch: epoch, authorizationRevision: "a") }
    func make(_ fake: Fake, _ locks: MemoryLocks, session: @escaping () -> CouponManagementSession?) -> CouponManagementCoordinator {
        .init(adapter: .init(transport: fake, syntheticWritesEnabled: true), authorizer: fake, locks: locks, currentSession: session)
    }
    func testChinaValidityWirePreservesSelectedTimesAndSameDayRange() throws {
        var draft = CouponManagementSyntheticFixtures.draft()
        draft.startTime = try XCTUnwrap(CouponValidityTime.parse("2026-10-04 09:30:00"))
        draft.endTime = try XCTUnwrap(CouponValidityTime.parse("2026-10-04 18:45:00"))
        XCTAssertNil(draft.blocker)
        let request = try CouponManagementContract.publish(draft)
        guard case .json(let data) = request.body else { return XCTFail("JSON required") }
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(payload["startTime"] as? String, "2026-10-04 09:30:00")
        XCTAssertEqual(payload["endTime"] as? String, "2026-10-04 18:45:00")
        XCTAssertEqual(CouponValidityTime.display(draft.startTime!), "2026.10.04 09:30:00")
        XCTAssertEqual(CouponValidityTime.display(payload["endTime"] as? String), "2026.10.04 18:45:00")
        draft.endTime = draft.startTime
        XCTAssertEqual(draft.blocker, "couponManagement.dateOrder")
        draft.endTime = draft.startTime!.addingTimeInterval(0.5)
        XCTAssertEqual(draft.blocker, "couponManagement.dateOrder")
        draft.endTime = draft.startTime!.addingTimeInterval(-60)
        XCTAssertEqual(draft.blocker, "couponManagement.dateOrder")
    }
    func testChinaValidityPickerCalendarDoesNotInheritBuddhistDeviceCalendar() throws {
        let instant = try XCTUnwrap(CouponValidityTime.parse("2026-10-04 09:30:00"))
        var deviceCalendar = Calendar(identifier: .buddhist)
        deviceCalendar.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        XCTAssertNotEqual(deviceCalendar.component(.year, from: instant), 2026)
        let pickerCalendar = CouponValidityTime.calendar
        XCTAssertEqual(pickerCalendar.identifier, .gregorian)
        XCTAssertEqual(pickerCalendar.timeZone.secondsFromGMT(for: instant), 8 * 3600)
        let parts = pickerCalendar.dateComponents([.year, .month, .day, .hour, .minute], from: instant)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 10)
        XCTAssertEqual(parts.day, 4)
        XCTAssertEqual(parts.hour, 9)
        XCTAssertEqual(parts.minute, 30)
        XCTAssertEqual(CouponValidityTime.wire(try XCTUnwrap(pickerCalendar.date(from: parts))), "2026-10-04 09:30:00")
    }
    func testChinaValidityStrictRoundTripAndUTCBoundary() throws {
        for bad in ["2026-02-30 12:00:00", "2026-10-04 25:00:00", "2026-10-04", "2026-10-04 09:30:00junk", " 2026-10-04 09:30:00", "2026-10-04T09:30:00Z"] {
            XCTAssertNil(CouponValidityTime.parse(bad), bad)
            XCTAssertNil(CouponValidityTime.display(bad), bad)
        }
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-03T16:15:00Z"))
        XCTAssertEqual(CouponValidityTime.wire(instant), "2026-10-04 00:15:00")
        XCTAssertEqual(CouponValidityTime.parse("2026-10-04 00:15:00"), instant)
        XCTAssertEqual(CouponValidityTime.display("2028-02-29 23:59:59"), "2028.02.29 23:59:59")
        XCTAssertNil(CouponValidityTime.display(nil))
    }
    func testWireTypesValidationAndExactPublishFields() throws {
        var draft = CouponManagementDraft()
        XCTAssertEqual(draft.blocker, "couponManagement.nameRequired")
        draft.name = "Example"; XCTAssertEqual(draft.blocker, "couponManagement.datesRequired")
        draft = CouponManagementSyntheticFixtures.draft()
        for type in 0...3 {
            draft.couponType = type
            let request = try CouponManagementContract.publish(draft)
            XCTAssertEqual(request.path, "/api/coupon/publish"); XCTAssertEqual(request.method, "POST")
            guard case .json(let data) = request.body else { return XCTFail("JSON required") }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(body["couponType"] as? Int, type)
            XCTAssertEqual(Set(body.keys), Set(["scope", "name", "startTime", "endTime", "publishCount", "couponType"]))
        }
        draft.couponType = 4; XCTAssertEqual(draft.blocker, "couponManagement.typeRequired")
        draft.couponType = 0; draft.quantity = "0"; XCTAssertEqual(draft.blocker, "couponManagement.quantityRequired")
        draft.quantity = "1"; draft.endTime = draft.startTime; XCTAssertEqual(draft.blocker, "couponManagement.dateOrder")
    }
    func testMissingMoneyCountsAndUnknownStatusesStayUnknown() throws {
        let rows = try CouponManagementContract.decodePublished(CouponManagementSyntheticFixtures.published, status: 200)
        XCTAssertNil(rows[0].amount); XCTAssertNil(rows[0].currency); XCTAssertNil(rows[0].perLimit)
        XCTAssertEqual(rows[0].remaining, 17); XCTAssertNil(rows[1].remaining)
        XCTAssertFalse(rows[1].state.canStop); XCTAssertFalse(rows[2].state.canStop)
        for raw in [nil, -1, 5, 99] as [Int?] { XCTAssertEqual(CouponDefinitionStatus(raw), .unknown) }
        XCTAssertNil(CouponDefinition.displayDay("2026-02-30"))
        XCTAssertEqual(CouponDefinition.displayDay("2026-10-01T23:30:00-10:00"), "2026.10.01")
    }
    func testDefinitionIDsAndDuplicateListFailClosed() throws {
        XCTAssertThrowsError(try CouponDefinitionID(0))
        XCTAssertThrowsError(try CouponManagementContract.decodePublished(Data(#"{"code":200,"data":[{"id":1},{"id":1}]}"#.utf8), status: 200))
        XCTAssertThrowsError(try CouponManagementContract.decodePublished(Data(#"{"code":200}"#.utf8), status: 200))
        let stop = CouponManagementContract.stop(try CouponDefinitionID(710))
        XCTAssertEqual(stop.body, .multipart(["couponId": "710", "scope": "MERCHANT"]))
        let encoded = try stop.encodedBody(boundary: "Example-1")
        XCTAssertEqual(encoded.contentType, "multipart/form-data; boundary=Example-1")
        XCTAssertTrue(String(decoding: encoded.data, as: UTF8.self).contains("name=\"couponId\"\r\n\r\n710"))
        XCTAssertThrowsError(try stop.encodedBody(boundary: "bad\r\nvalue"))
    }
    func testDefaultAndNonSyntheticWriteGatesSendNothing() async throws {
        let fake = Fake(); let request = try CouponManagementContract.publish(CouponManagementSyntheticFixtures.draft()); let session = try session()
        let dormant = CouponManagementAdapter(transport: fake)
        let result = await dormant.submit(request, session: session); XCTAssertEqual(result, .notSent)
        fake.isSynthetic = false
        let enabled = CouponManagementAdapter(transport: fake, syntheticWritesEnabled: true)
        let liveResult = await enabled.submit(request, session: session); XCTAssertEqual(liveResult, .notSent)
        XCTAssertTrue(fake.requests.isEmpty)
    }
    func testEditedReviewCannotSend() async throws {
        let fake = Fake(), locks = MemoryLocks(); let session = try session(); let core = make(fake, locks) { session }
        core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish(); let review = try XCTUnwrap(core.review)
        var draft = core.draft; draft.name = "Changed"; core.change(draft)
        await core.confirm(review); XCTAssertTrue(fake.requests.isEmpty)
    }
    func testFreshPublisherRevocationPreventsDispatch() async throws {
        let fake = Fake(), locks = MemoryLocks(); let session = try session(); let core = make(fake, locks) { session }
        core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish(); let review = try XCTUnwrap(core.review)
        fake.permission = .init(revision: "revoked", mayPublish: false)
        await core.confirm(review); XCTAssertEqual(core.issue, .changed); XCTAssertTrue(fake.requests.isEmpty); XCTAssertTrue(locks.items.isEmpty)
    }
    func testStopFreshStatusAndOwnerCheck() async throws {
        let fake = Fake(), locks = MemoryLocks(); let session = try session(); let core = make(fake, locks) { session }
        await core.prepareStop(try CouponDefinitionID(710)); let review = try XCTUnwrap(core.review)
        fake.list = Data(#"{"code":200,"data":[{"id":710,"status":4}]}"#.utf8)
        await core.confirm(review); XCTAssertEqual(core.issue, .changed); XCTAssertFalse(fake.requests.contains(where: \.mutates))
        await core.prepareStop(try CouponDefinitionID(999)); XCTAssertEqual(core.issue, .forbidden)
    }
    func testUnknownSurvivesNewCoordinatorAndEpochAndChangedDraft() async throws {
        let fake = Fake(), locks = MemoryLocks(); var current = try session(); fake.fail = true
        let core = make(fake, locks) { current }; core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish()
        await core.confirm(try XCTUnwrap(core.review)); XCTAssertEqual(core.issue, .locked); XCTAssertEqual(locks.items.count, 1)
        current = try session(2)
        let reopened = make(fake, locks) { current }; var draft = CouponManagementSyntheticFixtures.draft(); draft.name = "Different draft"; reopened.change(draft)
        await reopened.preparePublish(); XCTAssertEqual(reopened.issue, .locked)
        XCTAssertEqual(fake.requests.filter(\.mutates).count, 1)
    }
    func testStorageFailureAndStaleSessionNeverDispatch() async throws {
        let fake = Fake(), locks = MemoryLocks(); var current = try session(); let core = make(fake, locks) { current }
        core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish(); locks.failWrites = true
        await core.confirm(try XCTUnwrap(core.review)); XCTAssertFalse(fake.requests.contains(where: \.mutates))
        locks.failWrites = false; await core.preparePublish(); let review = try XCTUnwrap(core.review)
        current = try session(2, account: 2); await core.confirm(review); XCTAssertFalse(fake.requests.contains(where: \.mutates)); XCTAssertTrue(core.rows.isEmpty)
    }
    func testUnknownStopRereadsWithoutClearingLock() async throws {
        let fake = Fake(), locks = MemoryLocks(); let session = try session(); let core = make(fake, locks) { session }; fake.fail = true
        await core.prepareStop(try CouponDefinitionID(710)); await core.confirm(try XCTUnwrap(core.review))
        XCTAssertEqual(core.issue, .locked); XCTAssertEqual(locks.items.count, 1)
        XCTAssertEqual(fake.requests.filter { !$0.mutates }.count, 3)
        await core.prepareStop(try CouponDefinitionID(710)); XCTAssertEqual(core.issue, .locked)
    }
    func testSyntheticDefiniteRejectionPreservesMessageAndReleasesLock() async throws {
        let fake = Fake(), locks = MemoryLocks(); let session = try session(); let core = make(fake, locks) { session }
        fake.response = Data(#"{"code":429,"msg":"发券太频繁,请稍后再试"}"#.utf8)
        core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish(); await core.confirm(try XCTUnwrap(core.review))
        XCTAssertEqual(core.serverMessage, "发券太频繁,请稍后再试"); XCTAssertTrue(locks.items.isEmpty)
    }
    func testExclusivePersistentLocksAndCorruptionRemainBlocked() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try CouponManagementFileLocks(directory: folder), second = try CouponManagementFileLocks(directory: folder)
        let record = CouponManagementPending(operationID: UUID(), ownerKey: "synthetic:1", resource: "publish", request: try CouponManagementContract.publish(CouponManagementSyntheticFixtures.draft()), createdAt: Date())
        try store.acquire(record); XCTAssertThrowsError(try second.acquire(record)); XCTAssertEqual(try second.pending(ownerKey: record.ownerKey, resource: record.resource), record)
        let path = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        try Data("broken".utf8).write(to: path)
        XCTAssertThrowsError(try second.pending(ownerKey: record.ownerKey, resource: record.resource)); XCTAssertThrowsError(try second.acquire(record))
    }
    func testNumericAndStringMoneyPreserveAbsentCurrency() throws {
        let data = Data(#"{"code":200,"data":[{"id":1,"amount":"12.50"},{"id":2,"amount":0},{"id":3,"amount":null}]}"#.utf8)
        let rows = try CouponManagementContract.decodePublished(data, status: 200)
        XCTAssertEqual(rows[0].amount, Decimal(string: "12.50")); XCTAssertNil(rows[0].currency)
        XCTAssertEqual(rows[1].amount, 0); XCTAssertNil(rows[2].amount)
    }
    func testSessionChangesDuringDispatchRetainOldOwnerLock() async throws {
        let fake = Fake(), locks = MemoryLocks(); var current = try session(); let original = current
        let core = make(fake, locks) { current }; core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish()
        let changed = try session(2, account: 2)
        fake.onSend = { current = changed }
        await core.confirm(try XCTUnwrap(core.review)); core.synchronize()
        XCTAssertEqual(locks.items.count, 1); XCTAssertNotNil(try locks.pending(ownerKey: original.ownerKey, resource: "publish"))
        XCTAssertFalse(core.simulated); XCTAssertNil(core.serverMessage)
    }
    func testFiveHundredRedirectMalformedAndContradictoryResponsesStayUnknown() async throws {
        let fake = Fake(); let adapter = CouponManagementAdapter(transport: fake, syntheticWritesEnabled: true)
        let request = try CouponManagementContract.publish(CouponManagementSyntheticFixtures.draft()), current = try session()
        for pair in [(500, #"{"code":500,"msg":"Failed"}"#), (302, #"{"code":302,"msg":"Redirect"}"#), (200, "broken"), (400, #"{"code":200,"msg":"Contradiction"}"#)] {
            fake.status = pair.0; fake.response = Data(pair.1.utf8)
            let outcome = await adapter.submit(request, session: current); XCTAssertEqual(outcome, .unknown)
        }
    }
    actor ReadHTTP: HTTPTransport {
        var requests: [URLRequest] = []
        func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (CouponManagementSyntheticFixtures.published, 200) }
        func saved() -> [URLRequest] { requests }
    }
    func testHTTPReadBridgeRejectsMutationAndUsesExactMultipartRead() async throws {
        let http = ReadHTTP(), current = try session()
        let credential = try CouponManagementReadCredentials(session: current, token: "synthetic-token")
        let config = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test")))
        let reader = CouponManagementHTTPReadTransport(configuration: config, http: http, credentials: { credential })
        let adapter = CouponManagementAdapter(transport: reader)
        let rows = try await adapter.published(session: current, keyword: "example")
        XCTAssertEqual(rows.count, 3)
        do { _ = try await reader.send(CouponManagementContract.stop(try CouponDefinitionID(710)), session: current); XCTFail("Mutation bridge must reject") } catch {}
        let requests = await http.saved(); XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.path, "/api/coupon/mypublishlist")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertTrue(requests[0].value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data") == true)
    }

    actor WriteHTTP: HTTPTransport {
        var requests: [URLRequest] = []
        let response: Data
        let status: Int
        let fail: Bool
        init(response: String = #"{"code":200,"msg":"Acknowledged fixture","data":{"id":910}}"#, status: Int = 200, fail: Bool = false) { self.response = Data(response.utf8); self.status = status; self.fail = fail }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path == "/api/coupon/mypublishlist" { return (CouponManagementSyntheticFixtures.published, 200) }
            if fail { throw URLError(.timedOut) }; return (response, status)
        }
        func saved() -> [URLRequest] { requests }
    }
    func testDormantHTTPBothGrantsOffAndExactPublicationAndStopSerialization() async throws {
        let http = WriteHTTP(), current = try session()
        let credential = try CouponManagementReadCredentials(session: current, token: "synthetic-token")
        let config = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test")))
        let disabled = CouponManagementHTTPDormantTransport(configuration: config, http: http, credentials: { credential })
        let publish = try CouponManagementContract.publish(CouponManagementSyntheticFixtures.draft())
        do { _ = try await disabled.send(publish, session: current); XCTFail("Transport grant is off") } catch {}
        let granted = CouponManagementHTTPDormantTransport(configuration: config, http: http, dormantWritesEnabled: true, credentials: { credential })
        let adapterOff = CouponManagementAdapter(transport: granted)
        let notSent = await adapterOff.submit(publish, session: current); XCTAssertEqual(notSent, .notSent)
        let before = await http.saved(); XCTAssertTrue(before.isEmpty)
        let adapter = CouponManagementAdapter(transport: granted, dormantWritesEnabled: true)
        let publishResult = await adapter.submit(publish, session: current)
        XCTAssertEqual(publishResult, .receipt(try CouponDefinitionID(910), "Acknowledged fixture"))
        let stopResult = await adapter.submit(CouponManagementContract.stop(try CouponDefinitionID(710)), session: current)
        XCTAssertEqual(stopResult, .acknowledged("Acknowledged fixture"))
        let requests = await http.saved(); XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].url?.path, "/api/coupon/publish"); XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
        guard case .json(let body) = publish.body else { return XCTFail("Expected JSON") }
        XCTAssertEqual(requests[0].httpBody, body)
        XCTAssertEqual(requests[1].url?.path, "/api/coupon/stop")
        XCTAssertTrue(requests[1].value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertTrue(String(decoding: try XCTUnwrap(requests[1].httpBody), as: UTF8.self).contains("name=\"couponId\"\r\n\r\n710\r\n"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "synthetic-token")
    }
    func testDormantHTTPTimeoutUsesPersistentCoordinatorLock() async throws {
        let http = WriteHTTP(fail: true), current = try session(), fake = Fake(), locks = MemoryLocks()
        let credential = try CouponManagementReadCredentials(session: current, token: "synthetic-token")
        let config = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test")))
        let transport = CouponManagementHTTPDormantTransport(configuration: config, http: http, dormantWritesEnabled: true, credentials: { credential })
        let core = CouponManagementCoordinator(adapter: .init(transport: transport, dormantWritesEnabled: true), authorizer: fake, locks: locks, currentSession: { current })
        core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish(); await core.confirm(try XCTUnwrap(core.review))
        XCTAssertEqual(core.issue, .locked); XCTAssertEqual(locks.items.count, 1)
        let requests = await http.saved(); XCTAssertEqual(requests.count, 1)
    }
    func testDormantHTTPAmbiguousRejectionPreservesOriginalMessageAndUnknown() async throws {
        let http = WriteHTTP(response: #"{"code":429,"msg":"发券太频繁,请稍后再试"}"#), current = try session()
        let credential = try CouponManagementReadCredentials(session: current, token: "synthetic-token")
        let config = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test")))
        let transport = CouponManagementHTTPDormantTransport(configuration: config, http: http, dormantWritesEnabled: true, credentials: { credential })
        let adapter = CouponManagementAdapter(transport: transport, dormantWritesEnabled: true)
        let outcome = await adapter.submit(try CouponManagementContract.publish(CouponManagementSyntheticFixtures.draft()), session: current)
        XCTAssertEqual(outcome, .unknownWithMessage("发券太频繁,请稍后再试"))
    }

    func testApprovedReadGrantRejectsForeignAccountAndWritePaths() async throws {
        let current = try session(), other = try session(2, account: 2), http = ReadHTTP()
        let config = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test")))
        let approval = try OperationEndpointApproval(baseURL: config.baseURL, namespace: current.namespace, accountID: current.accountID, paths: ["api/coupon/mypublishlist"])
        let wrapped = CouponManagementApprovedReadTransport(configuration: config, approval: approval, transport: http, currentSession: { other })
        var request = URLRequest(url: config.baseURL.appendingPathComponent("api/coupon/mypublishlist")); request.httpMethod = "POST"
        do { _ = try await wrapped.send(request); XCTFail("Foreign account") } catch {}
        let owned = CouponManagementApprovedReadTransport(configuration: config, approval: approval, transport: http, currentSession: { current })
        request.url = config.baseURL.appendingPathComponent("api/coupon/stop")
        do { _ = try await owned.send(request); XCTFail("No mutation through read grant") } catch {}
        let calls = await http.saved(); XCTAssertTrue(calls.isEmpty)
    }
    func testApprovedReadGrantAcceptsOnlyExactOwnedPath() async throws {
        let current = try session(), http = ReadHTTP()
        let config = try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.test")))
        let approval = try OperationEndpointApproval(baseURL: config.baseURL, namespace: current.namespace, accountID: current.accountID, paths: ["api/coupon/mypublishlist"])
        let wrapped = CouponManagementApprovedReadTransport(configuration: config, approval: approval, transport: http, currentSession: { current })
        var request = URLRequest(url: config.baseURL.appendingPathComponent("api/coupon/mypublishlist")); request.httpMethod = "POST"
        _ = try await wrapped.send(request)
        let calls = await http.saved(); XCTAssertEqual(calls.count, 1)
    }

    func testMalformedEnvelopeCodeTypesCannotProveSuccessOrBusinessRejection() throws {
        for code in ["true", "false", "\"500\"", "null", "409.5"] {
            for status in [200, 400] {
                let data = Data("{\"code\":\(code),\"msg\":\"Not proof of rejection\"}".utf8)
                XCTAssertThrowsError(try CouponManagementContract.requireSuccess(data, status: status)) { error in
                    XCTAssertEqual(error as? CouponManagementError, .malformed)
                }
            }
        }
    }
    func testLongDeploymentNamespaceUsesBoundedDurableFilename() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let locks = try CouponManagementFileLocks(directory: folder)
        let owner = String(repeating: "deployment-namespace", count: 80)
        let record = CouponManagementPending(operationID: UUID(), ownerKey: owner, resource: "publish", request: try CouponManagementContract.publish(CouponManagementSyntheticFixtures.draft()), createdAt: Date())
        try locks.acquire(record)
        XCTAssertEqual(try locks.pending(ownerKey: owner, resource: "publish"), record)
        let path = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(path.lastPathComponent.utf8.count, 69)
    }

}
