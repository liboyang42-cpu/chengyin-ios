import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamFeaturedActivitySelectionViewTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    func testPlaceOverviewDoesNotAutomaticallyInvokeActivityFactory() throws {
        let place = try decode(RoamPlace.self, #"{"id":11,"type":2,"name":"Synthetic place"}"#)
        var destinations: [RoamEventDestination] = []
        let host = UIHostingController(rootView: RoamItemDetailView(item: .place(place), reader: RoamFixtureReader(),
            eventDestination: { destinations.append($0); return AnyView(Text("Synthetic detail")) }))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertTrue(destinations.isEmpty)
    }
    func testExistingActivityFactoryReceivesFeaturedIDRatherThanPOIOrMerchantID() throws {
        let reader = RoamFixtureReader(), snapshot = UUID()
        let scope = try XCTUnwrap(RoamEventNavigationScope(readerID: ObjectIdentifier(reader), identity: reader.identity,
            area: reader.searchArea, presentationID: UUID(), isConfigured: reader.isConfigured))
        let place = try decode(RoamPlace.self, #"{"id":11,"type":2,"name":"Synthetic place"}"#)
        let node = try decode(RoamNodeDetail.self, #"{"poiId":11,"merchantId":22,"status":1}"#)
        let detail = try decode(RoamMerchantDetail.self, #"{"data":{"id":22},"featured":{"featuredType":1,"featuredId":33,"name":"Synthetic activity"}}"#)
        let selected = try XCTUnwrap(RoamFeaturedActivitySelection(place: place, currentPlace: place, node: node, currentNode: node,
            detail: detail, currentDetail: detail, rendered: scope, current: scope,
            snapshotID: snapshot, currentSnapshotID: snapshot))
        let destination = RoamEventDestination.activity(selected.target.activityID)
        XCTAssertEqual(destination, .activity(33))
        XCTAssertNotEqual(destination, .activity(11)); XCTAssertNotEqual(destination, .activity(22))
        XCTAssertFalse(selected.mayRemainOpen(in: scope, snapshotID: UUID()))
    }
}
