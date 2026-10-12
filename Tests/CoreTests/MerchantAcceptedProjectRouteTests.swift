import XCTest
@testable import QuestifyCore

final class MerchantAcceptedProjectRouteTests: XCTestCase {
    private func row(type: Int = 0, status: Int = 1, topic: CoopFlowJSON = .id(70), id: CoopFlowJSON = .id(71), legacy: CoopFlowJSON = .null) -> CoopFlowJSON {
        .object(["id": id, "topicId": topic, "inviteType": .id(type), "status": .id(status), "legacyReadonly": legacy])
    }
    func testOnlyTwoExactMerchantSidesCanOpen() {
        XCTAssertNotNil(MerchantAcceptedProjectRoute(row: row(type: 0), direction: .received))
        XCTAssertNotNil(MerchantAcceptedProjectRoute(row: row(type: 1), direction: .sent))
        XCTAssertNil(MerchantAcceptedProjectRoute(row: row(type: 0), direction: .sent))
        XCTAssertNil(MerchantAcceptedProjectRoute(row: row(type: 1), direction: .received))
    }
    func testOnlyAcceptedStatusAndNonlegacyTypes() {
        for status in [0,2,3,4,5,99] { XCTAssertNil(MerchantAcceptedProjectRoute(row: row(status: status), direction: .received)) }
        for type in [-1,2,99] { XCTAssertNil(MerchantAcceptedProjectRoute(row: row(type: type), direction: .received)) }
        XCTAssertNil(MerchantAcceptedProjectRoute(row: row(legacy: .bool(true)), direction: .received))
    }
    func testUnknownLegacyShapeCannotAuthorizeEntry() {
        for legacy in [CoopFlowJSON.string("false"), .id(0)] { XCTAssertNil(MerchantAcceptedProjectRoute(row: row(legacy: legacy), direction: .received)) }
    }
    func testBadIDsAndRoundedNumbersAreRejected() {
        for id in [CoopFlowJSON.null, .bool(true), .id(0), .id(-1), .string("+70"), .string(" 70"), .string("70.5"), .id(9_007_199_254_740_992)] {
            XCTAssertNil(MerchantAcceptedProjectRoute(row: row(topic: id), direction: .received))
            XCTAssertNil(MerchantAcceptedProjectRoute(row: row(id: id), direction: .received))
        }
    }
    func testExactLongStringIDsFollowMiniParserWithoutNumberRounding() throws {
        let route = try XCTUnwrap(MerchantAcceptedProjectRoute(row: row(topic: .string("9223372036854775807"), id: .string("00071")), direction: .received))
        XCTAssertEqual(route.topicID, Int.max); XCTAssertEqual(route.invitationID, 71)
        XCTAssertNil(MerchantAcceptedProjectRoute(row: row(topic: .string("9223372036854775808")), direction: .received))
    }
    func testConflictingAliasOrIdentityErrorRejectsEntry() {
        var fields: [String: CoopFlowJSON] = ["id": .id(71), "topicId": .id(70), "inviteType": .id(0), "status": .id(1), "inviteId": .id(72)]
        XCTAssertNil(MerchantAcceptedProjectRoute(row: .object(fields), direction: .received))
        fields["inviteId"] = .string("0071"); fields["identityError"] = .string("")
        XCTAssertNotNil(MerchantAcceptedProjectRoute(row: .object(fields), direction: .received))
        fields["identityError"] = .string("conflict")
        XCTAssertNil(MerchantAcceptedProjectRoute(row: .object(fields), direction: .received))
    }
    func testUniqueFreshInvitationMustRetainExactTopicAndRole() throws {
        let original = row(), route = try XCTUnwrap(MerchantAcceptedProjectRoute(row: original, direction: .received))
        XCTAssertTrue(route.matchesUniqueRow([original])); XCTAssertFalse(route.matchesUniqueRow([]))
        XCTAssertFalse(route.matchesUniqueRow([original,original]))
        XCTAssertFalse(route.matchesUniqueRow([row(topic: .id(72))]))
        XCTAssertFalse(route.matchesUniqueRow([row(status: 3)]))
        XCTAssertEqual(route.sourceKey, "received")
    }
}
