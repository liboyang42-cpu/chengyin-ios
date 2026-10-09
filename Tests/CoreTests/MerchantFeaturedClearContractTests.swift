import Foundation
import XCTest
@testable import QuestifyCore

final class MerchantFeaturedClearContractTests: XCTestCase {
    private func decode(_ raw: String) throws -> MerchantStoreDecor {
        try JSONDecoder().decode(MerchantStoreDecor.self, from: Data(raw.utf8))
    }
    func testExplicitClearOnlyPayloadIsValidAndEncodesZeroAndNull() throws {
        let draft = try decode(#"{"featuredType":0,"featuredId":null}"#)
        XCTAssertNil(draft.blocker)
        let fields = try draft.fields()
        XCTAssertEqual(fields["featuredType"] as? Int, 0); XCTAssertTrue(fields["featuredId"] is NSNull)
        let request = try XCTUnwrap(MerchantOperationsDraft.decor(draft).previews().first)
        XCTAssertEqual(request.path, "api/merchant/decor/save")
    }
    func testMissingAndNullTypeRemainEmptyInsteadOfDefaultingToClear() throws {
        for raw in ["{}", #"{"featuredType":null,"featuredId":null}"#, #"{"featuredId":null}"#] {
            let draft = try decode(raw)
            XCTAssertNil(draft.featuredType); XCTAssertEqual(draft.blocker, "merchant.operations.decorEmpty")
        }
    }
    func testClearDoesNotAllowConflictingIDOrOversizedGallery() throws {
        XCTAssertEqual(try decode(#"{"featuredType":0,"featuredId":7}"#).blocker, "merchant.operations.featuredIncomplete")
        var draft = try decode(#"{"featuredType":0,"featuredId":null}"#)
        draft.gallery = Array(repeating: "image", count: 10)
        XCTAssertEqual(draft.blocker, "merchant.operations.galleryLimit")
    }
}
