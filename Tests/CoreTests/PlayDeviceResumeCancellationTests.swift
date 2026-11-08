import XCTest
@testable import QuestifyCore

@MainActor final class PlayDeviceResumeCancellationTests: XCTestCase {
    private func context() throws -> PlayDeviceContext {
        try .init(session: .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic"), scope: .activity(41), nodeID: 701)
    }
    func testPhotoAndScanPreviewDisappearForLostOrDifferentTaskIdentity() async throws {
        for kind in [PlayDeviceKind.photo, .scan] {
            var owner: PlayDeviceContext? = try context()
            let original = owner
            let provider = PlaySyntheticDeviceProvider(supported: [kind]) { _, _ in
                kind == .photo ? .photo(Data([1, 2, 3]), mimeType: "image/png") : .scan("synthetic-private-code")
            }
            let model = PlayDeviceCaptureCoordinator(provider: provider, current: { owner })
            await model.capture(kind)
            XCTAssertNotNil(model.currentOutput)
            owner = nil
            XCTAssertNil(model.currentOutput); XCTAssertFalse(model.canReviewOutput)
            // The previous raw output remains non-authoritative, preserving existing lifecycle semantics.
            XCTAssertNotNil(model.output)
            owner = try .init(session: .init(accountID: 8, epoch: 2, namespace: "synthetic", token: "other"), scope: .activity(41), nodeID: 701)
            XCTAssertNil(model.currentOutput)
            owner = try .init(session: .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic"), scope: .activity(41), nodeID: 702)
            XCTAssertNil(model.currentOutput)
            owner = original
            model.cancel()
            XCTAssertNil(model.currentOutput); XCTAssertNil(model.output)
            XCTAssertEqual(provider.captured.count, 1)
        }
    }
    func testCancelledReturnedScreenCannotReacquireLocationOrReplaceEvidence() async throws {
        let owner = try context()
        let provider = PlaySyntheticDeviceProvider(supported: [.location]) { _, _ in
            .location(121, 31, coordinateSystem: "GCJ02")
        }
        let model = PlayDeviceCaptureCoordinator(provider: provider, current: { owner })
        await model.capture(.location)
        let output = model.output, id = model.outputID
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await model.capture(.location)
        }
        await task.value
        XCTAssertEqual(provider.captured.count, 1)
        XCTAssertEqual(model.output, output); XCTAssertEqual(model.outputID, id)
        XCTAssertTrue(model.canReviewOutput); XCTAssertFalse(model.busy)
    }
    func testCancelledUploadNeverTransmitsAndPreservesOriginalPreview() async throws {
        let owner = try context()
        let provider = PlaySyntheticDeviceProvider(supported: [.photo]) { _, _ in .photo(Data([1, 2, 3]), mimeType: "image/png") }
        var uploads = 0
        let model = PlayDeviceCaptureCoordinator(provider: provider, upload: { _, _, _ in
            uploads += 1; return "https://example.test/synthetic.png"
        }, current: { owner })
        await model.capture(.photo)
        let output = model.output, id = model.outputID
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await model.uploadPhoto(expectedOutputID: id)
        }
        await task.value
        XCTAssertEqual(uploads, 0)
        XCTAssertEqual(model.output, output); XCTAssertEqual(model.outputID, id)
        XCTAssertNil(model.uploadedPhoto); XCTAssertFalse(model.busy)
        // A fresh explicit action still uses the original captured bytes.
        await model.uploadPhoto(expectedOutputID: id)
        XCTAssertEqual(uploads, 1)
    }
}
