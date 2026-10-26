import XCTest
@testable import QuestifyCore

final class PublishMediaChainTests: XCTestCase {
    // Synthetic profile values for tests only; production limits come from the server.
    private func profile(_ version: String = "synthetic-1", items: Int = 3) throws -> PublishMediaProfile {
        try JSONDecoder().decode(PublishMediaProfile.self, from: Data("{\"profileVersion\":\"\(version)\",\"maxItems\":\(items),\"maxImageBytes\":1000,\"maxVideoBytes\":5000,\"maxVideoMilliseconds\":60000}".utf8))
    }
    private let digest = String(repeating: "c", count: 64)

    func testKindsComeFromUniformTypesAndRejectMarkup() throws {
        XCTAssertEqual(try PublishMediaKind(uniformType: "public.jpeg"), .image)
        XCTAssertEqual(try PublishMediaKind(uniformType: "com.apple.quicktime-movie"), .video)
        XCTAssertThrowsError(try PublishMediaKind(uniformType: "public.svg-image"))
        XCTAssertThrowsError(try PublishMediaKind(uniformType: "public.html"))
    }

    func testLimitsAndDurationShapeAreEnforced() throws {
        let p = try profile()
        XCTAssertThrowsError(try PublishMediaItem(kind: .image, byteCount: 1001, durationMilliseconds: nil, profile: p)) { XCTAssertEqual($0 as? PublishMediaIssue, .tooLarge) }
        XCTAssertThrowsError(try PublishMediaItem(kind: .image, byteCount: 10, durationMilliseconds: 5, profile: p))
        XCTAssertThrowsError(try PublishMediaItem(kind: .video, byteCount: 10, durationMilliseconds: nil, profile: p))
        XCTAssertThrowsError(try PublishMediaItem(kind: .video, byteCount: 10, durationMilliseconds: 60001, profile: p)) { XCTAssertEqual($0 as? PublishMediaIssue, .tooLong) }
    }

    func testVideoWalksEveryStageInOrderWithMatchingReadbacks() throws {
        var item = try PublishMediaItem(kind: .video, byteCount: 4000, durationMilliseconds: 30000, profile: profile())
        XCTAssertThrowsError(try item.markUploaded(assetId: "a1", serverSHA256: digest)) { XCTAssertEqual($0 as? PublishMediaIssue, .outOfOrder) }
        try item.markProcessed(sha256: digest)
        XCTAssertThrowsError(try item.markUploaded(assetId: "a1", serverSHA256: String(repeating: "d", count: 64))) { XCTAssertEqual($0 as? PublishMediaIssue, .mismatchedReadback) }
        try item.markUploaded(assetId: "a1", serverSHA256: digest)
        XCTAssertThrowsError(try item.markReviewed(.approved)) // video needs a server poster.
        try item.markReviewed(.approved, posterAssetId: "p1")
        XCTAssertThrowsError(try item.markSaved(referencedAssetId: "other"))
        try item.markSaved(referencedAssetId: "a1")
        try item.markReadable(readbackAssetId: "a1", readbackSHA256: digest)
        try item.markPlayable()
        XCTAssertEqual(item.stage, .playable)
    }

    func testRejectedMediaIsNeverPublishable() throws {
        var selection = try PublishMediaSelection(profile: profile())
        var item = try PublishMediaItem(kind: .image, byteCount: 10, durationMilliseconds: nil, profile: profile())
        try item.markProcessed(sha256: digest); try item.markUploaded(assetId: "a2", serverSHA256: digest); try item.markReviewed(.rejected)
        XCTAssertThrowsError(try item.markSaved(referencedAssetId: "a2"))
        try selection.append(item)
        XCTAssertFalse(selection.publishable)
        XCTAssertTrue(selection.restorable().isEmpty)
    }

    func testSelectionCountAndProfileChangeAreChecked() throws {
        var selection = try PublishMediaSelection(profile: profile(items: 1))
        try selection.append(PublishMediaItem(kind: .image, byteCount: 10, durationMilliseconds: nil, profile: profile()))
        XCTAssertThrowsError(try selection.append(PublishMediaItem(kind: .image, byteCount: 10, durationMilliseconds: nil, profile: profile()))) { XCTAssertEqual($0 as? PublishMediaIssue, .tooMany) }
        XCTAssertThrowsError(try selection.requireProfile(profile("synthetic-2", items: 1))) { XCTAssertEqual($0 as? PublishMediaIssue, .staleProfile) }
    }
}
