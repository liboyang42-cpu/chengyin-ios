import Foundation
import XCTest
@testable import Questify

final class PlayRouteMapMenuLabelsTests: XCTestCase {
    private func presentation(_ nodes: String) throws -> PlayRouteMapPresentation {
        let data = Data("{\"mode\":1,\"playable\":true,\"registered\":true,\"nodes\":\(nodes)}".utf8)
        let result = try JSONDecoder().decode(PlayNodesResult.self, from: data)
        return try XCTUnwrap(PlayRouteMapPresentation(snapshot: PlaySnapshot(scope: .activity(41), result: result)))
    }
    func testDuplicateNamesUseExistingSnapshotOrderNotNodeID() throws {
        let value = try presentation(#"[{"nodeId":90,"name":"Gate","done":true},{"nodeId":12,"name":"Square","done":false},{"nodeId":3,"name":"Gate","done":false}]"#)
        let labels = PlayRouteMapMenuLabels(presentation: value)
        XCTAssertEqual(labels.ordinal(for: 90), 1); XCTAssertEqual(labels.ordinal(for: 3), 3)
        XCTAssertNil(labels.ordinal(for: 12))
        XCTAssertEqual(value.stops.map(\.id), [90, 12, 3]); XCTAssertEqual(value.stops.map(\.name), ["Gate", "Square", "Gate"])
        XCTAssertTrue(value.mappedStops.isEmpty, "No coordinates are needed or inferred")
    }
    func testUnnamedAndWhitespaceEquivalentNamesCanBeDistinguished() throws {
        let value = try presentation(#"[{"nodeId":1,"done":true},{"nodeId":2,"name":"  ","done":false},{"nodeId":3,"name":"Gate","done":false},{"nodeId":4,"name":" Gate ","done":false}]"#)
        let labels = PlayRouteMapMenuLabels(presentation: value)
        for index in 1...4 { XCTAssertEqual(labels.ordinal(for: index), index) }
        XCTAssertEqual(value.stops.last?.name, " Gate ", "Display names are not rewritten")
    }
    func testLockedAndHiddenRowsDoNotCreateMenuDuplicates() throws {
        let value = try presentation(#"[{"nodeId":1,"name":"Gate","done":false},{"nodeId":2,"name":"Gate","locked":true,"done":false},{"nodeId":3,"name":"Gate","routeNodeState":"HIDDEN","done":false}]"#)
        let labels = PlayRouteMapMenuLabels(presentation: value)
        XCTAssertNil(labels.ordinal(for: 1)); XCTAssertNil(labels.ordinal(for: 2)); XCTAssertNil(labels.ordinal(for: 3))
        XCTAssertEqual(value.stops.map(\.id), [1, 2]); XCTAssertNil(value.stops.last?.name)
    }
    func testNewSnapshotRecomputesOrderAndUniqueNameNeedsNoPrefix() throws {
        let first = try presentation(#"[{"nodeId":4,"name":"门","done":true},{"nodeId":8,"name":"门","done":false}]"#)
        let second = try presentation(#"[{"nodeId":8,"name":"门","done":false},{"nodeId":4,"name":"门","done":true}]"#)
        XCTAssertEqual(PlayRouteMapMenuLabels(presentation: first).ordinal(for: 8), 2)
        XCTAssertEqual(PlayRouteMapMenuLabels(presentation: second).ordinal(for: 8), 1)
        let unique = try presentation(#"[{"nodeId":8,"name":"门😀","done":false}]"#)
        XCTAssertNil(PlayRouteMapMenuLabels(presentation: unique).ordinal(for: 8))
        XCTAssertEqual(unique.stops.first?.name, "门😀")
    }
}
