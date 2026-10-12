import XCTest
@testable import QuestifyCore

final class MerchantOnboardingBrandImagesTests: XCTestCase {
    private let a = "https://fixtures.example/brand-a.jpg", b = "https://fixtures.example/brand-b.jpg"
    func testEmptyFieldRemainsOptionalForUntouchedExistingDrafts() throws {
        let d = try makeMerchantOnboardingDraft()
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: d.jsonData()) as? [String: Any])
        XCTAssertNil(fields["derivatives"])
    }
    func testSourceOrderAndCommaSerialization() throws { let images = try MerchantOnboardingBrandImages(urls: [a,b]); XCTAssertEqual(images.wireValue, a + "," + b) }
    func testSixImagesIsHardLimit() throws {
        var images = try MerchantOnboardingBrandImages(urls: Array(repeating: a, count: 6)); XCTAssertFalse(images.canAdd)
        XCTAssertThrowsError(try images.append(serverURL: b)); XCTAssertEqual(images.urls.count, 6)
        XCTAssertThrowsError(try MerchantOnboardingBrandImages(urls: Array(repeating: a, count: 7)))
    }
    func testDuplicateSourceURLsAreNotDeduplicated() throws { XCTAssertEqual(try MerchantOnboardingBrandImages(urls: [a,a]).urls, [a,a]) }
    func testRemoveUsesExactIndexAndPreservesOrder() throws {
        var images = try MerchantOnboardingBrandImages(urls: [a,b,a]); try images.remove(at: 1); XCTAssertEqual(images.urls, [a,a])
    }
    func testBadIndexDoesNotChangeImages() throws {
        var images = try MerchantOnboardingBrandImages(urls: [a]); XCTAssertThrowsError(try images.remove(at: -1)); XCTAssertThrowsError(try images.remove(at: 1)); XCTAssertEqual(images.urls,[a])
    }
    func testUnsafeOrUnserializableURLsRejected() throws {
        for value in ["http://fixtures.example/a", "file:///tmp/a", "https://user:secret@fixtures.example/a", "https://fixtures.example/a,b", "data:image/jpeg;base64,AA"] {
            XCTAssertThrowsError(try MerchantOnboardingBrandImages(urls: [value]))
        }
    }
    func testAppendRequiresReturnedURLAndNormalizesSourceWhitespace() throws {
        var images = try MerchantOnboardingBrandImages(); try images.append(serverURL: " \(a) "); XCTAssertEqual(images.urls, [a])
    }
    func testNewFieldDoesNotChangeLicenseOrOtherPayloadValues() throws {
        var d = try makeMerchantOnboardingDraft(); let before = try XCTUnwrap(JSONSerialization.jsonObject(with: d.jsonData()) as? [String: String])
        d.brandImages = try .init(urls: [a,b]); var after = try XCTUnwrap(JSONSerialization.jsonObject(with: d.jsonData()) as? [String: String])
        XCTAssertEqual(after.removeValue(forKey: "derivatives"),a + "," + b); XCTAssertEqual(after,before)
    }
    func testExplicitClearSerializesEmptyString() throws {
        var d = try makeMerchantOnboardingDraft(); d.brandImages = try .init(urls:[a]); try d.brandImages?.remove(at:0)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with:d.jsonData()) as? [String:Any]); XCTAssertEqual(fields["derivatives"] as? String,"")
    }
    func testRejectedApplicationRestoresValidImagesOnly() throws {
        let app = try makeMerchantOnboardingApplication(status:2,extras:["derivatives":a + "," + b]);let d = try MerchantOnboardingDraft(reapplying:app)
        XCTAssertEqual(d.brandImages?.urls,[a,b]);XCTAssertFalse(d.brandImagesSourceUnavailable);XCTAssertEqual(d.wechat,"")
    }
    func testUnknownHistoricalSourceIsOmittedNotSilentlyCleared() throws {
        let d = try MerchantOnboardingDraft(reapplying:makeMerchantOnboardingApplication(status:2))
        XCTAssertNil(d.brandImages);XCTAssertTrue(d.brandImagesSourceUnavailable)
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with:d.jsonData()) as? [String:Any]);XCTAssertNil(fields["derivatives"])
    }
}
