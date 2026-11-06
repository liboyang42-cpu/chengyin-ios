import XCTest
import Foundation
@testable import QuestifyCore

@MainActor final class InvoiceLaunchJournalCapacityTests: XCTestCase {
    private typealias S = InvoiceLaunchTestSupport
    private struct Record: Encodable {
        let version: Int
        let ownerKey: String
        let pending: InvoiceLaunchPending
    }
    private func oversizedCommand() throws -> InvoiceLaunchApply {
        try InvoiceLaunchApply(requestId: "synthetic-large-request", titleId: 11,
                               orderIds: (1...20_000).map { Int64($0) })
    }
    // Synthetic namespace controls bytes without changing any business limits or
    // storing PII. Match the real sorted encoder and persisted record contract.
    private func exactCapacityHarness(_ pending: InvoiceLaunchPending) throws -> S.Harness {
        var length = 65_000
        for _ in 0..<8 {
            let session = try S.session(namespace: String(repeating: "x", count: length))
            let bytes = try InvoiceLaunchWire.encode(Record(version: 1, ownerKey: session.ownerKey, pending: pending))
            if bytes.count == 65_536 { return try S.Harness(captured: session) }
            length += 65_536 - bytes.count
        }
        throw InvoiceLaunchIssue.invalid
    }
    func testOversizedApplyNeverWritesOrDispatchesAndNormalIntentRemainsPossible() async throws {
        let h = try S.Harness()
        await S.expect(.storageUnavailable) { _ = try await h.coordinator().apply(self.oversizedCommand()) }
        XCTAssertEqual(h.memory.writeCount, 0)
        XCTAssertTrue(h.memory.values.isEmpty)
        XCTAssertTrue(h.wire.requests.isEmpty)
        XCTAssertNil(try h.store.load())
        let normal = InvoiceLaunchPending(kind: .apply, apply: try h.command())
        try h.store.save(normal)
        XCTAssertEqual(try h.store.load(), normal)
    }
    func testExistingOriginalWinsOverOversizedNewIntentWithoutChangingBytes() async throws {
        let h = try S.Harness()
        let original = InvoiceLaunchPending(kind: .saveTitle, titleRequestID: "original-title")
        try h.store.save(original)
        let bytes = h.memory.values
        await S.expect(.pendingConflict) { _ = try await h.coordinator().apply(self.oversizedCommand()) }
        XCTAssertEqual(h.memory.values, bytes)
        XCTAssertEqual(h.memory.writeCount, 1)
        XCTAssertTrue(h.wire.requests.isEmpty)
        XCTAssertEqual(try h.store.load(), original)
    }
    func testExactLimitLoadsButLargerApplicationCheckpointPreservesOriginal() async throws {
        let pending = InvoiceLaunchPending(kind: .apply,
            apply: try InvoiceLaunchApply(requestId: "synthetic-limit", titleId: 11, orderIds: [21]))
        let h = try exactCapacityHarness(pending)
        try h.store.save(pending)
        XCTAssertEqual(try XCTUnwrap(h.memory.values.values.first).count, 65_536)
        let bytes = h.memory.values
        XCTAssertThrowsError(try h.store.checkpoint(pending, applicationID: 51)) {
            XCTAssertEqual($0 as? InvoiceLaunchIssue, .storageUnavailable)
        }
        XCTAssertEqual(h.memory.values, bytes)
        XCTAssertEqual(h.memory.writeCount, 1)
        XCTAssertEqual(try h.store.load(), pending)
    }
    func testOversizedTitleCheckpointCanStillRecoverExactOriginalReceipt() async throws {
        let pending = InvoiceLaunchPending(kind: .saveTitle, titleRequestID: "synthetic-title-limit")
        let h = try exactCapacityHarness(pending)
        h.originalReceipts = true
        try h.store.save(pending)
        let bytes = h.memory.values
        XCTAssertThrowsError(try h.store.checkpointTitle(pending, acknowledgedTitleID: 11)) {
            XCTAssertEqual($0 as? InvoiceLaunchIssue, .storageUnavailable)
        }
        XCTAssertEqual(h.memory.values, bytes)
        XCTAssertEqual(h.memory.writeCount, 1)
        h.wire.responses = [try S.success(["requestId": "synthetic-title-limit", "titleId": "11", "status": "SAVED"])]
        let result = try await h.coordinator().recover()
        guard case .titleSaved(let receipt) = result else { return XCTFail("Expected original title receipt") }
        XCTAssertEqual(receipt.titleId, 11)
        XCTAssertNil(try h.store.load())
        XCTAssertEqual(h.wire.requests.map { $0.url!.path }, ["/native/api/invoice/titles/request"])
    }
    func testPreviouslyOversizedOrCorruptSlotIsNotReplacedOrDeleted() async throws {
        let h = try S.Harness()
        try h.store.save(.init(kind: .cancel, targetID: 51))
        let key = try XCTUnwrap(h.memory.values.keys.first)
        h.memory.values[key] = Data(repeating: 120, count: 65_537)
        let bytes = h.memory.values
        await S.expect(.storageUnavailable) { _ = try await h.coordinator().apply(h.command()) }
        XCTAssertEqual(h.memory.values, bytes)
        XCTAssertEqual(h.memory.writeCount, 1)
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
}
