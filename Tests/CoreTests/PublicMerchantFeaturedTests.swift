import XCTest
@testable import QuestifyCore

final class PublicMerchantFeaturedTests: XCTestCase {
    private let owner = PublicMerchantHomeTarget.ownerMemberID(PublicMerchantOwnerID(41)!)
    private let row = PublicMerchantHomeTarget.legacyMerchantRowID(PublicMerchantRowID(73)!)
    private let homeScope = UUID()
    private let destinationScope = UUID()
    private let snapshotID = UUID()
    private func home(_ featured: String = Self.activity, identity: String = #""id":73,"memberId":41"#) throws -> PublicMerchantHome {
        try JSONDecoder().decode(PublicMerchantHome.self,
            from: Data("{\(identity),\"name\":\"Synthetic shop\",\"featured\":\(featured)}".utf8))
    }
    private func selection(_ home: PublicMerchantHome, target: PublicMerchantHomeTarget? = nil) -> PublicMerchantFeaturedSelection? {
        .init(home: home, target: target ?? owner, homeScope: homeScope,
              destinationScope: destinationScope, snapshotID: snapshotID)
    }
    func testWhitelistedActivityUsesOnlyExactNestedFields() throws {
        let value = try home()
        XCTAssertEqual(value.featured?.kind, .activity)
        XCTAssertEqual(value.featured?.route, .activity(601))
        XCTAssertEqual(value.featured?.name, "Synthetic walk")
        XCTAssertEqual(value.featured?.description, "Public description")
        XCTAssertEqual(value.featured?.imageURL, "https://example.com/featured.jpg")
        XCTAssertEqual(selection(value)?.merchant, value.reviewTarget)
    }
    func testCouponDefinitionRoutesOnlyToWalletAndCannotBecomeOwnedHistoryID() throws {
        let value = try home(#"{"id":601,"featuredType":2,"featuredId":601,"name":"Synthetic coupon","imgUrl":"https://example.com/not-public.jpg","couponType":1,"amount":10}"#)
        XCTAssertEqual(value.featured?.kind, .coupon)
        XCTAssertEqual(value.featured?.route, .couponWallet)
        XCTAssertNil(value.featured?.imageURL)
        XCTAssertEqual(selection(value)?.route, .couponWallet)
    }
    func testMissingNullPrimitiveArrayAndUnknownKindsKeepProfileButNoRoute() throws {
        for payload in ["null", "true", "42", #""text""#, "[]", "{}",
                        #"{"id":601,"featuredType":3,"featuredId":601}"#,
                        #"{"id":601,"featuredType":"1","featuredId":601}"#] {
            let value = try home(payload)
            XCTAssertEqual(value.name, "Synthetic shop", payload)
            XCTAssertNil(value.featured?.route, payload)
            XCTAssertNil(selection(value), payload)
        }
        let missing = try JSONDecoder().decode(PublicMerchantHome.self, from: Data(#"{"id":73,"memberId":41}"#.utf8))
        XCTAssertNil(missing.featured)
    }
    func testBadIDsNeverTruncateCoerceOrFallBack() throws {
        for id in ["0", "-1", "1.5", "true", #""601""#, "null", "9223372036854775808"] {
            let value = try home("{\"id\":601,\"featuredType\":1,\"featuredId\":\(id)}")
            XCTAssertNil(value.featured?.route, id)
            XCTAssertNil(selection(value), id)
        }
        for payload in [#"{"id":601,"featuredType":1}"#,
                        #"{"featuredType":1,"featuredId":601}"#,
                        #"{"id":602,"featuredType":1,"featuredId":601}"#,
                        #"{"id":601,"featuredType":1,"activityId":601,"dataId":601}"#] {
            XCTAssertNil(try home(payload).featured?.route)
        }
    }
    func testRootDecorationIDsAndPresentationAliasesDoNotCreatePublicCard() throws {
        let value = try JSONDecoder().decode(PublicMerchantHome.self, from: Data(#"{"id":73,"memberId":41,"featuredType":1,"featuredId":601,"featured":{"title":"Unapproved alias","coverImg":"https://example.com/a","img":"https://example.com/b"}}"#.utf8))
        XCTAssertNil(value.featured?.route); XCTAssertNil(value.featured?.name); XCTAssertNil(value.featured?.imageURL)
    }
    func testMalformedOptionalDisplayFieldsDoNotEraseValidCardIdentity() throws {
        let value = try home(#"{"id":601,"featuredType":1,"featuredId":601,"name":{},"description":[],"imgUrl":true}"#)
        XCTAssertEqual(value.featured?.route, .activity(601))
        XCTAssertNil(value.featured?.name); XCTAssertNil(value.featured?.description); XCTAssertNil(value.featured?.imageURL)
    }
    func testBothMerchantNamespacesRequireReturnedIdentities() throws {
        let value = try home()
        XCTAssertNotNil(selection(value, target: owner)); XCTAssertNotNil(selection(value, target: row))
        XCTAssertNotNil(value.publicFeatured(for: owner)); XCTAssertNotNil(value.publicFeatured(for: row))
        XCTAssertNil(value.publicFeatured(for: .ownerMemberID(PublicMerchantOwnerID(73)!)))
        XCTAssertNil(value.publicFeatured(for: .legacyMerchantRowID(PublicMerchantRowID(41)!)))
        XCTAssertNil(try home(identity: #""id":73"#).publicFeatured(for: owner))
        XCTAssertNil(try home(identity: #""memberId":41"#).publicFeatured(for: owner))
        XCTAssertNil(selection(value, target: .ownerMemberID(PublicMerchantOwnerID(73)!)))
        XCTAssertNil(selection(value, target: .legacyMerchantRowID(PublicMerchantRowID(41)!)))
        XCTAssertNil(selection(try home(identity: #""id":73"#)))
        XCTAssertNil(selection(try home(identity: #""memberId":41"#)))
        XCTAssertNil(selection(try home(identity: #""id":0,"memberId":41"#)))
    }
    func testSelectionRejectsChangedHomeScopeDestinationScopeAndSnapshot() throws {
        let value = try home(); let selected = try XCTUnwrap(selection(value))
        XCTAssertTrue(selected.isCurrent(home: value, target: owner, homeScope: homeScope,
                                         destinationScope: destinationScope, snapshotID: snapshotID))
        XCTAssertFalse(selected.isCurrent(home: value, target: owner, homeScope: UUID(),
                                          destinationScope: destinationScope, snapshotID: snapshotID))
        XCTAssertFalse(selected.isCurrent(home: value, target: owner, homeScope: homeScope,
                                          destinationScope: UUID(), snapshotID: snapshotID))
        XCTAssertFalse(selected.isCurrent(home: value, target: owner, homeScope: homeScope,
                                          destinationScope: destinationScope, snapshotID: UUID()))
    }
    func testSelectionRejectsChangedKindIDTitleMerchantAndNamespace() throws {
        let selected = try XCTUnwrap(selection(home()))
        let changed = [Self.activity.replacingOccurrences(of: "601", with: "602"),
                       Self.activity.replacingOccurrences(of: "featuredType\":1", with: "featuredType\":2"),
                       Self.activity.replacingOccurrences(of: "Synthetic walk", with: "Replacement")]
        for payload in changed {
            XCTAssertFalse(selected.isCurrent(home: try home(payload), target: owner, homeScope: homeScope,
                                              destinationScope: destinationScope, snapshotID: snapshotID))
        }
        XCTAssertFalse(selected.isCurrent(home: try home(identity: #""id":74,"memberId":41"#), target: owner,
                                          homeScope: homeScope, destinationScope: destinationScope, snapshotID: snapshotID))
        XCTAssertFalse(selected.isCurrent(home: try home(), target: row, homeScope: homeScope,
                                          destinationScope: destinationScope, snapshotID: snapshotID))
    }
    func testUnavailableCardInvalidatesAnExistingSelection() throws {
        let selected = try XCTUnwrap(selection(home()))
        XCTAssertFalse(selected.isCurrent(home: try home("null"), target: owner, homeScope: homeScope,
                                          destinationScope: destinationScope, snapshotID: snapshotID))
    }
    private static let activity = #"{"id":601,"featuredType":1,"featuredId":601,"name":" Synthetic walk ","description":"Public description","imgUrl":"https://example.com/featured.jpg","ownerSecret":"ignored"}"#
}
