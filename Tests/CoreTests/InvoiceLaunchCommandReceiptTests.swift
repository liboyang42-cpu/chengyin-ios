import XCTest
import Foundation
@testable import QuestifyCore

@MainActor final class InvoiceLaunchCommandReceiptTests: XCTestCase {
    private typealias S = InvoiceLaunchTestSupport
    @MainActor private final class Harness {
        let captured: InvoiceLaunchSession
        var current: InvoiceLaunchSession?
        var enabled = true, mutations = true, commands = true
        let memory: S.Memory
        let wire = S.Wire()
        lazy var service = InvoiceLaunchService(session: captured, transport: wire,
            enabled: { [unowned self] in enabled }, mutationsEnabled: { [unowned self] in mutations },
            commandReceiptsEnabled: { [unowned self] in commands }, current: { [unowned self] in current })
        lazy var store = InvoiceLaunchPendingStore(session: captured, storage: memory)
        init(memory: S.Memory? = nil, account: Int64 = 7, epoch: UInt64 = 1) throws {
            captured = try S.session(account: account, epoch: epoch); current = captured
            self.memory = memory ?? S.Memory()
        }
        func coordinator() throws -> InvoiceLaunchCoordinator { try .init(service: service, store: store) }
    }
    private func receipt(_ request: String, target: Int64 = 11, cancel: Bool = false) -> [String: Any] {
        ["requestId": request, "operation": cancel ? "CANCEL_APPLICATION" : "DELETE_TITLE",
         "targetId": String(target), "outcome": cancel ? "CANCELLED" : "DELETED"]
    }
    func testNewDeletePersistsBeforeDispatchAndReadsExactReceiptBeforeEntity() async throws {
        let h = try Harness()
        h.wire.beforeSend = {
            let request = try XCTUnwrap(h.wire.requests.last)
            let pending = try XCTUnwrap(h.store.load())
            let key = try XCTUnwrap(pending.commandRequestID)
            XCTAssertEqual(pending.targetID, Int64.max)
            if request.url!.path.hasSuffix("/titles/delete-request") {
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                XCTAssertEqual(Set(body.keys), ["requestId", "id"])
                XCTAssertEqual(body["requestId"] as? String, key)
                XCTAssertEqual(body["id"] as? String, String(Int64.max))
                h.wire.responses = [try S.success(self.receipt(key, target: Int64.max))]
            } else if request.url!.path.hasSuffix("/commands/request") {
                h.wire.responses = [try S.success(self.receipt(key, target: Int64.max))]
            } else { h.wire.responses = [try S.success([])] }
        }
        try await h.coordinator().deleteTitle(id: Int64.max)
        XCTAssertNil(try h.store.load())
        XCTAssertEqual(h.wire.requests.map { $0.url!.path }, ["/native/api/invoice/titles/delete-request", "/native/api/invoice/commands/request", "/native/api/invoice/titles"])
    }
    func testLostCancelResponseRestartsWithOriginalReadOnlyRequest() async throws {
        let h = try Harness(); h.wire.failNext = true
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().cancel(id: 51) }
        let pending = try XCTUnwrap(h.store.load()), key = try XCTUnwrap(pending.commandRequestID)
        let resumed = try Harness(memory: h.memory, epoch: 2); resumed.mutations = false
        resumed.wire.responses = [try S.success(receipt(key, target: 51, cancel: true)), try S.success(S.application(status: "CANCELLED"))]
        let result = try await resumed.coordinator().recover()
        guard case .application(let app) = result else { return XCTFail("Expected verified original target") }
        XCTAssertEqual(app.id, 51); XCTAssertNil(try resumed.store.load())
        XCTAssertEqual(resumed.wire.requests.map { $0.url!.path }, ["/native/api/invoice/commands/request", "/native/api/invoice/detail"])
        let body = try JSONSerialization.jsonObject(with: resumed.wire.requests[0].httpBody!) as! [String: Any]
        XCTAssertEqual(body["requestId"] as? String, key); XCTAssertEqual(Set(body.keys), ["requestId"])
    }
    func testMissingOriginalReceiptNeverFallsBackToCurrentState() async throws {
        let h = try Harness(); h.wire.failNext = true
        await S.expect(.outcomeUnknown) { try await h.coordinator().deleteTitle(id: 11) }
        let original = try XCTUnwrap(h.store.load())
        h.wire.responses = [try S.failure("INVOICE_NOT_FOUND"), try S.success([])]
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
        XCTAssertEqual(try h.store.load(), original); XCTAssertEqual(h.wire.requests.count, 2)
        XCTAssertTrue(h.wire.requests.last!.url!.path.hasSuffix("/commands/request"))
    }
    func testWrongRequestOperationTargetOrOutcomeCannotClearOriginal() async throws {
        let h = try Harness(); h.wire.failNext = true
        await S.expect(.outcomeUnknown) { try await h.coordinator().deleteTitle(id: 11) }
        let pending = try XCTUnwrap(h.store.load()), key = try XCTUnwrap(pending.commandRequestID)
        for (field, value) in [("requestId", "another"), ("operation", "CANCEL_APPLICATION"), ("targetId", "12"), ("outcome", "CANCELLED")] {
            var wrong = receipt(key); wrong[field] = value; h.wire.responses = [try S.success(wrong)]
            await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
            XCTAssertEqual(try h.store.load(), pending)
        }
        XCTAssertTrue(h.wire.requests.dropFirst().allSatisfy { $0.url!.path.hasSuffix("/commands/request") })
    }
    func testCommandFeatureLossNeverDowngradesJournalToLegacyRecovery() async throws {
        let h = try Harness(); h.wire.failNext = true
        await S.expect(.outcomeUnknown) { try await h.coordinator().deleteTitle(id: 11) }
        let pending = try XCTUnwrap(h.store.load()); h.commands = false
        await S.expect(.outcomeUnknown) { _ = try await h.coordinator().recover() }
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(try h.store.load(), pending)
    }
    func testOldJournalDoesNotInventRequestWhenFeatureBecomesAvailable() async throws {
        let h = try Harness()
        try h.store.save(InvoiceLaunchPending(kind: .deleteTitle, targetID: 11))
        h.wire.responses = [try S.success([])]
        let result = try await h.coordinator().recover(); XCTAssertEqual(result, .titleAbsent(11))
        XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["titles"])
    }
    func testDefaultServiceStillUsesLegacyRouteAndNoCommandKey() async throws {
        let h = try S.Harness(); h.wire.failNext = true
        await S.expect(.outcomeUnknown) { try await h.coordinator().deleteTitle(id: 11) }
        XCTAssertNil(try h.store.load()?.commandRequestID)
        XCTAssertEqual(h.wire.requests.map { $0.url!.lastPathComponent }, ["delete"])
        XCTAssertEqual(InvoiceLaunchRoute.allCases.count, 11)
    }
    func testStaleSessionResponseRetainsJournalAndOtherOwnerCannotReadIt() async throws {
        let h = try Harness()
        h.wire.beforeSend = { let p = try XCTUnwrap(h.store.load()); h.wire.responses = [try S.success(self.receipt(try XCTUnwrap(p.commandRequestID)))] }
        h.wire.afterSend = { h.current = nil }
        await S.expect(.outcomeUnknown) { try await h.coordinator().deleteTitle(id: 11) }
        XCTAssertNotNil(try h.store.load())
        let other = try Harness(memory: h.memory, account: 99)
        let recovered = try await other.coordinator().recover(); XCTAssertEqual(recovered, .none); XCTAssertTrue(other.wire.requests.isEmpty)
    }
    func testStorageFailurePreventsAnyNewWriteAndJournalHasNoPrivateTitleData() async throws {
        let h = try Harness(); h.memory.failWrite = true
        await S.expect(.storageUnavailable) { try await h.coordinator().deleteTitle(id: 11) }
        XCTAssertTrue(h.wire.requests.isEmpty)
        h.memory.failWrite = false; h.wire.failNext = true
        await S.expect(.outcomeUnknown) { try await h.coordinator().deleteTitle(id: 11) }
        let raw = String(decoding: try XCTUnwrap(h.memory.values.values.first), as: UTF8.self)
        let record = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
        XCTAssertEqual(record["version"] as? Int, 2)
        XCTAssertFalse(raw.contains("synthetic-invoice-token")); XCTAssertFalse(raw.contains("titleName")); XCTAssertFalse(raw.contains("taxNo"))
    }
    func testReceiptTargetIDMustBeExactCanonicalDecimalString() throws {
        let invalidValues: [Any] = [11, "011", "1e1", "-1", "0", "9223372036854775808"]
        for invalid in invalidValues {
            var object = receipt("request"); object["targetId"] = invalid
            XCTAssertThrowsError(try JSONDecoder().decode(InvoiceLaunchCommandReceipt.self, from: S.data(object)))
        }
        let exact = try JSONDecoder().decode(InvoiceLaunchCommandReceipt.self, from: S.data(receipt("request", target: Int64.max)))
        XCTAssertEqual(exact.targetId, Int64.max)
    }
    func testCommandMarkerCannotBeAttachedToApplyOrSaveJournal() throws {
        let apply = try InvoiceLaunchApply(titleId: 11, orderIds: [21])
        XCTAssertThrowsError(try InvoiceLaunchPending(kind: .apply, apply: apply, commandRequestID: "request").validate())
        XCTAssertThrowsError(try InvoiceLaunchPending(kind: .saveTitle, commandRequestID: "request").validate())
        XCTAssertThrowsError(try InvoiceLaunchPending(kind: .deleteTitle, targetID: 11, commandRequestID: "bad key").validate())
    }
    func testNewCancelSuccessReadsOriginalReceiptThenCurrentTarget() async throws {
        let h = try Harness()
        h.wire.beforeSend = {
            let pending = try XCTUnwrap(h.store.load()), key = try XCTUnwrap(pending.commandRequestID)
            if h.wire.requests.last!.url!.lastPathComponent == "detail" {
                h.wire.responses = [try S.success(S.application(status: "CANCELLED"))]
            } else { h.wire.responses = [try S.success(self.receipt(key, target: 51, cancel: true))] }
        }
        let app = try await h.coordinator().cancel(id: 51)
        XCTAssertEqual(app.id, 51); XCTAssertEqual(app.status, .cancelled); XCTAssertNil(try h.store.load())
        XCTAssertEqual(h.wire.requests.map { $0.url!.path }, ["/native/api/invoice/cancel-request", "/native/api/invoice/commands/request", "/native/api/invoice/detail"])
    }
    func testCommandFeatureRevokedDuringResponseDoesNotAcknowledgeWrite() async throws {
        let h = try Harness()
        h.wire.beforeSend = { let p = try XCTUnwrap(h.store.load()); h.wire.responses = [try S.success(self.receipt(try XCTUnwrap(p.commandRequestID)))] }
        h.wire.afterSend = { h.commands = false }
        await S.expect(.outcomeUnknown) { try await h.coordinator().deleteTitle(id: 11) }
        XCTAssertNotNil(try h.store.load()); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testOnlyMutationRollbackClearsJournalNotRequestReuse() async throws {
        let h = try Harness(); h.wire.responses = [try S.failure("INVOICE_ARGUMENT_INVALID")]
        await S.expect(.rejected("INVOICE_ARGUMENT_INVALID")) { try await h.coordinator().deleteTitle(id: 11) }
        XCTAssertNil(try h.store.load())
        h.wire.responses = [try S.failure("INVOICE_REQUEST_REUSED")]
        await S.expect(.outcomeUnknown) { try await h.coordinator().deleteTitle(id: 11) }
        XCTAssertNotNil(try h.store.load())
    }

}
