import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Source-backed preflight rejection vocabulary. Uses real decoder/runtime/coordinator/file locks
/// with injected HTTP/authority and a failing-release wrapper. No live endpoint or default grants.
@MainActor final class CouponCommandPreflightRejectionRecoveryTests: XCTestCase {
    private let reasons = ["INPUT_CHANGED", "SAFETY_REJECTED"]
    private let message = "原请求未发布，请核对后重新确认"
    private let base = URL(string: "https://example.test/native")!
    private func session(epoch: UInt64 = 1) throws -> CouponManagementSession {
        try .init(accountID: 7002, namespace: "preflight-recovery-test", epoch: epoch, authorizationRevision: "session-\(epoch)")
    }
    private func draft() -> CouponManagementDraft {
        var value = CouponManagementDraft(); value.name = "原确认券"; value.description = "保留原稿"
        value.couponType = 1; value.quantity = "10"
        value.startTime = Date(timeIntervalSince1970: 1_793_928_000)
        value.endTime = Date(timeIntervalSince1970: 1_794_014_400)
        return value
    }
    private func record(stop: Bool = false) throws -> CouponManagementPending {
        let request: CouponManagementRequest
        if stop { request = CouponManagementContract.stop(try CouponDefinitionID(44)) }
        else { request = try CouponManagementContract.publish(draft()) }
        var value = CouponManagementPending(operationID: UUID(uuidString: "12345678-1234-4234-8234-123456789abc")!,
            ownerKey: try session().ownerKey, resource: stop ? "stop:44" : "publish", request: request, createdAt: Date(timeIntervalSince1970: 1_793_900_000))
        value.wire = try .init(request: request)
        value.command = try .init(record: value, session: session(), permission: .init(revision: "current-authority", mayPublish: true, merchantID: 11, ownerMemberID: 9001))
        return value
    }
    private func envelope(_ reason: String, record: CouponManagementPending) throws -> [String: Any] {
        let c = try XCTUnwrap(record.command)
        return ["code": 500, "msg": message, "data": ["commandReceipt": [
            "version": c.version, "requestId": c.requestID, "operation": c.operation, "scope": "MERCHANT",
            "merchantId": c.merchantID, "ownerMemberId": c.ownerMemberID, "actorMemberId": c.actorMemberID,
            "payloadHash": c.payloadHash, "outcome": "REJECTED", "reasonCode": reason,
            "couponId": NSNull(), "couponStatusAtExecution": NSNull(), "completedAt": "2026-11-05T18:59:00.123Z"]]]
    }
    private func bytes(_ reason: String, record: CouponManagementPending) throws -> Data {
        try JSONSerialization.data(withJSONObject: envelope(reason, record: record))
    }
    private func replaceReceipt(_ original: [String: Any], field: String, value: Any) throws -> Data {
        var envelope = original; var data = try XCTUnwrap(envelope["data"] as? [String: Any])
        var receipt = try XCTUnwrap(data["commandReceipt"] as? [String: Any]); receipt[field] = value
        data["commandReceipt"] = receipt; envelope["data"] = data
        return try JSONSerialization.data(withJSONObject: envelope)
    }
    private func directory() -> URL {
        let result = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: result) }; return result
    }
    private func journalURL(_ directory: URL) throws -> URL {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        XCTAssertEqual(files.count, 1); return try XCTUnwrap(files.first)
    }
    private final class Authority: CouponPublisherAuthorizing {
        var reads = 0, owner = 9001
        var revision = "current-authority"
        func freshPermission(session: CouponManagementSession) async throws -> CouponPublisherPermission {
            reads += 1; return .init(revision: revision, mayPublish: true, merchantID: 11, ownerMemberID: owner)
        }
    }
    private final class State {
        var session: CouponManagementSession?
        init(_ session: CouponManagementSession) { self.session = session }
    }
    private final class Wire: CouponManagementConfirmedHTTPTransport {
        let configuration: APIConfiguration
        let credentials: CouponManagementReadCredentials
        var response = Data(), receiptReads = 0, listReads = 0, writes = 0
        var requests: [URLRequest] = [], submitted: [CouponManagementPending] = []
        var onReceipt: (() throws -> Void)?
        var responseToWrite: ((CouponManagementPending) throws -> Data)?
        var pause = false
        var onPaused: (() -> Void)?
        var continuation: CheckedContinuation<(Data, Int), Error>?
        init(configuration: APIConfiguration, credentials: CouponManagementReadCredentials) { self.configuration = configuration; self.credentials = credentials }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path.hasSuffix("/command-receipt") == true {
                receiptReads += 1; try onReceipt?()
                if pause {
                    return try await withCheckedThrowingContinuation { continuation in
                        self.continuation = continuation; onPaused?()
                    }
                }
                return (response, 200)
            }
            guard request.url?.path.hasSuffix("/mypublishlist") == true else {
                XCTFail("Recovery sent an unexpected route"); throw CouponManagementError.unavailable
            }
            listReads += 1; return (Data(#"{"code":200,"data":[]}"#.utf8), 200)
        }
        func finish() {
            let pending = continuation; continuation = nil; pending?.resume(returning: (response, 200))
        }
        func sendConfirmed(_ request: URLRequest, authorization: CouponManagementDispatchAuthorization) async throws -> (Data, Int) {
            try authorization.consume(request, configuration: configuration, credentials: credentials)
            writes += 1; submitted.append(authorization.record)
            guard let responseToWrite else { XCTFail("Read-only recovery must never resend"); throw CouponManagementError.unavailable }
            return (try responseToWrite(authorization.record), 200)
        }
    }
    private final class FailingRelease: CouponManagementLocking {
        let base: CouponManagementFileLocks
        var releaseAttempts = 0
        init(_ base: CouponManagementFileLocks) { self.base = base }
        func pending(ownerKey: String, resource: String) throws -> CouponManagementPending? { try base.pending(ownerKey: ownerKey, resource: resource) }
        func acquire(_ pending: CouponManagementPending) throws { try base.acquire(pending) }
        func pendingCommands(ownerKey: String) throws -> [CouponManagementPending] { try base.pendingCommands(ownerKey: ownerKey) }
        func release(_ pending: CouponManagementPending) throws { releaseAttempts += 1; throw CouponManagementError.storage }
    }
    private struct Harness {
        let core: CouponManagementCoordinator
        let wire: Wire
        let authority: Authority
        let capability: CouponCommandProtocolApproval?
        let state: State
    }
    private func harness(locks: any CouponManagementLocking, epoch: UInt64 = 1, protocolEnabled: Bool = true, writes: Bool = false) throws -> Harness {
        let s = try session(epoch: epoch), state = State(s)
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "merchant",
            session: try .init(accountID: s.accountID, epoch: s.epoch, namespace: s.namespace, token: "synthetic-preflight-token"))
        let capability: CouponCommandProtocolApproval?
        if protocolEnabled { capability = try CouponCommandProtocolApproval(context: context, merchantID: 11, verifiedVersion: 1, expiresAt: Date().addingTimeInterval(600)) }
        else { capability = nil }
        let wire = Wire(configuration: try .init(baseURL: base), credentials: try .init(session: s, token: "synthetic-preflight-token"))
        let authority = Authority()
        let transport = CouponManagementRuntimeTransport(configuration: wire.configuration, http: wire,
            actions: writes ? [.publish] : [], commandProtocol: capability, credentials: { state.session == s ? wire.credentials : nil })
        let core = CouponManagementCoordinator(adapter: .init(transport: transport, dormantWritesEnabled: writes),
            authorizer: authority, locks: locks, currentSession: { state.session })
        return .init(core: core, wire: wire, authority: authority, capability: capability, state: state)
    }

    func testBothOriginalPreflightReasonsAreOnlyExactPublicationRejections() throws {
        let original = try record()
        for reason in reasons {
            XCTAssertEqual(CouponCommandReceipt.outcome(try bytes(reason, record: original), status: 200, record: original), .rejected(message), reason)
        }
    }
    func testReasonsNeverTurnIntoSuccessOrApplyToStopCommands() throws {
        for reason in reasons {
            let original = try record(), stop = try record(stop: true)
            // A fully valid success shape must not borrow a preflight rejection reason.
            var success = try self.envelope(reason, record: original)
            var data = try XCTUnwrap(success["data"] as? [String: Any])
            var receipt = try XCTUnwrap(data["commandReceipt"] as? [String: Any])
            success["code"] = 200; receipt["outcome"] = "SUCCEEDED"; receipt["couponId"] = 44; receipt["couponStatusAtExecution"] = 1
            data["id"] = 44; data["commandReceipt"] = receipt; success["data"] = data
            XCTAssertEqual(CouponCommandReceipt.outcome(try JSONSerialization.data(withJSONObject: success), status: 200, record: original), .unknown)
            receipt["reasonCode"] = "PUBLISHED"; data["commandReceipt"] = receipt; success["data"] = data
            XCTAssertEqual(CouponCommandReceipt.outcome(try JSONSerialization.data(withJSONObject: success), status: 200, record: original), .receipt(try .init(44), message))
            // All other STOP dimensions, including the precise target, are canonical.
            var stopped = try self.envelope(reason, record: stop)
            var stopData = try XCTUnwrap(stopped["data"] as? [String: Any])
            var stopReceipt = try XCTUnwrap(stopData["commandReceipt"] as? [String: Any]); stopReceipt["couponId"] = 44
            for status in [NSNull(), 0, 1, 2, 3, 4] as [Any] {
                stopReceipt["couponStatusAtExecution"] = status; stopData["commandReceipt"] = stopReceipt; stopped["data"] = stopData
                XCTAssertEqual(CouponCommandReceipt.outcome(try JSONSerialization.data(withJSONObject: stopped), status: 200, record: stop), .unknown)
            }
            stopReceipt["reasonCode"] = "COUPON_ALREADY_STOPPED"; stopReceipt["couponStatusAtExecution"] = 4
            stopData["commandReceipt"] = stopReceipt; stopped["data"] = stopData
            XCTAssertEqual(CouponCommandReceipt.outcome(try JSONSerialization.data(withJSONObject: stopped), status: 200, record: stop), .rejected(message))
            XCTAssertEqual(CouponCommandReceipt.outcome(try bytes(reason.lowercased(), record: original), status: 200, record: original), .unknown)
        }
    }
    func testEachIdentityAndTerminalContradictionStaysUnknownForBothReasons() throws {
        let original = try record()
        let variants: [(String, Any)] = [("version", 2), ("requestId", UUID().uuidString.lowercased()), ("actorMemberId", 7003),
            ("merchantId", 12), ("ownerMemberId", 9002), ("scope", "CLUB"), ("operation", "STOP"),
            ("payloadHash", String(repeating: "0", count: 64)), ("outcome", "PENDING"), ("reasonCode", "UNREVIEWED_REASON"),
            ("couponId", 44), ("couponStatusAtExecution", 1), ("completedAt", "not-a-date")]
        for reason in reasons {
            for (field, value) in variants {
                XCTAssertEqual(CouponCommandReceipt.outcome(try replaceReceipt(envelope(reason, record: original), field: field, value: value), status: 200, record: original), .unknown, "\(reason):\(field)")
            }
        }
    }
    func testHTTPEnvelopeAndLegacyJournalCannotProveRejection() throws {
        let original = try record()
        for reason in reasons {
            for status in [202, 400, 401, 403, 500, 503] {
                XCTAssertEqual(CouponCommandReceipt.outcome(try bytes(reason, record: original), status: status, record: original), .unknown)
            }
            for code in [200, 404, 409, 503] {
                var envelope = try self.envelope(reason, record: original); envelope["code"] = code
                XCTAssertEqual(CouponCommandReceipt.outcome(try JSONSerialization.data(withJSONObject: envelope), status: 200, record: original), .unknown)
            }
            var envelope = try self.envelope(reason, record: original); var data = try XCTUnwrap(envelope["data"] as? [String: Any]); data["id"] = 44; envelope["data"] = data
            XCTAssertEqual(CouponCommandReceipt.outcome(try JSONSerialization.data(withJSONObject: envelope), status: 200, record: original), .unknown)
            var legacy = original; legacy.command = nil
            XCTAssertEqual(CouponCommandReceipt.outcome(try bytes(reason, record: original), status: 200, record: legacy), .unknown)
            let generic = try JSONSerialization.data(withJSONObject: ["code": 500, "msg": reason])
            XCTAssertEqual(CouponCommandReceipt.outcome(generic, status: 200, record: original), .unknown)
        }
    }
    func testPersistedWireChangeCannotBorrowOriginalRejectionReceipt() throws {
        let original = try record(); var value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        var wire = try XCTUnwrap(value["wire"] as? [String: Any]); wire["data"] = Data("{}".utf8).base64EncodedString(); value["wire"] = wire
        let changed = try JSONDecoder().decode(CouponManagementPending.self, from: JSONSerialization.data(withJSONObject: value))
        for reason in reasons { XCTAssertEqual(CouponCommandReceipt.outcome(try bytes(reason, record: original), status: 200, record: changed), .unknown) }
    }
    func testRestartRecoveryReleasesOnlyOriginalRejectionWithoutWriteLeaseOrSuccess() async throws {
        for reason in reasons {
            let path = directory(), locks = try CouponManagementFileLocks(directory: path), original = try record()
            try locks.acquire(original)
            let reopened = try CouponManagementFileLocks(directory: path), h = try harness(locks: reopened, epoch: 2)
            h.wire.response = try bytes(reason, record: original); let retainedDraft = draft(); h.core.change(retainedDraft)
            XCTAssertFalse(h.core.canSubmit); await h.core.recoverPendingCommands()
            XCTAssertEqual(h.wire.receiptReads, 1); XCTAssertEqual(h.wire.writes, 0); XCTAssertEqual(h.authority.reads, 2)
            XCTAssertEqual(h.core.recoveredCommandCount, 1); XCTAssertTrue(h.core.recoveryFinished); XCTAssertFalse(h.core.acknowledged)
            XCTAssertNil(h.core.acknowledgedDefinitionID); XCTAssertNil(h.core.verifiedRecord); XCTAssertEqual(h.core.serverMessage, message)
            XCTAssertEqual(h.core.draft, retainedDraft); XCTAssertNil(h.core.review); XCTAssertFalse(h.core.canSubmit)
            XCTAssertNil(try locks.pending(ownerKey: original.ownerKey, resource: original.resource))
            let request = try XCTUnwrap(h.wire.requests.first)
            XCTAssertNotNil(CouponCommandReadRoute(request: request, baseURL: base, merchantID: 11))
            XCTAssertNil(request.value(forHTTPHeaderField: "X-Coupon-Command-Id"))
            XCTAssertTrue(String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)?.contains(original.command!.requestID) == true)
        }
    }
    func testUnknownReasonRetainsExactDiskBytesWithoutResend() async throws {
        let path = directory(), locks = try CouponManagementFileLocks(directory: path), original = try record(); try locks.acquire(original)
        let file = try journalURL(path), before = try Data(contentsOf: file), h = try harness(locks: locks)
        h.wire.response = try bytes("UNREVIEWED_REASON", record: original); await h.core.recoverPendingCommands()
        XCTAssertEqual(h.core.issue, .locked); XCTAssertEqual(h.core.recoveredCommandCount, 0); XCTAssertFalse(h.core.acknowledged)
        XCTAssertEqual(h.wire.writes, 0); XCTAssertEqual(h.wire.receiptReads, 1); XCTAssertEqual(try Data(contentsOf: file), before)
    }
    func testMissingOrRevokedProtocolNeverLooksUpOrReleasesRejection() async throws {
        for enabled in [false, true] {
            let path = directory(), locks = try CouponManagementFileLocks(directory: path), original = try record(); try locks.acquire(original)
            let file = try journalURL(path), before = try Data(contentsOf: file), h = try harness(locks: locks, protocolEnabled: enabled)
            h.capability?.revoke(); h.wire.response = try bytes("INPUT_CHANGED", record: original); await h.core.recoverPendingCommands()
            XCTAssertEqual(h.wire.receiptReads, 0); XCTAssertEqual(h.wire.writes, 0); XCTAssertEqual(h.core.recoveredCommandCount, 0)
            XCTAssertFalse(h.core.canSubmit); XCTAssertEqual(try Data(contentsOf: file), before)
        }
    }
    func testProtocolRevokedDuringReceiptReadRetainsJournal() async throws {
        let path = directory(), locks = try CouponManagementFileLocks(directory: path), original = try record(); try locks.acquire(original)
        let file = try journalURL(path), before = try Data(contentsOf: file), h = try harness(locks: locks)
        h.wire.response = try bytes("SAFETY_REJECTED", record: original); h.wire.onReceipt = { [capability = h.capability] in capability?.revoke() }
        await h.core.recoverPendingCommands(); XCTAssertEqual(h.wire.receiptReads, 1); XCTAssertEqual(h.wire.writes, 0)
        XCTAssertEqual(h.core.recoveredCommandCount, 0); XCTAssertFalse(h.core.acknowledged); XCTAssertEqual(try Data(contentsOf: file), before)
    }
    func testChangedCurrentAuthorityAfterReceiptCannotReleaseOriginalJournal() async throws {
        let path = directory(), locks = try CouponManagementFileLocks(directory: path), original = try record(); try locks.acquire(original)
        let file = try journalURL(path), before = try Data(contentsOf: file), h = try harness(locks: locks)
        h.wire.response = try bytes("INPUT_CHANGED", record: original); h.wire.onReceipt = { [authority = h.authority] in authority.owner = 9002; authority.revision = "changed" }
        await h.core.recoverPendingCommands(); XCTAssertEqual(h.authority.reads, 2); XCTAssertEqual(h.core.issue, .changed)
        XCTAssertEqual(h.core.recoveredCommandCount, 0); XCTAssertFalse(h.core.acknowledged); XCTAssertEqual(h.wire.writes, 0); XCTAssertEqual(try Data(contentsOf: file), before)
    }
    func testAccountLeavesDuringReceiptReadRetainsJournal() async throws {
        let path = directory(), locks = try CouponManagementFileLocks(directory: path), original = try record(); try locks.acquire(original)
        let file = try journalURL(path), before = try Data(contentsOf: file), h = try harness(locks: locks)
        h.wire.response = try bytes("SAFETY_REJECTED", record: original); h.wire.onReceipt = { [state = h.state] in state.session = nil }
        await h.core.recoverPendingCommands(); XCTAssertEqual(h.core.recoveredCommandCount, 0); XCTAssertFalse(h.core.acknowledged)
        XCTAssertEqual(h.wire.writes, 0); XCTAssertEqual(try Data(contentsOf: file), before)
    }
    func testReplacementJournalCannotBeReleasedByOldRejection() async throws {
        let path = directory(), locks = try CouponManagementFileLocks(directory: path), original = try record(); try locks.acquire(original)
        let file = try journalURL(path), h = try harness(locks: locks)
        var value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]); value["createdAt"] = 1
        let replacement = try JSONSerialization.data(withJSONObject: value)
        h.wire.response = try bytes("INPUT_CHANGED", record: original); h.wire.onReceipt = { try replacement.write(to: file, options: .atomic) }
        await h.core.recoverPendingCommands(); XCTAssertEqual(h.core.issue, .storage); XCTAssertEqual(h.core.recoveredCommandCount, 0)
        XCTAssertFalse(h.core.acknowledged); XCTAssertEqual(h.wire.writes, 0); XCTAssertEqual(try Data(contentsOf: file), replacement)
    }
    func testCancelledSuspendedRejectionNeverReleasesOrResends() async throws {
        for reason in reasons {
            let path = directory(), locks = try CouponManagementFileLocks(directory: path), original = try record(); try locks.acquire(original)
            let file = try journalURL(path), before = try Data(contentsOf: file), h = try harness(locks: locks)
            h.wire.response = try bytes(reason, record: original); h.wire.pause = true
            let paused = expectation(description: "original rejection lookup is suspended")
            h.wire.onPaused = { paused.fulfill() }
            let task = Task { await h.core.recoverPendingCommands() }
            await fulfillment(of: [paused], timeout: 2); XCTAssertNotNil(h.wire.continuation)
            task.cancel(); h.wire.finish(); await task.value
            XCTAssertEqual(h.wire.receiptReads, 1); XCTAssertEqual(h.wire.writes, 0); XCTAssertEqual(h.core.recoveredCommandCount, 0)
            XCTAssertFalse(h.core.acknowledged); XCTAssertFalse(h.core.busy); XCTAssertEqual(try Data(contentsOf: file), before)
        }
    }
    func testFailedJournalReleaseDoesNotClaimRecoveryOrSuccess() async throws {
        for reason in reasons {
            let path = directory(), locks = try CouponManagementFileLocks(directory: path), original = try record(); try locks.acquire(original)
            let file = try journalURL(path), before = try Data(contentsOf: file), failing = FailingRelease(locks), h = try harness(locks: failing)
            h.wire.response = try bytes(reason, record: original); await h.core.recoverPendingCommands()
            XCTAssertEqual(failing.releaseAttempts, 1); XCTAssertEqual(h.core.issue, .storage)
            XCTAssertEqual(h.core.recoveredCommandCount, 0); XCTAssertFalse(h.core.acknowledged); XCTAssertEqual(h.wire.writes, 0)
            XCTAssertEqual(try Data(contentsOf: file), before)
        }
    }
    func testDirectRejectionKeepsDraftAndRequiresNewExplicitReviewNeverReplay() async throws {
        for reason in reasons {
            let locks = try CouponManagementFileLocks(directory: directory()), h = try harness(locks: locks, writes: true), originalDraft = draft()
            h.wire.responseToWrite = { [self] record in try bytes(reason, record: record) }
            h.core.change(originalDraft); await h.core.preparePublish(); let accepted = try XCTUnwrap(h.core.review)
            await h.core.confirm(accepted)
            XCTAssertEqual(h.wire.writes, 1); XCTAssertEqual(h.core.serverMessage, message); XCTAssertEqual(h.core.draft, originalDraft)
            XCTAssertFalse(h.core.acknowledged); XCTAssertNil(h.core.acknowledgedDefinitionID); XCTAssertNil(h.core.review)
            XCTAssertNil(try locks.pending(ownerKey: session().ownerKey, resource: "publish"))
            await h.core.confirm(accepted); XCTAssertEqual(h.wire.writes, 1); XCTAssertEqual(h.core.issue, .changed)
            await h.core.preparePublish(); let next = try XCTUnwrap(h.core.review)
            XCTAssertNotEqual(next.id, accepted.id); XCTAssertEqual(h.wire.writes, 1, "Preparing a new review is not confirmation")
            await h.core.confirm(next)
            XCTAssertEqual(h.wire.writes, 2); XCTAssertEqual(h.wire.submitted.count, 2)
            XCTAssertEqual(h.wire.submitted.last?.operationID, next.id)
            XCTAssertEqual(h.wire.submitted.last?.command?.requestID, next.id.uuidString.lowercased())
            XCTAssertNotEqual(h.wire.submitted.first?.command?.requestID, h.wire.submitted.last?.command?.requestID)
            XCTAssertFalse(h.core.acknowledged); XCTAssertEqual(h.core.draft, originalDraft)
        }
    }
}
