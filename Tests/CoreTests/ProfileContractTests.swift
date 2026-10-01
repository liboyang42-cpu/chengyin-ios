import XCTest
@testable import QuestifyCore

final class ProfileContractTests: XCTestCase {
    private func decode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testOrderKeepsMissingAmountAndUnknownStatusesUnknown() throws {
        let order = try decode(ProfileOrder.self, #"{"id":12,"registrationStatus":99,"paymentStatus":7}"#)
        XCTAssertNil(order.payableAmount)
        XCTAssertEqual(order.registrationState, .unknown)
        XCTAssertEqual(order.paymentStatus, 7)
        XCTAssertNil(order.verificationStatus)
        XCTAssertNil(order.refundPayoutStatus)
    }
    func testExplicitZeroIsDifferentFromMissingAmount() throws {
        let zero = try decode(ProfileOrder.self, #"{"id":12,"payableAmount":0}"#)
        XCTAssertEqual(zero.payableAmount, .zero)
        XCTAssertNil(try decode(ProfileOrder.self, #"{"id":12,"payableAmount":null}"#).payableAmount)
    }
    func testOrderRejectsMoneyCoercionAndNegativeAmount() {
        for value in [#""12.50""#, "-0.01", "true"] {
            XCTAssertThrowsError(try decode(ProfileOrder.self, "{\"id\":12,\"payableAmount\":\(value)}"))
        }
    }
    func testOrderPreservesDecimalWithoutUnitOrCurrencyConversion() throws {
        let order = try decode(ProfileOrder.self, #"{"id":12,"payableAmount":123.45}"#)
        XCTAssertEqual(order.payableAmount, Decimal(string: "123.45"))
    }
    func testBothOwnerTypesAndMissingProductTypeRemainVisible() throws {
        let topic = try decode(ProfileOrder.self, #"{"id":1,"ownerType":1,"cmsTopic":{"name":"Topic","productType":null}}"#)
        let activity = try decode(ProfileOrder.self, #"{"id":2,"ownerType":2,"cmsActivity":{"name":"Activity","productType":1}}"#)
        XCTAssertEqual(topic.title, "Topic")
        XCTAssertNil(topic.productType)
        XCTAssertEqual(activity.productType, 1)
        XCTAssertEqual(activity.title, "Activity")
    }
    func testAssociatedActivityWinsOverTopicAsInSource() throws {
        let order = try decode(ProfileOrder.self, #"{"id":12,"cmsActivity":{"name":"Activity","productType":"2","startDate":"2026-10-03 10:00:00"},"cmsTopic":{"name":"Topic"}}"#)
        XCTAssertEqual(order.title, "Activity")
        XCTAssertEqual(order.productType, 2)
        XCTAssertEqual(order.startDate, "2026-10-03 10:00:00")
    }
    func testRefundZeroIsNotMissingAndStatusDoesNotDeclareSettlement() throws {
        let order = try decode(ProfileOrder.self, #"{"id":12,"registrationStatus":3,"verificationStatus":1,"refundApplication":{"payoutStatus":0},"statusText":"Server-owned status","orderHint":"Server-owned hint"}"#)
        XCTAssertEqual(order.refundPayoutStatus, 0)
        XCTAssertEqual(order.registrationState, .cancelled)
        XCTAssertEqual(order.verificationStatus, 1)
        XCTAssertNil(order.paymentStatus)
        XCTAssertEqual(order.statusText, "Server-owned status")
        XCTAssertEqual(order.orderHint, "Server-owned hint")
    }
    func testRegistrationKnownStatesAndUnknownDoNotCollapseToPendingPayment() {
        XCTAssertEqual(ProfileRegistrationState(code: 1), .awaitingPayment)
        XCTAssertEqual(ProfileRegistrationState(code: 2), .registered)
        XCTAssertEqual(ProfileRegistrationState(code: 3), .cancelled)
        XCTAssertEqual(ProfileRegistrationState(code: 4), .expired)
        XCTAssertEqual(ProfileRegistrationState(code: nil), .unknown)
        XCTAssertEqual(ProfileRegistrationState(code: -1), .unknown)
    }
    func testParticipantPreservesWholeRegionAndDoesNotInventCityFields() throws {
        let value = try decode(ProfileParticipant.self, #"{"id":1,"fullName":"Fixture Person","mobilePhone":"00000000000","province":"Province City District","detailAddress":"Fixture street","isDefault":"1"}"#)
        XCTAssertEqual(value.province, "Province City District")
        XCTAssertEqual(value.oneLineAddress, "Province City District Fixture street")
        XCTAssertTrue(value.isDefault)
    }
    func testParticipantOnlyRowDoesNotGainAnAddress() throws {
        let value = try decode(ProfileParticipant.self, #"{"id":1,"fullName":"Fixture Person","mobilePhone":"00000000000"}"#)
        XCTAssertTrue(value.oneLineAddress.isEmpty)
        XCTAssertFalse(value.isDefault)
        XCTAssertEqual(try decode(ProfileParticipant.self, #"{"id":2,"province":"  ","detailAddress":"Only detail"}"#).oneLineAddress, "Only detail")
    }
    func testParticipantDefaultTruthFollowsAddressSource() throws {
        for value in ["true", "1", #""1""#] {
            XCTAssertTrue(try decode(ProfileParticipant.self, "{\"id\":1,\"isDefault\":\(value)}").isDefault)
        }
        XCTAssertFalse(try decode(ProfileParticipant.self, #"{"id":1,"isDefault":"true"}"#).isDefault)
    }
    func testInvalidIDsCannotBecomeNavigableRows() {
        XCTAssertThrowsError(try decode(ProfileOrder.self, #"{"id":0}"#))
        XCTAssertThrowsError(try decode(ProfileOrder.self, #"{}"#))
        XCTAssertThrowsError(try decode(ProfileParticipant.self, #"{"id":-1}"#))
    }
    func testBadgeWireTruthAndUnknownCategoryRemainSourceValues() throws {
        for value in ["true", "1", #""1""#, #""true""#] {
            let badge = try decode(ProfileIdentityBadge.self, "{\"badgeCode\":\"fixture\",\"unlocked\":\(value),\"category\":\"FUTURE_KIND\"}")
            XCTAssertTrue(badge.unlocked)
            XCTAssertEqual(badge.category, "FUTURE_KIND")
        }
        XCTAssertFalse(try decode(ProfileIdentityBadge.self, #"{"unlocked":0}"#).unlocked)
    }
    func testAchievementDoesNotBorrowCityCondition() throws {
        let medal = try decode(ProfileMedal.self, #"{"templateId":"7","kind":"achievement","condition":"City condition must not be shown","getTime":"2026-10-01 10:30:00"}"#)
        XCTAssertEqual(medal.templateID, 7)
        XCTAssertTrue(medal.isAchievement)
        XCTAssertTrue(medal.displayCondition.isEmpty)
        XCTAssertEqual(medal.getTime, "2026-10-01 10:30:00")
        let city = try decode(ProfileMedal.self, #"{"kind":"city","condition":"Server condition"}"#)
        XCTAssertEqual(city.displayCondition, "Server condition")
    }
    func testPartialWallIsNotAnEmptySuccess() {
        let wall = ProfileBadgeWall(identities: [], medals: nil)
        XCTAssertTrue(wall.isPartial)
        XCTAssertFalse(wall.isEmpty)
        XCTAssertTrue(ProfileBadgeWall(identities: [], medals: []).isEmpty)
    }
}
