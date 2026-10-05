import XCTest
@testable import QuestifyCore

final class RoamAreaInputTests: XCTestCase {
    func testEmptyInputNeverSelectsADefaultCoordinate() {
        XCTAssertThrowsError(try RoamSearchArea.manual(latitude: "", longitude: "")) {
            XCTAssertEqual($0 as? RoamAreaInputError, .missingLatitude)
        }
        XCTAssertThrowsError(try RoamSearchArea.manual(latitude: "1", longitude: "  ")) {
            XCTAssertEqual($0 as? RoamAreaInputError, .missingLongitude)
        }
    }
    func testManualAreaPreservesExplicitCoordinateAndTrimsLabel() throws {
        let area = try RoamSearchArea.manual(latitude: " -12.5 ", longitude: " 130.75 ", label: " Chosen area ")
        XCTAssertEqual(area.coordinate, RoamCoordinate(latitude: -12.5, longitude: 130.75))
        XCTAssertEqual(area.label, "Chosen area")
        let zero = try RoamSearchArea.manual(latitude: "0", longitude: "0")
        XCTAssertEqual(zero.coordinate, RoamCoordinate(latitude: 0, longitude: 0))
        XCTAssertEqual(zero.label, "")
    }
    func testLatitudeRejectsNonNumericNonFiniteAndOutOfBoundsValues() {
        for value in ["text", "NaN", "inf", "-91", "90.001", "1,2"] {
            XCTAssertThrowsError(try RoamSearchArea.manual(latitude: value, longitude: "1")) {
                XCTAssertEqual($0 as? RoamAreaInputError, .invalidLatitude)
            }
        }
    }
    func testLongitudeRejectsNonFiniteAndOutOfBoundsButAcceptsEdges() throws {
        for value in ["text", "NaN", "inf", "-181", "180.001"] {
            XCTAssertThrowsError(try RoamSearchArea.manual(latitude: "1", longitude: value)) {
                XCTAssertEqual($0 as? RoamAreaInputError, .invalidLongitude)
            }
        }
        XCTAssertNotNil(try RoamSearchArea.manual(latitude: "90", longitude: "180"))
        XCTAssertNotNil(try RoamSearchArea.manual(latitude: "-90", longitude: "-180"))
    }
}
