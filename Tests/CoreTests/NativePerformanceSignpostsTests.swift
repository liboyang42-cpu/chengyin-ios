import XCTest
@testable import QuestifyCore

/// The measurement script and handoff checklist depend on these exact names.
/// Instruments capture itself needs a real device; this only freezes the catalog.
final class NativePerformanceSignpostsTests: XCTestCase {
    func testCatalogNamesAreFrozenUniqueAndCoverEveryHotPath() {
        XCTAssertEqual(NativePerformancePoint.allCases.map(\.rawValue), [
            "walking.refreshTick", "walking.cameraFit", "playRoute.mapProjection",
            "playRoute.cameraFocus", "image.artworkLoad", "audio.startToPlaying"])
        XCTAssertEqual(Set(NativePerformancePoint.allCases.map(\.rawValue)).count, NativePerformancePoint.allCases.count)
        XCTAssertEqual(Set(NativePerformancePoint.allCases.map(\.area)), Set(NativePerformancePoint.Area.allCases))
        XCTAssertEqual(NativePerformanceSignposts.subsystem, "Questify.Performance")
    }

    func testStaticNamesMatchRawValuesAndCarryNoDynamicValues() {
        for point in NativePerformancePoint.allCases {
            XCTAssertEqual(point.signpostName.description, point.rawValue)
            XCTAssertNotNil(point.rawValue.range(of: #"^[a-z][A-Za-z]*\.[a-z][A-Za-z]*$"#, options: .regularExpression), point.rawValue)
        }
    }

    func testIntervalEndIsIdempotentForEveryLifecycleExit() {
        for signposts in [NativePerformanceSignposts(), NativePerformanceSignposts(enabled: false)] {
            let interval = signposts.begin(.audioStartToPlaying)
            XCTAssertTrue(interval.isOpen)
            interval.end(); XCTAssertFalse(interval.isOpen)
            interval.end(); XCTAssertFalse(interval.isOpen)
        }
    }

    func testMeasureReturnsBodyValueAndRethrows() {
        struct Failure: Error {}
        let signposts = NativePerformanceSignposts(enabled: false)
        XCTAssertEqual(signposts.measure(.playRouteMapProjection) { 41 + 1 }, 42)
        XCTAssertThrowsError(try signposts.measure(.walkingCameraFit) { throw Failure() })
    }
}
