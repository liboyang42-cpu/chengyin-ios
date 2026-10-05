import XCTest
@testable import QuestifyCore

final class MerchantImageCropTests: XCTestCase {
    func testOnlySourceBackedMerchantFieldsSelectCrop() {
        XCTAssertEqual(MerchantImageCropAspect.forDestination(.merchant(merchantRowID: 41, field: .logo)), .logo)
        XCTAssertEqual(MerchantImageCropAspect.forDestination(.merchant(merchantRowID: 41, field: .coverImage)), .cover)
        XCTAssertEqual(MerchantImageCropAspect.forDestination(.merchant(merchantRowID: 41, field: .gallery)), .gallery)
        for field in [MerchantImageField.avatar, .imgUrl] {
            XCTAssertNil(MerchantImageCropAspect.forDestination(.merchant(merchantRowID: 41, field: field)))
        }
        XCTAssertNil(MerchantImageCropAspect.forDestination(.stamp))
        XCTAssertNil(MerchantImageCropAspect.forDestination(.publicReview(merchantRowID: 41, registrationID: 19)))
    }
    func testSquareCenterAndCoverExactRatio() throws {
        let square = try MerchantImageCropRect(sourceWidth: 300, sourceHeight: 200, aspect: .logo)
        XCTAssertEqual(square.x, 50); XCTAssertEqual(square.y, 0)
        XCTAssertEqual(square.width, 200); XCTAssertEqual(square.height, 200)
        let cover = try MerchantImageCropRect(sourceWidth: 301, sourceHeight: 200, aspect: .cover)
        XCTAssertEqual(cover.width, 300); XCTAssertEqual(cover.height, 180)
        XCTAssertEqual(cover.y, 10)
    }
    func testPanZoomAndPortraitStayInsideUprightSource() throws {
        for aspect in [MerchantImageCropAspect.logo, .cover, .gallery] {
            for dimensions in [(200, 300), (4096, 17), (17, 4096), (301, 199)] {
                for zoom in [1.0, 2.2, 4.0] {
                    for position in [0.0, 0.5, 1.0] {
                        let r = try MerchantImageCropRect(sourceWidth: dimensions.0, sourceHeight: dimensions.1,
                            aspect: aspect, horizontal: position, vertical: position, zoom: zoom)
                        XCTAssertGreaterThan(r.width, 0); XCTAssertGreaterThan(r.height, 0)
                        XCTAssertGreaterThanOrEqual(r.x, 0); XCTAssertGreaterThanOrEqual(r.y, 0)
                        XCTAssertLessThanOrEqual(r.x + r.width, dimensions.0)
                        XCTAssertLessThanOrEqual(r.y + r.height, dimensions.1)
                        XCTAssertEqual(r.width * aspect.heightUnits, r.height * aspect.widthUnits)
                    }
                }
            }
        }
    }
    func testMinimumCoverDoesNotLoseControlsAtMaximumZoom() throws {
        let r = try MerchantImageCropRect(sourceWidth: 5, sourceHeight: 3, aspect: .cover, zoom: 4)
        XCTAssertEqual(r.width, 5); XCTAssertEqual(r.height, 3)
    }
    func testRejectsUnboundedOrNonfiniteGeometry() {
        for dimension in [0, -1, 4097, Int.max] {
            XCTAssertThrowsError(try MerchantImageCropRect(sourceWidth: dimension, sourceHeight: 200, aspect: .logo))
        }
        for value in [Double.nan, .infinity, -.infinity, -0.1, 1.1] {
            XCTAssertThrowsError(try MerchantImageCropRect(sourceWidth: 100, sourceHeight: 100, aspect: .logo, horizontal: value))
            XCTAssertThrowsError(try MerchantImageCropRect(sourceWidth: 100, sourceHeight: 100, aspect: .logo, vertical: value))
        }
        for value in [Double.nan, .infinity, 0, 4.1] {
            XCTAssertThrowsError(try MerchantImageCropRect(sourceWidth: 100, sourceHeight: 100, aspect: .logo, zoom: value))
        }
        XCTAssertThrowsError(try MerchantImageCropRect(sourceWidth: 4, sourceHeight: 3, aspect: .cover))
    }
    func testGalleryExactRatioRoundingMinimumAndNoUpscale() throws {
        let rect = try MerchantImageCropRect(sourceWidth: 301, sourceHeight: 200, aspect: .gallery)
        XCTAssertEqual(rect.width, 288); XCTAssertEqual(rect.height, 162)
        XCTAssertEqual(rect.x, 7); XCTAssertEqual(rect.y, 19)
        let minimum = try MerchantImageCropRect(sourceWidth: 16, sourceHeight: 9, aspect: .gallery, zoom: 4)
        XCTAssertEqual(minimum.width, 16); XCTAssertEqual(minimum.height, 9)
        XCTAssertThrowsError(try MerchantImageCropRect(sourceWidth: 15, sourceHeight: 9, aspect: .gallery))
        XCTAssertThrowsError(try MerchantImageCropRect(sourceWidth: 16, sourceHeight: 8, aspect: .gallery))
    }

}
