import Foundation
import XCTest
@testable import QuestifyCore

final class NativeEntryRoutingTests: XCTestCase {
    func testDefaultPolicyAcceptsNothing() { XCTAssertNil(NativeEntryLinkPolicy().parse(URL(string: "https://example.test/door?scene=abcdef0123456789abcdef0123456789ab")!)) }
    func testApprovedDoorPreservesRawOneDecode() {
        let policy = NativeEntryLinkPolicy(verifiedHTTPSOrigins: ["https://example.test"])
        guard case .door(let intent) = policy.parse(URL(string: "https://example.test/door?scene=abcdef0123456789abcdef0123456789ab&inviter=42")!) else { return XCTFail() }
        XCTAssertEqual(intent.inviter, "42")
        XCTAssertEqual(DoorParsing.scene(intent.scene), "abcdef0123456789abcdef0123456789ab")
    }
    func testInvitationIsTypedWithoutMerchantGuess() {
        let policy = NativeEntryLinkPolicy(verifiedHTTPSOrigins: ["https://example.test"])
        guard case .merchantInvitation(let route) = policy.parse(URL(string: "https://example.test/merchant/team?invite=synthetic-token")!) else { return XCTFail() }
        XCTAssertEqual(route.invitation.token, "synthetic-token")
    }
    func testRejectsSpoofingAndUnsupportedRoutes() {
        let policy = NativeEntryLinkPolicy(verifiedHTTPSOrigins: ["https://example.test"])
        for text in ["http://example.test/merchant/team?invite=a", "https://evil.test/merchant/team?invite=a", "https://u@example.test/merchant/team?invite=a", "https://example.test:443/merchant/team?invite=a", "https://example.test/merchant/team?invite=a#x", "https://example.test/merchant/team?invite=a&invite=b", "https://example.test/merchant/team?invite=a&extra=1", "https://example.test/merchant/%74eam?invite=a", "https://example.test/merchant/team?%69nvite=a", "https://example.test/other?invite=a"] { XCTAssertNil(policy.parse(URL(string: text)!), text) }
    }
}
