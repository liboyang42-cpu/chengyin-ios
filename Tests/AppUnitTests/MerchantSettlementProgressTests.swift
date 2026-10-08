import Foundation
import XCTest
@testable import Questify

// Authored App-hosted tests. All clipboard writes go to an in-memory spy.
@MainActor final class MerchantSettlementVoucherCopyTests: XCTestCase {
    private enum SyntheticError: Error { case offline, readDidNotStart }
    @MainActor private final class Reader: MerchantBusinessReading {
        var scope: MerchantBusinessScope? = .init(realm: "synthetic://settlement", accountID: 99001, epoch: 1)
        var authorizationGeneration: UUID? = UUID()
        var isConfigured = true
        let isOfflineExample = true
        let canExecuteSyntheticMutation = false
        var calls = 0
        var pending: [CheckedContinuation<MerchantBusinessSnapshot, Error>] = []
        func access() async throws -> MerchantBusinessAccess { throw SyntheticError.offline }
        func snapshot(_ query: MerchantBusinessQuery) async throws -> MerchantBusinessSnapshot {
            calls += 1
            return try await withCheckedThrowingContinuation { pending.append($0) }
        }
        func execute(_ mutation: MerchantBusinessMutation, requestID: String, scope: MerchantBusinessScope) async throws -> MerchantBusinessReceipt {
            XCTFail("Settlement copying must never mutate the backend"); throw SyntheticError.offline
        }
    }
    private func snapshot(merchant: Int = 610, batch: Int = 66001, permitted: Bool = true,
                          payment: String = "PAID", voucher: String = "SYNTHETIC-VOUCHER") throws -> MerchantBusinessSnapshot {
        let access = try MerchantBusinessAccess([
            "active": .bool(true), "merchant": .object(["id": .int(merchant)]), "roleCode": .string("MERCHANT_FINANCE"),
            "permissions": .array(permitted ? [.string("merchant:finance:read")] : [])])
        let fields: MerchantBusinessObject = ["batchId": .int(batch), "periodYm": .string("2026-09"), "amountTotal": .string("12.50"),
            "netDirection": .string("PLATFORM_PAYS_MERCHANT"), "paymentState": .string(payment), "invoiceState": .string("NONE"),
            "holdState": .string("NORMAL"), "paidAt": .string("2026-10-08 10:00:00"), "payVoucherNo": .string(voucher)]
        let document = try MerchantBusinessDocument(query: .batch(.init(batch)), payload: .object([
            "batch": .object(fields), "earningEntries": .array([]), "adjustments": .array([])]))
        return .init(access: access, document: document)
    }
    private func progress(_ snapshot: MerchantBusinessSnapshot) throws -> MerchantSettlementProgress {
        try .init(record: XCTUnwrap(snapshot.document.rows.first))
    }
    private func started(_ reader: Reader, _ count: Int = 1) async throws {
        for _ in 0..<500 { if reader.pending.count == count { return }; await Task.yield() }
        XCTFail("Synthetic read did not suspend"); throw SyntheticError.readDidNotStart
    }
    func testExplicitClickFreshReadsThenCopiesExactlyTheVoucher() async throws {
        let reader = Reader(), model = MerchantSettlementVoucherCopyModel(), baseline = try snapshot()
        let displayed = try progress(baseline); var writes: [String] = []
        let task = Task { await model.copy(displayed, intent: model.intentID, reader: reader, currentSnapshot: { baseline }, write: { writes.append($0) }) }
        try await started(reader); XCTAssertTrue(writes.isEmpty)
        reader.pending[0].resume(returning: baseline); await task.value
        XCTAssertEqual(writes, ["SYNTHETIC-VOUCHER"]); XCTAssertEqual(model.messageKey, "merchant.settlementProgress.copied")
        XCTAssertFalse(model.busy)
    }
    func testDeniedCurrentSnapshotMakesNoReadOrClipboardWrite() async throws {
        let reader = Reader(), model = MerchantSettlementVoucherCopyModel(), baseline = try snapshot(permitted: false)
        var writes: [String] = []
        await model.copy(try progress(baseline), intent: model.intentID, reader: reader, currentSnapshot: { baseline }, write: { writes.append($0) })
        XCTAssertEqual(reader.calls, 0); XCTAssertTrue(writes.isEmpty)
    }
    func testUnpaidCurrentSnapshotMakesNoReadOrClipboardWrite() async throws {
        let reader = Reader(), model = MerchantSettlementVoucherCopyModel(), baseline = try snapshot(payment: "PENDING")
        var writes: [String] = []
        await model.copy(try progress(baseline), intent: model.intentID, reader: reader, currentSnapshot: { baseline }, write: { writes.append($0) })
        XCTAssertEqual(reader.calls, 0); XCTAssertTrue(writes.isEmpty)
    }
    func testLogoutAccountAuthorizationAndConfigurationChangesBlockLateRead() async throws {
        for change in 0..<4 {
            let reader = Reader(), model = MerchantSettlementVoucherCopyModel(), baseline = try snapshot()
            let displayed = try progress(baseline); var writes: [String] = []
            let task = Task { await model.copy(displayed, intent: model.intentID, reader: reader, currentSnapshot: { baseline }, write: { writes.append($0) }) }
            try await started(reader)
            switch change {
            case 0: reader.scope = nil
            case 1: reader.scope = .init(realm: "synthetic://settlement", accountID: 99002, epoch: 2)
            case 2: reader.authorizationGeneration = UUID()
            default: reader.isConfigured = false
            }
            reader.pending[0].resume(returning: baseline); await task.value
            XCTAssertTrue(writes.isEmpty); XCTAssertNotEqual(model.messageKey, "merchant.settlementProgress.copied")
        }
    }
    func testNewMerchantGrantBatchVoucherAndPaymentInvalidateFreshRead() async throws {
        let changed = try [snapshot(merchant: 611), snapshot(permitted: false), snapshot(batch: 66002),
                           snapshot(voucher: "SYNTHETIC-REPLACEMENT"), snapshot(payment: "PENDING")]
        for latest in changed {
            let reader = Reader(), model = MerchantSettlementVoucherCopyModel(), baseline = try snapshot()
            let displayed = try progress(baseline); var writes: [String] = []
            let task = Task { await model.copy(displayed, intent: model.intentID, reader: reader, currentSnapshot: { baseline }, write: { writes.append($0) }) }
            try await started(reader); reader.pending[0].resume(returning: latest); await task.value
            XCTAssertTrue(writes.isEmpty)
        }
    }
    func testDismissedOrReplacedSnapshotCannotCopyAfterAwait() async throws {
        for replace in [false, true] {
            let reader = Reader(), model = MerchantSettlementVoucherCopyModel(), baseline = try snapshot()
            let displayed = try progress(baseline); var visible: MerchantBusinessSnapshot? = baseline; var writes: [String] = []
            let task = Task { await model.copy(displayed, intent: model.intentID, reader: reader, currentSnapshot: { visible }, write: { writes.append($0) }) }
            try await started(reader); visible = replace ? try snapshot(batch: 66002) : nil
            reader.pending[0].resume(returning: baseline); await task.value
            XCTAssertTrue(writes.isEmpty)
        }
    }
    func testDismissAndReopenRejectsOldQueuedIntentBeforeRead() async throws {
        let reader = Reader(), model = MerchantSettlementVoucherCopyModel(), baseline = try snapshot()
        let oldIntent = model.intentID; model.invalidate(); var writes: [String] = []
        await model.copy(try progress(baseline), intent: oldIntent, reader: reader, currentSnapshot: { baseline }, write: { writes.append($0) })
        XCTAssertEqual(reader.calls, 0); XCTAssertTrue(writes.isEmpty); XCTAssertNil(model.messageKey)
    }
    func testRepeatedTapStartsOneReadAndOneClipboardWrite() async throws {
        let reader = Reader(), model = MerchantSettlementVoucherCopyModel(), baseline = try snapshot()
        let displayed = try progress(baseline); var writes: [String] = []
        let task = Task { await model.copy(displayed, intent: model.intentID, reader: reader, currentSnapshot: { baseline }, write: { writes.append($0) }) }
        try await started(reader)
        await model.copy(displayed, intent: model.intentID, reader: reader, currentSnapshot: { baseline }, write: { writes.append($0) })
        XCTAssertEqual(reader.calls, 1)
        reader.pending[0].resume(returning: baseline); await task.value
        XCTAssertEqual(writes.count, 1)
    }
    func testCancelledCopyNeverTouchesClipboard() async throws {
        let reader = Reader(), model = MerchantSettlementVoucherCopyModel(), baseline = try snapshot()
        let displayed = try progress(baseline); var writes: [String] = []
        let task = Task { await model.copy(displayed, intent: model.intentID, reader: reader, currentSnapshot: { baseline }, write: { writes.append($0) }) }
        try await started(reader); task.cancel(); reader.pending[0].resume(returning: baseline); await task.value
        XCTAssertTrue(writes.isEmpty); XCTAssertFalse(model.busy)
    }
    func testFailedReadNeverClaimsCopied() async throws {
        let reader = Reader(), model = MerchantSettlementVoucherCopyModel(), baseline = try snapshot()
        let displayed = try progress(baseline); var writes: [String] = []
        let task = Task { await model.copy(displayed, intent: model.intentID, reader: reader, currentSnapshot: { baseline }, write: { writes.append($0) }) }
        try await started(reader); reader.pending[0].resume(throwing: SyntheticError.offline); await task.value
        XCTAssertTrue(writes.isEmpty); XCTAssertEqual(model.messageKey, "merchant.settlementProgress.copyUnavailable")
    }
    func testLateOldReadCannotResetNewAttemptOrCopy() async throws {
        let reader = Reader(), model = MerchantSettlementVoucherCopyModel(), baseline = try snapshot()
        let displayed = try progress(baseline); var writes: [String] = []
        let oldIntent = model.intentID
        let old = Task { await model.copy(displayed, intent: oldIntent, reader: reader, currentSnapshot: { baseline }, write: { writes.append($0) }) }
        try await started(reader); model.invalidate()
        let currentIntent = model.intentID
        let current = Task { await model.copy(displayed, intent: currentIntent, reader: reader, currentSnapshot: { baseline }, write: { writes.append($0) }) }
        try await started(reader, 2); reader.pending[0].resume(returning: baseline); await old.value
        XCTAssertTrue(writes.isEmpty); XCTAssertTrue(model.busy)
        reader.pending[1].resume(returning: baseline); await current.value
        XCTAssertEqual(writes.count, 1); XCTAssertFalse(model.busy)
    }
}
