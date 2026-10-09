import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamPlaceReadStatusViewTests: XCTestCase {
    private func item() throws -> RoamMapItem {
        .place(try JSONDecoder().decode(RoamPlace.self,
            from: Data(#"{"id":11,"type":2,"name":"Synthetic","found":true,"pendingRedeem":true}"#.utf8)))
    }
    func testRetainedAndDefaultRowsCannotAccidentallyExposeCurrentFactBadges() throws {
        XCTAssertFalse(try RoamItemRow(item: item()).showsCurrentReadStatus)
        XCTAssertFalse(try RoamItemRow(item: item(), navigable: false).showsCurrentReadStatus)
        XCTAssertTrue(try RoamItemRow(item: item(), showsCurrentReadStatus: true).showsCurrentReadStatus)
    }
    func testUnknownAndKnownFieldsUseIndependentReadOnlyLabels() {
        let unknown = RoamPlaceReadStatusLabel(status: .init(found: nil, pendingRedeem: nil))
        XCTAssertEqual(unknown.discoveryKey, "roamPlaceRead.discoveryUnknown")
        XCTAssertEqual(unknown.redemptionKey, "roamPlaceRead.redemptionUnknown")
        let independent = RoamPlaceReadStatusLabel(status: .init(found: false, pendingRedeem: true))
        XCTAssertEqual(independent.discoveryKey, "roamPlaceRead.notDiscovered")
        XCTAssertEqual(independent.redemptionKey, "roamPlaceRead.pending")
    }
    func testReadOnlyLabelBuildsWithoutReaderOrRewardAction() {
        let host = UIHostingController(rootView: RoamPlaceReadStatusLabel(status: .init(found: true, pendingRedeem: true))
            .environment(\.dynamicTypeSize, .accessibility3))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view)
    }
}
