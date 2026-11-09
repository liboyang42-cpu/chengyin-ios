import XCTest
@testable import QuestifyCore

/// qx-u4 gesture maths. Thresholds match the mini-program lane qx-u1.
final class QuestoGestureMathTests: XCTestCase {
    private let bounds = (minX: 16.0, minY: 16.0, maxX: 374.0, maxY: 784.0)
    private let item = (width: 64.0, height: 64.0)

    func testSheetSizesAreTheBriefsPeekHalfFull() {
        XCTAssertEqual(QuestoSheetSize.allCases.map(\.fraction), [0.3, 0.6, 0.8])
    }

    func testRubberBandResistsOvershootByAQuarterAndReducedMotionClampsHard() {
        XCTAssertEqual(QuestoRubberBand.clamp(50, to: 0...100), 50)
        XCTAssertEqual(QuestoRubberBand.clamp(140, to: 0...100), 110)
        XCTAssertEqual(QuestoRubberBand.clamp(-40, to: 0...100), -10)
        XCTAssertEqual(QuestoRubberBand.clamp(140, to: 0...100, reduceMotion: true), 100)
        XCTAssertEqual(QuestoRubberBand.clamp(-40, to: 0...100, reduceMotion: true), 0)
    }

    func testCornerCentresStayInsideTheSafeBounds() {
        let c = QuestoCornerSnap.center(of: .topLeading, item: item, bounds: bounds)
        XCTAssertEqual(c.x, 48); XCTAssertEqual(c.y, 48)
        let d = QuestoCornerSnap.center(of: .bottomTrailing, item: item, bounds: bounds)
        XCTAssertEqual(d.x, 342); XCTAssertEqual(d.y, 752)
    }

    func testSlowReleaseSnapsToTheNearestCorner() {
        XCTAssertEqual(QuestoCornerSnap.target(position: (x: 100, y: 120), velocity: (x: 0, y: 0), item: item, bounds: bounds), .topLeading)
        XCTAssertEqual(QuestoCornerSnap.target(position: (x: 300, y: 700), velocity: (x: 0, y: 0), item: item, bounds: bounds), .bottomTrailing)
    }

    func testFlingCarriesMomentumToTheFarCorner() {
        // Released near the top-left but flung down and right: momentum decides, like iOS PiP.
        XCTAssertEqual(QuestoCornerSnap.target(position: (x: 120, y: 160), velocity: (x: 900, y: 1600), item: item, bounds: bounds), .bottomTrailing)
        XCTAssertEqual(QuestoCornerSnap.projection(velocity: 0), 0)
        XCTAssertEqual(QuestoCornerSnap.projection(velocity: 1000), 499, accuracy: 0.5)
    }
}
