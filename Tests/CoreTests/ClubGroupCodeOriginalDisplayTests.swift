import Foundation
import XCTest
@testable import QuestifyCore

final class ClubGroupCodeOriginalDisplayTests: XCTestCase {
    func testOriginalScopeMismatchAndAbsoluteExpiryReject() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let receipt: ClubGovernanceValue = .object(["qrcodeUrl": .string("https://example.test/offline.png"),
            "code": .string("SYNTHETIC-NONREDEEMABLE"), "ttlMs": .integer(300000),
            "expiresAt": .integer(1001000), "clubId": .integer(7), "activityId": .integer(8)])
        let value = try ClubGovernanceGroupCode(receipt: receipt, receivedAt: now, expectedClubID: 7, expectedActivityID: 8)
        XCTAssertEqual(value.expiresAt, Date(timeIntervalSince1970: 1001))
        XCTAssertFalse(value.isActive(at: Date(timeIntervalSince1970: 1001)))
        XCTAssertThrowsError(try ClubGovernanceGroupCode(receipt: receipt, receivedAt: now, expectedClubID: 7, expectedActivityID: 9))
        XCTAssertThrowsError(try ClubGovernanceGroupCode(receipt: receipt, receivedAt: Date(timeIntervalSince1970: 1002)))
    }
    func testInlineRequiresBoundedRealPNGWithoutRemoteFallback() throws {
        // A synthetic one-pixel PNG, not a QR code or credential.
        let inline = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAAAAAA6fptVAAAACklEQVR4nGNgAAAAAgABSK+kcQAAAABJRU5ErkJggg=="
        XCTAssertEqual(try ClubGroupCodeImage.inlinePNG(inline).count, 67)
        XCTAssertThrowsError(try ClubGroupCodeImage.inlinePNG("https://example.test/image.png"))
        XCTAssertThrowsError(try ClubGroupCodeImage.inlinePNG("data:image/png;base64,AAAA"))
        XCTAssertThrowsError(try ClubGroupCodeImage.validatePNG(Data(repeating: 0, count: ClubGroupCodeImage.maximumBytes + 1)))
    }
}
