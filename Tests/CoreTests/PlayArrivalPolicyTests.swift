import XCTest
@testable import QuestifyCore

/// Table-driven against the shared arrival contract fixture (mirrors hengyin
/// docs/contracts/arrival-policy.v2.json). Every case must hold in all three clients.
final class PlayArrivalPolicyTests: XCTestCase {
    private func contract() throws -> [String: Any] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Fixtures/ArrivalPolicy/arrival-policy.v2.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }

    func testFixtureIsVersionTwoWithCases() throws {
        let json = try contract()
        XCTAssertEqual(json["contract"] as? String, "arrival-policy")
        XCTAssertEqual(json["version"] as? Int, 2)
        XCTAssertGreaterThanOrEqual((json["cases"] as? [[String: Any]])?.count ?? 0, 19)
    }

    func testConstantsMatchContract() throws {
        let json = try contract()
        let start = try XCTUnwrap(json["start"] as? [String: Any])
        XCTAssertEqual(number(start["radiusMeters"]), PlayArrivalPolicy.startRadiusMeters)
        XCTAssertEqual(number(start["maxRelaxMeters"]), PlayArrivalPolicy.startMaxRelaxMeters)
        XCTAssertEqual(number(start["maxAccuracyMeters"]), PlayArrivalPolicy.startMaxAccuracyMeters)
        let visit = try XCTUnwrap(json["freeExploreVisit"] as? [String: Any])
        XCTAssertEqual(number(visit["defaultRadiusMeters"]), Double(PlayArrivalPolicy.visitDefaultRadiusMeters))
        XCTAssertEqual(number(visit["minRadiusMeters"]), Double(PlayArrivalPolicy.visitMinRadiusMeters))
        XCTAssertEqual(number(visit["maxRadiusMeters"]), Double(PlayArrivalPolicy.visitMaxRadiusMeters))
        XCTAssertEqual(number(visit["maxRelaxMeters"]), PlayArrivalPolicy.visitMaxRelaxMeters)
        XCTAssertEqual(number(visit["missingAccuracyMeters"]), PlayArrivalPolicy.visitMissingAccuracyMeters)
        XCTAssertEqual(number(visit["maxAccuracyMeters"]), PlayArrivalPolicy.visitMaxAccuracyMeters)
        XCTAssertEqual(number(json["stationHighlightMeters"]), PlayArrivalPolicy.stationHighlightMeters)
    }

    func testEveryContractCase() throws {
        let cases = try XCTUnwrap(try contract()["cases"] as? [[String: Any]])
        for (index, row) in cases.enumerated() {
            let kind = try XCTUnwrap(row["kind"] as? String), expect = try XCTUnwrap(row["expect"] as? String)
            let distance = try XCTUnwrap(number(row["distance"])), accuracy = number(row["accuracy"])
            let verdict: PlayArrivalVerdict
            switch kind {
            case "start": verdict = PlayArrivalPolicy.start(distanceMeters: distance, accuracyMeters: try XCTUnwrap(accuracy))
            case "visit": verdict = PlayArrivalPolicy.visit(distanceMeters: distance, accuracyMeters: accuracy, configuredRadiusMeters: number(row["radius"]).map { Int($0) })
            default: XCTFail("unknown kind \(kind) at case \(index)"); continue
            }
            XCTAssertEqual(verdict.rawValue, expect, "case \(index): \(row)")
        }
    }

    func testVisitRadiusClampAndDistanceRounding() {
        XCTAssertEqual(PlayArrivalPolicy.visitRadiusMeters(configured: nil), 300)
        XCTAssertEqual(PlayArrivalPolicy.visitRadiusMeters(configured: 100), 300)
        XCTAssertEqual(PlayArrivalPolicy.visitRadiusMeters(configured: 420), 420)
        XCTAssertEqual(PlayArrivalPolicy.visitRadiusMeters(configured: 900), 500)
        XCTAssertEqual(PlayArrivalPolicy.roundedDistanceMeters(337), 340)
        XCTAssertEqual(PlayArrivalPolicy.roundedDistanceMeters(334.9), 330)
        XCTAssertNil(PlayArrivalPolicy.roundedDistanceMeters(.nan))
        XCTAssertNil(PlayArrivalPolicy.roundedDistanceMeters(-1))
    }

    func testHaversineDistanceIsSymmetricAndPlausible() {
        let a = PlayArrivalPolicy.distanceMeters(latitude: 31.2304, longitude: 121.4737, toLatitude: 31.2334, toLongitude: 121.4737)
        let b = PlayArrivalPolicy.distanceMeters(latitude: 31.2334, longitude: 121.4737, toLatitude: 31.2304, toLongitude: 121.4737)
        XCTAssertEqual(a, b, accuracy: 0.001)
        XCTAssertEqual(a, 333.6, accuracy: 1.0)
        XCTAssertEqual(PlayArrivalPolicy.distanceMeters(latitude: 22.3, longitude: 114.17, toLatitude: 22.3, toLongitude: 114.17), 0, accuracy: 0.0001)
    }

    func testInvalidInputsNeverPass() {
        XCTAssertNotEqual(PlayArrivalPolicy.start(distanceMeters: .nan, accuracyMeters: 5), .pass)
        XCTAssertNotEqual(PlayArrivalPolicy.start(distanceMeters: 10, accuracyMeters: -1), .pass)
        XCTAssertNotEqual(PlayArrivalPolicy.visit(distanceMeters: .infinity, accuracyMeters: 5, configuredRadiusMeters: nil), .pass)
    }
}
