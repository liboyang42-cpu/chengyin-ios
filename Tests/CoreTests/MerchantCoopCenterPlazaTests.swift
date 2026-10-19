import XCTest
@testable import QuestifyCore

final class MerchantCoopCenterPlazaTests: XCTestCase {
    /// 2026-10-01 12:00 +08:00
    private let now = Date(timeIntervalSince1970: 1_790_827_200)
    private func value(_ json: String) throws -> MerchantContentValue { try JSONDecoder().decode(MerchantContentValue.self, from: Data(json.utf8)) }
    private func home(items: String = "[]", recruiting: String = #""count":1"#) -> String {
        #"{"recruiting":{"# + recruiting + #","items":"# + items + #"},"coupons":{"couponCount":0,"received":0,"verified":0},"content":{"topicCount":0,"freeExploreCount":0,"activityCount":0}}"#
    }
    private func route(_ json: String) throws -> MerchantCoopCenterRoute? { MerchantCoopCenterRoute(try value(json), now: now) }

    func testTabDefaultsToPlazaAndAcceptsOfficial() {
        XCTAssertEqual(MerchantCoopCenterTab(sourceTab: nil), .plaza)
        XCTAssertEqual(MerchantCoopCenterTab(sourceTab: "invites"), .plaza)
        XCTAssertEqual(MerchantCoopCenterTab(sourceTab: "official"), .official)
    }

