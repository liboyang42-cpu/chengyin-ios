import XCTest
@testable import QuestifyCore

final class TemplateImageCropTests: XCTestCase {
    func testIdentityPreservesFullSourceAndOriginalOutputDimensions() throws {
        for (w, h) in [(301, 199), (199, 301), (4096, 3071), (1, 1), (1, 4096)] {
            for position in [0.0, 0.5, 1.0] {
                let rect = try TemplateImageCropRect(sourceWidth: w, sourceHeight: h,
                    horizontal: position, vertical: position)
                XCTAssertTrue(rect.isIdentity)
                XCTAssertEqual(rect.x, 0); XCTAssertEqual(rect.y, 0)
                XCTAssertEqual(rect.width, Double(w)); XCTAssertEqual(rect.height, Double(h))
                XCTAssertEqual(rect.outputWidth, w); XCTAssertEqual(rect.outputHeight, h)
            }
        }
    }

    func testSourceAspectSurvivesCoprimeDimensionsAndFractionalZoom() throws {
        let rect = try TemplateImageCropRect(sourceWidth: 301, sourceHeight: 199, zoom: 2.2)
        XCTAssertFalse(rect.isIdentity)
        XCTAssertEqual(rect.width, 301 / 2.2, accuracy: 1e-12)
        XCTAssertEqual(rect.height, 199 / 2.2, accuracy: 1e-12)
        XCTAssertEqual(rect.width / rect.height, 301.0 / 199.0, accuracy: 1e-12)
        XCTAssertEqual(rect.outputWidth, 137); XCTAssertEqual(rect.outputHeight, 90)
    }

    func testLeadingCenterAndTrailingPanSelectAvailableTravel() throws {
        for (position, x, y) in [(0.0, 0.0, 0.0), (0.5, 75.0, 50.0), (1.0, 150.0, 100.0)] {
            let rect = try TemplateImageCropRect(sourceWidth: 300, sourceHeight: 200,
                horizontal: position, vertical: position, zoom: 2)
            XCTAssertEqual(rect.x, x); XCTAssertEqual(rect.y, y)
            XCTAssertEqual(rect.width, 150); XCTAssertEqual(rect.height, 100)
        }
    }

    func testFractionalSourceBoundsAndAspectAcrossPortraitLandscapeAndTinyInputs() throws {
        for (w, h) in [(301, 199), (199, 301), (4096, 4095), (1, 4096), (4096, 1), (1, 1)] {
            for zoom in [1.0, 1.001, 1.75, 2.2, 3.999, 4.0] {
                for horizontal in [0.0, 0.17, 0.5, 0.89, 1.0] {
                    for vertical in [0.0, 0.29, 0.5, 1.0] {
                        let rect = try TemplateImageCropRect(sourceWidth: w, sourceHeight: h,
                            horizontal: horizontal, vertical: vertical, zoom: zoom)
                        XCTAssertGreaterThan(rect.width, 0); XCTAssertGreaterThan(rect.height, 0)
                        XCTAssertGreaterThanOrEqual(rect.x, 0); XCTAssertGreaterThanOrEqual(rect.y, 0)
                        XCTAssertLessThanOrEqual(rect.x + rect.width, Double(w))
                        XCTAssertLessThanOrEqual(rect.y + rect.height, Double(h))
                        XCTAssertEqual(rect.width / rect.height, Double(w) / Double(h), accuracy: 1e-9)
                        XCTAssertGreaterThanOrEqual(rect.outputWidth, 1)
                        XCTAssertGreaterThanOrEqual(rect.outputHeight, 1)
                        if !rect.isIdentity {
                            XCTAssertLessThanOrEqual(max(rect.outputWidth, rect.outputHeight), 1440)
                        }
                    }
                }
            }
        }
    }

    func testEditedOutputCapUsesBothEdgesAndNearestPixelRounding() throws {
        let landscape = try TemplateImageCropRect(sourceWidth: 4096, sourceHeight: 3071, zoom: 1.25)
        XCTAssertEqual(landscape.outputWidth, 1440); XCTAssertEqual(landscape.outputHeight, 1080)
        let portrait = try TemplateImageCropRect(sourceWidth: 3071, sourceHeight: 4096, zoom: 1.25)
        XCTAssertEqual(portrait.outputWidth, 1080); XCTAssertEqual(portrait.outputHeight, 1440)
        let small = try TemplateImageCropRect(sourceWidth: 120, sourceHeight: 60, zoom: 4)
        XCTAssertEqual(small.outputWidth, 30); XCTAssertEqual(small.outputHeight, 15)
    }

    func testTinyEditedOutputCannotRoundDownToAnEmptyImage() throws {
        let tiny = try TemplateImageCropRect(sourceWidth: 1, sourceHeight: 1, zoom: 4)
        XCTAssertEqual(tiny.width, 0.25); XCTAssertEqual(tiny.height, 0.25)
        XCTAssertEqual(tiny.outputWidth, 1); XCTAssertEqual(tiny.outputHeight, 1)
    }

    func testInvalidDimensionsFailBeforeArithmetic() {
        for value in [Int.min, -1, 0, 4097, Int.max] {
            XCTAssertThrowsError(try TemplateImageCropRect(sourceWidth: value, sourceHeight: 100))
            XCTAssertThrowsError(try TemplateImageCropRect(sourceWidth: 100, sourceHeight: value))
        }
    }

    func testNonfiniteAndOutOfRangeControlsFailClosed() {
        for value in [Double.nan, .infinity, -.infinity, -0.001, 1.001] {
            XCTAssertThrowsError(try TemplateImageCropRect(sourceWidth: 100, sourceHeight: 100, horizontal: value))
            XCTAssertThrowsError(try TemplateImageCropRect(sourceWidth: 100, sourceHeight: 100, vertical: value))
        }
        for value in [Double.nan, .infinity, -.infinity, -1, 0.999, 4.001] {
            XCTAssertThrowsError(try TemplateImageCropRect(sourceWidth: 100, sourceHeight: 100, zoom: value))
        }
    }

    func testMerchantFixedRatioGeometryRemainsSeparate() throws {
        let template = try TemplateImageCropRect(sourceWidth: 300, sourceHeight: 200)
        XCTAssertEqual(template.width / template.height, 1.5)
        for aspect in [MerchantImageCropAspect.logo, .cover, .gallery] {
            let merchant = try MerchantImageCropRect(sourceWidth: 300, sourceHeight: 200, aspect: aspect)
            XCTAssertEqual(merchant.width * aspect.heightUnits, merchant.height * aspect.widthUnits)
        }
    }
}
