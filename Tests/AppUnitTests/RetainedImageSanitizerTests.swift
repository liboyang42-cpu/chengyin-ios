import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Questify
@MainActor final class RetainedImageSanitizerTests: XCTestCase {
    func testMetadataStrippedAndDimensionsBounded() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 5000, height: 20))
        let source = renderer.image { c in UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 5000, height: 20)) }
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil))
        let metadata: [CFString: Any] = [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 1.2], kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private marker"]]
        CGImageDestinationAddImage(destination, try XCTUnwrap(source.cgImage), metadata as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let selected = try RetainedImageSanitizer.sanitize(output as Data)
        XCTAssertLessThanOrEqual(selected.width, 4096); XCTAssertLessThanOrEqual(selected.jpeg.count, RetainedSelectedImage.maximumBytes)
        let parsed = try XCTUnwrap(CGImageSourceCreateWithData(selected.jpeg as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(parsed, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertFalse(String(decoding: selected.jpeg, as: UTF8.self).contains("private marker"))
    }
    func testRejectsMalformedAndOversizeInput() {
        XCTAssertThrowsError(try RetainedImageSanitizer.sanitize(Data([255,216,255])))
        XCTAssertThrowsError(try RetainedImageSanitizer.sanitize(Data(repeating: 0, count: RetainedSelectedImage.maximumInputBytes + 1)))
    }
    func testDisabledPickerDoesNotPresent() async {
        var count = 0
        let picker = RetainedNativeImagePicker(present: { _ in count += 1; return true }, dismiss: {})
        do { _ = try await picker.select(); XCTFail() } catch { XCTAssertEqual(error as? RetainedImageFailure, .disabled) }
        XCTAssertEqual(count, 0)
    }
    func testPickerCancellationCompletesAndAllowsAnotherSelection() async throws {
        let picker = RetainedNativeImagePicker(enabled: true, present: { _ in true }, dismiss: {})
        let pending = Task { try await picker.select() }
        await Task.yield(); picker.cancel()
        let selected = try await pending.value; XCTAssertNil(selected)
        let again = Task { try await picker.select() }
        await Task.yield(); picker.cancel(); let next = try await again.value; XCTAssertNil(next)
    }
}
