import XCTest
import UIKit
import ImageIO
@testable import Questify

@MainActor final class RoamStampFramingPixelTests: XCTestCase {
    private func image(width: Int = 400, height: Int = 500) -> UIImage {
        let size = CGSize(width: CGFloat(width), height: CGFloat(height))
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor.red.setFill(); context.fill(CGRect(x: size.width * 0.3, y: size.height * 0.3, width: size.width * 0.4, height: size.height * 0.4))
        }
    }
    private func frame(_ ratio: Double) throws -> RoamStampFrame {
        try .init(viewportWidth: 400, viewportHeight: 500, ratio: ratio)
    }
    private func rgba(_ image: UIImage, x: Int, y: Int) throws -> [UInt8] {
        let raw = try XCTUnwrap(image.cgImage)
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { pointer in
            let context = try XCTUnwrap(CGContext(data: pointer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(raw, in: CGRect(x: -CGFloat(x), y: -CGFloat(y), width: CGFloat(raw.width), height: CGFloat(raw.height)))
        }
        return bytes
    }
    func testNarrowFrameExportsSelectedPixelsNotFullPhoto() throws {
        let result = try RoamStampFramedPixels.render(image(), frame: frame(0.4))
        XCTAssertEqual(result.width, 160); XCTAssertEqual(result.height, 200)
        let output = try XCTUnwrap(UIImage(data: result.jpeg))
        let edge = try rgba(output, x: 10, y: 10)
        XCTAssertGreaterThan(edge[0], 200); XCTAssertLessThan(edge[2], 50)
    }
    func testLargerFrameActuallyIncludesSurroundings() throws {
        let result = try RoamStampFramedPixels.render(image(), frame: frame(0.9))
        XCTAssertEqual(result.width, 360); XCTAssertEqual(result.height, 450)
        let output = try XCTUnwrap(UIImage(data: result.jpeg))
        let edge = try rgba(output, x: 10, y: 10), center = try rgba(output, x: 180, y: 225)
        XCTAssertGreaterThan(edge[2], 200); XCTAssertLessThan(edge[0], 50)
        XCTAssertGreaterThan(center[0], 200); XCTAssertLessThan(center[2], 50)
    }
    func testOutputIsStrictFourByFiveCappedAndByteBounded() throws {
        let result = try RoamStampFramedPixels.render(image(width: 3000, height: 4000), frame: frame(0.9))
        XCTAssertEqual(result.width, 1600); XCTAssertEqual(result.height, 2000)
        XCTAssertEqual(result.width * 5, result.height * 4)
        XCTAssertLessThanOrEqual(result.jpeg.count, RetainedSelectedImage.maximumBytes)
    }
    func testAllExifOrientationsNormalizeBeforeCrop() throws {
        let original = try XCTUnwrap(image(width: 600, height: 400).cgImage)
        for orientation in [UIImage.Orientation.up, .upMirrored, .down, .downMirrored, .left, .leftMirrored, .right, .rightMirrored] {
            let input = UIImage(cgImage: original, scale: 1, orientation: orientation)
            let result = try RoamStampFramedPixels.render(input, frame: frame(0.5))
            let sideways = [.left, .leftMirrored, .right, .rightMirrored].contains(orientation)
            XCTAssertEqual(result.width, sideways ? 200 : 160)
            XCTAssertEqual(result.height, sideways ? 250 : 200)
            XCTAssertEqual(try XCTUnwrap(UIImage(data: result.jpeg)).imageOrientation, .up)
        }
    }
    func testImageScaleDoesNotChangePixelCoordinates() throws {
        let raw = try XCTUnwrap(image().cgImage)
        let one = try RoamStampFramedPixels.render(UIImage(cgImage: raw, scale: 1, orientation: .up), frame: frame(0.4))
        let three = try RoamStampFramedPixels.render(UIImage(cgImage: raw, scale: 3, orientation: .up), frame: frame(0.4))
        XCTAssertEqual(one.width, three.width); XCTAssertEqual(one.height, three.height)
        let center = try rgba(XCTUnwrap(UIImage(data: three.jpeg)), x: 80, y: 100)
        XCTAssertGreaterThan(center[0], 200)
    }
    func testRealGPSMetadataNegativeControlIsRemoved() throws {
        let sourceImage = try XCTUnwrap(image().cgImage)
        let inputData = NSMutableData()
        let writer = try XCTUnwrap(CGImageDestinationCreateWithData(inputData as CFMutableData, "public.jpeg" as CFString, 1, nil))
        let metadata: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 31.2304, kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 121.4737, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "PRIVATE-CAMERA-COMMENT"]
        ]
        CGImageDestinationAddImage(writer, sourceImage, metadata as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(inputData as CFData, nil))
        let sourceProperties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNotNil(sourceProperties[kCGImagePropertyGPSDictionary])
        let result = try RoamStampFramedPixels.render(XCTUnwrap(UIImage(data: inputData as Data)), frame: frame(0.74))
        let output = try XCTUnwrap(CGImageSourceCreateWithData(result.jpeg as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment])
    }
    func testEmptyImageFailsWithoutReturningOriginalContainer() throws {
        XCTAssertThrowsError(try RoamStampFramedPixels.render(UIImage(), frame: frame(0.74)))
    }
    func testFractionalFrameProducesNoAspectRatioRoundingDrift() throws {
        let fractional = try RoamStampFrame(viewportWidth: 367.5, viewportHeight: 459.375, ratio: 0.743)
        let output = try RoamStampFramedPixels.render(image(width: 1333, height: 1777), frame: fractional)
        XCTAssertEqual(output.width * 5, output.height * 4)
        XCTAssertLessThanOrEqual(output.width, 1600)
    }
}
