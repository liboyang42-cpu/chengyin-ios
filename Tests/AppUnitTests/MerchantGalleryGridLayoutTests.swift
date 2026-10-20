import XCTest
@testable import Questify

final class MerchantGalleryGridLayoutTests: XCTestCase {
    func testFixedNineSlotsPreserveOrderAndPadEmptySlots() {
        let layout = MerchantGalleryGridLayout(gallery: ["img-a", "img-b", "img-c", "img-d"])
        XCTAssertEqual(layout.slots.count, 9)
        XCTAssertEqual(layout.rows.count, 3)
        XCTAssertEqual(layout.rows.map(\.count), [3, 3, 3])
        XCTAssertEqual(layout.imageCount, 4)
        XCTAssertFalse(layout.isFull)
        XCTAssertEqual(layout.slots[0], .image(index: 0, reference: "img-a"))
        XCTAssertEqual(layout.slots[3], .image(index: 3, reference: "img-d"))
        XCTAssertEqual(layout.slots[4], .empty(index: 4))
        XCTAssertEqual(layout.slots[8], .empty(index: 8))
    }

    func testDeletingMiddleSlotPreservesSurvivingRelativeOrder() {
        var gallery = ["img-0", "img-1", "img-2", "img-3"]
        XCTAssertTrue(MerchantGalleryGridLayout.canRemove(index: 1, in: gallery))
        gallery.remove(at: 1)
        let after = MerchantGalleryGridLayout(gallery: gallery)
        XCTAssertEqual(after.imageCount, 3)
        XCTAssertEqual(after.slots[0], .image(index: 0, reference: "img-0"))
        XCTAssertEqual(after.slots[1], .image(index: 1, reference: "img-2"))
        XCTAssertEqual(after.slots[2], .image(index: 2, reference: "img-3"))
        XCTAssertEqual(after.slots[3], .empty(index: 3))
        XCTAssertFalse(MerchantGalleryGridLayout.canRemove(index: 3, in: gallery))
        XCTAssertFalse(MerchantGalleryGridLayout.canRemove(index: -1, in: gallery))
        XCTAssertFalse(MerchantGalleryGridLayout.canRemove(index: 9, in: Array(repeating: "x", count: 12)))
    }
}
