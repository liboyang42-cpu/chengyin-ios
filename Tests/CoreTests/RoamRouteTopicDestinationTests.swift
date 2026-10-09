import XCTest
@testable import QuestifyCore

final class RoamRouteTopicDestinationTests: XCTestCase {
    private final class ReaderMarker {}
    private let reader = ReaderMarker()
    private let presentation = UUID()
    private func route(id: Int = 7, topic: Int? = 99, node: Int = 11, title: String = "Synthetic route") throws -> RoamRouteNode {
        var payload: [String: Any] = ["id":id,"nodeId":node,"addressName":title]
        if let topic { payload["topicId"] = topic }
        return try JSONDecoder().decode(RoamRouteNode.self, from: JSONSerialization.data(withJSONObject: payload))
    }
    private func scope(epoch: UInt64 = 1, presentation: UUID? = nil) throws -> RoamEventNavigationScope {
        try XCTUnwrap(.init(readerID: ObjectIdentifier(reader), identity: .init(accountID: 7, epoch: epoch),
                           area: .init(coordinate: .init(latitude: 1, longitude: 2)!, label: "Manual"),
                           presentationID: presentation ?? self.presentation, isConfigured: true))
    }
    func testOnlyExplicitTopicIDIsUsedInsteadOfRouteOrNodeIdentity() throws {
        let result = try XCTUnwrap(RoamRouteTopicDestination(route: route()))
        XCTAssertEqual(result.routeID, 7); XCTAssertEqual(result.topicID, 99)
        XCTAssertNotEqual(result.topicID, 7); XCTAssertNotEqual(result.topicID, 11)
    }
    func testMissingOrInvalidTopicNeverFallsBackAndCoordinatesAreNotRequired() throws {
        for topic in [Int?.none, 0, -1] { XCTAssertNil(RoamRouteTopicDestination(route: try route(topic: topic))) }
        XCTAssertNil(RoamRouteTopicDestination(route: try route(id: 0)))
        let noCoordinates = try route(); XCTAssertNil(noCoordinates.coordinate)
        XCTAssertNotNil(RoamRouteTopicDestination(route: noCoordinates))
    }
    func testSameRouteIDChangedTopicOrPayloadRejectsCapturedAction() throws {
        let route = try route(), scope = try scope()
        for current in [try self.route(topic: 100), try self.route(title: "Replacement"), try self.route(id: 8)] {
            XCTAssertNil(RoamRouteTopicNavigationSelection(route: route, currentRoute: current, rendered: scope, current: scope))
        }
        XCTAssertNil(RoamRouteTopicNavigationSelection(route: route, currentRoute: nil, rendered: scope, current: scope))
    }
    func testNormalPushKeepsAcceptedTopicButRetiredOverviewCannotIssueNewAction() throws {
        let route = try route(), original = try scope(), retired = try scope(presentation: UUID())
        let selected = try XCTUnwrap(RoamRouteTopicNavigationSelection(route: route, currentRoute: route, rendered: original, current: original))
        XCTAssertEqual(selected.destination.topicID, 99)
        XCTAssertTrue(selected.mayRemainOpen(in: retired))
        XCTAssertNil(RoamRouteTopicNavigationSelection(route: route, currentRoute: route, rendered: original, current: retired))
    }
    func testNewSessionOrMissingScopeRevokesAcceptedRoute() throws {
        let route = try route(), original = try scope(), changed = try scope(epoch: 2)
        let selected = try XCTUnwrap(RoamRouteTopicNavigationSelection(route: route, currentRoute: route, rendered: original, current: original))
        XCTAssertFalse(selected.mayRemainOpen(in: changed)); XCTAssertFalse(selected.mayRemainOpen(in: nil))
        XCTAssertNil(RoamRouteTopicNavigationSelection(route: route, currentRoute: route, rendered: original, current: changed))
        XCTAssertNil(RoamRouteTopicNavigationSelection(route: route, currentRoute: route, rendered: nil, current: nil))
    }
}
