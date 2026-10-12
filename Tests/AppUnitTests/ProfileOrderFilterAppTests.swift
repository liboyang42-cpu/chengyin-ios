import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileOrderFilterAppTests: XCTestCase {
    func testSelectingAllFiltersDoesNotReadAgain() async throws {
        let reader = ProfileOrderFilterFixtureReader(); let rows = try await reader.profileOrders()
        for filter in ProfileOrderHistoryFilter.allCases { _ = filter.orders(in: rows) }
        XCTAssertEqual(reader.listReads, 1); XCTAssertEqual(reader.detailReads, 0)
    }
    func testFilteredEmptyCanReturnOriginalAllRows() async throws {
        let reader = ProfileOrderFilterFixtureReader(); let rows = try await reader.profileOrders()
        XCTAssertTrue(ProfileOrderHistoryFilter.manualRefund.orders(in: rows).isEmpty)
        XCTAssertEqual(ProfileOrderHistoryFilter.all.orders(in: rows), rows)
    }
    func testSelectedOrderUsesOriginalDetailID() async throws {
        let reader = ProfileOrderFilterFixtureReader(); let rows = try await reader.profileOrders()
        let row = try XCTUnwrap(ProfileOrderHistoryFilter.refunded.orders(in: rows).first)
        let detail = try await reader.profileOrder(id: row.id)
        XCTAssertEqual(detail.id, 705); XCTAssertEqual(reader.detailReads, 1)
    }
    func testSyntheticSwitchDoesNotReturnOtherAccountsRows() async throws {
        let reader = ProfileOrderFilterFixtureReader(); reader.identity = .init(accountID:7002,epoch:2)
        let rows = try await reader.profileOrders(); XCTAssertTrue(rows.isEmpty)
    }
    func testRevokedFixtureCannotRead() async {
        let reader = ProfileOrderFilterFixtureReader(); reader.isConfigured = false
        do { _ = try await reader.profileOrders(); XCTFail() } catch { XCTAssertEqual(error as? APIError,.notConfigured) }
        XCTAssertEqual(reader.listReads,0)
    }
    func testGenuineEmptyCollectionDoesNotInventOrders() async throws {
        let reader = ProfileOrderFilterFixtureReader(empty:true); let rows = try await reader.profileOrders()
        for filter in ProfileOrderHistoryFilter.allCases { XCTAssertTrue(filter.orders(in:rows).isEmpty) }
    }
    func testFilterSectionRendersWithoutServices() {
        let host = UIHostingController(rootView:List { ProfileOrderFilterSection(selection:.constant(.manualRefund),isEmpty:true) })
        host.loadViewIfNeeded(); XCTAssertNotNil(host.view)
    }
}
