import Foundation
import XCTest
@testable import QuestifyCore

final class CommunityMediaIntegrationTests: XCTestCase {
    private let policy = NativeEntryLinkPolicy(verifiedHTTPSOrigins: ["https://example.test"])
    func testCanonicalMerchantUsesOwnerIdentity() throws {
        let route = try XCTUnwrap(policy.parse(URL(string: "https://example.test/merchant/public-home/member/42")!))
        guard case .publicMerchant(.ownerMemberID(let owner)) = route else { return XCTFail("wrong identity") }
        XCTAssertEqual(owner.rawValue, 42)
    }
    func testLegacyMerchantUsesRowIdentity() throws {
        let route = try XCTUnwrap(policy.parse(URL(string: "https://example.test/merchant/public-home/42")!))
        guard case .publicMerchant(.legacyMerchantRowID(let row)) = route else { return XCTFail("wrong identity") }
        XCTAssertEqual(row.rawValue, 42)
    }
    func testMerchantPathsRejectAmbiguityAndMalformedIdentity() {
        for path in ["/merchant/public-home/member/0", "/merchant/public-home/member/042", "/merchant/public-home/42?memberId=1", "/merchant//public-home/42", "/merchant/public-home/42/", "/merchant/public-home/%34%32"] {
            XCTAssertNil(policy.parse(URL(string: "https://example.test" + path)!))
        }
    }
    func testUnapprovedMerchantOriginStaysDisabled() {
        XCTAssertNil(NativeEntryLinkPolicy().parse(URL(string: "https://example.test/merchant/public-home/42")!))
    }
    func testOrderMapDestinationComesFromTicketOnly() throws {
        let data = Data(#"{"id":1,"cmsActivity":{"addressName":"Different activity address"},"omsTicket":{"meetingPoint":"Selected ticket gate","gatherLat":12.3,"gatherLng":45.6}}"#.utf8)
        let order = try JSONDecoder().decode(ProfileOrder.self, from: data)
        XCTAssertEqual(order.addressName, "Different activity address")
        XCTAssertEqual(order.meetingPoint, "Selected ticket gate")
        XCTAssertEqual(order.gatherLatitude, 12.3)
        XCTAssertEqual(order.gatherLongitude, 45.6)
    }
    func testOrderMissingTicketDoesNotInventCoordinates() throws {
        let order = try JSONDecoder().decode(ProfileOrder.self, from: Data(#"{"id":1,"cmsActivity":{"latitude":12,"longitude":45,"addressName":"Activity"}}"#.utf8))
        XCTAssertNil(order.meetingPoint); XCTAssertNil(order.gatherLatitude); XCTAssertNil(order.gatherLongitude)
    }
    func testPlayNodeCoordinatesAreOptionalSourceFields() throws {
        let node = try JSONDecoder().decode(PlayNode.self, from: Data(#"{"nodeId":9,"latitude":"12.3","longitude":45.6}"#.utf8))
        XCTAssertEqual(node.latitude, 12.3); XCTAssertEqual(node.longitude, 45.6)
        let missing = try JSONDecoder().decode(PlayNode.self, from: Data(#"{"nodeId":9}"#.utf8))
        XCTAssertNil(missing.latitude); XCTAssertNil(missing.longitude)
    }
    func testBadPlayCoordinatesDoNotBecomeDestination() throws {
        let node = try JSONDecoder().decode(PlayNode.self, from: Data(#"{"nodeId":9,"latitude":"nan","longitude":"bad"}"#.utf8))
        XCTAssertNil(node.latitude); XCTAssertNil(node.longitude)
    }
}
