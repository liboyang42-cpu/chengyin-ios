import XCTest
import UIKit
import UniformTypeIdentifiers
@testable import Questify

@MainActor final class SquarePostLocalMediaPresentationTests: XCTestCase {
    private func scope(account: Int = 42, epoch: UInt64 = 1, draft: String = "draft-one", lane: SquareWorkspaceLane = .legacy) throws -> SquarePostLocalMediaScope {
        try .init(session: .init(accountID: account, namespace: "synthetic", epoch: epoch), draftID: draft, lane: lane)
    }
    private func png() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 3)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 2, height: 3))
        }
        return try XCTUnwrap(image.pngData())
    }
    private func begin(_ model: SquarePostLocalMediaPresentation, scope: SquarePostLocalMediaScope? = nil) throws -> SquarePostLocalMediaByteInspection {
        model.beginPicker(scope: try scope ?? self.scope())
        return try XCTUnwrap(model.beginSelection(kind: .image, request: XCTUnwrap(model.pickerRequest)))
    }
    private func preview(_ inspection: SquarePostLocalMediaByteInspection) throws -> SquarePostLocalMediaImagePreview {
        let data = try png()
        return try SquarePostLocalMediaInspector.decodeImage(data, expectedType: .png, maximumBytes: data.count, inspection: inspection)
    }
    func testImageDecodeOwnsBytesAndPreviewWithoutUpgradingCoreAuthority() throws {
        let model = SquarePostLocalMediaPresentation(), inspection = try begin(model)
        let result = try preview(inspection)
        XCTAssertTrue(model.complete(result)); XCTAssertNotNil(model.thumbnail)
        XCTAssertEqual(model.imageUpload?.bytes, result.bytes)
        XCTAssertEqual(model.imageUpload?.mimeType, "image/png")
        XCTAssertEqual(model.snapshot?.assessment, .policyUnavailable)
        XCTAssertFalse(result.evidence.appDecodingPerformed)
        XCTAssertEqual(result.evidence.description.kind, .image)
        XCTAssertEqual(result.evidence.byteCount, Int64(result.bytes.count))
    }
    func testImageDecodeRejectsCorruptionAndProviderMIMEContradiction() throws {
        let model = SquarePostLocalMediaPresentation()
        XCTAssertThrowsError(try SquarePostLocalMediaInspector.decodeImage(Data("not an image".utf8), expectedType: .png, maximumBytes: 100, inspection: begin(model)))
        let bytes = try png()
        XCTAssertThrowsError(try SquarePostLocalMediaInspector.decodeImage(bytes, expectedType: .jpeg, maximumBytes: bytes.count, inspection: begin(model)))
        XCTAssertNil(model.imageUpload); XCTAssertNil(model.thumbnail)
    }
    func testImageByteLimitAllowsExactBoundAndRejectsOneLess() throws {
        let model = SquarePostLocalMediaPresentation(), bytes = try png()
        XCTAssertThrowsError(try SquarePostLocalMediaInspector.decodeImage(bytes, expectedType: .png, maximumBytes: bytes.count - 1, inspection: begin(model))) { error in
            XCTAssertEqual(error as? SquarePostLocalMediaIssue, .byteLimit)
        }
        let exact = try SquarePostLocalMediaInspector.decodeImage(bytes, expectedType: .png, maximumBytes: bytes.count, inspection: begin(model))
        XCTAssertTrue(model.complete(exact))
    }
    func testEmptyImageNeverCreatesPreviewOrUploadInput() throws {
        let model = SquarePostLocalMediaPresentation()
        XCTAssertThrowsError(try SquarePostLocalMediaInspector.decodeImage(Data(), expectedType: .png, maximumBytes: 100, inspection: begin(model)))
        XCTAssertNil(model.imageUpload); XCTAssertNil(model.thumbnail)
    }
    func testRemoveRetiresInflightAttemptAndDropsAllOwnedPixels() throws {
        let model = SquarePostLocalMediaPresentation(), result = try preview(begin(model))
        model.remove()
        XCTAssertFalse(model.complete(result)); XCTAssertEqual(model.state, .empty)
        XCTAssertFalse(model.hasSelection); XCTAssertNil(model.imageUpload); XCTAssertNil(model.thumbnail)
        XCTAssertTrue(model.snapshot?.items.isEmpty == true)
    }
    func testCancelReadRejectsLateResultAndRetainsRemovableCancelledRow() throws {
        let model = SquarePostLocalMediaPresentation(), result = try preview(begin(model))
        model.cancelInspection()
        XCTAssertFalse(model.complete(result)); XCTAssertEqual(model.state, .cancelled)
        XCTAssertTrue(model.hasSelection); XCTAssertNil(model.imageUpload); XCTAssertNil(model.thumbnail)
        model.remove(); XCTAssertFalse(model.hasSelection)
    }
    func testReselectionRejectsOldSuccessAndOldFailureWithoutChangingNewAttempt() throws {
        let model = SquarePostLocalMediaPresentation(), old = try preview(begin(model))
        let next = try preview(begin(model))
        XCTAssertFalse(model.complete(old)); model.fail(old.evidence.token)
        XCTAssertEqual(model.state, .loading); XCTAssertTrue(model.complete(next))
        XCTAssertEqual(model.imageUpload?.reference, next.evidence.token.reference)
    }
    func testCancelReselectionPreservesPreviousReadyImage() throws {
        let model = SquarePostLocalMediaPresentation(), result = try preview(begin(model))
        XCTAssertTrue(model.complete(result)); let upload = try XCTUnwrap(model.imageUpload)
        model.beginPicker(scope: upload.scope); model.cancelPicker()
        XCTAssertEqual(model.state, .imagePreview); XCTAssertEqual(model.imageUpload?.reference, upload.reference)
        XCTAssertNotNil(model.thumbnail); XCTAssertNil(model.pickerRequest)
    }
    func testEmptyPickerCancellationIsAnExplicitNonFailure() throws {
        let model = SquarePostLocalMediaPresentation(); model.beginPicker(scope: try scope())
        let request = try XCTUnwrap(model.pickerRequest)
        XCTAssertTrue(model.accept(provider: nil, request: request, maximumImageBytes: 100, scopeIsCurrent: { true }))
        XCTAssertEqual(model.state, .cancelled); XCTAssertNil(model.imageUpload); XCTAssertFalse(model.hasSelection)
    }
    func testMissingVideoPolicyNeverReadsProviderAndCannotMakeImageUpload() throws {
        let unexpected = expectation(description: "No video byte read"); unexpected.isInverted = true
        // public.video is a known movie subtype, not an unknown representation.
        for type in [UTType.movie, .video, .mpeg4Movie] {
            let model = SquarePostLocalMediaPresentation(), provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
                unexpected.fulfill(); completion(Data("video fixture".utf8), nil); return nil
            }
            XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier))
            model.beginPicker(scope: try scope()); let request = try XCTUnwrap(model.pickerRequest)
            XCTAssertTrue(model.accept(provider: provider, request: request, maximumImageBytes: 100, scopeIsCurrent: { true }))
            XCTAssertEqual(model.state, .videoUnavailable); XCTAssertEqual(model.selectedKind, .video)
            XCTAssertNil(model.imageUpload); XCTAssertNil(model.thumbnail); XCTAssertNil(model.loadTask)
            XCTAssertEqual(model.snapshot?.items.first?.phase, .selected)
            XCTAssertTrue(model.hasSelection); XCTAssertFalse(model.unresolvedSelection)
            model.remove(); XCTAssertFalse(model.hasSelection)
        }
        wait(for: [unexpected], timeout: 0.01)
    }
    func testStalePickerCannotReplaceAReadyNewSelection() throws {
        let model = SquarePostLocalMediaPresentation(); model.beginPicker(scope: try scope())
        let old = try XCTUnwrap(model.pickerRequest), new = try preview(begin(model))
        XCTAssertTrue(model.complete(new))
        XCTAssertFalse(model.accept(provider: NSItemProvider(), request: old, maximumImageBytes: 100, scopeIsCurrent: { false }))
        XCTAssertEqual(model.imageUpload?.reference, new.evidence.token.reference)
        XCTAssertEqual(model.state, .imagePreview)
    }
    func testAccountEpochDraftAndLaneChangesRetireOldEvidence() throws {
        for replacement in [try scope(account: 43), try scope(epoch: 2), try scope(draft: "draft-two"), try scope(lane: .communityV1)] {
            let model = SquarePostLocalMediaPresentation(), old = try preview(begin(model))
            model.bind(scope: replacement)
            XCTAssertFalse(model.complete(old)); XCTAssertEqual(model.scope, replacement)
            XCTAssertNil(model.imageUpload); XCTAssertNil(model.thumbnail); XCTAssertNil(model.pickerRequest)
        }
    }
    func testPageExitOrBackgroundInvalidatesPreviewAndSameScopeReopenCannotRestoreIt() throws {
        let model = SquarePostLocalMediaPresentation(), old = try preview(begin(model))
        XCTAssertTrue(model.complete(old)); model.openPreview(); let previewID = try XCTUnwrap(model.previewRequest)
        model.invalidate(); XCTAssertEqual(model.state, .expired); XCTAssertFalse(model.previewIsCurrent(previewID))
        XCTAssertNil(model.scope); XCTAssertNil(model.thumbnail); XCTAssertNil(model.imageUpload)
        model.bind(scope: try scope()); XCTAssertFalse(model.complete(old)); XCTAssertEqual(model.state, .empty)
    }
    func testPreviewCloseAndRemovalNeverRetainOldSheetPixels() throws {
        let model = SquarePostLocalMediaPresentation(), result = try preview(begin(model))
        XCTAssertTrue(model.complete(result)); model.openPreview(); let first = try XCTUnwrap(model.previewRequest)
        model.closePreview(); XCTAssertFalse(model.previewIsCurrent(first)); XCTAssertNotNil(model.thumbnail)
        model.openPreview(); let second = try XCTUnwrap(model.previewRequest)
        XCTAssertNotEqual(first, second); model.remove(); XCTAssertFalse(model.previewIsCurrent(second)); XCTAssertNil(model.thumbnail)
    }
    func testFailedImageCanBeReselectedAndClearedAfterExistingUpload() throws {
        let model = SquarePostLocalMediaPresentation(), first = try begin(model)
        model.fail(first.token); XCTAssertEqual(model.state, .failed); XCTAssertNil(model.imageUpload)
        let retry = try preview(begin(model)); XCTAssertTrue(model.complete(retry))
        let input = try XCTUnwrap(model.imageUpload); model.clearUploaded(input)
        XCTAssertEqual(model.state, .empty); XCTAssertNil(model.imageUpload); XCTAssertNil(model.thumbnail)
    }
    func testLateUploadCleanupCannotClearNewSelection() throws {
        let model = SquarePostLocalMediaPresentation(), old = try preview(begin(model))
        XCTAssertTrue(model.complete(old)); let oldUpload = try XCTUnwrap(model.imageUpload)
        let next = try preview(begin(model)); XCTAssertTrue(model.complete(next))
        model.clearUploaded(oldUpload)
        XCTAssertEqual(model.imageUpload?.reference, next.evidence.token.reference)
    }
    func testCurrentPickerWithExpiredOwnerScopeIsInvalidatedBeforeByteRead() throws {
        let model = SquarePostLocalMediaPresentation(); model.beginPicker(scope: try scope())
        let request = try XCTUnwrap(model.pickerRequest)
        XCTAssertFalse(model.accept(provider: NSItemProvider(), request: request, maximumImageBytes: 100, scopeIsCurrent: { false }))
        XCTAssertEqual(model.state, .expired); XCTAssertNil(model.pickerRequest); XCTAssertNil(model.scope)
    }
    func testCoreCopiedStreamStillCannotRecoverAfterFailureThroughAppDecoder() throws {
        let model = SquarePostLocalMediaPresentation(), first = try begin(model)
        var stream = first
        XCTAssertThrowsError(try stream.finish(.init(reference: stream.token.reference, kind: .image, mimeType: "image/png", reportedByteCount: 1, width: 1, height: 1, durationMilliseconds: nil)))
        XCTAssertThrowsError(try preview(first)) { error in XCTAssertEqual(error as? SquarePostLocalMediaIssue, .finished) }
        XCTAssertNil(model.imageUpload)
    }
    private func imageProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(nil, SquarePostLocalMediaIssue.inspectionFailed); return nil
        }
        return provider
    }
    func testAsyncOldScopeCompletionDoesNotInvalidateNewAccountSelection() async throws {
        let started = expectation(description: "old read started")
        var pending: CheckedContinuation<SquarePostLocalMediaImagePreview, Error>?
        var oldResult: SquarePostLocalMediaImagePreview?
        var ownerCurrent = true
        let model = SquarePostLocalMediaPresentation { _, _, _, inspection in
            oldResult = try self.preview(inspection)
            return try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
        }
        model.beginPicker(scope: try scope()); let request = try XCTUnwrap(model.pickerRequest)
        XCTAssertTrue(model.accept(provider: imageProvider(), request: request, maximumImageBytes: 1000, scopeIsCurrent: { ownerCurrent }))
        await fulfillment(of: [started], timeout: 1)
        let oldTask = try XCTUnwrap(model.loadTask)
        ownerCurrent = false
        let replacement = try scope(account: 43)
        let current = try preview(begin(model, scope: replacement)); XCTAssertTrue(model.complete(current))
        pending?.resume(returning: try XCTUnwrap(oldResult)); pending = nil
        await oldTask.value
        XCTAssertEqual(model.scope, replacement); XCTAssertEqual(model.state, .imagePreview)
        XCTAssertEqual(model.imageUpload?.reference, current.evidence.token.reference)
    }
    func testAsyncCancelledReadFailureCannotOverwriteReselectedImage() async throws {
        let started = expectation(description: "old read started")
        var pending: CheckedContinuation<SquarePostLocalMediaImagePreview, Error>?
        let model = SquarePostLocalMediaPresentation { _, _, _, _ in
            try await withCheckedThrowingContinuation { pending = $0; started.fulfill() }
        }
        model.beginPicker(scope: try scope()); let request = try XCTUnwrap(model.pickerRequest)
        XCTAssertTrue(model.accept(provider: imageProvider(), request: request, maximumImageBytes: 1000, scopeIsCurrent: { true }))
        await fulfillment(of: [started], timeout: 1)
        let oldTask = try XCTUnwrap(model.loadTask); model.cancelInspection()
        let current = try preview(begin(model)); XCTAssertTrue(model.complete(current))
        pending?.resume(throwing: CancellationError()); pending = nil
        await oldTask.value
        XCTAssertEqual(model.state, .imagePreview); XCTAssertEqual(model.imageUpload?.reference, current.evidence.token.reference)
    }

    private func fileProvider(_ url: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil); return nil
        }
        return provider
    }
    func testActualProviderFileReadReturnsOwnedBytesAndDecodedThumbnail() async throws {
        let model = SquarePostLocalMediaPresentation(), bytes = try png()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try bytes.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let result = try await SquarePostLocalMediaInspector.loadImage(provider: fileProvider(url), type: .png,
            maximumBytes: bytes.count, inspection: begin(model))
        XCTAssertEqual(result.bytes, bytes); XCTAssertEqual(result.evidence.byteCount, Int64(bytes.count))
        XCTAssertTrue(model.complete(result)); XCTAssertNotNil(model.thumbnail)
    }
    func testActualProviderFileReadRejectsOversizedInputBeforeDecode() async throws {
        let model = SquarePostLocalMediaPresentation(), bytes = try png()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try bytes.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await SquarePostLocalMediaInspector.loadImage(provider: fileProvider(url), type: .png,
                maximumBytes: bytes.count - 1, inspection: begin(model))
            XCTFail("An oversized file must not become an image preview")
        } catch { XCTAssertEqual(error as? SquarePostLocalMediaIssue, .byteLimit) }
        XCTAssertNil(model.thumbnail); XCTAssertNil(model.imageUpload)
    }
    func testPreCancelledProviderReadDoesNotRequestBytes() async throws {
        let model = SquarePostLocalMediaPresentation(), inspection = try begin(model), provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            XCTFail("A pre-cancelled read must not request a representation")
            completion(nil, false, SquarePostLocalMediaIssue.inspectionFailed); return nil
        }
        let task = Task { try await SquarePostLocalMediaInspector.loadImage(provider: provider, type: .png,
            maximumBytes: 100, inspection: inspection) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(model.imageUpload)
    }
    func testProviderFailureReturnsNoPixelsOrUploadBytes() async throws {
        let model = SquarePostLocalMediaPresentation(), provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            completion(nil, false, SquarePostLocalMediaIssue.inspectionFailed); return nil
        }
        do {
            _ = try await SquarePostLocalMediaInspector.loadImage(provider: provider, type: .png,
                maximumBytes: 100, inspection: begin(model))
            XCTFail("A failed provider must not produce a preview")
        } catch { XCTAssertEqual(error as? SquarePostLocalMediaIssue, .inspectionFailed) }
        XCTAssertNil(model.thumbnail); XCTAssertNil(model.imageUpload)
    }

    func testCurrentUploadAcknowledgmentAppendsExactlyOnceAndConsumesSelection() throws {
        let model = SquarePostLocalMediaPresentation(), result = try preview(begin(model))
        XCTAssertTrue(model.complete(result)); let upload = try XCTUnwrap(model.imageUpload)
        var applied = 0
        XCTAssertTrue(model.applyUploadAcknowledgment(upload) { applied += 1 })
        XCTAssertEqual(applied, 1); XCTAssertNil(model.imageUpload); XCTAssertFalse(model.hasSelection)
        XCTAssertFalse(model.applyUploadAcknowledgment(upload) { applied += 1 })
        XCTAssertEqual(applied, 1)
    }
    func testBackgroundRetiredSelectionRejectsLateUploadAcknowledgment() throws {
        let model = SquarePostLocalMediaPresentation(), result = try preview(begin(model))
        XCTAssertTrue(model.complete(result)); let upload = try XCTUnwrap(model.imageUpload)
        model.invalidate() // The composer's non-active scenePhase path.
        var applied = false
        XCTAssertFalse(model.applyUploadAcknowledgment(upload) { applied = true })
        XCTAssertFalse(applied); XCTAssertEqual(model.state, .expired); XCTAssertNil(model.thumbnail)
    }
    func testPageExitAndSameScopeReturnRejectLateUploadAcknowledgment() throws {
        let model = SquarePostLocalMediaPresentation(), result = try preview(begin(model))
        XCTAssertTrue(model.complete(result)); let upload = try XCTUnwrap(model.imageUpload)
        model.invalidate(); model.bind(scope: upload.scope) // onDisappear, then same draft reopened.
        var applied = false
        XCTAssertFalse(model.applyUploadAcknowledgment(upload) { applied = true })
        XCTAssertFalse(applied); XCTAssertEqual(model.state, .empty)
    }
    func testRemovedSelectionRejectsLateUploadAcknowledgment() throws {
        let model = SquarePostLocalMediaPresentation(), result = try preview(begin(model))
        XCTAssertTrue(model.complete(result)); let upload = try XCTUnwrap(model.imageUpload)
        model.remove(); var applied = false
        XCTAssertFalse(model.applyUploadAcknowledgment(upload) { applied = true })
        XCTAssertFalse(applied); XCTAssertFalse(model.hasSelection)
    }
    func testReselectedImageRejectsOldUploadAcknowledgmentWithoutClearingNewImage() throws {
        let model = SquarePostLocalMediaPresentation(), first = try preview(begin(model))
        XCTAssertTrue(model.complete(first)); let old = try XCTUnwrap(model.imageUpload)
        let next = try preview(begin(model)); XCTAssertTrue(model.complete(next))
        var applied = false
        XCTAssertFalse(model.applyUploadAcknowledgment(old) { applied = true })
        XCTAssertFalse(applied); XCTAssertEqual(model.imageUpload?.reference, next.evidence.token.reference)
        XCTAssertEqual(model.state, .imagePreview)
    }


    private func unsupportedProvider(_ type: UTType) -> NSItemProvider {
        unsupportedProvider(typeIdentifier: type.identifier)
    }
    private func unsupportedProvider(typeIdentifier: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: typeIdentifier, visibility: .all) { completion in
            XCTFail("Unsupported formats must not start a byte read")
            completion(nil, SquarePostLocalMediaIssue.inspectionFailed); return nil
        }
        return provider
    }
    func testUnsupportedHEICSelectionBlocksSaveUntilExplicitRemoval() throws {
        let model = SquarePostLocalMediaPresentation(); model.beginPicker(scope: try scope())
        XCTAssertFalse(model.accept(provider: unsupportedProvider(.heic), request: try XCTUnwrap(model.pickerRequest),
            maximumImageBytes: 1000, scopeIsCurrent: { true }))
        XCTAssertEqual(model.state, .failed); XCTAssertTrue(model.unresolvedSelection); XCTAssertTrue(model.hasSelection)
        XCTAssertNil(model.imageUpload); XCTAssertNil(model.thumbnail); XCTAssertNil(model.loadTask)
        model.remove(); XCTAssertFalse(model.hasSelection); XCTAssertFalse(model.unresolvedSelection)
    }
    func testUnsupportedWebPSelectionNeverReadsAndBlocksSaveUntilExplicitRemoval() throws {
        for replacesReadyImage in [false, true] {
            let model = SquarePostLocalMediaPresentation()
            if replacesReadyImage { XCTAssertTrue(model.complete(try preview(begin(model)))) }
            model.beginPicker(scope: try scope())
            XCTAssertFalse(model.accept(provider: unsupportedProvider(.webP), request: try XCTUnwrap(model.pickerRequest),
                maximumImageBytes: 1000, scopeIsCurrent: { true }))
            XCTAssertEqual(model.state, .failed); XCTAssertTrue(model.unresolvedSelection); XCTAssertTrue(model.hasSelection)
            XCTAssertNil(model.imageUpload); XCTAssertNil(model.thumbnail); XCTAssertNil(model.loadTask)
            model.beginPicker(scope: try scope()); model.cancelPicker()
            XCTAssertEqual(model.state, .failed); XCTAssertTrue(model.hasSelection)
            model.remove(); XCTAssertFalse(model.hasSelection); XCTAssertFalse(model.unresolvedSelection)
        }
    }
    func testWebPProviderWithJPEGRepresentationUsesOnlyDecodedJPEG() async throws {
        let image = try XCTUnwrap(UIImage(data: png()))
        let bytes = try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        try bytes.write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        let provider = unsupportedProvider(.webP)
        provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil); return nil
        }
        let model = SquarePostLocalMediaPresentation(); model.beginPicker(scope: try scope())
        XCTAssertEqual(SquarePostLocalMediaInspector.imageType(in: provider), .jpeg)
        XCTAssertTrue(model.accept(provider: provider, request: try XCTUnwrap(model.pickerRequest),
            maximumImageBytes: bytes.count, scopeIsCurrent: { true }))
        let task = try XCTUnwrap(model.loadTask); await task.value
        XCTAssertEqual(model.state, .imagePreview); XCTAssertNotNil(model.thumbnail)
        XCTAssertEqual(model.imageUpload?.mimeType, "image/jpeg"); XCTAssertEqual(model.imageUpload?.bytes, bytes)
        model.remove(); XCTAssertFalse(model.hasSelection)
    }
    func testUnknownVideoRepresentationBlocksSaveUntilExplicitRemoval() throws {
        // Deliberately undeclared raw identifier: the name alone grants no media conformance.
        let typeIdentifier = "com.questify.tests.unknown-video"
        for replacesReadyImage in [false, true] {
            let provider = unsupportedProvider(typeIdentifier: typeIdentifier)
            XCTAssertEqual(provider.registeredTypeIdentifiers, [typeIdentifier])
            XCTAssertFalse(provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier))
            XCTAssertFalse(provider.hasItemConformingToTypeIdentifier(UTType.image.identifier))
            XCTAssertNil(SquarePostLocalMediaInspector.imageType(in: provider))
            let model = SquarePostLocalMediaPresentation()
            if replacesReadyImage { XCTAssertTrue(model.complete(try preview(begin(model)))) }
            model.beginPicker(scope: try scope())
            XCTAssertFalse(model.accept(provider: provider, request: try XCTUnwrap(model.pickerRequest),
                maximumImageBytes: 1000, scopeIsCurrent: { true }))
            XCTAssertEqual(model.state, .failed); XCTAssertTrue(model.unresolvedSelection); XCTAssertTrue(model.hasSelection)
            XCTAssertNil(model.selectedKind); XCTAssertNil(model.loadTask); XCTAssertNil(model.imageUpload); XCTAssertNil(model.thumbnail)
            model.beginPicker(scope: try scope()); model.cancelPicker()
            XCTAssertEqual(model.state, .failed); XCTAssertTrue(model.unresolvedSelection); XCTAssertTrue(model.hasSelection)
            model.remove(); XCTAssertFalse(model.hasSelection); XCTAssertFalse(model.unresolvedSelection)
        }
    }
    func testProviderWithNoUsableRepresentationRemainsAnUnresolvedSelection() throws {
        let model = SquarePostLocalMediaPresentation(); model.beginPicker(scope: try scope())
        XCTAssertFalse(model.accept(provider: NSItemProvider(), request: try XCTUnwrap(model.pickerRequest),
            maximumImageBytes: 1000, scopeIsCurrent: { true }))
        XCTAssertEqual(model.state, .failed); XCTAssertTrue(model.hasSelection); XCTAssertNil(model.imageUpload)
        model.beginPicker(scope: try scope()); model.cancelPicker()
        XCTAssertEqual(model.state, .failed); XCTAssertTrue(model.hasSelection)
        model.remove(); XCTAssertFalse(model.hasSelection)
    }
    func testUnsupportedReselectionCannotFallBackToPublishingWithoutTheFailedMedia() throws {
        let model = SquarePostLocalMediaPresentation(), ready = try preview(begin(model))
        XCTAssertTrue(model.complete(ready)); let oldUpload = try XCTUnwrap(model.imageUpload)
        model.beginPicker(scope: oldUpload.scope)
        XCTAssertFalse(model.accept(provider: NSItemProvider(), request: try XCTUnwrap(model.pickerRequest),
            maximumImageBytes: 1000, scopeIsCurrent: { true }))
        XCTAssertTrue(model.hasSelection); XCTAssertNil(model.imageUpload); XCTAssertNil(model.thumbnail)
        var applied = false
        XCTAssertFalse(model.applyUploadAcknowledgment(oldUpload) { applied = true }); XCTAssertFalse(applied)
        model.remove(); XCTAssertFalse(model.hasSelection)
    }

    func testMixedMovieAndJPEGProviderNeverDowngradesToImageOrReadsRepresentations() throws {
        for types in [[UTType.jpeg, .movie], [UTType.movie, .jpeg]] {
            let model = SquarePostLocalMediaPresentation(), provider = NSItemProvider()
            for type in types {
                provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
                    XCTFail("Neither a movie nor its JPEG representation may be loaded without the video contract")
                    completion(nil, SquarePostLocalMediaIssue.inspectionFailed); return nil
                }
            }
            model.beginPicker(scope: try scope()); let request = try XCTUnwrap(model.pickerRequest)
            XCTAssertTrue(model.accept(provider: provider, request: request, maximumImageBytes: 1000, scopeIsCurrent: { true }))
            XCTAssertEqual(model.state, .videoUnavailable); XCTAssertEqual(model.selectedKind, .video)
            XCTAssertEqual(model.snapshot?.items.first?.kind, .video)
            XCTAssertEqual(model.snapshot?.items.first?.phase, .selected)
            XCTAssertNil(model.loadTask); XCTAssertNil(model.thumbnail); XCTAssertNil(model.imageUpload)
            XCTAssertTrue(model.hasSelection)
            model.remove(); XCTAssertFalse(model.hasSelection)
        }
    }

}
