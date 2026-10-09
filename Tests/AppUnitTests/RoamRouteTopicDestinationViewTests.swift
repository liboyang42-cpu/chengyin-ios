import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class RoamRouteTopicDestinationViewTests: XCTestCase {
    private func route() throws -> RoamRouteNode {
        try JSONDecoder().decode(RoamRouteNode.self, from: Data(#"{"id":7,"nodeId":11,"topicId":99,"addressName":"Synthetic route"}"#.utf8))
    }
    func testConstructingRouteOverviewDoesNotInvokeTopicFactory() throws {
        var requested: [RoamEventDestination] = []
        let host = UIHostingController(rootView: RoamItemDetailView(item: .route(try route()), reader: RoamFixtureReader(),
            eventDestination: { requested.append($0); return AnyView(Text("Synthetic topic")) }))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertTrue(requested.isEmpty)
    }
    func testExactNativeReaderRouteProducesOnlyItsAssociatedTopicReference() throws {
        let reader = RoamFixtureReader(), route = try route()
        let scope = try XCTUnwrap(RoamEventNavigationScope(readerID: ObjectIdentifier(reader), identity: reader.identity,
            area: reader.searchArea, presentationID: UUID(), isConfigured: reader.isConfigured))
        let selected = try XCTUnwrap(RoamRouteTopicNavigationSelection(route: route, currentRoute: route, rendered: scope, current: scope))
        let destination = RoamEventDestination.topic(selected.destination.topicID)
        XCTAssertEqual(destination, .topic(99)); XCTAssertNotEqual(destination, .topic(7)); XCTAssertNotEqual(destination, .topic(11))
    }
}
