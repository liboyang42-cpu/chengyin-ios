import XCTest
import UIKit
import ImageIO
@testable import Questify

@MainActor final class RoamStampPixelTests: XCTestCase {
    func testCropExportsActualFourByFivePixelsAndBoundsBytes() throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let input = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200), format: format).image { c in
            UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
        }
        let clean = try RoamStampPixelCrop.render(input)
        XCTAssertEqual(clean.width * 5, clean.height * 4)
        XCTAssertLessThanOrEqual(clean.width, 1600); XCTAssertLessThanOrEqual(clean.height, 2000)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(clean.jpeg as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertLessThanOrEqual(clean.jpeg.count, RetainedSelectedImage.maximumBytes)
    }
    func testEmptyImageFailsClosed() { XCTAssertThrowsError(try RoamStampPixelCrop.render(UIImage())) }
}
