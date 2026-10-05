import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Questify

/// Synthetic pixels only. These tests require an Apple app-hosted test target.
@MainActor final class TemplateImageCropAppTests: XCTestCase {
    private func source(width: Int = 120, height: Int = 80, orientation: Int = 1) throws -> RetainedSelectedImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            UIColor.blue.setFill(); context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.3],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "synthetic-private-marker"]
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return try RetainedImageSanitizer.sanitize(bytes as Data)
    }

    private func assertClean(_ selected: RetainedSelectedImage, file: StaticString = #filePath, line: UInt = #line) throws {
        let decoded = try XCTUnwrap(CGImageSourceCreateWithData(selected.jpeg as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary], file: file, line: line)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment], file: file, line: line)
        XCTAssertEqual(UIImage(data: selected.jpeg)?.imageOrientation, .up, file: file, line: line)
        XCTAssertEqual(UIImage(data: selected.jpeg)?.cgImage?.width, selected.width, file: file, line: line)
        XCTAssertEqual(UIImage(data: selected.jpeg)?.cgImage?.height, selected.height, file: file, line: line)
        XCTAssertLessThanOrEqual(selected.jpeg.count, RetainedSelectedImage.maximumBytes, file: file, line: line)
    }

    func testIdentityReturnsSameIDAndExactSanitizedBytesForAllEXIFOrientations() throws {
        for orientation in 1...8 {
            let selected = try source(orientation: orientation)
            XCTAssertEqual(selected.width, orientation >= 5 ? 80 : 120)
            XCTAssertEqual(selected.height, orientation >= 5 ? 120 : 80)
            let rect = try TemplateImageCropRect(sourceWidth: selected.width, sourceHeight: selected.height)
            let result = try TemplateImageCropRenderer.render(selected, rect: rect)
            XCTAssertEqual(result, selected); XCTAssertEqual(result.id, selected.id)
            XCTAssertEqual(result.jpeg, selected.jpeg)
            try assertClean(result)
        }
    }

    func testIdentityDoesNotApplyEditedOutputCapOrReencode() throws {
        let selected = try source(width: 1800, height: 1200)
        let result = try TemplateImageCropRenderer.render(selected,
            rect: .init(sourceWidth: selected.width, sourceHeight: selected.height))
        XCTAssertEqual(result, selected); XCTAssertEqual(result.width, 1800)
    }

    func testEditedPixelsAreUprightBoundedAndMetadataFreeForAllEXIFOrientations() throws {
        for orientation in 1...8 {
            let selected = try source(orientation: orientation)
            let rect = try TemplateImageCropRect(sourceWidth: selected.width, sourceHeight: selected.height,
                horizontal: 0, vertical: 1, zoom: 2)
            let result = try TemplateImageCropRenderer.render(selected, rect: rect)
            XCTAssertNotEqual(result.id, selected.id)
            XCTAssertEqual(result.width, selected.width / 2); XCTAssertEqual(result.height, selected.height / 2)
            try assertClean(result)
        }
    }

    func testPanChoosesDifferentPixelsAndPreviewMatchesExportDimensions() throws {
        let selected = try source()
        let left = try TemplateImageCropRect(sourceWidth: selected.width, sourceHeight: selected.height, horizontal: 0, zoom: 4)
        let right = try TemplateImageCropRect(sourceWidth: selected.width, sourceHeight: selected.height, horizontal: 1, zoom: 4)
        let a = try TemplateImageCropRenderer.render(selected, rect: left)
        let b = try TemplateImageCropRenderer.render(selected, rect: right)
        XCTAssertNotEqual(a.jpeg, b.jpeg)
        let preview = try TemplateImageCropRenderer.preview(selected, rect: right)
        XCTAssertEqual(preview.cgImage?.width, b.width); XCTAssertEqual(preview.cgImage?.height, b.height)
        // Synthetic solid left/right regions make channel dominance independent of JPEG loss.
        XCTAssertGreaterThan(try redMinusBlue(a.jpeg), 150)
        XCTAssertLessThan(try redMinusBlue(b.jpeg), -150)
    }

    private func redMinusBlue(_ jpeg: Data) throws -> Int {
        let image = try XCTUnwrap(UIImage(data: jpeg)?.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { storage in
            let context = try XCTUnwrap(CGContext(data: storage.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Int(pixel[0]) - Int(pixel[2])
    }

    func testFractionalCoprimeCropAndEditedOutputCapEncodeExpectedDimensions() throws {
        for (w, h, zoom, outW, outH) in [(301, 199, 2.2, 137, 90), (1800, 1200, 1.1, 1440, 960)] {
            let selected = try source(width: w, height: h)
            let result = try TemplateImageCropRenderer.render(selected,
                rect: .init(sourceWidth: w, sourceHeight: h, horizontal: 1, vertical: 1, zoom: zoom))
            XCTAssertEqual(result.width, outW); XCTAssertEqual(result.height, outH)
            try assertClean(result)
        }
    }

    func testWrongSourceDimensionsMalformedBytesAndNonUprightInputFailClosed() throws {
        let selected = try source()
        let wrong = try TemplateImageCropRect(sourceWidth: selected.height, sourceHeight: selected.width)
        XCTAssertThrowsError(try TemplateImageCropRenderer.render(selected, rect: wrong))
        let malformed = try RetainedSelectedImage(jpeg: Data([255, 216, 255]), width: 120, height: 80)
        let rect = try TemplateImageCropRect(sourceWidth: 120, sourceHeight: 80)
        XCTAssertThrowsError(try TemplateImageCropRenderer.render(malformed, rect: rect))
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(UIImage(data: selected.jpeg)?.cgImage),
                                  [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let tilted = try RetainedSelectedImage(jpeg: bytes as Data, width: 120, height: 80)
        XCTAssertThrowsError(try TemplateImageCropRenderer.render(tilted, rect: rect))
    }

    func testCancelPreservesPreviousSelectionAndDelayedConfirmationCannotReplaceIt() throws {
        let previous = try source(), candidate = try source(width: 100, height: 100)
        let session = TemplateImageCropSession(selection: previous, isCurrent: { true })
        session.stage(candidate); let draft = try XCTUnwrap(session.draft)
        XCTAssertEqual(session.selection, previous)
        session.cancel(id: draft.id)
        XCTAssertNil(session.draft); XCTAssertEqual(session.selection, previous)
        XCTAssertNil(session.confirm(id: draft.id, rect: try .init(sourceWidth: 100, sourceHeight: 100)))
        XCTAssertEqual(session.selection, previous)
    }

    func testReplacingCandidateRejectsOldConfirmAndOldDismissal() throws {
        let previous = try source(), candidate = try source(width: 100, height: 100)
        let session = TemplateImageCropSession(selection: previous, isCurrent: { true })
        session.stage(candidate); let old = try XCTUnwrap(session.draft)
        session.stage(candidate); let next = try XCTUnwrap(session.draft)
        let rect = try TemplateImageCropRect(sourceWidth: 100, sourceHeight: 100)
        XCTAssertNil(session.confirm(id: old.id, rect: rect)); session.cancel(id: old.id)
        XCTAssertEqual(session.draft?.id, next.id); XCTAssertEqual(session.selection, previous)
        XCTAssertEqual(session.confirm(id: next.id, rect: rect), candidate)
        XCTAssertNil(session.confirm(id: next.id, rect: rect))
        session.cancel(id: next.id)
        XCTAssertEqual(session.selection, candidate); XCTAssertNil(session.draft)
    }

    func testRenderAndReplacementFailurePreservePreviousSelection() throws {
        let previous = try source(), candidate = try source(width: 100, height: 100)
        let session = TemplateImageCropSession(selection: previous, isCurrent: { true })
        session.stage(candidate); let draft = try XCTUnwrap(session.draft)
        XCTAssertNil(session.confirm(id: draft.id, rect: try .init(sourceWidth: 90, sourceHeight: 100)))
        XCTAssertTrue(session.failed); XCTAssertEqual(session.draft?.id, draft.id)
        XCTAssertEqual(session.selection, previous)
        session.stage(try .init(jpeg: Data([255, 216, 255]), width: 100, height: 100))
        XCTAssertTrue(session.failed); XCTAssertNil(session.draft); XCTAssertEqual(session.selection, previous)
        XCTAssertNil(session.confirm(id: draft.id, rect: try .init(sourceWidth: 100, sourceHeight: 100)))
    }

    func testScopeChangeAndExplicitInvalidationReleaseAllBytesAndStayTerminal() throws {
        let selected = try source(); var current = true
        let session = TemplateImageCropSession(selection: selected, isCurrent: { current })
        session.stage(selected); let draft = try XCTUnwrap(session.draft)
        current = false
        XCTAssertNil(session.confirm(id: draft.id, rect: try .init(sourceWidth: 120, sourceHeight: 80)))
        XCTAssertNil(session.selection); XCTAssertNil(session.draft)
        current = true; session.stage(selected); XCTAssertNil(session.draft)
        let other = TemplateImageCropSession(selection: selected, isCurrent: { true })
        other.stage(selected); let pending = try XCTUnwrap(other.draft)
        other.invalidate(); other.stage(selected)
        XCTAssertNil(other.confirm(id: pending.id, rect: try .init(sourceWidth: 120, sourceHeight: 80)))
        XCTAssertNil(other.selection); XCTAssertNil(other.draft)
    }
}
