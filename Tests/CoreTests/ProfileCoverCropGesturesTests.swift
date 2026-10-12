import XCTest
@testable import QuestifyCore

final class ProfileCoverCropGesturesTests: XCTestCase {
    private func rect(_ p: ProfileCoverCropPosition, _ w: Int = 1600, _ h: Int = 900) throws -> MerchantImageCropRect {
        try p.rect(sourceWidth: w, sourceHeight: h)
    }
    func testDefaultIsExistingCenteredSixteenByNine() throws {
        let actual = try rect(.init(), 900, 1600)
        let old = try MerchantImageCropRect(sourceWidth: 900, sourceHeight: 1600, aspect: .gallery)
        XCTAssertEqual(actual, old)
    }
    func testPanMovesImageOppositeCropOrigin() throws {
        let p = ProfileCoverCropPosition(zoom: 2)
        let moved = try p.panned(deltaX: 40, deltaY: -20, viewportWidth: 320, viewportHeight: 180, sourceWidth: 1600, sourceHeight: 900)
        let before = try rect(p), after = try rect(moved)
        XCTAssertEqual(after.x, before.x - 100); XCTAssertEqual(after.y, before.y + 50)
        XCTAssertEqual(after.width, before.width); XCTAssertEqual(moved.zoom, 2)
    }
    func testPanClampsBothEdgesWithoutChangingAspect() throws {
        let p = ProfileCoverCropPosition(zoom: 2)
        let a = try p.panned(deltaX: 100_000, deltaY: 100_000, viewportWidth: 320, viewportHeight: 180, sourceWidth: 1600, sourceHeight: 900)
        let b = try p.panned(deltaX: -100_000, deltaY: -100_000, viewportWidth: 320, viewportHeight: 180, sourceWidth: 1600, sourceHeight: 900)
        XCTAssertEqual(a.horizontal, 0); XCTAssertEqual(a.vertical, 0)
        let r = try rect(b); XCTAssertEqual(r.x + r.width, 1600); XCTAssertEqual(r.y + r.height, 900)
        XCTAssertEqual(r.width * 9, r.height * 16)
    }
    func testNoTravelAxisStaysCenteredAndFinite() throws {
        let p = try ProfileCoverCropPosition().panned(deltaX: 100, deltaY: 100, viewportWidth: 320, viewportHeight: 180, sourceWidth: 1600, sourceHeight: 900)
        XCTAssertEqual(p.horizontal, 0.5); XCTAssertEqual(p.vertical, 0.5)
        XCTAssertEqual(try rect(p).x, 0); XCTAssertEqual(try rect(p).y, 0)
    }
    func testTinyIncrementalPanAccumulatesInsteadOfRoundingAway() throws {
        var p = ProfileCoverCropPosition(zoom: 2)
        for _ in 0..<100 { p = try p.panned(deltaX: 0.01, deltaY: 0, viewportWidth: 320, viewportHeight: 180, sourceWidth: 1600, sourceHeight: 900) }
        XCTAssertLessThan(p.horizontal, 0.5)
        XCTAssertEqual(p.horizontal, 0.5 - 2.5 / 800, accuracy: 0.000001)
    }
    func testPinchKeepsSourceCenterUntilAnEdgeIsReached() throws {
        let p = ProfileCoverCropPosition(horizontal: 0.25, vertical: 0.75, zoom: 2)
        let next = try p.pinched(by: 1.5, sourceWidth: 1600, sourceHeight: 900)
        let a = try rect(p), b = try rect(next)
        XCTAssertEqual(Double(a.x) + Double(a.width) / 2, Double(b.x) + Double(b.width) / 2, accuracy: 1)
        XCTAssertEqual(Double(a.y) + Double(a.height) / 2, Double(b.y) + Double(b.height) / 2, accuracy: 1)
        XCTAssertEqual(next.zoom, 3)
    }
    func testPinchLimitsMatchExistingSliderRange() throws {
        let p = ProfileCoverCropPosition(zoom: 2)
        XCTAssertEqual(try p.pinched(by: 100, sourceWidth: 1600, sourceHeight: 900).zoom, 4)
        XCTAssertEqual(try p.pinched(by: 0.0001, sourceWidth: 1600, sourceHeight: 900).zoom, 1)
    }
    func testPanThenPinchThenSliderUsesOneGeometry() throws {
        var p = try ProfileCoverCropPosition(zoom: 2).panned(deltaX: -24, deltaY: 8, viewportWidth: 320, viewportHeight: 180, sourceWidth: 1600, sourceHeight: 900)
        p = try p.pinched(by: 1.2, sourceWidth: 1600, sourceHeight: 900)
        p.horizontal = 1; p.vertical = 0
        let r = try rect(p)
        XCTAssertEqual(r.x + r.width, 1600); XCTAssertEqual(r.y, 0)
        XCTAssertEqual(r, try MerchantImageCropRect(sourceWidth: 1600, sourceHeight: 900, aspect: .gallery, horizontal: p.horizontal, vertical: p.vertical, zoom: p.zoom))
    }
    func testInvalidGestureNumbersRejected() {
        let p = ProfileCoverCropPosition()
        for bad in [Double.nan, .infinity, -.infinity] {
            XCTAssertThrowsError(try p.panned(deltaX: bad, deltaY: 0, viewportWidth: 320, viewportHeight: 180, sourceWidth: 1600, sourceHeight: 900))
            XCTAssertThrowsError(try p.panned(deltaX: 0, deltaY: bad, viewportWidth: 320, viewportHeight: 180, sourceWidth: 1600, sourceHeight: 900))
            XCTAssertThrowsError(try p.pinched(by: bad, sourceWidth: 1600, sourceHeight: 900))
        }
        for bad in [0.0, -1.0] { XCTAssertThrowsError(try p.pinched(by: bad, sourceWidth: 1600, sourceHeight: 900)) }
    }
    func testInvalidViewportRejected() {
        for bad in [0.0, -1, Double.nan, .infinity] {
            XCTAssertThrowsError(try ProfileCoverCropPosition().panned(deltaX: 1, deltaY: 1, viewportWidth: bad, viewportHeight: 180, sourceWidth: 1600, sourceHeight: 900))
            XCTAssertThrowsError(try ProfileCoverCropPosition().panned(deltaX: 1, deltaY: 1, viewportWidth: 320, viewportHeight: bad, sourceWidth: 1600, sourceHeight: 900))
        }
    }
    func testInvalidSourceAndExistingPositionRejected() {
        for (w, h) in [(0, 900), (1600, 0), (4097, 900), (15, 8)] { XCTAssertThrowsError(try rect(.init(), w, h)) }
        for p in [ProfileCoverCropPosition(horizontal: -.infinity), .init(vertical: 2), .init(zoom: 0), .init(zoom: .nan)] { XCTAssertThrowsError(try rect(p)) }
    }
    func testExtremeFiniteValuesCannotOverflowExportGeometry() {
        let p = ProfileCoverCropPosition(zoom: 2)
        XCTAssertThrowsError(try p.panned(deltaX: Double.greatestFiniteMagnitude, deltaY: 0, viewportWidth: 0.00001, viewportHeight: 180, sourceWidth: 1600, sourceHeight: 900))
        XCTAssertThrowsError(try p.pinched(by: Double.greatestFiniteMagnitude, sourceWidth: 1600, sourceHeight: 900))
    }
    func testPortraitAndLandscapeStayInsideSourceForGestureSequence() throws {
        for (w, h) in [(4096, 4096), (900, 1600), (1600, 900), (31, 19)] {
            var p = ProfileCoverCropPosition()
            for i in 0..<100 {
                p = try p.pinched(by: i % 2 == 0 ? 1.07 : 0.98, sourceWidth: w, sourceHeight: h)
                p = try p.panned(deltaX: Double(i % 11 - 5), deltaY: Double(i % 7 - 3), viewportWidth: 320, viewportHeight: 180, sourceWidth: w, sourceHeight: h)
                let r = try rect(p, w, h)
                XCTAssertGreaterThanOrEqual(r.x, 0); XCTAssertGreaterThanOrEqual(r.y, 0)
                XCTAssertLessThanOrEqual(r.x + r.width, w); XCTAssertLessThanOrEqual(r.y + r.height, h)
                XCTAssertEqual(r.width * 9, r.height * 16)
            }
        }
    }
}
