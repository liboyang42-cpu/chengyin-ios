import Foundation
import CryptoKit
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class NativeChannelReportRetiredHostRecoveryTests: XCTestCase {
    func testRetiredHostColdNewEpochRestoresLegacyJournalAndReadsOnlyOriginalReceipt() async throws {
        let h = CRHostRecoveryHarness(); let writer = try await h.saveOriginal()
        let bytes = h.store.rows, post = try XCTUnwrap(h.wire.requests.first)
        h.hostCurrent = false
        let cold = try h.directory(context: h.context(epoch: 9, token: "new-token"))
        cold.reload()
        XCTAssertEqual(cold.state, .ready); XCTAssertFalse(cold.hasUnreadableRecords)
        let entry = try XCTUnwrap(cold.visibleEntries.first)
        XCTAssertEqual(entry.requestID, h.requestID.uuidString)
        XCTAssertEqual(entry.owner.state, .unknown); XCTAssertFalse(writer.isCurrent)
        XCTAssertTrue(entry.owner.canRecover); XCTAssertFalse(entry.owner.canSubmit)
        XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.wire.requests.count, 1)
        await entry.owner.recover()
        XCTAssertEqual(entry.owner.state, .acknowledged(reportID: "61", status: "PENDING"))
        XCTAssertFalse(entry.owner.hasPending); XCTAssertTrue(h.store.rows.isEmpty)
        XCTAssertEqual(h.wire.requests.count, 2)
        let read = try XCTUnwrap(h.wire.requests.last)
        XCTAssertEqual(read.httpMethod, "GET"); XCTAssertNil(read.httpBody)
        XCTAssertEqual(read.url?.path, "/api/channel-platform/governance/reports/requests/" + h.requestID.uuidString)
        XCTAssertEqual(read.value(forHTTPHeaderField: "Authorization"), "new-token")
        XCTAssertFalse(read.httpShouldHandleCookies)
        XCTAssertEqual(h.wire.requests.first?.httpBody, post.httpBody)
        cold.reload(); XCTAssertTrue(cold.visibleEntries.isEmpty)
        XCTAssertEqual(h.generated, 1); XCTAssertEqual(h.store.writes, 1); XCTAssertEqual(h.store.removes, 1)
    }

    func testReporterLocatorRejectsForeignAccountNamespaceBaseFamilyAndNoncanonicalKeysWithoutRecordReads() async throws {
        let h = CRHostRecoveryHarness(); _ = try await h.saveOriginal()
        let original = try XCTUnwrap(h.store.rows.keys.first), context = try h.context()
        XCTAssertEqual(NativeChannelReportJournalLocator.conversationID(in: original, context: context), 2)
        for foreign in [try h.context(account: 18), try h.context(namespace: "another"),
                        try h.context(base: "https://another.example.test/")] {
            XCTAssertNil(NativeChannelReportJournalLocator.conversationID(in: original, context: foreign))
            let directory = try h.directory(context: foreign)
            h.store.reads = []; directory.reload()
            XCTAssertTrue(directory.visibleEntries.isEmpty); XCTAssertTrue(h.store.reads.isEmpty)
        }
        let owner = [context.session.namespace, context.baseURL.absoluteString, "17"].map { "\($0.utf8.count):\($0)" }.joined()
        let malformed = ["1:0", "2:02", "1:2extra", "01:2", "1:-2", "1:2:1:x"]
            .map { "native-channel-report.v1." + Data((owner + $0).utf8).base64EncodedString() }
            + [original + "=", original.replacingOccurrences(of: "report.v1", with: "report.v2"), "ordinary-im-safety.v1." + original]
        for key in malformed { XCTAssertNil(NativeChannelReportJournalLocator.conversationID(in: key, context: context)) }
        XCTAssertEqual(h.store.rows.count, 1); XCTAssertEqual(h.wire.requests.count, 1)
    }

    func testLocatorUsesUTF8ByteIdentityNotUnicodeCanonicalEquality() throws {
        let h = CRHostRecoveryHarness()
        let first = try h.context(namespace: "caf\u{e9}"), second = try h.context(namespace: "cafe\u{301}")
        let values = [first.session.namespace, first.baseURL.absoluteString, "17", "2"]
        let key = "native-channel-report.v1." + Data(values.map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
        XCTAssertEqual(NativeChannelReportJournalLocator.conversationID(in: key, context: first), 2)
        XCTAssertNil(NativeChannelReportJournalLocator.conversationID(in: key, context: second))
    }

    func testDirectoryFailureIsNotEmptyAndNeverWritesOrDeletesOriginalJournal() async throws {
        let h = CRHostRecoveryHarness(); _ = try await h.saveOriginal(); let bytes = h.store.rows
        let directory = try h.directory(keys: { throw NativeChannelTextJournalError.unavailable })
        directory.reload()
        XCTAssertEqual(directory.state, .unavailable); XCTAssertTrue(directory.visibleEntries.isEmpty)
        XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.writes, 1); XCTAssertEqual(h.store.removes, 0)
        XCTAssertEqual(h.wire.requests.count, 1)
    }

    func testCorruptOrFutureJournalRemainsUntouchedAndCannotBecomeSuccessfulEmpty() async throws {
        for future in [false, true] {
            let h = CRHostRecoveryHarness(); _ = try await h.saveOriginal()
            let key = try XCTUnwrap(h.store.rows.keys.first)
            if future {
                var row = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(h.store.rows[key])) as? [String: Any])
                row["future_field"] = true; h.store.rows[key] = try JSONSerialization.data(withJSONObject: row)
            } else { h.store.rows[key] = Data("unreadable-original".utf8) }
            let bytes = h.store.rows, directory = try h.directory(); directory.reload()
            XCTAssertEqual(directory.state, .ready); XCTAssertTrue(directory.hasUnreadableRecords)
            XCTAssertTrue(directory.visibleEntries.isEmpty); XCTAssertEqual(h.store.rows, bytes)
            XCTAssertEqual(h.store.removes, 0); XCTAssertEqual(h.wire.requests.count, 1)
        }
    }

    func testExactReceiptGrantRequiredEvenWhenAnotherRequestIsGranted() async throws {
        let h = CRHostRecoveryHarness(); _ = try await h.saveOriginal(); let bytes = h.store.rows
        h.receiptAllowed = false
        let directory = try h.directory(); directory.reload(); let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        XCTAssertFalse(owner.canRecover); XCTAssertFalse(owner.canSubmit)
        await owner.recover(); await owner.submit()
        XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.wire.requests.count, 1)
        h.receiptAllowed = true; await owner.recover()
        XCTAssertEqual(owner.state, .acknowledged(reportID: "61", status: "PENDING"))
    }

    func testUnknownPendingNotFoundAndRetryFlagNeverPostOrClearInRecoveryHost() async throws {
        let results: [[String: Any]] = [["state": "UNKNOWN"], ["state": "PENDING"],
            ["state": "NOT_FOUND", "retry_with_original_request": false],
            ["state": "NOT_FOUND", "retry_with_original_request": true]]
        for result in results {
            let h = CRHostRecoveryHarness(); _ = try await h.saveOriginal(); let bytes = h.store.rows
            h.hostCurrent = false; h.wire.lookup = result
            let directory = try h.directory(); directory.reload(); let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
            await owner.recover(); await owner.submit()
            XCTAssertEqual(owner.state, .unknown); XCTAssertTrue(owner.hasPending)
            XCTAssertEqual(h.wire.requests.map(\.httpMethod), ["POST", "GET"])
            XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0); XCTAssertEqual(h.generated, 1)
        }
    }

    func testOriginalAuthorizedHostRetryContractStillUsesSameUUIDAndBody() async throws {
        let h = CRHostRecoveryHarness(); let writer = try await h.saveOriginal()
        let body = h.wire.requests.first?.httpBody, bytes = h.store.rows
        h.wire.lookup = ["state": "NOT_FOUND", "retry_with_original_request": true]
        let directory = try h.directory(); directory.reload(); let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        await owner.recover(); await owner.submit()
        XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
        await writer.submit()
        XCTAssertEqual(h.wire.requests.map(\.httpMethod), ["POST", "GET", "GET", "POST"])
        XCTAssertEqual(h.wire.requests.last?.httpBody, body); XCTAssertEqual(h.store.rows, bytes)
        XCTAssertEqual(h.generated, 1); XCTAssertEqual(h.store.writes, 1)
    }

    func testReceiptBindingAndLegalStatusAreStillParsedByOriginalFlow() async throws {
        for field in ["request_id", "reporter_member_id", "target_id", "channel_id", "body_digest", "status", "audit_task_id"] {
            let h = CRHostRecoveryHarness(); _ = try await h.saveOriginal(); let bytes = h.store.rows
            var response = h.wire.receipt; response[field] = "mismatch"; h.wire.lookup = response
            let directory = try h.directory(); directory.reload(); let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
            await owner.recover()
            XCTAssertEqual(owner.state, .unknown); XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0)
        }
        for status in ["PENDING", "ACCEPTED", "REJECTED", "DUPLICATE"] {
            let h = CRHostRecoveryHarness(); _ = try await h.saveOriginal()
            h.wire.receipt["status"] = status
            let directory = try h.directory(); directory.reload(); let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
            await owner.recover(); XCTAssertEqual(owner.state, .acknowledged(reportID: "61", status: status))
        }
    }

    func testRetirementOrReloadWhileReadInFlightNeverSettlesStaleOriginalOwner() async throws {
        for reload in [false, true] {
            let h = CRHostRecoveryHarness(); _ = try await h.saveOriginal(); let bytes = h.store.rows
            let directory = try h.directory(); directory.reload(); let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
            h.wire.beforeGET = { if reload { directory.reload() } else { directory.retire() } }
            await owner.recover()
            XCTAssertFalse(owner.isCurrent); XCTAssertEqual(owner.state, .unknown)
            XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0)
            if !reload { directory.reload(); XCTAssertFalse(directory.isCurrent); XCTAssertTrue(directory.visibleEntries.isEmpty) }
            h.wire.beforeGET = nil
            let fresh = try h.directory(); fresh.reload(); await fresh.visibleEntries.first?.owner.recover()
            XCTAssertTrue(h.store.rows.isEmpty)
        }
    }

    func testChangedAccountTokenEpochOrViewerCurrentNeverReadsNorExpiresReplacement() async throws {
        let h = CRHostRecoveryHarness(); _ = try await h.saveOriginal(); let bytes = h.store.rows
        let directory = try h.directory(); directory.reload(); let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        h.wire.beforeGET = { h.reporterCurrent = false }; h.wire.status = 401
        await owner.recover()
        XCTAssertFalse(owner.isCurrent); XCTAssertTrue(directory.visibleEntries.isEmpty)
        XCTAssertEqual(owner.state, .unknown); XCTAssertEqual(h.unauthorizedCount, 0)
        XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0)
        await owner.recover(); XCTAssertEqual(h.wire.requests.count, 2)
    }

    func testCurrentUnauthorizedReceiptExpiresOnlyCapturedReporterAndPreservesJournal() async throws {
        let h = CRHostRecoveryHarness(); _ = try await h.saveOriginal(); let bytes = h.store.rows
        let directory = try h.directory(); directory.reload(); let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        h.wire.status = 401; await owner.recover()
        XCTAssertEqual(h.unauthorizedCount, 1); XCTAssertEqual(owner.state, .unknown)
        XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0)
    }

    func testCancelledReceiptReadRetainsOriginalForAnotherEntryWithoutPost() async throws {
        let h = CRHostRecoveryHarness(); _ = try await h.saveOriginal(); let bytes = h.store.rows
        let directory = try h.directory(); directory.reload(); let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        var waiting: CheckedContinuation<Void, Never>?
        h.wire.beforeGET = { await withCheckedContinuation { waiting = $0 } }
        let task = Task { await owner.recover() }
        while waiting == nil { await Task.yield() }
        task.cancel(); waiting?.resume(); await task.value
        XCTAssertEqual(owner.state, .unknown); XCTAssertTrue(owner.hasPending)
        XCTAssertEqual(h.store.rows, bytes); XCTAssertEqual(h.store.removes, 0)
        h.wire.beforeGET = nil
        directory.reload(); await directory.visibleEntries.first?.owner.recover()
        XCTAssertTrue(h.store.rows.isEmpty)
        XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    func testOfflineReceiptRetainsOriginalAcrossDirectoryReconstruction() async throws {
        let h = CRHostRecoveryHarness(); _ = try await h.saveOriginal(); let bytes = h.store.rows
        let first = try h.directory(); first.reload(); h.wire.failGET = true
        await first.visibleEntries.first?.owner.recover()
        XCTAssertEqual(first.visibleEntries.first?.owner.state, .unknown)
        XCTAssertEqual(h.store.rows, bytes); first.retire()
        let second = try h.directory(); second.reload(); h.wire.failGET = false
        await second.visibleEntries.first?.owner.recover()
        XCTAssertTrue(h.store.rows.isEmpty)
        XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }

    func testSharedOriginalLeaseBlocksConcurrentHostAndRecoveryQueries() async throws {
        let h = CRHostRecoveryHarness(); let writer = try await h.saveOriginal()
        let directory = try h.directory(); directory.reload(); let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        h.wire.beforeGET = { await owner.recover() }
        await writer.recover()
        XCTAssertEqual(h.wire.requests.map(\.httpMethod), ["POST", "GET"])
        XCTAssertEqual(writer.state, .acknowledged(reportID: "61", status: "PENDING"))
        XCTAssertEqual(h.store.removes, 1)
    }

    func testFailedSettlementDoesNotManufactureSuccessOrForgetOriginal() async throws {
        let h = CRHostRecoveryHarness(); _ = try await h.saveOriginal(); let bytes = h.store.rows
        h.store.rejectRemoval = true
        let directory = try h.directory(); directory.reload(); let owner = try XCTUnwrap(directory.visibleEntries.first?.owner)
        await owner.recover()
        XCTAssertEqual(owner.state, .unknown); XCTAssertTrue(owner.hasPending); XCTAssertEqual(h.store.rows, bytes)
        h.store.rejectRemoval = false; await owner.recover()
        XCTAssertEqual(owner.state, .acknowledged(reportID: "61", status: "PENDING"))
        XCTAssertEqual(h.wire.requests.filter { $0.httpMethod == "POST" }.count, 1)
    }
}

