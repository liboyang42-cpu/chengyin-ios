import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Questify

@MainActor final class MerchantImageCropAppTests: XCTestCase {
    private final class NoNetwork: HTTPTransport {
        var calls = 0
        func send(_ request: URLRequest) async throws -> (Data, Int) { calls += 1; throw APIError.notConfigured }
    }
    private func source(orientation: Int = 1) throws -> RetainedSelectedImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 60), format: format).image { c in
            UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
            UIColor.blue.setFill(); c.fill(CGRect(x: 60, y: 0, width: 60, height: 60))
        }
        let bytes = NSMutableData()
        let out = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(out, try XCTUnwrap(image.cgImage), [kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 1.2]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(out))
        return try RetainedImageSanitizer.sanitize(bytes as Data)
    }
    private func setup(field: MerchantImageField = .logo) throws -> (RetainedImageSelectionModel, NoNetwork) {
        let scope = try RetainedImageScope(accountID: 8, epoch: UUID(), realm: "https://api.example.com/",
            destination: .merchant(merchantRowID: 41, field: field), accessRevision: UUID(), namespace: "synthetic")
        let network = NoNetwork()
        let uploader = try RetainedImageHTTPUploader(configuration: APIConfiguration(baseURL: URL(string: scope.realm)!),
            transport: network, enabled: true, approvedOrigins: ["https://media.example.com"], currentScope: { scope }, token: { "synthetic-token" })
        var storage: [String: Data] = [:]
        let journal = StoredImageUploadJournal(read: { storage[$0] }, write: { storage[$1] = $0 })
        let context = RetainedImageSelectionContext(scope: scope, currentScope: { scope },
            picker: .init(present: { _ in XCTFail("Must not open OS picker"); return false }, dismiss: {}),
            uploads: .init(uploader: uploader, journal: journal))
        return (RetainedImageSelectionModel(context: context), network)
    }
    func testCropThenSeparateUploadReviewWithoutTransmission() throws {
        let (model, network) = try setup(field: .coverImage)
        model.stage(try source())
        let draft = try XCTUnwrap(model.cropDraft)
        XCTAssertEqual(model.context.uploads.state, .idle)
        let rect = try MerchantImageCropRect(sourceWidth: draft.source.width, sourceHeight: draft.source.height, aspect: draft.aspect)
        model.confirmCrop(id: draft.id, rect: rect)
        XCTAssertNil(model.cropDraft)
        guard case .reviewing(let review) = model.context.uploads.state else { return XCTFail("Missing separate review") }
        XCTAssertEqual(review.selection.width * 3, review.selection.height * 5)
        XCTAssertEqual(network.calls, 0); XCTAssertFalse(model.context.picker.enabled)
    }
    func testReplacementRejectsOldCropAndClearsPreviousReview() throws {
        let (model, network) = try setup(); let image = try source()
        model.stage(image); let old = try XCTUnwrap(model.cropDraft)
        let rect = try MerchantImageCropRect(sourceWidth: image.width, sourceHeight: image.height, aspect: .logo)
        model.stage(image); let next = try XCTUnwrap(model.cropDraft)
        model.confirmCrop(id: old.id, rect: rect)
        XCTAssertEqual(model.cropDraft?.id, next.id); XCTAssertEqual(model.context.uploads.state, .idle)
        model.confirmCrop(id: next.id, rect: rect)
        model.stage(image)
        XCTAssertNotNil(model.cropDraft); XCTAssertEqual(model.context.uploads.state, .idle); XCTAssertEqual(network.calls, 0)
    }
    func testCancelAndLeaveDropImageBytesAndDoNotUpload() throws {
        let (model, network) = try setup()
        model.stage(try source()); model.cancelCrop()
        XCTAssertNil(model.cropDraft); XCTAssertEqual(model.context.uploads.state, .idle)
        model.stage(try source()); let old = try XCTUnwrap(model.cropDraft)
        model.leave()
        model.confirmCrop(id: old.id, rect: try .init(sourceWidth: 120, sourceHeight: 60, aspect: .logo))
        XCTAssertNil(model.cropDraft); XCTAssertEqual(model.context.uploads.state, .idle); XCTAssertEqual(network.calls, 0)
    }
    func testStaleScopeCannotConfirmCrop() throws {
        let (base, network) = try setup()
        var current = true
        let context = RetainedImageSelectionContext(scope: base.context.scope,
            currentScope: { current ? base.context.scope : nil }, picker: base.context.picker, uploads: base.context.uploads)
        let model = RetainedImageSelectionModel(context: context)
        model.stage(try source()); let draft = try XCTUnwrap(model.cropDraft)
        current = false
        model.confirmCrop(id: draft.id, rect: try .init(sourceWidth: 120, sourceHeight: 60, aspect: .logo))
        XCTAssertEqual(model.context.uploads.state, .idle); XCTAssertEqual(network.calls, 0)
        model.leave(); XCTAssertNil(model.cropDraft)
    }
    func testNoncropPickerFailurePreservesPriorReview() async throws {
        let (model, network) = try setup(field: .avatar)
        model.stage(try source())
        let previous = model.context.uploads.state
        guard case .reviewing = previous else { return XCTFail("Expected existing review") }
        await model.select() // Disabled synthetic OS picker fails without opening anything.
        XCTAssertEqual(model.context.uploads.state, previous)
        XCTAssertNil(model.cropDraft); XCTAssertEqual(network.calls, 0)
    }
    func testNoncropPickerCancellationPreservesPriorReview() async throws {
        let (base, network) = try setup(field: .avatar)
        let presented = expectation(description: "Synthetic picker request")
        let picker = RetainedNativeImagePicker(enabled: true, present: { _ in presented.fulfill(); return true }, dismiss: {})
        let context = RetainedImageSelectionContext(scope: base.context.scope, currentScope: base.context.currentScope,
            picker: picker, uploads: base.context.uploads)
        let model = RetainedImageSelectionModel(context: context)
        model.stage(try source()); let previous = context.uploads.state
        let selection = Task { await model.select() }
        await fulfillment(of: [presented], timeout: 1)
        picker.cancel(); await selection.value
        XCTAssertEqual(context.uploads.state, previous)
        XCTAssertNil(model.cropDraft); XCTAssertFalse(model.selecting); XCTAssertEqual(network.calls, 0)
    }
    func testUnknownUploadLockCannotBeBypassedByCropReplacement() async throws {
        let (model, network) = try setup(); model.stage(try source())
        let draft = try XCTUnwrap(model.cropDraft)
        model.confirmCrop(id: draft.id, rect: try .init(sourceWidth: 120, sourceHeight: 60, aspect: .logo))
        guard case .reviewing(let review) = model.context.uploads.state else { return XCTFail("Missing review") }
        await model.context.uploads.confirm(review) // NoNetwork rejects in memory, with no socket.
        XCTAssertTrue(model.context.uploads.locked)
        model.stage(try source()); XCTAssertNil(model.cropDraft)
        model.leave(); XCTAssertTrue(model.context.uploads.locked)
        XCTAssertEqual(network.calls, 1)
    }
    func testAllEXIFOrientationsNormalizeBeforeCropAndRemoveMetadata() throws {
        for orientation in 1...8 {
            let image = try source(orientation: orientation)
            XCTAssertEqual(image.width, orientation >= 5 ? 60 : 120)
            XCTAssertEqual(image.height, orientation >= 5 ? 120 : 60)
            for aspect in [MerchantImageCropAspect.logo, .cover, .gallery] {
                let rect = try MerchantImageCropRect(sourceWidth: image.width, sourceHeight: image.height, aspect: aspect)
                let result = try MerchantImageCropRenderer.render(image, rect: rect)
                XCTAssertEqual(result.width * aspect.heightUnits, result.height * aspect.widthUnits)
                let decoded = try XCTUnwrap(CGImageSourceCreateWithData(result.jpeg as CFData, nil))
                let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any])
                XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
                XCTAssertEqual(UIImage(data: result.jpeg)?.imageOrientation, .up)
                XCTAssertLessThanOrEqual(result.jpeg.count, RetainedSelectedImage.maximumBytes)
            }
        }
    }
    func testPanSelectsDifferentPixelsAndRejectsWrongAspect() throws {
        let image = try source()
        let left = try MerchantImageCropRect(sourceWidth: image.width, sourceHeight: image.height, aspect: .logo, horizontal: 0)
        let right = try MerchantImageCropRect(sourceWidth: image.width, sourceHeight: image.height, aspect: .logo, horizontal: 1)
        XCTAssertNotEqual(try MerchantImageCropRenderer.render(image, rect: left).jpeg,
                          try MerchantImageCropRenderer.render(image, rect: right).jpeg)
        let (model, _) = try setup(field: .coverImage); model.stage(image)
        model.confirmCrop(id: try XCTUnwrap(model.cropDraft).id, rect: left)
        XCTAssertNotNil(model.cropDraft); XCTAssertEqual(model.context.uploads.state, .idle)
    }
    func testGalleryCropReviewReplacementCancelAndLeave() throws {
        let (model, network) = try setup(field: .gallery)
        let image = try source()
        model.stage(image)
        let first = try XCTUnwrap(model.cropDraft)
        XCTAssertEqual(first.aspect, .gallery)
        XCTAssertEqual(model.context.uploads.state, .idle)
        let rect = try MerchantImageCropRect(sourceWidth: image.width, sourceHeight: image.height, aspect: .gallery)
        model.confirmCrop(id: first.id, rect: try .init(sourceWidth: image.width, sourceHeight: image.height, aspect: .logo))
        XCTAssertEqual(model.cropDraft?.id, first.id)
        model.stage(image)
        let replacement = try XCTUnwrap(model.cropDraft)
        model.confirmCrop(id: first.id, rect: rect)
        XCTAssertEqual(model.cropDraft?.id, replacement.id)
        model.confirmCrop(id: replacement.id, rect: rect)
        guard case .reviewing(let review) = model.context.uploads.state else { return XCTFail("Missing gallery upload review") }
        XCTAssertEqual(review.scope.destination, .merchant(merchantRowID: 41, field: .gallery))
        XCTAssertEqual(review.selection.width * 9, review.selection.height * 16)
        XCTAssertNil(model.cropDraft)
        model.stage(image) // Replacing an untransmitted review starts a new crop.
        XCTAssertEqual(model.context.uploads.state, .idle)
        model.cancelCrop()
        XCTAssertNil(model.cropDraft)
        model.confirmCrop(id: replacement.id, rect: rect)
        XCTAssertEqual(model.context.uploads.state, .idle)
        model.stage(image)
        let leaving = try XCTUnwrap(model.cropDraft)
        model.leave() // Also used by scene background and current-scope loss.
        model.confirmCrop(id: leaving.id, rect: rect)
        XCTAssertNil(model.cropDraft); XCTAssertEqual(model.context.uploads.state, .idle)
        XCTAssertEqual(network.calls, 0)
    }
    func testGalleryScopeChangeRejectsReviewAndUnknownLocksReplacement() async throws {
        let (base, network) = try setup(field: .gallery)
        var currentScope: RetainedImageScope? = base.context.scope
        let model = RetainedImageSelectionModel(context: .init(scope: base.context.scope,
            currentScope: { currentScope }, picker: base.context.picker, uploads: base.context.uploads))
        let image = try source()
        let rect = try MerchantImageCropRect(sourceWidth: image.width, sourceHeight: image.height, aspect: .gallery)
        model.stage(image); let draft = try XCTUnwrap(model.cropDraft)
        currentScope = try .init(accountID: 8, epoch: base.context.scope.epoch, realm: base.context.scope.realm,
            destination: .merchant(merchantRowID: 41, field: .gallery), accessRevision: UUID(), namespace: "synthetic")
        model.confirmCrop(id: draft.id, rect: rect)
        XCTAssertEqual(model.context.uploads.state, .idle); XCTAssertEqual(network.calls, 0)
        model.leave(); XCTAssertNil(model.cropDraft)
        currentScope = base.context.scope
        model.stage(image)
        model.confirmCrop(id: try XCTUnwrap(model.cropDraft).id, rect: rect)
        guard case .reviewing(let review) = model.context.uploads.state else { return XCTFail("Missing review") }
        await model.context.uploads.confirm(review) // Synthetic transport only; never a socket.
        XCTAssertTrue(model.context.uploads.locked)
        model.stage(image); await model.select(); model.cancelCrop(); model.leave()
        XCTAssertNil(model.cropDraft); XCTAssertTrue(model.context.uploads.locked)
        XCTAssertEqual(network.calls, 1)
    }
    func testGalleryPickerCancellationDropsReplacementWithoutUpload() async throws {
        let (base, network) = try setup(field: .gallery)
        let presented = expectation(description: "Synthetic gallery picker request")
        let picker = RetainedNativeImagePicker(enabled: true, present: { _ in presented.fulfill(); return true }, dismiss: {})
        let model = RetainedImageSelectionModel(context: .init(scope: base.context.scope,
            currentScope: base.context.currentScope, picker: picker, uploads: base.context.uploads))
        model.stage(try source())
        let draft = try XCTUnwrap(model.cropDraft)
        model.confirmCrop(id: draft.id, rect: try .init(sourceWidth: draft.source.width, sourceHeight: draft.source.height, aspect: .gallery))
        let selection = Task { await model.select() }
        await fulfillment(of: [presented], timeout: 1)
        picker.cancel(); await selection.value
        XCTAssertNil(model.cropDraft); XCTAssertEqual(model.context.uploads.state, .idle)
        XCTAssertFalse(model.selecting); XCTAssertEqual(network.calls, 0)
    }

}
