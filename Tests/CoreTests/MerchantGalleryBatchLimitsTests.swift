import XCTest
@testable import QuestifyCore

final class MerchantGalleryBatchLimitsTests: XCTestCase {
    private func image(bytes: Int = 4) throws -> RetainedSelectedImage {
        var data = Data([255, 216, 255]); data.append(Data(repeating: 0, count: bytes - 3))
        return try .init(jpeg: data, width: 160, height: 90)
    }
    func testCapacityAndStableUniqueIdentity() throws {
        XCTAssertEqual(MerchantGalleryBatchLimits.remaining(currentCount: 0), 9)
        XCTAssertEqual(MerchantGalleryBatchLimits.remaining(currentCount: 8), 1)
        for count in [-1, 9, 10] { XCTAssertEqual(MerchantGalleryBatchLimits.remaining(currentCount: count), 0) }
        let a = try image(), b = try image()
        XCTAssertTrue(MerchantGalleryBatchLimits.accepts([a, b], currentCount: 7))
        XCTAssertFalse(MerchantGalleryBatchLimits.accepts([a, b], currentCount: 8))
        XCTAssertFalse(MerchantGalleryBatchLimits.accepts([a, a], currentCount: 0))
        XCTAssertFalse(MerchantGalleryBatchLimits.accepts([], currentCount: 0))
    }
    func testAggregateBytesBoundBeforeQueueRetention() throws {
        let images = try (0..<4).map { _ in try image(bytes: RetainedSelectedImage.maximumBytes) }
        XCTAssertTrue(MerchantGalleryBatchLimits.accepts(Array(images.prefix(3)), currentCount: 0))
        XCTAssertFalse(MerchantGalleryBatchLimits.accepts(images, currentCount: 0))
    }
}