    func testNormalizeRejectsMissingAggregateCounts() throws {
        XCTAssertNoThrow(try MerchantCoopCenterPlaza(home: value(home()), now: now))
        XCTAssertThrowsError(try MerchantCoopCenterPlaza(home: value(#"{"recruiting":{"count":1,"items":[]}}"#), now: now))
        XCTAssertThrowsError(try MerchantCoopCenterPlaza(home: value(home(recruiting: #""count":null"#)), now: now))
        XCTAssertThrowsError(try MerchantCoopCenterPlaza(home: value(home(recruiting: #""count":-1"#)), now: now))
        XCTAssertThrowsError(try MerchantCoopCenterPlaza(home: value(home(recruiting: #""count":""#)), now: now))
        XCTAssertNoThrow(try MerchantCoopCenterPlaza(home: value(home(recruiting: #""count":"3""#)), now: now))
        XCTAssertThrowsError(try MerchantCoopCenterPlaza(home: value(#"{"recruiting":{"count":1,"items":{}},"coupons":{"couponCount":0,"received":0,"verified":0},"content":{"topicCount":0,"freeExploreCount":0,"activityCount":0}}"#), now: now))
    }

    func testScopeFooterOnlyWhenServerSaysTruncated() throws {
        XCTAssertNil(try MerchantCoopCenterPlaza(home: value(home(recruiting: #""count":12,"openCount":12,"shownCount":10"#)), now: now).scope)
        XCTAssertNil(try MerchantCoopCenterPlaza(home: value(home(recruiting: #""count":12,"hasMoreOpen":"true""#)), now: now).scope)
        let explicit = try MerchantCoopCenterPlaza(home: value(home(recruiting: #""count":12,"openCount":11,"shownCount":10,"hasMoreOpen":true"#)), now: now)
        XCTAssertEqual(explicit.scope, .init(openCount: 11, shownCount: 10))
        // Older servers: openCount falls back to count, shownCount to the raw item count.
        let legacy = try MerchantCoopCenterPlaza(home: value(home(items: #"[{"id":1,"name":"A"},{"id":"","name":"dropped"}]"#, recruiting: #""count":7,"hasMoreOpen":true"#)), now: now)
        XCTAssertEqual(legacy.scope, .init(openCount: 7, shownCount: 2))
        XCTAssertEqual(legacy.routes.map(\.id), ["1"])
    }

    func testDropsItemsWithoutIDOrName() throws {
        XCTAssertNil(try route(#"{"id":"","name":"A"}"#))
        XCTAssertNil(try route(#"{"id":1,"name":"  "}"#))
        XCTAssertNil(try route(#"{"id":1}"#))
        XCTAssertNil(try route(#"{"id":true,"name":"A"}"#))
        XCTAssertEqual(try route(#"{"id":"9","name":"A"}"#)?.topicID, 9)
        XCTAssertNil(try route(#"{"id":"abc","name":"A"}"#)?.topicID)
    }

    func testModeDatesMetaAndCover() throws {
        let r = try XCTUnwrap(route(#"{"id":70,"name":"Walk","imgUrl":"https://example.com/a.jpg","productType":1,"startDate":"2026-10-12","endDate":"2026-10-14 20:00:00","cityKeyword":"Sample City","locationCount":3}"#))
        XCTAssertEqual(r.mode, .cityOrienteering)
        XCTAssertEqual(r.dateRange?.0, .init(month: 10, day: 12))
        XCTAssertEqual(r.dateRange?.1, .init(month: 10, day: 14))
        XCTAssertEqual(r.city, "Sample City"); XCTAssertEqual(r.stationCount, "3")
        XCTAssertEqual(r.cover, "https://example.com/a.jpg")
        let single = try XCTUnwrap(route(#"{"id":71,"name":"Trail","productType":"2","startDate":"2026-10-20","endDate":"2026-10-20 23:00","locationCount":0,"imgUrl":""}"#))
        XCTAssertEqual(single.mode, .freeExploration)
        XCTAssertEqual(single.dateRange?.0, .init(month: 10, day: 20)); XCTAssertNil(single.dateRange?.1)
        XCTAssertNil(single.stationCount); XCTAssertNil(single.city); XCTAssertNil(single.cover)
        let endOnly = try XCTUnwrap(route(#"{"id":72,"name":"Loop","endDate":"2026-10-20","productType":3}"#))
        XCTAssertNil(endOnly.dateRange); XCTAssertNil(endOnly.mode)
    }

    func testChinaCalendarIndependentOfDeviceZone() {
        // 2026-10-11T16:30Z is already 10-12 in China.
        XCTAssertEqual(MerchantCoopCenterTime.instant(.string("2026-10-11T16:30:00Z")).map(MerchantCoopCenterTime.monthDay), MerchantCoopCenterMonthDay(month: 10, day: 12))
        XCTAssertEqual(MerchantCoopCenterTime.instant(.string("2026-10-12")), Date(timeIntervalSince1970: 1_791_734_400))
        XCTAssertEqual(MerchantCoopCenterTime.instant(.integer(1_791_734_400)), Date(timeIntervalSince1970: 1_791_734_400))
        XCTAssertEqual(MerchantCoopCenterTime.instant(.string("1791734400000")), Date(timeIntervalSince1970: 1_791_734_400))
        XCTAssertEqual(MerchantCoopCenterTime.instant(.string("2026/2/3 4:05")).map(MerchantCoopCenterTime.monthDay), MerchantCoopCenterMonthDay(month: 2, day: 3))
        XCTAssertNil(MerchantCoopCenterTime.instant(.string("2026-02-30")))
        XCTAssertNil(MerchantCoopCenterTime.instant(.string("2026-10-12 24:00:00")))
        XCTAssertNil(MerchantCoopCenterTime.instant(.integer(0)))
        XCTAssertNil(MerchantCoopCenterTime.instant(.bool(true)))
        XCTAssertNil(MerchantCoopCenterTime.instant(.string("soon")))
    }

    func testTermsLineVariants() throws {
        XCTAssertEqual(try route(#"{"id":1,"name":"A","termsModes":["PERK"],"perkMinValue":20}"#)?.terms, .single(.perk, amount: "20"))
        XCTAssertEqual(try route(#"{"id":1,"name":"A","termsModes":["PERK"]}"#)?.terms, .single(.perk, amount: nil))
        XCTAssertEqual(try route(#"{"id":1,"name":"A","termsModes":["REVSHARE"],"maxPerHeadFee":8.5}"#)?.terms, .single(.revshare, amount: "8.5"))
        XCTAssertEqual(try route(#"{"id":1,"name":"A","termsModes":["REVSHARE"],"perkMinValue":9}"#)?.terms, .single(.revshare, amount: nil))
        XCTAssertEqual(try route(#"{"id":1,"name":"A","termsModes":["TRAFFIC"],"perkMinValue":9}"#)?.terms, .single(.traffic, amount: nil))
        XCTAssertEqual(try route(#"{"id":1,"name":"A","termsModes":["PERK","BOGUS","TRAFFIC"]}"#)?.terms, .mixed([.perk, .traffic]))
        XCTAssertEqual(try route(#"{"id":1,"name":"A","termsModes":["BOGUS"]}"#)?.terms, MerchantCoopCenterRoute.Terms.none)
        XCTAssertEqual(try route(#"{"id":1,"name":"A","termsModes":"PERK"}"#)?.terms, MerchantCoopCenterRoute.Terms.none)
    }

    func testDeadlinePrefersRecruitDeadlineAndComparesWithNow() throws {
        XCTAssertEqual(try route(#"{"id":1,"name":"A","recruitDeadline":"2026-10-10 18:00:00","merchantSignUpEndDate":"2026-09-01"}"#)?.deadline, .open(.init(month: 10, day: 10)))
        XCTAssertEqual(try route(#"{"id":1,"name":"A","recruitDeadline":"","merchantSignUpEndDate":"2026-10-15"}"#)?.deadline, .open(.init(month: 10, day: 15)))
        XCTAssertEqual(try route(#"{"id":1,"name":"A","merchantSignUpEndDate":"2026-09-20"}"#)?.deadline, .closed)
        // Date-only deadlines mean China midnight; the same day at noon is already closed.
        XCTAssertEqual(try route(#"{"id":1,"name":"A","recruitDeadline":"2026-10-01"}"#)?.deadline, .closed)
        XCTAssertNil(try route(#"{"id":1,"name":"A","recruitDeadline":"bad"}"#)?.deadline)
        XCTAssertNil(try route(#"{"id":1,"name":"A"}"#)?.deadline)
    }

    func testSeatThresholds() throws {
        XCTAssertNil(try route(#"{"id":1,"name":"A","remainingMerchantCount":null}"#)?.seat)
        XCTAssertNil(try route(#"{"id":1,"name":"A","remainingMerchantCount":""}"#)?.seat)
        XCTAssertNil(try route(#"{"id":1,"name":"A","remainingMerchantCount":"many"}"#)?.seat)
        XCTAssertEqual(try route(#"{"id":1,"name":"A","remainingMerchantCount":0}"#)?.seat, .full)
        XCTAssertEqual(try route(#"{"id":1,"name":"A","remainingMerchantCount":-2}"#)?.seat, .full)
        XCTAssertEqual(try route(#"{"id":1,"name":"A","remainingMerchantCount":1}"#)?.seat, .remaining("1", tight: true))
        XCTAssertEqual(try route(#"{"id":1,"name":"A","remainingMerchantCount":"3"}"#)?.seat, .remaining("3", tight: false))
    }
}
