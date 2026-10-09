import XCTest
@testable import QuestifyCore

final class ProgressiveBlurParametersTests: XCTestCase {
    func testInvalidAndNonfiniteParametersDoNotBecomeAnEffect() {
        for pair in [(0.5, 0.5), (0.8, 0.2), (-0.1, 1), (0, 1.1), (.nan, 1), (0, .infinity)] {
            XCTAssertNil(ProgressiveBlurParameters(start: pair.0, end: pair.1, maxRadius: 16))
        }
        for radius in [-1.0, 33, .nan, .infinity] {
            XCTAssertNil(ProgressiveBlurParameters(start: 0.3, end: 0.9, maxRadius: radius))
        }
    }
    func testBothCurvesRemainClearBeforeStartAndReachMaximumAfterEnd() throws {
        for curve in [ProgressiveBlurParameters.Curve.linear, .smoothstep] {
            let value = try XCTUnwrap(ProgressiveBlurParameters(start: 0.3, end: 0.8, maxRadius: 16, curve: curve))
            XCTAssertEqual(value.intensity(at: 0), 0); XCTAssertEqual(value.intensity(at: 0.3), 0)
            XCTAssertEqual(value.intensity(at: 0.8), 1); XCTAssertEqual(value.intensity(at: 1), 1)
            var prior = 0.0
            for step in 0...1000 {
                let next = value.intensity(at: Double(step) / 1000)
                XCTAssertGreaterThanOrEqual(next, prior); XCTAssertLessThanOrEqual(next, 1); prior = next
            }
        }
    }
    func testZeroRadiusIsValidAndPixelsUseEffectiveOutputScale() throws {
        XCTAssertEqual(try XCTUnwrap(ProgressiveBlurParameters(start: 0, end: 1, maxRadius: 0)).maxRadius, 0)
        let regular = try XCTUnwrap(ProgressiveBlurOutput(pointWidth: 300, pointHeight: 200, scale: 3))
        XCTAssertEqual(regular.width, 900); XCTAssertEqual(regular.height, 600); XCTAssertEqual(regular.effectiveScale, 3)
        let large = try XCTUnwrap(ProgressiveBlurOutput(pointWidth: 4000, pointHeight: 4000, scale: 3))
        XCTAssertLessThanOrEqual(large.width * large.height, 2_000_000)
        XCTAssertLessThanOrEqual(max(large.width, large.height), 2048)
        XCTAssertLessThan(large.effectiveScale, large.requestedScale)
    }
    func testUnknownAndDegenerateGeometryDoesNotAllocatePixels() {
        for dimensions in [(0.0, 100.0, 2.0), (100, -1, 2), (.nan, 100, 2), (100, .infinity, 2), (100, 100, 0), (100, 100, 5), (10_001, 1, 1)] {
            XCTAssertNil(ProgressiveBlurOutput(pointWidth: dimensions.0, pointHeight: dimensions.1, scale: dimensions.2))
        }
    }
    func testParametersAndRequestedScaleParticipateInIdentity() throws {
        let a = try XCTUnwrap(ProgressiveBlurParameters(start: 0.3, end: 0.9, maxRadius: 16))
        let b = try XCTUnwrap(ProgressiveBlurParameters(start: 0.4, end: 0.9, maxRadius: 16))
        XCTAssertNotEqual(a, b)
        XCTAssertNotEqual(ProgressiveBlurOutput(pointWidth: 300, pointHeight: 200, scale: 2),
                          ProgressiveBlurOutput(pointWidth: 300, pointHeight: 200, scale: 3))
    }
}
