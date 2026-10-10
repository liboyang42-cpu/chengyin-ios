import SwiftUI
import XCTest
@testable import Questify

@MainActor private final class PendingOrderWalletReader: TicketWalletReading {
    var scope = UUID()
    var isConfigured = true
    var isAuthenticated = true
    let isOfflineExample = true
    var reads = 0
    func ticketWallet() async throws -> TicketWalletSnapshot { reads += 1; return .init(tickets: []) }
    func ticketDetail(id: Int) async throws -> TicketWalletTicket { reads += 1; throw APIError.notConfigured }
}
@MainActor private final class PendingOrderLifecycleReader: OrderLifecycleReading {
    var scope = UUID()
    var accountID: Int? = 7
    var isConfigured = true
    let isOfflineExample = true
    var reads: [Int] = []
    func detail(id: Int) async throws -> OrderLifecycleDetail { reads.append(id); throw APIError.notConfigured }
}

@MainActor final class TicketWalletPendingOrderNavigationTests: XCTestCase {
    private func ticket(id: Int = 41, status: Int? = 1, verification: Int = 0, owner: Int? = nil) throws -> TicketWalletTicket {
        var row: [String: Any] = ["id": id, "verificationStatus": verification]
        row["registrationStatus"] = status; row["ownerId"] = owner
        return try JSONDecoder().decode(TicketWalletTicket.self, from: JSONSerialization.data(withJSONObject: row))
    }
    private func provider(_ reader: PendingOrderWalletReader, _ order: PendingOrderLifecycleReader,
                          revision: UInt64 = 1, current: @escaping @MainActor () -> UInt64 = { 1 }) -> TicketWalletPendingOrderProvider {
        .init(reader: reader, coordinator: OrderLifecycleCoordinator(reader: order), revision: revision, currentRevision: current)
    }
    private func opened(_ reader: PendingOrderWalletReader, _ provider: TicketWalletPendingOrderProvider) throws -> TicketWalletPendingOrderEntry {
        var value = TicketWalletPendingOrderEntry(); value.appear()
        let row = try ticket()
        value.activate(ticket: row, rowIndex: 0, snapshot: .init(tickets: [row]), reader: reader,
                       provider: provider, presentationID: value.presentationID)
        XCTAssertNotNil(value.target); return value
    }
    func testEnvironmentProviderDefaultsToNil() {
        XCTAssertNil(EnvironmentValues().ticketWalletPendingOrderProvider)
    }
    func testOnlyExactPendingStatusIsEligibleRegardlessOfVerificationDisplay() throws {
        for status in [Int?.none, -1, 0, 2, 3, 4, 5, 99] {
            for verification in [0, 1] {
                XCTAssertFalse(TicketWalletPendingOrderEntry.isPending(try ticket(status: status, verification: verification)))
            }
        }
        for verification in [0, 1] {
            XCTAssertTrue(TicketWalletPendingOrderEntry.isPending(try ticket(verification: verification)))
        }
    }
    func testRegistrationIDIsUsedWithoutOwnerIDGuessing() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader()
        let source = provider(reader, order); var entry = TicketWalletPendingOrderEntry(); entry.appear()
        let row = try ticket(id: 41, owner: 900)
        entry.activate(ticket: row, rowIndex: 0, snapshot: .init(tickets: [row]), reader: reader,
                       provider: source, presentationID: entry.presentationID)
        let target = try XCTUnwrap(entry.target)
        let view = try XCTUnwrap(source.destination(target: target, reader: reader))
        XCTAssertEqual(view.id, 41)
        XCTAssertTrue(order.reads.isEmpty); XCTAssertEqual(reader.reads, 0)
    }
    func testProviderRetainsExistingCoordinatorAndDoesNotReadOrPreparePayment() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader()
        let coordinator = OrderLifecycleCoordinator(reader: order)
        let source = TicketWalletPendingOrderProvider(reader: reader, coordinator: coordinator, revision: 1, currentRevision: { 1 })
        let entry = try opened(reader, source)
        XCTAssertTrue(source.coordinator === coordinator)
        XCTAssertNotNil(source.destination(target: try XCTUnwrap(entry.target), reader: reader))
        XCTAssertNil(coordinator.review); XCTAssertNil(coordinator.attempt(orderID: 41)); XCTAssertFalse(coordinator.canDispatch)
        XCTAssertTrue(order.reads.isEmpty); XCTAssertEqual(reader.reads, 0)
    }
    func testMissingAuthenticationConfigurationOrAccountRejectsEntry() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader()
        for kind in 0..<4 {
            reader.isAuthenticated = kind != 0; reader.isConfigured = kind != 1
            order.accountID = kind == 2 ? nil : (kind == 3 ? 0 : 7)
            let source = provider(reader, order); var entry = TicketWalletPendingOrderEntry(); entry.appear()
            XCTAssertFalse(entry.canOpen(ticket: try ticket(), reader: reader, provider: source))
        }
        XCTAssertTrue(order.reads.isEmpty); XCTAssertEqual(reader.reads, 0)
    }
    func testStaleOrDifferentReaderCannotUseSameOpaqueScope() throws {
        let reader = PendingOrderWalletReader(), other = PendingOrderWalletReader(), order = PendingOrderLifecycleReader()
        other.scope = reader.scope
        let source = provider(reader, order); let entry = try opened(reader, source); let target = try XCTUnwrap(entry.target)
        XCTAssertFalse(source.matches(reader: other)); XCTAssertNil(source.destination(target: target, reader: other))
        reader.scope = UUID()
        XCTAssertNil(source.destination(target: target, reader: reader))
    }
    func testWalletAuthenticationAndConfigurationRevocationRejectDestination() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader()
        let source = provider(reader, order); let entry = try opened(reader, source); let target = try XCTUnwrap(entry.target)
        reader.isAuthenticated = false; XCTAssertNil(source.destination(target: target, reader: reader))
        reader.isAuthenticated = true; reader.isConfigured = false; XCTAssertNil(source.destination(target: target, reader: reader))
    }
    func testSessionRevisionInvalidatesSelectionBeforeViewUpdate() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader(); var revision: UInt64 = 1
        let source = provider(reader, order, current: { revision }); let entry = try opened(reader, source)
        let target = try XCTUnwrap(entry.target); revision = 2
        XCTAssertNil(source.destination(target: target, reader: reader))
        XCTAssertFalse(entry.matches(target, snapshot: .init(tickets: [try ticket()]), reader: reader, provider: source))
    }
    func testOrderScopeOrAccountChangeInvalidatesDestination() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader()
        let source = provider(reader, order); let entry = try opened(reader, source); let target = try XCTUnwrap(entry.target)
        let scope = order.scope; order.scope = UUID()
        XCTAssertNil(source.destination(target: target, reader: reader))
        order.scope = scope; order.accountID = 8
        XCTAssertNil(source.destination(target: target, reader: reader))
        order.accountID = nil
        XCTAssertNil(source.destination(target: target, reader: reader))
    }
    func testNewCoordinatorCannotAdoptOldTargetEvenWithSameScopeAndAccount() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader()
        let source = provider(reader, order); let entry = try opened(reader, source); let target = try XCTUnwrap(entry.target)
        let replacement = provider(reader, order)
        XCTAssertNil(replacement.destination(target: target, reader: reader))
        XCTAssertFalse(entry.matches(target, snapshot: .init(tickets: [try ticket()]), reader: reader, provider: replacement))
    }
    func testActivationRequiresExactRowAndBoundsInCurrentSnapshot() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader(); let source = provider(reader, order)
        let row = try ticket()
        for index in [-1, 1, 100] {
            var entry = TicketWalletPendingOrderEntry(); entry.appear()
            entry.activate(ticket: row, rowIndex: index, snapshot: .init(tickets: [row]), reader: reader,
                           provider: source, presentationID: entry.presentationID)
            XCTAssertNil(entry.target)
        }
        for snapshot in [TicketWalletSnapshot(tickets: []), .init(tickets: [try ticket(id: 42)]), .init(tickets: [try ticket(status: 2)])] {
            var entry = TicketWalletPendingOrderEntry(); entry.appear()
            entry.activate(ticket: row, rowIndex: 0, snapshot: snapshot, reader: reader, provider: source, presentationID: entry.presentationID)
            XCTAssertNil(entry.target)
        }
    }
    func testChangedCurrentSnapshotRevokesNavigation() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader(); let source = provider(reader, order)
        let entry = try opened(reader, source); let target = try XCTUnwrap(entry.target)
        for rows in [[], [try ticket(id: 42)], [try ticket(status: 2)], [try ticket(verification: 1)]] {
            XCTAssertFalse(entry.matches(target, snapshot: .init(tickets: rows), reader: reader, provider: source))
        }
    }
    func testRepeatedServerIDUsesSelectedRowWithoutDeduplication() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader(); let source = provider(reader, order)
        let row = try ticket(), other = try ticket(status: 2)
        let snapshot = TicketWalletSnapshot(tickets: [other, row])
        var entry = TicketWalletPendingOrderEntry(); entry.appear()
        entry.activate(ticket: row, rowIndex: 1, snapshot: snapshot, reader: reader, provider: source, presentationID: entry.presentationID)
        let target = try XCTUnwrap(entry.target)
        XCTAssertEqual(target.rowIndex, 1)
        XCTAssertTrue(entry.matches(target, snapshot: snapshot, reader: reader, provider: source))
        XCTAssertFalse(entry.matches(target, snapshot: .init(tickets: [row, other]), reader: reader, provider: source))
    }
    func testDuplicateTapKeepsOneTarget() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader(); let source = provider(reader, order)
        var entry = try opened(reader, source); let first = entry.target; let row = try ticket()
        entry.activate(ticket: row, rowIndex: 0, snapshot: .init(tickets: [row]), reader: reader,
                       provider: source, presentationID: entry.presentationID)
        XCTAssertEqual(entry.target, first)
    }
    func testPushBackAndReopenRejectsOldTapAndPreservesPushedDestination() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader(); let source = provider(reader, order)
        var entry = try opened(reader, source); let target = try XCTUnwrap(entry.target)
        let old = entry.presentationID; let row = try ticket(); entry.disappear()
        XCTAssertTrue(entry.matches(target, snapshot: .init(tickets: [row]), reader: reader, provider: source))
        entry.target = nil; entry.appear()
        entry.activate(ticket: row, rowIndex: 0, snapshot: .init(tickets: [row]), reader: reader, provider: source, presentationID: old)
        XCTAssertNil(entry.target)
        entry.activate(ticket: row, rowIndex: 0, snapshot: .init(tickets: [row]), reader: reader,
                       provider: source, presentationID: entry.presentationID)
        XCTAssertNotEqual(entry.target?.id, target.id)
    }
    func testBackgroundOrDepartureRejectsQueuedTap() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader(); let source = provider(reader, order)
        var entry = TicketWalletPendingOrderEntry(); entry.appear(); let old = entry.presentationID; entry.disappear()
        let row = try ticket()
        entry.activate(ticket: row, rowIndex: 0, snapshot: .init(tickets: [row]), reader: reader, provider: source, presentationID: old)
        XCTAssertNil(entry.target)
    }
    func testRefreshOrIdentityRetirementClearsTargetAndRejectsOldCallback() throws {
        let reader = PendingOrderWalletReader(), order = PendingOrderLifecycleReader(); let source = provider(reader, order)
        var entry = try opened(reader, source); let target = try XCTUnwrap(entry.target); let old = entry.presentationID
        let row = try ticket(); entry.retire()
        XCTAssertNil(entry.target)
        XCTAssertFalse(entry.matches(target, snapshot: .init(tickets: [row]), reader: reader, provider: source))
        entry.activate(ticket: row, rowIndex: 0, snapshot: .init(tickets: [row]), reader: reader, provider: source, presentationID: old)
        XCTAssertNil(entry.target)
    }
    func testInvalidRegistrationIDsCannotDecode() {
        for id in [-1, 0] { XCTAssertThrowsError(try ticket(id: id)) }
    }
}
