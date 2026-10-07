import XCTest
@testable import QuestifyCore

final class PlayRouteMapPresentationTests: XCTestCase {
    private func snapshot(_ nodes: String, route: String? = nil, mode: Int = 1, extra: String = "", scope: PlaySessionScope = .activity(41)) throws -> PlaySnapshot {
        let raw = "{\"mode\":\(mode),\"playable\":true,\"registered\":true,\"nodes\":\(nodes)\(route.map { ",\"routeState\":" + $0 } ?? "")\(extra)}"
        let result = try JSONDecoder().decode(PlayNodesResult.self, from: Data(raw.utf8))
        return try PlaySnapshot(scope: scope, result: result, authority: result.routeState?.isBranch == true ? result.routeState : nil)
    }
    func testCurrentCompletedAndLockedUseOnlySafeRows() throws {
        let value = try XCTUnwrap(PlayRouteMapPresentation(snapshot: snapshot(#"[{"nodeId":1,"name":"Completed","done":true,"latitude":31,"longitude":121},{"nodeId":2,"name":"Current","done":false,"latitude":32,"longitude":122},{"nodeId":3,"name":"SPOILER","storyText":"SECRET","address":"SECRET ADDRESS","done":false,"locked":true,"latitude":33,"longitude":123}]"#)))
        XCTAssertEqual(value.currentNodeID, 2)
        XCTAssertEqual(value.stops.map(\.state), [.completed, .current, .locked])
        XCTAssertEqual(value.stops.map(\.canOpen), [true, true, false])
        XCTAssertNil(value.stops[2].name); XCTAssertNil(value.stops[2].address); XCTAssertNil(value.stops[2].coordinate)
        XCTAssertEqual(value.mappedStops.map(\.id), [1, 2]); XCTAssertEqual(value.segments.count, 1)
    }
    func testLinearHiddenNodeNeverProjectsAnyMetadataOrGeometry() throws {
        let value = try XCTUnwrap(PlayRouteMapPresentation(snapshot: snapshot(#"[{"nodeId":1,"done":false},{"nodeId":2,"name":"SECRET","routeNodeState":"HIDDEN","latitude":10,"longitude":20}]"#)))
        XCTAssertEqual(value.stops.map(\.id), [1]); XCTAssertTrue(value.mappedStops.isEmpty)
        XCTAssertEqual(value.currentNodeID, 1)
    }
    func testBranchUsesAuthoritativeVisibilityAndIgnoresHiddenCurrent() throws {
        let route = #"{"routeMode":"BRANCH_GRAPH","sessionId":5,"version":3,"status":"ACTIVE","currentNodeId":3,"recommendedNodeId":2,"nodeStates":{"1":"COMPLETED","2":"PLAYABLE","3":"HIDDEN","4":"DISCOVERED_LOCKED","5":"FUTURE"}}"#
        let value = try XCTUnwrap(PlayRouteMapPresentation(snapshot: snapshot(#"[{"nodeId":1},{"nodeId":2,"done":false},{"nodeId":3,"done":false},{"nodeId":4,"name":"SECRET"},{"nodeId":5}]"#, route: route)))
        XCTAssertEqual(value.stops.map(\.id), [1, 2, 4]); XCTAssertEqual(value.currentNodeID, 2)
        XCTAssertEqual(value.stops.map(\.state), [.completed, .current, .locked]); XCTAssertNil(value.stops.last?.name)
    }
    func testMultipleAvailableStopsDoNotInventCurrentFromOrdering() throws {
        let value = try XCTUnwrap(PlayRouteMapPresentation(snapshot: snapshot(#"[{"nodeId":2,"sortId":9,"done":false},{"nodeId":1,"sortId":1,"done":false}]"#)))
        XCTAssertNil(value.currentNodeID); XCTAssertEqual(value.stops.map(\.id), [2, 1])
        XCTAssertEqual(value.stops.map(\.order), [1, 2]); XCTAssertFalse(value.stops.contains(where: \.canOpen))
    }
    func testAuthoritativeCurrentWinsOnlyWhenEligible() throws {
        let route = #"{"routeMode":"LINEAR","sessionId":5,"version":1,"status":"ACTIVE","currentNodeId":2,"recommendedNodeId":1}"#
        let value = try XCTUnwrap(PlayRouteMapPresentation(snapshot: snapshot(#"[{"nodeId":1,"done":false},{"nodeId":2,"done":false}]"#, route: route)))
        XCTAssertEqual(value.currentNodeID, 2); XCTAssertEqual(value.stops.map(\.canOpen), [false, true])
    }
    func testMissingInvalidAndPartialCoordinatesRetainListAndBreakLine() throws {
        let value = try XCTUnwrap(PlayRouteMapPresentation(snapshot: snapshot(#"[{"nodeId":1,"done":true,"latitude":0,"longitude":0},{"nodeId":2,"done":true,"latitude":30},{"nodeId":3,"done":true,"latitude":91,"longitude":20},{"nodeId":4,"done":true,"latitude":30,"longitude":181},{"nodeId":5,"done":false,"latitude":31,"longitude":121}]"#)))
        XCTAssertEqual(value.stops.count, 5); XCTAssertEqual(value.mappedStops.map(\.id), [1, 5])
        XCTAssertTrue(value.stops.allSatisfy(\.canOpen)); XCTAssertTrue(value.segments.isEmpty)
    }
    func testCoordinateValidatorRejectsNonfiniteWithoutRejectingZeroOrBoundaries() {
        XCTAssertNil(PlayRouteMapPresentation.Coordinate(latitude: .nan, longitude: 1))
        XCTAssertNil(PlayRouteMapPresentation.Coordinate(latitude: 1, longitude: .infinity))
        XCTAssertNil(PlayRouteMapPresentation.Coordinate(latitude: nil, longitude: 1))
        XCTAssertNotNil(PlayRouteMapPresentation.Coordinate(latitude: 0, longitude: 0))
        XCTAssertNotNil(PlayRouteMapPresentation.Coordinate(latitude: -90, longitude: 180))
        XCTAssertNotNil(PlayRouteMapPresentation.Coordinate(latitude: 90, longitude: -180))
    }
    func testUnavailableAndOtherModesFailClosed() throws {
        for mode in [2, 0, 9] { XCTAssertNil(PlayRouteMapPresentation(snapshot: try snapshot(#"[{"nodeId":1,"done":false}]"#, mode: mode))) }
        let route = #"{"routeMode":"LINEAR","status":"PAUSED"}"#
        XCTAssertNil(PlayRouteMapPresentation(snapshot: try snapshot(#"[{"nodeId":1,"done":false}]"#, route: route)))
        let raw = #"{"mode":1,"playable":true,"registered":false,"nodes":[{"nodeId":1,"name":"SECRET"}]}"#
        let result = try JSONDecoder().decode(PlayNodesResult.self, from: Data(raw.utf8))
        XCTAssertNil(PlayRouteMapPresentation(snapshot: try PlaySnapshot(scope: .activity(41), result: result)))
    }
    func testCompletedRouteKeepsReplayWithoutInventingCurrent() throws {
        let value = try XCTUnwrap(PlayRouteMapPresentation(snapshot: snapshot(#"[{"nodeId":1,"done":true}]"#, extra: #", "total":1,"doneCount":1"#)))
        XCTAssertNil(value.currentNodeID); XCTAssertTrue(value.stops[0].canOpen); XCTAssertEqual(value.stops[0].state, .completed)
    }
    func testContradictoryLockedCompletedRemainsRedactedAndInert() throws {
        let value = try XCTUnwrap(PlayRouteMapPresentation(snapshot: snapshot(#"[{"nodeId":1,"done":true,"locked":true,"name":"SECRET","latitude":30,"longitude":120}]"#)))
        XCTAssertEqual(value.stops[0].state, .locked); XCTAssertNil(value.stops[0].name)
        XCTAssertFalse(value.stops[0].canOpen); XCTAssertTrue(value.mappedStops.isEmpty)
    }
    func testUnknownCompletionCannotBeOpenedOrPromotedToCurrent() throws {
        let value = try XCTUnwrap(PlayRouteMapPresentation(snapshot: snapshot(#"[{"nodeId":1,"name":"Known visible"}]"#)))
        XCTAssertNil(value.currentNodeID); XCTAssertEqual(value.stops[0].state, .unknown); XCTAssertFalse(value.stops[0].canOpen)
    }
    func testCoordinateStringsCanBeUsedAndInputOrderIsPreserved() throws {
        let value = try XCTUnwrap(PlayRouteMapPresentation(snapshot: snapshot(#"[{"nodeId":9,"done":true,"latitude":"31.1","longitude":"121.1"},{"nodeId":2,"done":false,"latitude":"31.2","longitude":"121.2"}]"#)))
        XCTAssertEqual(value.stops.map(\.id), [9, 2]); XCTAssertEqual(value.segments.first?.id, 9)
        XCTAssertEqual(value.segments.first?.end.latitude, 31.2)
    }
}
