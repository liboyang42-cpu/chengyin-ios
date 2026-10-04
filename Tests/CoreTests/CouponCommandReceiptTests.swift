import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class CouponCommandReceiptTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/CouponCommandReceipts/\(name).json"))
    }
    private func context(epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: "https://example.test/native")!, role: "merchant",
              session: try .init(accountID: 7002, epoch: epoch, namespace: "command-test", token: "synthetic-command"))
    }
    private func session(epoch: UInt64 = 1) throws -> CouponManagementSession {
        try .init(accountID: 7002, namespace: "command-test", epoch: epoch, authorizationRevision: "test-lease-\(epoch)")
    }
    private func permission(owner: Int = 9001, merchant: Int = 11) -> CouponPublisherPermission {
        .init(revision: "current-authority", mayPublish: true, merchantID: merchant, ownerMemberID: owner)
    }
    private func directory() throws -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: value) }; return value
    }
    private func record(id: String = "11111111-1111-4111-8111-111111111111", request: CouponManagementRequest? = nil) throws -> CouponManagementPending {
        let request = try request ?? CouponManagementRequest(path: "/api/coupon/publish", body: .json(fixture("command-publish-request")), mutates: true)
        var value = CouponManagementPending(operationID: UUID(uuidString: id)!, ownerKey: try session().ownerKey,
            resource: request.path.hasSuffix("publish") ? "publish" : "stop:\(try CouponCommandCanonical.stopID(request))", request: request, createdAt: Date())
        value.wire = try .init(request: request)
        value.command = try .init(record: value, session: session(), permission: permission())
        return value
    }
    func testExactProductionJacksonReceiptFixtures() throws {
        let publish = try record()
        XCTAssertEqual(publish.command?.payloadHash, "a72d49610a0a0687449a8068e4565db197cb007ca6d6b28ffa140235b6817cbb")
        XCTAssertEqual(CouponCommandReceipt.outcome(try fixture("command-publish-succeeded"), status: 200, record: publish), .receipt(try .init(1001), "发布成功"))
        let rejected = try record(id: "22222222-2222-4222-8222-222222222222")
        guard case .rejected = CouponCommandReceipt.outcome(try fixture("command-publish-rejected"), status: 200, record: rejected) else { return XCTFail("A code500 terminal receipt must be recognized") }
        XCTAssertEqual(try CouponCommandOwnerIdentity.decode(fixture("coop-profile-owner"), status: 200, merchantID: 11), 9001)
        XCTAssertThrowsError(try CouponCommandOwnerIdentity.decode(fixture("coop-profile-owner"), status: 200, merchantID: 12))
        XCTAssertThrowsError(try CouponCommandOwnerIdentity.decode(Data(#"{"code":200,"data":{"id":11}}"#.utf8), status: 200, merchantID: 11))
    }
    func testJavaGoldenBinaryVectorsIncludingUnicodeAndTypedCounts() throws {
        struct Vector: Decodable {
            let label: String; let operation: String; let merchantId: Int; let ownerMemberId: Int; let couponId: Int?
            let name: String?; let description: String?; let couponType: Int?; let publishCount: Int?
            let startMilliseconds: Int64?; let endMilliseconds: Int64?; let payloadHash: String
        }
        let vectors = try JSONDecoder().decode([Vector].self, from: fixture("java-canonical-vectors"))
        XCTAssertEqual(vectors.count, 12)
        for vector in vectors {
            let request: CouponManagementRequest
            if vector.operation == "STOP" { request = try .stopForTest(XCTUnwrap(vector.couponId)) }
            else {
                var body: [String: Any] = ["scope": "MERCHANT", "name": try XCTUnwrap(vector.name), "couponType": try XCTUnwrap(vector.couponType), "publishCount": try XCTUnwrap(vector.publishCount),
                    "startTime": CouponValidityTime.wire(Date(timeIntervalSince1970: Double(try XCTUnwrap(vector.startMilliseconds)) / 1000)),
                    "endTime": CouponValidityTime.wire(Date(timeIntervalSince1970: Double(try XCTUnwrap(vector.endMilliseconds)) / 1000))]
                if let description = vector.description { body["description"] = description }
                request = .init(path: "/api/coupon/publish", body: .json(try JSONSerialization.data(withJSONObject: body)), mutates: true)
            }
            let actual = try CouponCommandCanonical.hash(request, merchantID: vector.merchantId, ownerMemberID: vector.ownerMemberId)
            if vector.label == "millisecond-difference" {
                // Native wire contains whole seconds. The backend's +1ms raw-Date vector must NOT match.
                XCTAssertNotEqual(actual, vector.payloadHash)
                XCTAssertEqual(actual, vectors.first { $0.label == "null-description" }?.payloadHash)
            } else { XCTAssertEqual(actual, vector.payloadHash, vector.label) }
        }
    }
    func testWrongReceiptDimensionsAndOldServerNeverProveTerminal() throws {
        let value = try record(); let original = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("command-publish-succeeded")) as? [String: Any])
        for (field, changed) in [("version", 2 as Any), ("requestId", UUID().uuidString.lowercased()), ("actorMemberId", 7003), ("merchantId", 12), ("ownerMemberId", 9002), ("scope", "CLUB"), ("operation", "STOP"), ("payloadHash", String(repeating: "0", count: 64)), ("outcome", "PENDING"), ("reasonCode", "UNKNOWN"), ("couponId", 0), ("couponStatusAtExecution", 4), ("completedAt", "not-a-date")] {
            var envelope = original; var data = try XCTUnwrap(envelope["data"] as? [String: Any]); var receipt = try XCTUnwrap(data["commandReceipt"] as? [String: Any])
            receipt[field] = changed; data["commandReceipt"] = receipt; envelope["data"] = data
            XCTAssertEqual(CouponCommandReceipt.outcome(try JSONSerialization.data(withJSONObject: envelope), status: 200, record: value), .unknown, field)
        }
        for code in [200, 404, 409, 500, 503] {
            let data = Data("{\"code\":\(code),\"data\":{\"id\":1001},\"msg\":\"unknown\"}".utf8)
            XCTAssertEqual(CouponCommandReceipt.outcome(data, status: 200, record: value), .unknown)
        }
        for status in [202, 400, 401, 403, 500, 503] {
            XCTAssertEqual(CouponCommandReceipt.outcome(try fixture("command-publish-succeeded"), status: status, record: value), .unknown)
        }
        var legacy = value; legacy.command = nil
        XCTAssertEqual(CouponCommandReceipt.outcome(try fixture("command-publish-succeeded"), status: 200, record: legacy), .unknown)
    }
    func testPersistedWireMismatchAndUnrelatedCorruptFileNeverUnlock() async throws {
        let original = try record()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var wire = try XCTUnwrap(json["wire"] as? [String: Any]); wire["data"] = Data("{}".utf8).base64EncodedString(); json["wire"] = wire
        let changed = try JSONDecoder().decode(CouponManagementPending.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try changed.command?.validate(record: changed, session: session(), permission: permission()))
        XCTAssertEqual(CouponCommandReceipt.outcome(try fixture("command-publish-succeeded"), status: 200, record: changed), .unknown)
        let dir = try directory(), locks = try CouponManagementFileLocks(directory: dir); try locks.acquire(original)
        let unrelated = dir.appendingPathComponent("unrelated-account.json"); try Data("truncated".utf8).write(to: unrelated)
        XCTAssertThrowsError(try locks.pendingCommands(ownerKey: session().ownerKey))
        XCTAssertEqual(try locks.pending(ownerKey: session().ownerKey, resource: "publish"), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }
    func testStopTerminalReceiptRequiresExactTargetAndCompatibleState() throws {
        let request = CouponManagementContract.stop(try .init(1001)), value = try record(request: request), command = try XCTUnwrap(value.command)
        var receipt: [String: Any] = ["version": 1, "requestId": command.requestID, "operation": "STOP", "scope": "MERCHANT", "merchantId": 11,
            "ownerMemberId": 9001, "actorMemberId": 7002, "payloadHash": command.payloadHash, "outcome": "SUCCEEDED", "reasonCode": "STOPPED", "couponId": 1001, "couponStatusAtExecution": 4, "completedAt": "2026-10-04T22:00:00.123+08:00"]
        func result(_ code: Int) throws -> CouponManagementOutcome {
            CouponCommandReceipt.outcome(try JSONSerialization.data(withJSONObject: ["code": code, "data": ["commandReceipt": receipt]]), status: 200, record: value)
        }
        XCTAssertEqual(try result(200), .receipt(try .init(1001), nil))
        receipt["couponId"] = 1002; XCTAssertEqual(try result(200), .unknown); receipt["couponId"] = 1001
        receipt["outcome"] = "REJECTED"; receipt["reasonCode"] = "COUPON_ALREADY_STOPPED"
        guard case .rejected = try result(500) else { return XCTFail() }
        receipt["couponStatusAtExecution"] = 1; XCTAssertEqual(try result(500), .unknown)
    }
    final class OwnerWire: HTTPTransport {
        var merchant = 11, owner = 9001, coop = true, coupon = true, ownerReads = 0
        var malformedOwner = false
        var afterOwner: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            if request.url!.path.hasSuffix("/access/me") {
                let permissions = (coupon ? ["merchant:coupon:manage"] : []) + (coop ? ["merchant:coop:manage"] : [])
                return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["active": true, "merchant": ["id": 11], "roleCode": "MERCHANT_MARKETING", "permissions": permissions]]), 200)
            }
            XCTAssertTrue(request.url!.path.hasSuffix("/coop-profile")); XCTAssertNil(request.httpBody)
            ownerReads += 1; afterOwner?()
            let value: [String: Any] = malformedOwner ? ["id": merchant] : ["id": merchant, "memberId": owner, "phone": "discard-this-unexpected-field"]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": value]), 200)
        }
    }
    func testRealAuthorizerRequiresDualPermissionAndFreshExactOwnerOnlyForV1() async throws {
        for mode in ["valid", "noCoop", "noCoupon", "wrongMerchant", "missingOwner", "zeroOwner", "session", "revoked", "permissionChanged"] {
            let s = try session(), c = try context(), wire = OwnerWire(); var current: CouponManagementSession? = s
            let approval = try CouponCommandProtocolApproval(context: c, merchantID: 11, verifiedVersion: 1, expiresAt: Date().addingTimeInterval(600))
            if mode == "noCoop" { wire.coop = false }; if mode == "noCoupon" { wire.coupon = false }
            if mode == "wrongMerchant" { wire.merchant = 12 }; if mode == "missingOwner" { wire.malformedOwner = true }; if mode == "zeroOwner" { wire.owner = 0 }
            if mode == "session" { wire.afterOwner = { current = nil } }; if mode == "revoked" { wire.afterOwner = { approval.revoke() } }
            if mode == "permissionChanged" { wire.afterOwner = { wire.coop = false } }
            let authorizer = CouponMerchantPublisherAuthorizer(configuration: try .init(baseURL: c.baseURL), http: wire, context: c, merchantID: 11, commandProtocol: approval, current: { current })
            do { let permission = try await authorizer.freshPermission(session: s); XCTAssertEqual(mode, "valid"); XCTAssertEqual(permission.ownerMemberID, 9001) }
            catch { XCTAssertNotEqual(mode, "valid") }
            if mode == "noCoop" || mode == "noCoupon" { XCTAssertEqual(wire.ownerReads, 0) }
        }
        let s = try session(), c = try context(), wire = OwnerWire(); wire.coop = false
        let legacy = CouponMerchantPublisherAuthorizer(configuration: try .init(baseURL: c.baseURL), http: wire, context: c, merchantID: 11, current: { s })
        let permission = try await legacy.freshPermission(session: s)
        XCTAssertNil(permission.ownerMemberID); XCTAssertEqual(wire.ownerReads, 0)
    }
    func testReceiptReadRouteRejectsAlternateMethodsFieldsHeadersAndURLs() throws {
        let base = try context().baseURL
        let fields = ["requestId": "11111111-1111-4111-8111-111111111111", "merchantId": "11", "scope": "MERCHANT"]
        let canonical = try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/coupon/command-receipt"), fields: fields, token: "synthetic-command", boundary: "Fixed-boundary")
        XCTAssertNotNil(CouponCommandReadRoute(request: canonical, baseURL: base, merchantID: 11))
        var invalid: [URLRequest] = []
        for (key, value) in [("merchantId", "12"), ("merchantId", "011"), ("scope", "CLUB"), ("requestId", "not-a-uuid"), ("requestId", "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA"), ("couponId", "1")] {
            var altered = fields; altered[key] = value
            invalid.append(try AuthRequestBuilder.makeFormRequest(url: canonical.url!, fields: altered, token: "synthetic-command"))
        }
        var request = canonical; request.httpMethod = "GET"; invalid.append(request)
        request = canonical; request.setValue("id", forHTTPHeaderField: "X-Coupon-Command-Id"); invalid.append(request)
        request = canonical; request.httpBodyStream = InputStream(data: Data()); invalid.append(request)
        request = canonical; request.httpBody?.append(Data("extra".utf8)); invalid.append(request)
        for path in ["https://example.test/native/api/coupon/command-receipt?scope=MERCHANT", "https://example.test/native/api/coupon/command-receipt#x", "https://example.test/native/api/coupon/%63ommand-receipt", "https://other.test/native/api/coupon/command-receipt"] {
            request = canonical; request.url = URL(string: path); invalid.append(request)
        }
        for request in invalid { XCTAssertNil(CouponCommandReadRoute(request: request, baseURL: base, merchantID: 11)) }
    }
    final class Authority: CouponPublisherAuthorizing {
        var owner = 9001, merchant = 11, allowed = true
        var afterRead: (() -> Void)?
        func freshPermission(session: CouponManagementSession) async throws -> CouponPublisherPermission {
            guard allowed else { throw CouponManagementError.forbidden }
            afterRead?()
            return .init(revision: "authority", mayPublish: true, merchantID: merchant, ownerMemberID: owner)
        }
    }
    final class Wire: CouponManagementConfirmedHTTPTransport {
        let configuration: APIConfiguration
        var credentials: CouponManagementReadCredentials
        var writes = 0, receiptReads = 0
        var receiptResponse = Data(#"{"code":404,"data":{"reasonCode":"COMMAND_NOT_FOUND"}}"#.utf8)
        var command: CouponManagementPending?
        var lostResponse = true, legacyResponse = false, replayDenied = false
        var afterReceipt: (() -> Void)?
        init(configuration: APIConfiguration, credentials: CouponManagementReadCredentials) { self.configuration = configuration; self.credentials = credentials }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            if request.url!.path.hasSuffix("command-receipt") { receiptReads += 1; afterReceipt?(); return (receiptResponse, 200) }
            return (Data(#"{"code":200,"data":[]}"#.utf8), 200)
        }
        func sendConfirmed(_ request: URLRequest, authorization: CouponManagementDispatchAuthorization) async throws -> (Data, Int) {
            try authorization.consume(request, configuration: configuration, credentials: credentials)
            writes += 1; command = authorization.record
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Coupon-Command-Id"), command?.command?.requestID)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Coupon-Merchant-Id"), "11")
            do { try authorization.consume(request, configuration: configuration, credentials: credentials) } catch { replayDenied = true }
            if lostResponse { throw URLError(.timedOut) }
            return (legacyResponse ? Data(#"{"code":200,"data":{"id":1001}}"#.utf8) : receiptResponse, 200)
        }
    }
    private func runtime(_ wire: Wire, _ approval: CouponCommandProtocolApproval?, writes: Bool = true) -> CouponManagementRuntimeTransport {
        .init(configuration: wire.configuration, http: wire, actions: writes ? [.publish, .stop] : [], commandProtocol: approval, credentials: { wire.credentials })
    }
    private func response(for record: CouponManagementPending, rejected: Bool = false) throws -> Data {
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture(rejected ? "command-publish-rejected" : "command-publish-succeeded")) as? [String: Any])
        var data = try XCTUnwrap(value["data"] as? [String: Any]); var receipt = try XCTUnwrap(data["commandReceipt"] as? [String: Any]); let c = try XCTUnwrap(record.command)
        receipt["requestId"] = c.requestID; receipt["payloadHash"] = c.payloadHash
        data["commandReceipt"] = receipt; value["data"] = data
        return try JSONSerialization.data(withJSONObject: value)
    }
    func testFirstSendPersistsCommandBeforeTransportAndRestartRecoversWithoutWriteLease() async throws {
        let dir = try directory(), s = try session(), config = try APIConfiguration(baseURL: context().baseURL)
        let wire = Wire(configuration: config, credentials: try .init(session: s, token: "synthetic-command"))
        let capability = try CouponCommandProtocolApproval(context: context(), merchantID: 11, verifiedVersion: 1, expiresAt: Date().addingTimeInterval(600))
        let locks = try CouponManagementFileLocks(directory: dir), authorizer = Authority()
        let core = CouponManagementCoordinator(adapter: .init(transport: runtime(wire, capability), dormantWritesEnabled: true), authorizer: authorizer, locks: locks, currentSession: { s })
        core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish(); await core.confirm(try XCTUnwrap(core.review))
        XCTAssertEqual(wire.writes, 1); XCTAssertTrue(wire.replayDenied); XCTAssertEqual(core.issue, .locked)
        let persisted = try XCTUnwrap(locks.pending(ownerKey: s.ownerKey, resource: "publish")); XCTAssertEqual(persisted, wire.command)
        let s2 = try session(epoch: 2); wire.credentials = try .init(session: s2, token: "synthetic-command")
        let next = try CouponCommandProtocolApproval(context: context(epoch: 2), merchantID: 11, verifiedVersion: 1, expiresAt: Date().addingTimeInterval(600))
        wire.receiptResponse = try response(for: persisted)
        let reopened = CouponManagementCoordinator(adapter: .init(transport: runtime(wire, next, writes: false)), authorizer: authorizer, locks: try CouponManagementFileLocks(directory: dir), currentSession: { s2 })
        XCTAssertFalse(reopened.canSubmit); await reopened.recoverPendingCommands()
        XCTAssertEqual(wire.writes, 1); XCTAssertEqual(wire.receiptReads, 1); XCTAssertEqual(reopened.recoveredCommandCount, 1)
        XCTAssertNil(try locks.pending(ownerKey: s.ownerKey, resource: "publish")); XCTAssertTrue(reopened.acknowledged)
    }
    func testNotFoundConflictDisabledMalformedAndLegacyRemainLockedWithoutResend() async throws {
        for body in [#"{"code":404}"#, #"{"code":409}"#, #"{"code":503}"#, #"{"code":200,"data":{"id":1001}}"#, "invalid"] {
            let s = try session(), locks = try CouponManagementFileLocks(directory: directory()), record = try record()
            try locks.acquire(record)
            let wire = Wire(configuration: try .init(baseURL: context().baseURL), credentials: try .init(session: s, token: "synthetic-command")); wire.receiptResponse = Data(body.utf8)
            let approval = try CouponCommandProtocolApproval(context: context(), merchantID: 11, verifiedVersion: 1, expiresAt: Date().addingTimeInterval(600))
            let core = CouponManagementCoordinator(adapter: .init(transport: runtime(wire, approval, writes: false)), authorizer: Authority(), locks: locks, currentSession: { s })
            await core.recoverPendingCommands(); XCTAssertEqual(core.issue, .locked); XCTAssertEqual(wire.writes, 0)
            XCTAssertEqual(try locks.pending(ownerKey: s.ownerKey, resource: "publish"), record)
        }
        let s = try session(), locks = try CouponManagementFileLocks(directory: directory()); var legacy = try record(); legacy.command = nil
        try locks.acquire(legacy); XCTAssertTrue(try locks.pendingCommands(ownerKey: s.ownerKey).isEmpty)
        XCTAssertEqual(try locks.pending(ownerKey: s.ownerKey, resource: "publish"), legacy)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any]); json.removeValue(forKey: "command"); json.removeValue(forKey: "wire")
        let old = try JSONDecoder().decode(CouponManagementPending.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.command); XCTAssertNil(old.wire); XCTAssertEqual(old.operationID, legacy.operationID)
    }
    func testDeniedChangedOwnerRevocationAndSessionSwitchNeverClearRecovery() async throws {
        for mode in ["owner", "merchant", "permission", "revoked", "session", "ownerAfterReceipt", "permissionAfterReceipt"] {
            let s = try session(), locks = try CouponManagementFileLocks(directory: directory()), record = try record(); try locks.acquire(record)
            var current: CouponManagementSession? = s
            let wire = Wire(configuration: try .init(baseURL: context().baseURL), credentials: try .init(session: s, token: "synthetic-command")); wire.receiptResponse = try response(for: record)
            let approval = try CouponCommandProtocolApproval(context: context(), merchantID: 11, verifiedVersion: 1, expiresAt: Date().addingTimeInterval(600))
            let authority = Authority()
            if mode == "owner" { authority.owner = 9002 }; if mode == "merchant" { authority.merchant = 12 }; if mode == "permission" { authority.allowed = false }
            if mode == "revoked" { wire.afterReceipt = { approval.revoke() } }
            if mode == "session" { wire.afterReceipt = { current = nil } }
            if mode == "ownerAfterReceipt" { wire.afterReceipt = { authority.owner = 9002 } }
            if mode == "permissionAfterReceipt" { wire.afterReceipt = { authority.allowed = false } }
            let core = CouponManagementCoordinator(adapter: .init(transport: runtime(wire, approval, writes: false)), authorizer: authority, locks: locks, currentSession: { current })
            await core.recoverPendingCommands(); XCTAssertEqual(core.recoveredCommandCount, 0); XCTAssertEqual(wire.writes, 0)
            XCTAssertEqual(try locks.pending(ownerKey: s.ownerKey, resource: "publish"), record)
        }
    }
    func testTerminalRejectionCanClearButOldServerSuccessOnFirstSendCannot() async throws {
        let s = try session(), locks = try CouponManagementFileLocks(directory: directory()), record = try record(); try locks.acquire(record)
        let wire = Wire(configuration: try .init(baseURL: context().baseURL), credentials: try .init(session: s, token: "synthetic-command")); wire.receiptResponse = try response(for: record, rejected: true)
        let approval = try CouponCommandProtocolApproval(context: context(), merchantID: 11, verifiedVersion: 1, expiresAt: Date().addingTimeInterval(600))
        let core = CouponManagementCoordinator(adapter: .init(transport: runtime(wire, approval), dormantWritesEnabled: true), authorizer: Authority(), locks: locks, currentSession: { s })
        await core.recoverPendingCommands(); XCTAssertEqual(core.recoveredCommandCount, 1); XCTAssertFalse(core.acknowledged); XCTAssertEqual(wire.writes, 0)
        wire.lostResponse = false; wire.legacyResponse = true
        core.change(CouponManagementSyntheticFixtures.draft()); await core.preparePublish(); await core.confirm(try XCTUnwrap(core.review))
        XCTAssertEqual(wire.writes, 1); XCTAssertEqual(core.issue, .locked); XCTAssertNotNil(try locks.pending(ownerKey: s.ownerKey, resource: "publish"))
    }
    func testReceiptReturningAfterLeaveOrCancelRetainsExactRecord() async throws {
        for cancel in [false, true] {
            let s = try session(), locks = try CouponManagementFileLocks(directory: directory()), record = try record(); try locks.acquire(record)
            let wire = Wire(configuration: try .init(baseURL: context().baseURL), credentials: try .init(session: s, token: "synthetic-command")); wire.receiptResponse = try response(for: record)
            let approval = try CouponCommandProtocolApproval(context: context(), merchantID: 11, verifiedVersion: 1, expiresAt: Date().addingTimeInterval(600))
            let core = CouponManagementCoordinator(adapter: .init(transport: runtime(wire, approval, writes: false)), authorizer: Authority(), locks: locks, currentSession: { s })
            wire.afterReceipt = { if cancel { core.cancelReview() } else { core.leave() } }
            await core.recoverPendingCommands(); wire.afterReceipt = nil
            XCTAssertEqual(wire.receiptReads, 1); XCTAssertEqual(wire.writes, 0); XCTAssertEqual(core.recoveredCommandCount, 0)
            XCTAssertEqual(try locks.pending(ownerKey: s.ownerKey, resource: "publish"), record)
        }
    }
    func testStoppedCommandCanRecoverWithoutAnyPublishedListRow() async throws {
        let s = try session(), locks = try CouponManagementFileLocks(directory: directory())
        let pending = try record(request: CouponManagementContract.stop(try .init(1001))); try locks.acquire(pending)
        let command = try XCTUnwrap(pending.command)
        let wire = Wire(configuration: try .init(baseURL: context().baseURL), credentials: try .init(session: s, token: "synthetic-command"))
        wire.receiptResponse = try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["commandReceipt": ["version": 1, "requestId": command.requestID,
            "operation": "STOP", "scope": "MERCHANT", "merchantId": 11, "ownerMemberId": 9001, "actorMemberId": 7002, "payloadHash": command.payloadHash,
            "outcome": "SUCCEEDED", "reasonCode": "STOPPED", "couponId": 1001, "couponStatusAtExecution": 4, "completedAt": "2026-10-04T22:00:00.123+08:00"]]])
        let approval = try CouponCommandProtocolApproval(context: context(), merchantID: 11, verifiedVersion: 1, expiresAt: Date().addingTimeInterval(600))
        let core = CouponManagementCoordinator(adapter: .init(transport: runtime(wire, approval, writes: false)), authorizer: Authority(), locks: locks, currentSession: { s })
        await core.recoverPendingCommands()
        XCTAssertEqual(core.recoveredCommandCount, 1); XCTAssertEqual(core.acknowledgedDefinitionID?.value, 1001)
        XCTAssertTrue(core.rows.isEmpty); XCTAssertNil(core.verifiedRecord); XCTAssertEqual(wire.writes, 0)
        XCTAssertNil(try locks.pending(ownerKey: s.ownerKey, resource: "stop:1001"))
    }
    func testDefaultNilAndInvalidCapabilityCannotRecoverOrMintCommand() throws {
        let s = try session(), wire = Wire(configuration: try .init(baseURL: context().baseURL), credentials: try .init(session: s, token: "synthetic-command"))
        let value = runtime(wire, nil)
        XCTAssertFalse(value.canRecoverCommands)
        XCTAssertNil(try value.prepareCommand(record: record(), session: s, permission: permission()))
        XCTAssertThrowsError(try CouponCommandProtocolApproval(context: context(), merchantID: 11, verifiedVersion: 2, expiresAt: Date().addingTimeInterval(600)))
        let approval = try CouponCommandProtocolApproval(context: context(), merchantID: 11, verifiedVersion: 1, expiresAt: Date().addingTimeInterval(600)); approval.revoke()
        XCTAssertThrowsError(try runtime(wire, approval).prepareCommand(record: record(), session: s, permission: permission()))
    }
}
private extension CouponManagementRequest {
    static func stopForTest(_ id: Int) throws -> Self { CouponManagementContract.stop(try CouponDefinitionID(id)) }
}
