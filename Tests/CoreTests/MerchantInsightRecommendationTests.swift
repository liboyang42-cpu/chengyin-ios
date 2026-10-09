import Foundation
import XCTest
@testable import QuestifyCore

final class MerchantInsightRecommendationTests: XCTestCase {
    private func value(_ raw: String) throws -> MerchantMarketingValue { try JSONDecoder().decode(MerchantMarketingValue.self, from: Data(raw.utf8)) }
    private func content(_ raw: String) throws -> MerchantContentValue { try JSONDecoder().decode(MerchantContentValue.self, from: Data(raw.utf8)) }
    func testTopicUsesFinalResponseTopicIDAndNeverInternalAIOrDisplayID() throws {
        let row = try value(#"{"topicId":7,"id":99,"name":"Same name","hostName":"Host"}"#)
        let item = MerchantInsightRecommendation(row: row, kind: .topic, siblings: [row])
        XCTAssertEqual(item.targetID, 7); XCTAssertEqual(item.hostName, "Host")
        let legacyOnly = try value(#"{"id":7,"name":"Same name"}"#)
        XCTAssertNil(MerchantInsightRecommendation(row: legacyOnly, kind: .topic, siblings: [legacyOnly]).targetID)
    }
    func testPartnerUsesCanonicalMemberIDNeverMerchantRowID() throws {
        let row = try value(#"{"merchantId":31,"memberId":42,"id":99,"name":"Store"}"#)
        XCTAssertEqual(MerchantInsightRecommendation(row: row, kind: .partner, siblings: [row]).targetID, 42)
        let rowOnly = try value(#"{"merchantId":31,"id":42}"#)
        XCTAssertNil(MerchantInsightRecommendation(row: rowOnly, kind: .partner, siblings: [rowOnly]).targetID)
    }
    func testInvalidUnsafeOrMalformedIdentifiersDoNotBecomeLinks() throws {
        for id in ["0", "-1", "true", "null", "1.5", "9007199254740992", #""../7""#, #""+7""#] {
            let row = try value("{\"topicId\":" + id + "}")
            XCTAssertNil(MerchantInsightRecommendation(row: row, kind: .topic, siblings: [row]).targetID)
        }
    }
    func testUniqueNumericStringIDIsAcceptedWithoutUsingNameAsIdentity() throws {
        let row = try value(#"{"topicId":"007","name":"Anything"}"#)
        XCTAssertEqual(MerchantInsightRecommendation(row: row, kind: .topic, siblings: [row]).targetID, 7)
    }
    func testDuplicateTargetAndDetachedRowCannotCreateRoute() throws {
        let row = try value(#"{"memberId":42,"name":"One"}"#), other = try value(#"{"memberId":"42","name":"Two"}"#)
        XCTAssertNil(MerchantInsightRecommendation(row: row, kind: .partner, siblings: [row, other]).targetID)
        XCTAssertNil(MerchantInsightRecommendation(row: row, kind: .partner, siblings: [other]).targetID)
    }
    func testRouteCarriesIndependentlySuppliedStoreAndReaderScope() throws {
        let scope = UUID(), origin = try XCTUnwrap(MerchantInsightOrigin(merchantID: 31, readerScope: scope))
        let row = try value(#"{"memberId":42,"merchantId":99}"#)
        let route = try XCTUnwrap(MerchantInsightRecommendation(row: row, kind: .partner, siblings: [row]).route(origin: origin))
        XCTAssertEqual(route.targetID, 42); XCTAssertEqual(route.origin.merchantID, 31); XCTAssertEqual(route.origin.readerScope, scope)
        XCTAssertNotEqual(origin, MerchantInsightOrigin(merchantID: 32, readerScope: scope))
        XCTAssertNotEqual(origin, MerchantInsightOrigin(merchantID: 31, readerScope: UUID()))
        XCTAssertNil(MerchantInsightOrigin(merchantID: nil, readerScope: scope)); XCTAssertNil(MerchantInsightOrigin(merchantID: 31, readerScope: nil))
    }
    func testAIStringWhitelistStillOnlyAcceptsOriginalThreeTokens() {
        XCTAssertEqual(MerchantInsightDestination.allCases.map(\.sourcePath), ["/merchant/coop", "/merchant/decor", "/publish/pro"])
        XCTAssertEqual(MerchantInsightDestination(rawValue: "topic_coop"), .topicCooperation)
        for value in ["recommendation", "topic:7", "memberId=42", "/merchant/home", "https://example.test"] {
            XCTAssertNil(MerchantInsightDestination(rawValue: value))
        }
    }
    func testFocusFindsExactLoadedIDWhenDisplayNamesAreEqual() throws {
        let rows = try content(#"[{"id":1,"name":"Same name"},{"id":2,"name":"Same name"},{"id":3,"name":"Third"}]"#).array!
        let focus = MerchantInsightRecruitingFocus(rows: rows, topicID: 2)
        XCTAssertEqual(focus.rows.map { $0["id"].integer }, [2, 1, 3]); XCTAssertEqual(focus.matchedID, 2); XCTAssertFalse(focus.unavailable)
    }
    func testMissingOrDuplicateFocusKeepsLoadedRowsAndReportsUnavailable() throws {
        for raw in [#"[{"id":1,"name":"Same name"}]"#, #"[{"id":2},{"id":"2"}]"#] {
            let rows = try content(raw).array!, focus = MerchantInsightRecruitingFocus(rows: try content(raw).array!, topicID: 2)
            XCTAssertEqual(focus.rows, rows); XCTAssertNil(focus.matchedID); XCTAssertTrue(focus.unavailable)
        }
    }
    func testOrdinaryRecruitmentListHasNoFocusAndRetainsOriginalOrder() throws {
        let rows = try content(#"[{"id":2},{"id":1}]"#).array!
        let focus = MerchantInsightRecruitingFocus(rows: rows, topicID: nil)
        XCTAssertEqual(focus.rows, rows); XCTAssertNil(focus.matchedID); XCTAssertFalse(focus.unavailable)
    }
}
