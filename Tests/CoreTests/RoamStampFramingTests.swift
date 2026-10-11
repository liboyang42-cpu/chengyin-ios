import XCTest
@testable import QuestifyCore

final class RoamStampFramingTests: XCTestCase {
    func testSourceRatioContractAndClamps() {
        var state = RoamStampFramingState()
        XCTAssertEqual(state.ratio, 0.74)
        state.adjust(to: -10); XCTAssertEqual(state.ratio, 0.4)
        state.adjust(to: 10); XCTAssertEqual(state.ratio, 0.9)
    }
    func testNonFiniteGestureCannotChangeFraming() {
        var state = RoamStampFramingState()
        for value in [Double.nan, .infinity, -.infinity] { state.adjust(to: value); XCTAssertEqual(state.ratio, 0.74) }
    }
    func testFrameIsCenteredFourByFiveInsidePreview() throws {
        let frame = try RoamStampFrame(viewportWidth: 400, viewportHeight: 500, ratio: 0.74)
        XCTAssertEqual(frame.x, 52, accuracy: 0.00001); XCTAssertEqual(frame.y, 65, accuracy: 0.00001)
        XCTAssertEqual(frame.width, 296, accuracy: 0.00001); XCTAssertEqual(frame.height, 370, accuracy: 0.00001)
    }
    func testShortWidePreviewStillFits() throws {
        let frame = try RoamStampFrame(viewportWidth: 800, viewportHeight: 400, ratio: 0.9)
        XCTAssertEqual(frame.width, 288, accuracy: 0.00001); XCTAssertEqual(frame.height, 360, accuracy: 0.00001)
        XCTAssertGreaterThanOrEqual(frame.x, 0); XCTAssertGreaterThanOrEqual(frame.y, 0)
    }
    func testPortraitAspectFillMatchesVisibleViewport() throws {
        let crop = try RoamStampFrame(viewportWidth: 400, viewportHeight: 500, ratio: 0.74).crop(imageWidth: 3000, imageHeight: 4000)
        XCTAssertEqual(crop.x, 390, accuracy: 0.00001); XCTAssertEqual(crop.y, 612.5, accuracy: 0.00001)
        XCTAssertEqual(crop.width, 2220, accuracy: 0.00001); XCTAssertEqual(crop.height, 2775, accuracy: 0.00001)
        XCTAssertEqual(crop.outputWidth, 1600); XCTAssertEqual(crop.outputHeight, 2000)
    }
    func testLandscapeImageAspectFillIsNotSimpleCenterCrop() throws {
        let crop = try RoamStampFrame(viewportWidth: 400, viewportHeight: 500, ratio: 0.74).crop(imageWidth: 4000, imageHeight: 3000)
        XCTAssertEqual(crop.width, 1776, accuracy: 0.00001); XCTAssertEqual(crop.height, 2220, accuracy: 0.00001)
        XCTAssertEqual(crop.x + crop.width / 2, 2000, accuracy: 0.00001)
        XCTAssertEqual(crop.y + crop.height / 2, 1500, accuracy: 0.00001)
    }
    func testSmallerFrameActuallyNarrowsCapturedRegion() throws {
        let small = try RoamStampFrame(viewportWidth: 400, viewportHeight: 500, ratio: 0.4).crop(imageWidth: 3000, imageHeight: 4000)
        let large = try RoamStampFrame(viewportWidth: 400, viewportHeight: 500, ratio: 0.9).crop(imageWidth: 3000, imageHeight: 4000)
        XCTAssertLessThan(small.width, large.width); XCTAssertGreaterThan(small.x, large.x)
        XCTAssertEqual(small.outputWidth, 1200); XCTAssertEqual(small.outputHeight, 1500)
    }
    func testFractionalViewportNeverStretchesOutput() throws {
        let crop = try RoamStampFrame(viewportWidth: 367.5, viewportHeight: 459.375, ratio: 0.743).crop(imageWidth: 1333, imageHeight: 1777)
        XCTAssertEqual(crop.outputWidth * 5, crop.outputHeight * 4)
        XCTAssertEqual(crop.width * 5, crop.height * 4, accuracy: 0.00001)
        XCTAssertLessThanOrEqual(Double(crop.outputWidth), crop.width)
    }
    func testInvalidViewportRejectedWithoutPendingShot() {
        for value in [0.0, -1, .nan, .infinity, 30_001] {
            var state = RoamStampFramingState()
            XCTAssertThrowsError(try state.begin(viewportWidth: value, viewportHeight: 500)); XCTAssertNil(state.pending)
            XCTAssertThrowsError(try state.begin(viewportWidth: 400, viewportHeight: value)); XCTAssertNil(state.pending)
        }
    }
    func testInvalidDirectRatioRejected() {
        for value in [0.0, 0.39, 0.91, .nan, .infinity] {
            XCTAssertThrowsError(try RoamStampFrame(viewportWidth: 400, viewportHeight: 500, ratio: value))
        }
    }
    func testTinyFrameFailsClosed() {
        XCTAssertThrowsError(try RoamStampFrame(viewportWidth: 4, viewportHeight: 5, ratio: 0.4))
    }
    func testInvalidPhotoDimensionsFailClosed() throws {
        let frame = try RoamStampFrame(viewportWidth: 400, viewportHeight: 500, ratio: 0.74)
        for value in [0.0, -1, .leastNonzeroMagnitude, .nan, .infinity, 30_001] {
            XCTAssertThrowsError(try frame.crop(imageWidth: value, imageHeight: 4000))
            XCTAssertThrowsError(try frame.crop(imageWidth: 3000, imageHeight: value))
        }
        XCTAssertThrowsError(try frame.crop(imageWidth: 30_000, imageHeight: 30_000))
    }
    func testTinyPhotoCannotBeUpscaled() throws {
        let frame = try RoamStampFrame(viewportWidth: 400, viewportHeight: 500, ratio: 0.74)
        XCTAssertThrowsError(try frame.crop(imageWidth: 4, imageHeight: 5))
    }
    func testCropStaysInsideSensorAcrossAspectRatios() throws {
        for viewport in [(320.0, 400.0), (800, 240), (240, 800)] {
            for image in [(3000.0, 4000.0), (4000, 3000), (2000, 2000)] {
                for ratio in [0.4, 0.74, 0.9] {
                    let crop = try RoamStampFrame(viewportWidth: viewport.0, viewportHeight: viewport.1, ratio: ratio).crop(imageWidth: image.0, imageHeight: image.1)
                    XCTAssertGreaterThanOrEqual(crop.x, 0); XCTAssertGreaterThanOrEqual(crop.y, 0)
                    XCTAssertLessThanOrEqual(crop.x + crop.width, image.0 + 0.00001)
                    XCTAssertLessThanOrEqual(crop.y + crop.height, image.1 + 0.00001)
                    XCTAssertEqual(crop.outputWidth * 5, crop.outputHeight * 4)
                    XCTAssertLessThanOrEqual(crop.outputWidth, 1600)
                }
            }
        }
    }
    func testShutterFreezesExactViewportAndRatio() throws {
        var state = RoamStampFramingState(); state.adjust(to: 0.55)
        let shot = try XCTUnwrap(state.begin(viewportWidth: 320, viewportHeight: 400))
        state.adjust(to: 0.9)
        XCTAssertEqual(shot.ratio, 0.55); XCTAssertEqual(state.ratio, 0.55)
        XCTAssertEqual(state.pending?.frame.viewportWidth, 320)
    }
    func testRepeatedShutterCannotStartSecondCapture() throws {
        var state = RoamStampFramingState()
        let first = try XCTUnwrap(state.begin(viewportWidth: 320, viewportHeight: 400))
        XCTAssertNil(try state.begin(viewportWidth: 800, viewportHeight: 400)); XCTAssertEqual(state.pending, first)
    }
    func testForeignCompletionDoesNotConsumePending() throws {
        var state = RoamStampFramingState(); let shot = try XCTUnwrap(state.begin(viewportWidth: 320, viewportHeight: 400))
        XCTAssertFalse(state.resolve(UUID(), succeeded: true)); XCTAssertEqual(state.pending, shot); XCTAssertTrue(state.isActive)
    }
    func testFailedCaptureCanAdjustAndRetryWithNewIdentity() throws {
        var state = RoamStampFramingState(); let first = try XCTUnwrap(state.begin(viewportWidth: 320, viewportHeight: 400))
        XCTAssertTrue(state.resolve(first.id, succeeded: false)); state.adjust(to: 0.5)
        let retry = try XCTUnwrap(state.begin(viewportWidth: 400, viewportHeight: 500))
        XCTAssertNotEqual(retry.id, first.id); XCTAssertEqual(retry.ratio, 0.5)
        XCTAssertFalse(state.resolve(first.id, succeeded: true)); XCTAssertEqual(state.pending, retry)
    }
    func testSuccessfulCaptureIsSingleUse() throws {
        var state = RoamStampFramingState(); let shot = try XCTUnwrap(state.begin(viewportWidth: 320, viewportHeight: 400))
        XCTAssertTrue(state.resolve(shot.id, succeeded: true)); XCTAssertFalse(state.isActive); XCTAssertNil(state.pending)
        XCTAssertFalse(state.resolve(shot.id, succeeded: true)); XCTAssertNil(try state.begin(viewportWidth: 320, viewportHeight: 400))
    }
    func testCancelOrBackgroundRejectsLateBytes() throws {
        var state = RoamStampFramingState(); let shot = try XCTUnwrap(state.begin(viewportWidth: 320, viewportHeight: 400))
        state.cancel(); XCTAssertFalse(state.resolve(shot.id, succeeded: true)); XCTAssertFalse(state.isActive)
        state.adjust(to: 0.9); XCTAssertEqual(state.ratio, 0.74)
    }
    func testRetakeStartsFreshStateCannotConsumeOldPhoto() throws {
        var old = RoamStampFramingState(); let shot = try XCTUnwrap(old.begin(viewportWidth: 320, viewportHeight: 400)); old.cancel()
        var next = RoamStampFramingState(); XCTAssertEqual(next.ratio, 0.74)
        _ = try XCTUnwrap(next.begin(viewportWidth: 320, viewportHeight: 400))
        XCTAssertFalse(next.resolve(shot.id, succeeded: true)); XCTAssertNotNil(next.pending)
    }
}
