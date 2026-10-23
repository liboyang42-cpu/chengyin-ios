import XCTest
@testable import QuestifyCore

final class OrdinaryCityCourseSelectorTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_766_232_000) // 2025-12-20T10:00:00Z
    private func catalog() throws -> [OrdinaryCityCourseRecord] {
        let json = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"PUBLISHED",\
        "kind":"ORDINARY_CITY_ORIENTEERING","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2",\
        "participationMode":"TEAM","requiredClubIds":[11,22],"matchmakingStatus":"CANCELLED"}]
        """
        return try OrdinaryCityCourseSelector.decodeCatalog(Data(json.utf8))
    }
    private func clubs(_ member: Int = 701) -> [TeamClubMembership] {
        [TeamClubMembership(clubID: 11, memberID: member, status: "ACTIVE")!,
         TeamClubMembership(clubID: 22, memberID: member, status: "ACTIVE")!]
    }
    private func team(_ member: Int = 701) -> TeamRoster {
        TeamRoster(teamID: 501, memberIDs: [member, 702], formedBy: "INVITE", affiliatedClubIDs: [11, 22])!
    }
    func testFirstJourneyFreezesRuleVersionForFinishAndDispute() throws {
        let catalog = try catalog()
        let start = try XCTUnwrap(OrdinaryCityCourseSelector.prepareStart(
            courseID: 1001, catalog: catalog, actorMemberID: 701, actorClubs: clubs(), team: team(), now: now))
        XCTAssertEqual(start.selection.courseID, 1001)
        XCTAssertEqual(start.selection.cityTimeZoneIdentifier, "Asia/Shanghai")
        XCTAssertEqual(start.safety.versionID, "safety-v2")
        XCTAssertEqual(start.safety.cityCivilDate, "2025-12-20")
        XCTAssertTrue(start.eligibility.isEligible)
        XCTAssertEqual(start.eligibility.reasonCode, "TEAM_ELIGIBLE")
        XCTAssertEqual(start.payload.frozenRuleVersionID, "rule-v3")
        XCTAssertEqual(start.payload.resultVersionID, start.payload.frozenRuleVersionID)
        XCTAssertEqual(start.payload.safetyVersionID, "safety-v2")
        let finish = try XCTUnwrap(EventScoreVersionProjection.finish(start: start.payload, resultVersionID: "rule-v3"))
        let dispute = try XCTUnwrap(EventScoreVersionProjection.dispute(start: start.payload, resultVersionID: "rule-v3"))
        XCTAssertEqual(finish.kind, .finish)
        XCTAssertEqual(dispute.kind, .dispute)
        XCTAssertEqual(finish.resultVersionID, start.payload.resultVersionID)
        XCTAssertEqual(dispute.resultVersionID, start.payload.resultVersionID)
        XCTAssertNil(EventScoreVersionProjection.finish(start: start.payload, resultVersionID: "rule-v4"))
        XCTAssertNil(EventScoreVersionProjection.dispute(start: start.payload, resultVersionID: "rule-v4"))
        XCTAssertTrue(EventScoreVersionProjection.retainsFrozenRule(start: start.payload, laterPublishedRuleVersionID: "rule-v4"))
    }
    func testSafetyCivilDateUsesCityTimezoneNotUTCInstant() throws {
        let selection = try XCTUnwrap(OrdinaryCityCourseSelector.select(courseID: 1001, from: try catalog()))
        let shanghai = try XCTUnwrap(OrienteeringSafetyVersion.display(selection: selection, now: now))
        XCTAssertEqual(shanghai.cityCivilDate, "2025-12-20")
        let dusk = Date(timeIntervalSince1970: 1_766_217_600) // 2025-12-20T06:00:00Z == 14:00 Shanghai, 22:00 prior day in US/Hawaii
        let lateShanghai = try XCTUnwrap(OrienteeringSafetyVersion.cityCivilDate(
            now: dusk, timeZone: XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))))
        let hawaii = try XCTUnwrap(OrienteeringSafetyVersion.cityCivilDate(
            now: dusk, timeZone: XCTUnwrap(TimeZone(identifier: "Pacific/Honolulu"))))
        XCTAssertEqual(lateShanghai, "2025-12-20")
        XCTAssertEqual(hawaii, "2025-12-19")
    }
    func testUnpublishedFreeExploreGrowthAndGPSAreNotSelectable() throws {
        XCTAssertNotNil(OrdinaryCityCourseSelector.select(courseID: 1001, from: try catalog()))
        let unpublished = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"DRAFT",\
        "kind":"ORDINARY_CITY_ORIENTEERING","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2","participationMode":"TEAM"}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(unpublished.utf8))))
        let free = """
        [{"courseId":1001,"topicId":2001,"productType":2,"publicationStatus":"PUBLISHED",\
        "kind":"FREE_EXPLORATION","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2","participationMode":"SOLO"}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(free.utf8))))
        let growth = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"PUBLISHED",\
        "kind":"GROWTH_PERSONAL_RANK","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2","participationMode":"TEAM"}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(growth.utf8))))
        let gps = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"PUBLISHED",\
        "kind":"ORDINARY_CITY_ORIENTEERING","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2","participationMode":"TEAM",\
        "latitude":31.2,"longitude":121.5,"accuracyMeters":5}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(gps.utf8))))
        let matching = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"PUBLISHED",\
        "kind":"ORDINARY_CITY_ORIENTEERING","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2","participationMode":"TEAM",\
        "matchmakingStatus":"MATCHING"}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(matching.utf8))))
    }
    func testMissingCityTimezoneAndBlankVersionsFailClosed() throws {
        let noZone = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"PUBLISHED",\
        "kind":"ORDINARY_CITY_ORIENTEERING","cityTimeZone":"Not/AZone",\
        "publishedRuleVersionId":"rule-v3","safetyVersionId":"safety-v2","participationMode":"TEAM"}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(noZone.utf8))))
        let blank = """
        [{"courseId":1001,"topicId":2001,"productType":1,"publicationStatus":"PUBLISHED",\
        "kind":"ORDINARY_CITY_ORIENTEERING","cityTimeZone":"Asia/Shanghai",\
        "publishedRuleVersionId":"","safetyVersionId":"safety-v2","participationMode":"TEAM"}]
        """
        XCTAssertNil(OrdinaryCityCourseSelector.select(
            courseID: 1001, from: try OrdinaryCityCourseSelector.decodeCatalog(Data(blank.utf8))))
    }
    func testSafetyMismatchCannotFreezeStart() throws {
        let selection = try XCTUnwrap(OrdinaryCityCourseSelector.select(courseID: 1001, from: try catalog()))
        let safety = try XCTUnwrap(OrienteeringSafetyVersion.display(selection: selection, now: now))
        let other = OrdinaryCityCourseSelection(
            courseID: selection.courseID, topicID: selection.topicID,
            cityTimeZoneIdentifier: selection.cityTimeZoneIdentifier,
            publishedRuleVersionID: selection.publishedRuleVersionID,
            safetyVersionID: "safety-other", participationMode: selection.participationMode,
            requiredClubIDs: selection.requiredClubIDs)
        XCTAssertFalse(safety.matches(other))
        XCTAssertNil(EventScoreVersionProjection.freeze(selection: other, safety: safety))
    }
    func testPrepareStartRequiresEligibleTeam() throws {
        let catalog = try catalog()
        XCTAssertNil(OrdinaryCityCourseSelector.prepareStart(
            courseID: 1001, catalog: catalog, actorMemberID: 701, actorClubs: clubs(), team: nil, now: now))
        XCTAssertNil(OrdinaryCityCourseSelector.prepareStart(
            courseID: 1002, catalog: catalog, actorMemberID: 701, actorClubs: clubs(), team: team(), now: now))
    }
}
