import XCTest
@testable import QuestifyCore

final class OfficialDetailTopicLinksTests: XCTestCase {
    private func event(_ json: String) throws -> OfficialEvent { try JSONDecoder().decode(OfficialEvent.self, from: Data(json.utf8)) }
    private let missions = #"""
    [{"missionCode":"a","missionType":"THEME_VERIFIED_FINISH","binding":{"bindingType":"THEME","sourceRefId":"41"}},
     {"missionCode":"b","missionType":"THEME_VERIFIED_FINISH","complete":true,"binding":{"bindingType":"THEME","sourceRefId":42}},
     {"missionCode":"c","missionType":"EVENT_POINT_ARRIVAL","canVerifyArrival":true,"binding":{"bindingType":"THEME","sourceRefId":43}},
     {"missionCode":"d","missionType":"THEME_VERIFIED_FINISH","binding":{"bindingType":"POINT","sourceRefId":44}},
     {"missionCode":"e","missionType":"THEME_VERIFIED_FINISH","binding":{"bindingType":"THEME","sourceRefId":"41"}}]
    """#
    func testTopicIDsAreUniqueThemeBindingsInOrder() throws {
        let value = try event(#"{"id":1,"title":"t","contractVersion":2,"status":3,"signed":true,"missions":"# + missions + "}")
        XCTAssertEqual(OfficialDetailTopicLinks.topicIDs(value), [41, 42, 43])
        let v1 = try event(#"{"id":1,"title":"t","status":3,"missions":"# + missions + "}")
        XCTAssertEqual(OfficialDetailTopicLinks.topicIDs(v1), [])
    }
    func testOnlyIncompleteSignedThemeMissionsOpenTheirTopic() throws {
        let value = try event(#"{"id":1,"title":"t","contractVersion":2,"status":3,"signed":true,"missions":"# + missions + "}")
        XCTAssertEqual(value.missions.map { OfficialDetailTopicLinks.linkedTopic($0, signed: true) }, [41, nil, nil, nil, 41])
        XCTAssertEqual(value.missions.map { OfficialDetailTopicLinks.linkedTopic($0, signed: false) }, [nil, nil, nil, nil, nil])
        XCTAssertEqual(OfficialDetailTopicLinks.ctaTopic(value, cta: .themeSync), 41)
        XCTAssertNil(OfficialDetailTopicLinks.ctaTopic(value, cta: .roamArrival))
    }
    func testThemeTopicIDRejectsNonPositiveAndOtherBindings() throws {
        let value = try event(#"{"id":1,"title":"t","contractVersion":2,"missions":[{"missionType":"THEME_VERIFIED_FINISH","binding":{"bindingType":"THEME","sourceRefId":0}},{"missionType":"THEME_VERIFIED_FINISH","binding":{"bindingType":"THEME","sourceRefId":"x"}}]}"#)
        XCTAssertEqual(value.missions.map { $0.binding?.themeTopicID }, [nil, nil])
    }
    func testServiceFailureCopyOnlyForRetryableServerFailures() {
        XCTAssertTrue(OfficialDetailServiceFailure.matches(OfficialReadFailure.rejected(500)))
        XCTAssertTrue(OfficialDetailServiceFailure.matches(APIError.httpStatus(502)))
        XCTAssertTrue(OfficialDetailServiceFailure.matches(APIError.malformedResponse))
        XCTAssertFalse(OfficialDetailServiceFailure.matches(OfficialReadFailure.unavailable))
        XCTAssertFalse(OfficialDetailServiceFailure.matches(APIError.unauthorized))
        XCTAssertFalse(OfficialDetailServiceFailure.matches(URLError(.notConnectedToInternet)))
    }
}