@MainActor private final class CRHostRecoveryStore: ProjectEditDataStorage {
    var rows: [String: Data] = [:], reads: [String] = []
    var writes = 0, removes = 0; var rejectRemoval = false
    func read(_ key: String) throws -> Data? { reads.append(key); return rows[key] }
    func write(_ data: Data, key: String) throws { writes += 1; rows[key] = data }
    func remove(_ key: String) throws {
        removes += 1
        if rejectRemoval { throw NativeChannelTextJournalError.unavailable }
        rows[key] = nil
    }
}
@MainActor private final class CRHostRecoveryWire: HTTPTransport {
    var requests: [URLRequest] = [], receipt: [String: Any] = [:], lookup: [String: Any]?
    var status = 200; var failGET = false; var beforeGET: (() async -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.httpMethod == "POST" {
            let data = try XCTUnwrap(request.httpBody)
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
            receipt = ["state": "APPLIED", "request_id": body["submit_request_id"]!, "reporter_member_id": "17",
                       "target_type": "MESSAGE", "target_id": body["target_id"]!, "channel_id": "2",
                       "body_digest": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                       "report_id": "61", "audit_task_id": "71", "status": "PENDING"]
            throw URLError(.timedOut)
        }
        await beforeGET?()
        if failGET { throw URLError(.notConnectedToInternet) }
        return (try JSONSerialization.data(withJSONObject: ["code": status, "data": lookup ?? receipt]), status)
    }
}
@MainActor private final class CRHostRecoveryHarness {
    let requestID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let store = CRHostRecoveryStore(), wire = CRHostRecoveryWire()
    var hostCurrent = true, reporterCurrent = true, receiptAllowed = true
    var generated = 0, unauthorizedCount = 0
    var receiptPath: String { "api/channel-platform/governance/reports/requests/" + requestID.uuidString }
    func context(account: Int = 17, epoch: UInt64 = 3, token: String = "fixture-only",
                 namespace: String = "report-recovery-test", base: String = "https://example.test/") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: base)!, role: "player",
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    func saveOriginal() async throws -> NativeChannelReportFlow {
        let flow = try NativeChannelReportFlow(context: context(), conversationID: 2, transport: wire, storage: store,
            current: { self.hostCurrent }, permitsWrite: { true }, permitsRead: { $0 == self.receiptPath }, unauthorized: {},
            makeRequestID: { self.generated += 1; return self.requestID })
        XCTAssertTrue(flow.prepare(messageID: 81)); flow.select(reason: .privacy, note: "PRIVATE original note, never recovery UI")
        await flow.submit(); XCTAssertEqual(flow.state, .unknown); return flow
    }
    func directory(context: RuntimeDependencyContext? = nil, keys: (() throws -> [String])? = nil) throws -> NativeChannelReportRecoveryDirectory {
        try .init(context: context ?? self.context(), transport: wire, storage: store,
                  journalKeys: keys ?? { Array(self.store.rows.keys) }, current: { self.reporterCurrent },
                  permitsRead: { self.receiptAllowed && $0 == self.receiptPath },
                  unauthorized: { self.unauthorizedCount += 1 })
    }
}
