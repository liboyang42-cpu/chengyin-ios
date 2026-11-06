import XCTest
@testable import QuestifyCore

final class MiniCropGeometryTests: XCTestCase {
    func testRatioParsingMatchesMini() {
        XCTAssertEqual(MiniCropGeometry.ratio("16:9")!, 16.0 / 9.0, accuracy: 1e-9)
        XCTAssertEqual(MiniCropGeometry.ratio(" 3:4 ")!, 0.75, accuracy: 1e-9)
        for invalid in ["free", "0:1", "1:0", "a:b", "1:2:3", "", "-1:2"] { XCTAssertNil(MiniCropGeometry.ratio(invalid), invalid) }
        XCTAssertNil(MiniCropGeometry.ratio(nil))
        XCTAssertEqual(MiniCropGeometry.presets.compactMap(MiniCropGeometry.ratio).count, 7)
    }

    func testFrameFitsWidthThenHeight() {
        let wide = MiniCropGeometry.frame(ratio: "16:9", imageWidth: 100, imageHeight: 100, availableWidth: 320, availableHeight: 400)!
        XCTAssertEqual(wide.width, 320); XCTAssertEqual(wide.height, 180, accuracy: 1e-9)
        let tall = MiniCropGeometry.frame(ratio: "9:16", imageWidth: 100, imageHeight: 100, availableWidth: 320, availableHeight: 400)!
        XCTAssertEqual(tall.height, 400); XCTAssertEqual(tall.width, 225, accuracy: 1e-9)
        let free = MiniCropGeometry.frame(ratio: "free", imageWidth: 200, imageHeight: 100, availableWidth: 300, availableHeight: 300)!
        XCTAssertEqual(free.height, 150, accuracy: 1e-9)
    }

    func testClampKeepsFrameCovered() {
        let t = MiniCropGeometry.clamp(scale: 9, x: 1000, y: -1000, imageWidth: 200, imageHeight: 100, frameWidth: 100, frameHeight: 100)
        XCTAssertEqual(t.scale, 4)
        XCTAssertEqual(t.x, 350); XCTAssertEqual(t.y, -150)
        XCTAssertEqual(MiniCropGeometry.clamp(scale: 0.2, x: 0, y: 0, imageWidth: 200, imageHeight: 100, frameWidth: 100, frameHeight: 100).scale, 1)
    }

    func testCropRectCentersAndPans() {
        let centered = MiniCropGeometry.cropRect(scale: 1, x: 0, y: 0, imageWidth: 200, imageHeight: 100, frameWidth: 100, frameHeight: 100)!
        XCTAssertEqual(centered, .init(x: 50, y: 0, width: 100, height: 100))
        let left = MiniCropGeometry.cropRect(scale: 1, x: 999, y: 0, imageWidth: 200, imageHeight: 100, frameWidth: 100, frameHeight: 100)!
        XCTAssertEqual(left.x, 0)
        let zoomed = MiniCropGeometry.cropRect(scale: 2, x: 0, y: 0, imageWidth: 200, imageHeight: 100, frameWidth: 100, frameHeight: 100)!
        XCTAssertEqual(zoomed, .init(x: 75, y: 25, width: 50, height: 50))
        XCTAssertNil(MiniCropGeometry.cropRect(scale: 1, x: 0, y: 0, imageWidth: 0, imageHeight: 100, frameWidth: 100, frameHeight: 100))
    }

    func testOriginalShortcutOnlyForUntouchedFreeCrop() {
        XCTAssertTrue(MiniCropGeometry.keepsOriginal(ratio: "free", scale: 1, x: 0, y: 0))
        XCTAssertFalse(MiniCropGeometry.keepsOriginal(ratio: "1:1", scale: 1, x: 0, y: 0))
        XCTAssertFalse(MiniCropGeometry.keepsOriginal(ratio: "free", scale: 1.5, x: 0, y: 0))
    }
}
