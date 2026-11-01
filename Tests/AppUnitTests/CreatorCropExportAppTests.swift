import XCTest
import UIKit
@testable import Questify

@MainActor final class CreatorCropExportAppTests: XCTestCase {
    private func source(width: Int = 120, height: Int = 80) throws -> RetainedSelectedImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
            UIColor.blue.setFill(); context.fill(CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        }
        return try RetainedImageSanitizer.sanitize(XCTUnwrap(image.jpegData(compressionQuality: 0.9)))
    }

    func testOriginalPreservesExactBytesIdentityAndDimensions() throws {
        let selected = try source()
        let result = try CreatorCropExport.export(selected, result: .original)
        XCTAssertEqual(result, selected); XCTAssertEqual(result.id, selected.id); XCTAssertEqual(result.jpeg, selected.jpeg)
        XCTAssertEqual(result.width, 120); XCTAssertEqual(result.height, 80)
    }

    func testCropExportsUprightPixelsWithRectDimensions() throws {
        let selected = try source()
        let result = try CreatorCropExport.export(selected, result: .crop(.init(x: 0, y: 0, width: 60, height: 80)))
        XCTAssertEqual(result.width, 60); XCTAssertEqual(result.height, 80)
        XCTAssertEqual(UIImage(data: result.jpeg)?.imageOrientation, .up)
        XCTAssertEqual(UIImage(data: result.jpeg)?.cgImage?.width, 60)
        XCTAssertNotEqual(result.id, selected.id)
    }

    func testIllegalRectAndWrongSourceFailClosed() throws {
        let selected = try source()
        XCTAssertThrowsError(try CreatorCropExport.export(selected, result: .crop(.init(x: 100, y: 0, width: 60, height: 80))))
        XCTAssertThrowsError(try CreatorCropExport.export(selected, result: .crop(.init(x: 0, y: 0, width: 0, height: 80))))
        let malformed = try RetainedSelectedImage(jpeg: Data([255, 216, 255]), width: 120, height: 80)
        XCTAssertThrowsError(try CreatorCropExport.export(malformed, result: .original))
    }

    func testBatchConfirmIsOrderedAndOldDraftIDIsRejected() throws {
        let first = try source(), second = try source(width: 100, height: 100)
        let session = CreatorCropExportSession(isCurrent: { true })
        session.stage([first, second]); let old = try XCTUnwrap(session.draft)
        session.stage([first, second]); let next = try XCTUnwrap(session.draft)
        XCTAssertNil(session.confirm(id: old.id, results: [.original, .original]))
        let exported = try XCTUnwrap(session.confirm(id: next.id, results: [.original, .crop(.init(x: 0, y: 0, width: 50, height: 100))]))
        XCTAssertEqual(exported.map(\.width), [120, 50]); XCTAssertEqual(exported.first?.jpeg, first.jpeg)
        XCTAssertNil(session.confirm(id: next.id, results: [.original, .original]))
    }

    func testCancelAndFailurePreservePreviousSelections() throws {
        let previous = try source(), candidate = try source(width: 100, height: 100)
        let session = CreatorCropExportSession(isCurrent: { true })
        session.stage([previous]); let done = try XCTUnwrap(session.draft)
        XCTAssertNotNil(session.confirm(id: done.id, results: [.original]))
        session.stage([candidate]); let draft = try XCTUnwrap(session.draft)
        XCTAssertNil(session.confirm(id: draft.id, results: [.crop(.init(x: 90, y: 0, width: 50, height: 100))]))
        XCTAssertTrue(session.failed); XCTAssertEqual(session.selections, [previous])
        session.cancel(id: draft.id)
        XCTAssertNil(session.draft); XCTAssertEqual(session.selections, [previous])
    }

    func testInvalidationIsTerminalAndRejectsDelayedCallbacks() throws {
        let selected = try source(); var current = true
        let session = CreatorCropExportSession(isCurrent: { current })
        session.stage([selected]); let draft = try XCTUnwrap(session.draft)
        current = false
        XCTAssertNil(session.confirm(id: draft.id, results: [.original]))
        XCTAssertNil(session.draft); XCTAssertTrue(session.selections.isEmpty)
        current = true; session.stage([selected]); XCTAssertNil(session.draft)
    }
}
