import XCTest
@testable import QuestifyCore

@MainActor final class PlayDeviceExplicitOutputTests: XCTestCase {
    private func context() throws -> PlayDeviceContext {
        try .init(session: .init(accountID: 1, epoch: 1, namespace: "explicit-output-tests", token: "synthetic-token"), scope: .activity(41), nodeID: 701)
    }
    func testExplicitWrongIDRejectsLegacyUnboundPhotoUpload() async throws {
        let context = try context(); var writes = 0
        let provider = PlaySyntheticDeviceProvider(supported: [.photo]) { _, _ in .photo(Data([1, 2]), mimeType: "image/png") }
        let model = PlayDeviceCaptureCoordinator(provider: provider, upload: { _, _, _ in writes += 1; return "https://example.test/image" }, current: { context })
        await model.capture(.photo); await model.uploadPhoto(expectedOutputID: UUID())
        XCTAssertEqual(writes, 0); XCTAssertNil(model.uploadedPhoto)
        let actual = try XCTUnwrap(model.outputID); await model.uploadPhoto(expectedOutputID: actual)
        XCTAssertEqual(writes, 1); XCTAssertNotNil(model.reviewedPhoto(expectedOutputID: actual))
        XCTAssertNil(model.reviewedPhoto(expectedOutputID: UUID()))
    }
    func testReplacementCaptureRejectsOldExplicitUploadAndReadbackID() async throws {
        let context = try context(); var writes: [Data] = []; var bytes = Data([1])
        let provider = PlaySyntheticDeviceProvider(supported: [.photo]) { _, _ in .photo(bytes, mimeType: "image/png") }
        let model = PlayDeviceCaptureCoordinator(provider: provider, upload: { data, _, _ in writes.append(data); return "https://example.test/image" }, current: { context })
        await model.capture(.photo); let old = try XCTUnwrap(model.outputID)
        bytes = Data([2]); await model.capture(.photo); let fresh = try XCTUnwrap(model.outputID)
        await model.uploadPhoto(expectedOutputID: old); XCTAssertTrue(writes.isEmpty)
        await model.uploadPhoto(expectedOutputID: fresh); XCTAssertEqual(writes, [Data([2])])
        XCTAssertNil(model.reviewedPhoto(expectedOutputID: old)); XCTAssertNotNil(model.reviewedPhoto(expectedOutputID: fresh))
    }
    func testExistingNilCompatibilityForUnboundCaptureRemains() async throws {
        let context = try context(); var writes = 0
        let provider = PlaySyntheticDeviceProvider(supported: [.photo]) { _, _ in .photo(Data([1]), mimeType: "image/png") }
        let model = PlayDeviceCaptureCoordinator(provider: provider, upload: { _, _, _ in writes += 1; return "https://example.test/image" }, current: { context })
        await model.capture(.photo); await model.uploadPhoto()
        XCTAssertEqual(writes, 1); XCTAssertNotNil(model.reviewedPhoto())
    }
}
