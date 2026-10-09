import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class OfficialEventBrowseStateViewTests: XCTestCase {
    func testMineKeywordProducesSearchEmptyRatherThanClaimingNoParticipation() {
        XCTAssertEqual(OfficialEventBrowseQuery(bucket: .mine, keyword: "Missing").emptyKey, "official.searchEmpty")
        XCTAssertEqual(OfficialEventBrowseQuery(bucket: .mine, keyword: "").emptyKey, "official.emptyMine")
        XCTAssertTrue(OfficialEventBrowseQuery(bucket: .mine, keyword: "Missing").isPrivate)
    }
    func testUnknownTaskUsesUnknownCardTextWhileRemainingBrowsable() throws {
        let event = try JSONDecoder().decode(OfficialEvent.self, from: Data(#"{"id":71,"title":"Synthetic task","status":42,"signed":true}"#.utf8))
        XCTAssertEqual(OfficialEventBrowseQuery(bucket: .live, keyword: "task").visible([event]), [event])
        XCTAssertEqual(event.statusKey, "official.status.unknown")
        XCTAssertEqual(event.participationKey, "official.participation.unavailable")
        let host = UIHostingController(rootView: OfficialEventCard(event: event).environment(\.dynamicTypeSize, .accessibility3))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view)
    }
    func testGuestMineReadStillRejectsBeforeNetworkDespiteLocalSearchSupport() async throws {
        let reader = OfficialSessionReader(service: nil, currentContext: { OfficialReadContext(guestEpoch: 1) })
        do { _ = try await reader.myEvents(); XCTFail("Guest private data was read") }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
}
