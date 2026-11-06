import XCTest
import Foundation
@testable import QuestifyCore

@MainActor final class FreeExploreLaunchPendingStoreTests: XCTestCase {
    func testRecreatedStoreRetainsOriginalPayloadAcrossTokenEpoch() throws {
        let storage = FXStorage(), command = try FX.command()
        let store = FreeExploreLaunchPendingStore(storage: storage, session: try FX.session())
        try store.save(command)
        let reopened = FreeExploreLaunchPendingStore(storage: storage, session: try FX.session(epoch: 2))
        XCTAssertEqual(try reopened.load(), command)
        let raw = try XCTUnwrap(storage.values.values.first)
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("synthetic-test-credential"))
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("Authorization"))
    }
    func testOtherAccountMarketOriginAndNamespaceCannotLoadPending() throws {
        let storage = FXStorage()
        let store = FreeExploreLaunchPendingStore(storage: storage, session: try FX.session())
        try store.save(FX.command())
        let others = try [FX.session(account: 8), FX.session(market: "US"), FX.session(namespace: "other"), FX.session(host: "other.example.test")]
        for session in others {
            XCTAssertNil(try FreeExploreLaunchPendingStore(storage: storage, session: session).load())
        }
        XCTAssertNotNil(try store.load())
    }
    func testUnresolvedCommandCannotBeReplaced() throws {
        let store = FreeExploreLaunchPendingStore(storage: FXStorage(), session: try FX.session())
        try store.save(FX.command())
        XCTAssertThrowsError(try store.save(FX.command(key: "fx-second"))) {
            XCTAssertEqual($0 as? FreeExploreLaunchFailure, .pendingConflict)
        }
        XCTAssertEqual(try store.load(), try FX.command())
    }
    func testWriteFailureAndMissingReadbackPreventDispatchPreparation() throws {
        for ignore in [false, true] {
            let storage = FXStorage()
            storage.ignoreWrite = ignore; storage.failWrite = !ignore
            let store = FreeExploreLaunchPendingStore(storage: storage, session: try FX.session())
            XCTAssertThrowsError(try store.save(FX.command())) {
                XCTAssertEqual($0 as? FreeExploreLaunchFailure, .storageUnavailable)
            }
        }
    }
    func testCorruptRecordNeverMeansNoPending() throws {
        let storage = FXStorage()
        let store = FreeExploreLaunchPendingStore(storage: storage, session: try FX.session())
        try store.save(FX.command())
        let key = try XCTUnwrap(storage.values.keys.first)
        storage.values[key] = Data("broken".utf8)
        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual($0 as? FreeExploreLaunchFailure, .storageUnavailable)
        }
        XCTAssertThrowsError(try store.save(FX.command(key: "new")))
    }
    func testOnlyReceiptPlusOriginalOwnedOrderClearsPending() throws {
        let command = try FX.command(), store = FreeExploreLaunchPendingStore(storage: FXStorage(), session: try FX.session())
        try store.save(command)
        let receipt = try FX.decode(FreeExploreLaunchReservation.self, FX.receipt(command))
        let missing = try FX.decode(FreeExploreLaunchOrder.self, FX.order(command))
        XCTAssertThrowsError(try store.acknowledge(receipt: receipt, order: missing))
        XCTAssertEqual(try store.load(), command)
        let confirmed = try FX.decode(FreeExploreLaunchOrder.self, FX.order(command, reservations: [FX.receipt(command)], unitStatus: "RESERVED"))
        try store.acknowledge(receipt: receipt, order: confirmed)
        XCTAssertNil(try store.load())
    }
    func testFailedRemovalDoesNotReportAcknowledged() throws {
        let command = try FX.command(), storage = FXStorage()
        let store = FreeExploreLaunchPendingStore(storage: storage, session: try FX.session())
        try store.save(command); storage.ignoreRemove = true
        let receipt = try FX.decode(FreeExploreLaunchReservation.self, FX.receipt(command))
        let order = try FX.decode(FreeExploreLaunchOrder.self, FX.order(command, reservations: [FX.receipt(command)]))
        XCTAssertThrowsError(try store.acknowledge(receipt: receipt, order: order)) {
            XCTAssertEqual($0 as? FreeExploreLaunchFailure, .storageUnavailable)
        }
        XCTAssertEqual(try store.load(), command)
    }
}
