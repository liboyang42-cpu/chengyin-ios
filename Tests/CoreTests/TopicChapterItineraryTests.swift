import XCTest
@testable import QuestifyCore

final class TopicChapterItineraryTests: XCTestCase {
    private func chapter(_ nodes: String) throws -> TopicChapter {
        try JSONDecoder().decode(TopicChapter.self, from: Data("{\"id\":1,\"nodes\":[\(nodes)]}".utf8))
    }
    private func projection(_ nodes: String) throws -> TopicChapterItinerary {
        TopicChapterItinerary(chapter: try chapter(nodes))
    }
    private func node(_ fields: String = "", id: Int = 1) -> String {
        "{\"id\":\(id)\(fields.isEmpty ? "" : "," + fields)}"
    }
    private let origin = #""latitude":1,"longitude":1"#

    func testNumericAndStringCoordinatesUseSameEstimateAndKeepSourceOrder() throws {
        let value = try projection([
            node(origin, id: 9),
            node(#""latitude":" 1.001 ","longitude":"1""#, id: 3),
            node(#""latitude":1.002,"longitude":1"#, id: 9)
        ].joined(separator: ","))
        XCTAssertEqual(value.stops.map(\.id), [0, 1, 2])
        XCTAssertEqual(value.stops.map(\.node.id), [9, 3, 9])
        XCTAssertEqual(value.stops.map(\.estimatedWalkingMinutes), [nil, 1, 1])
        XCTAssertTrue(value.hasWalkingEstimates)
    }

    func testOnlyImmediatePredecessorCanSupplyAnEstimate() throws {
        let value = try projection([
            node(origin), node(), node(#""latitude":1.002,"longitude":1"#),
            node(#""latitude":1.003,"longitude":1"#)
        ].joined(separator: ","))
        XCTAssertEqual(value.stops.map(\.estimatedWalkingMinutes), [nil, nil, nil, 1])
    }

    func testFirstStopEmptyChapterAndSeparateChaptersHaveNoInventedLeg() throws {
        let empty = try projection("")
        XCTAssertTrue(empty.stops.isEmpty)
        XCTAssertFalse(empty.hasWalkingEstimates)
        for fields in [origin, #""latitude":1.001,"longitude":1"#] {
            let value = try projection(node(fields))
            XCTAssertEqual(value.stops.count, 1)
            XCTAssertNil(value.stops[0].estimatedWalkingMinutes)
            XCTAssertFalse(value.hasWalkingEstimates)
        }
    }

    func testMissingMalformedZeroAndOutOfRangeCoordinatesOmitBothAdjacentLegs() throws {
        let invalid = ["", #""latitude":null,"longitude":1"#, #""latitude":1"#,
                       #""latitude":"","longitude":1"#, #""latitude":"not-a-coordinate","longitude":1"#,
                       #""latitude":"NaN","longitude":1"#, #""latitude":1,"longitude":"inf""#,
                       #""latitude":true,"longitude":1"#, #""latitude":[],"longitude":1"#,
                       #""latitude":0,"longitude":1"#, #""latitude":1,"longitude":0"#,
                       #""latitude":91,"longitude":1"#, #""latitude":-91,"longitude":1"#,
                       #""latitude":1,"longitude":181"#, #""latitude":1,"longitude":-181"#]
        for fields in invalid {
            let value = try projection([node(origin), node(fields), node(origin)].joined(separator: ","))
            XCTAssertEqual(value.stops.map(\.estimatedWalkingMinutes), [nil, nil, nil], fields)
            XCTAssertFalse(value.hasWalkingEstimates, fields)
        }
    }

    func testIdenticalLocationsHaveNoArtificialOneMinuteWalk() throws {
        let value = try projection([node(origin), node(origin)].joined(separator: ","))
        XCTAssertEqual(value.stops.map(\.estimatedWalkingMinutes), [nil, nil])
    }

    func testNearestMinuteRoundingAndMinimumOneMinute() throws {
        for (meters, expected) in [(1.0, 1), (119.9, 1), (120.1, 2), (800.0, 10)] {
            let latitude = 1 + meters / 6_371_000 * 180 / Double.pi
            let value = try projection(node(origin) + "," + node("\"latitude\":\(latitude),\"longitude\":1"))
            XCTAssertEqual(value.stops[1].estimatedWalkingMinutes, expected)
        }
    }

    func testDwellChapterAndChallengeDurationsDoNotBecomeWalkingTime() throws {
        let fields = #""latitude":1.001,"longitude":1,"nodeTime":240,"totalTime":3600,"cmsMemberTemplate":{"id":1,"duration":120}"#
        let value = try projection(node(origin) + "," + node(fields))
        XCTAssertEqual(value.stops[1].estimatedWalkingMinutes, 1)
        let missingCoordinates = try projection(node(origin) + "," + node(#""nodeTime":240,"totalTime":3600"#))
        XCTAssertNil(missingCoordinates.stops[1].estimatedWalkingMinutes)
    }

    func testAntimeridianUsesShortDistanceAndAntipodesRemainFinite() throws {
        let nearby = try projection(node(#""latitude":1,"longitude":179.999"#) + "," + node(#""latitude":1,"longitude":-179.999"#))
        XCTAssertEqual(nearby.stops[1].estimatedWalkingMinutes, 3)
        let distant = try projection(node(origin) + "," + node(#""latitude":-1,"longitude":-179"#))
        XCTAssertEqual(distant.stops[1].estimatedWalkingMinutes, 250189)
    }
}
