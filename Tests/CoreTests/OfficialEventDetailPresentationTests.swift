import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class OfficialDetailTransport: HTTPTransport {
    let json: String
    let status: Int
    init(_ json: String, status: Int = 200) { self.json = json; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) { (Data(json.utf8), status) }
}
private struct OfficialDetailNetworkTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int) { throw URLError(.notConnectedToInternet) }
}
/// Synthetic source parity for pages/activity/official-detail; no live account or network.
final class OfficialEventDetailPresentationTests: XCTestCase {
    private let start = 1893427200000.0 // 2030-01-01 00:00 Beijing time
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }
    private func event(_ fields: String) throws -> OfficialEvent { try decode(OfficialEvent.self, "{\"id\":71,\"title\":\"Synthetic\"\(fields)}") }
    private func service(_ transport: any HTTPTransport) throws -> OfficialEventService {
        try OfficialEventService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    private func detailFailure(_ transport: any HTTPTransport) async throws -> Error? {
        do { _ = try await service(transport).detail(id: 71); return nil } catch { return error }
    }

    func testExplicitMissingEventIsUnavailableButMalformedSuccessStaysRetryable() async throws {
        for (json, status) in [("", 404), ("html", 410), (#"{"code":404,"msg":"Not found"}"#, 200),
                               (#"{"code":410}"#, 200), (#"{"code":500,"msg":" 活动不存在 "}"#, 200)] {
            let error = try await detailFailure(OfficialDetailTransport(json, status: status))
            XCTAssertEqual(error as? OfficialReadFailure, .unavailable, json)
            XCTAssertEqual(OfficialDetailLoadFailure(try XCTUnwrap(error)), .unavailable)
        }
        let malformed = try await detailFailure(OfficialDetailTransport(#"{"code":200,"data":null}"#))
        XCTAssertEqual(malformed as? APIError, .malformedResponse)
        XCTAssertEqual(OfficialDetailLoadFailure(try XCTUnwrap(malformed)), .other)
        let server = try await detailFailure(OfficialDetailTransport("", status: 500))
        XCTAssertEqual(server as? APIError, .httpStatus(500))
        let network = try await detailFailure(OfficialDetailNetworkTransport())
        XCTAssertEqual(OfficialDetailLoadFailure(try XCTUnwrap(network)), .network)
    }
    func testMissingStatusesStayScopedToTheDetailRead() async throws {
        do { _ = try await service(OfficialDetailTransport("", status: 404)).events(); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .httpStatus(404)) }
        do { _ = try await service(OfficialDetailTransport(#"{"code":404}"#)).events(); XCTFail() }
        catch { XCTAssertEqual(error as? OfficialReadFailure, .rejected(404)) }
    }
    func testCategoryKeysFollowSourceTableAndFallBackToOfficial() throws {
        let expected = ["city_light": "cityLight", "custom": "custom", "festival": "festival", "brand": "brand",
                        "challenge": "challenge", "hidden": "hidden", "community": "community", "merchant_hunt": "merchantHunt",
                        "future": "official"]
        for (raw, leaf) in expected {
            XCTAssertEqual(try event(",\"category\":\"\(raw)\"").categoryKey, "official.detailParity.category." + leaf)
        }
        XCTAssertEqual(try event("").categoryKey, "official.detailParity.category.official")
        XCTAssertEqual(try event(",\"category\":7").categoryKey, "official.detailParity.category.official")
    }
    func testMissionFallbacksActionsAndBinding() throws {
        let value = try event(#","contractVersion":2,"missions":[{"missionCode":"a","missionType":"EVENT_POINT_ARRIVAL","canVerifyArrival":true},{"missionCode":"b","title":"  ","missionType":"THEME_VERIFIED_FINISH","binding":{"bindingType":"THEME","sourceRefId":"0501"}},{"missionCode":"c","missionType":"ROAM_POI_ARRIVAL","binding":{"bindingType":"THEME","sourceRefId":0}},{"missionCode":"d","missionType":"ROAM_SESSION_AREA","binding":{"sourceRefId":"5x"}},{"missionCode":"e","title":"Synthetic named","description":"Synthetic rule","missionType":"FUTURE","binding":{"sourceRefId":9223372036854775807}},{"missionCode":"f","missionType":"THEME_VERIFIED_FINISH","complete":true}]"#)
        let rows = OfficialEventDetailPresentation(event: value, now: Date()).missions
        XCTAssertEqual(rows.map(\.index), [0, 1, 2, 3, 4, 5])
        XCTAssertEqual(rows[0].title, .key("official.detailParity.mission.eventPoint"))
        XCTAssertEqual(rows[0].description, .key("official.detailParity.mission.eventPointAction"))
        XCTAssertEqual(rows[1].title, .key("official.detailParity.mission.theme"))
        XCTAssertEqual(rows[1].description, .key("official.detailParity.mission.themeAction"))
        XCTAssertEqual(rows[2].description, .key("official.detailParity.mission.unsupportedAction"))
        XCTAssertEqual(rows[3].title, .key("official.detailParity.mission.roamArea"))
        XCTAssertEqual(rows[4].title, .verbatim("Synthetic named")); XCTAssertEqual(rows[4].description, .verbatim("Synthetic rule"))
        XCTAssertEqual(rows.map(\.action), [.verify, .automatic, .unsupported, .unsupported, .unsupported, .verified])
        XCTAssertEqual(rows.map(\.supported), [true, true, false, false, false, true])
        XCTAssertEqual(rows[1].binding?.bindingType, "THEME"); XCTAssertEqual(rows[1].binding?.sourceRefID, 501)
        XCTAssertNil(rows[2].binding?.sourceRefID); XCTAssertNil(rows[3].binding?.sourceRefID)
        XCTAssertEqual(rows[4].binding?.sourceRefID, Int64.max)
        let unknown = OfficialDetailMission(try decode(OfficialMission.self, #"{"missionType":"FUTURE"}"#), index: 0)
        XCTAssertEqual(unknown.title, .key("official.detailParity.mission.unknown"))
        XCTAssertEqual(unknown.description, .key("official.detailParity.mission.unknownAction"))
        XCTAssertEqual(OfficialMissionBinding?.none, try decode(OfficialMission.self, #"{"binding":null}"#).binding)
    }
    func testCallToActionMirrorsSourceOrder() throws {
        let cases: [(String, OfficialDetailCTA)] = [
            (#","status":9,"paused":true,"signed":true"#, .ended),
            (#","status":3,"paused":true"#, .paused),
            (#","status":3,"signed":true,"contractVersion":2,"missions":[{"missionType":"THEME_VERIFIED_FINISH","canVerifyArrival":true}]"#, .roamArrival),
            (#","status":3,"signed":true,"contractVersion":2,"missions":[{"missionType":"THEME_VERIFIED_FINISH"}]"#, .themeSync),
            (#","status":3,"signed":true,"contractVersion":2,"missions":[{"missionType":"ROAM_POI_ARRIVAL"},{"missionType":"FUTURE"}]"#, .unsupportedTasks),
            (#","status":3,"signed":true,"contractVersion":2,"missions":[{"missionType":"EVENT_POINT_ARRIVAL"}]"#, .waitTasks),
            (#","status":3,"signed":true,"contractVersion":2"#, .waitTasks),
            (#","status":3,"signed":true,"roamEnabled":true"#, .roamLight),
            (#","status":3,"signed":true"#, .explore),
            (#","status":1,"signed":true"#, .signedWaiting),
            (#","status":2,"signed":true"#, .signed),
            (#","status":2"#, .signup), (#","status":3,"signed":false"#, .signup),
            (#","status":1"#, .registrationSoon), (#","status":4"#, .unavailable), ("", .unavailable),
        ]
        for (fields, expected) in cases { XCTAssertEqual(try event(fields).detailCTA, expected, fields) }
        XCTAssertTrue(OfficialDetailCTA.signup.isSourceAction); XCTAssertFalse(OfficialDetailCTA.waitTasks.isSourceAction)
        XCTAssertEqual(OfficialDetailCTA.roamArrival.key, "official.detailParity.cta.roamArrival")
    }
    func testFactsStripForSignedV2WithNumericTimestamps() throws {
        let value = try event(",\"status\":3,\"participants\":12,\"signed\":true,\"contractVersion\":2,\"activityStart\":\(start),\"activityEnd\":1893643200000,\"missions\":[{\"complete\":true},{}]")
        let facts = OfficialEventDetailPresentation(event: value, now: Date(timeIntervalSince1970: start / 1000)).facts
        XCTAssertEqual(facts.map(\.id), ["participants", "progress", "duration", "dates", "scope", "tasks"])
        XCTAssertEqual(facts[0].value, .verbatim("12")); XCTAssertEqual(facts[0].sub, .key("official.detailParity.fact.participantsSub"))
        XCTAssertEqual(facts[1].value, .verbatim("1/2")); XCTAssertEqual(facts[1].sub, .key("official.detailParity.fact.progressTasks"))
        XCTAssertEqual(facts[2].value, .days(3))
        XCTAssertEqual(facts[3].value, .verbatim("1.1\u{2013}1.3")); XCTAssertEqual(facts[3].sub, .key("official.detailParity.fact.datesSub"))
        XCTAssertEqual(facts[4].value, .key("official.detailParity.fact.nationwide"))
        XCTAssertEqual(facts[4].sub, .countdown(.endsIn(.days(2))))
        XCTAssertEqual(facts[5].value, .verbatim("2"))
    }
    func testFactsStripForGuestV1AndTextDates() throws {
        let value = try event(#","status":4,"city":"Example city","myProgress":3,"activityStart":"2030-01-01 10:00:00","contentJson":"{\"tasks\":[\"Synthetic task\",{\"name\":\"Synthetic card\",\"type\":\"walk\"},{\"title\":\"\"},7]}""#)
        let presentation = OfficialEventDetailPresentation(event: value, now: Date())
        XCTAssertEqual(presentation.facts.map(\.id), ["participants", "duration", "dates", "scope", "tasks"])
        XCTAssertEqual(presentation.facts[0].value, .verbatim("0"))
        XCTAssertEqual(presentation.facts[1].value, .key("official.notAnnounced"))
        XCTAssertEqual(presentation.facts[2].value, .key("official.notAnnounced"))
        XCTAssertEqual(presentation.facts[3].value, .verbatim("Example city"))
        XCTAssertEqual(presentation.facts[3].sub, .key("official.status.settling"))
        XCTAssertEqual(presentation.facts[4].value, .verbatim("4"))
        XCTAssertEqual(presentation.cards.map(\.title), [.verbatim("Synthetic task"), .verbatim("Synthetic card"), .numberedTask(3), .numberedTask(4)])
        XCTAssertEqual(presentation.cards.map(\.description), [.numberedTask(1), .verbatim("walk"),
                                                               .key("official.detailParity.card.defaultDescription"), .key("official.detailParity.card.defaultDescription")])
        XCTAssertTrue(presentation.missions.isEmpty); XCTAssertNil(presentation.eligibilityKey)
        let signed = OfficialEventDetailPresentation(event: try event(#","signed":true,"myProgress":3"#), now: Date()).facts
        XCTAssertEqual(signed[1].value, .verbatim("3")); XCTAssertEqual(signed[1].sub, .key("official.detailParity.fact.progressCompleted"))
    }
    func testDurationAndDateRangeBoundaries() {
        XCTAssertEqual(OfficialEventDetailPresentation.duration(start: .milliseconds(start), end: .milliseconds(1893432600000)), .hours(2))
        XCTAssertEqual(OfficialEventDetailPresentation.duration(start: .milliseconds(start), end: .milliseconds(start + 86_400_000)), .days(1))
        XCTAssertEqual(OfficialEventDetailPresentation.duration(start: .milliseconds(start), end: .milliseconds(start)), .key("official.notAnnounced"))
        XCTAssertEqual(OfficialEventDetailPresentation.duration(start: .text("2030-01-01"), end: .milliseconds(start)), .key("official.notAnnounced"))
        XCTAssertEqual(OfficialEventDetailPresentation.dateRange(start: nil, end: .milliseconds(1893643200000)), .verbatim("1.3"))
        XCTAssertEqual(OfficialEventDetailPresentation.dateRange(start: .milliseconds(start - 1), end: nil), .verbatim("12.31"))
        XCTAssertEqual(OfficialEventDetailPresentation.dateRange(start: nil, end: nil), .key("official.notAnnounced"))
    }
    func testIntroStoryEligibilityPauseAndCollectiveCopy() throws {
        let both = OfficialEventDetailPresentation(event: try event(#","subtitle":"Sub","story":"Story","contractVersion":2,"eligible":true,"paused":true,"pausedReason":"  ","rewardJson":"{\"collectiveCouponId\":\"9\"}","collective":{"enabled":true,"current":3,"threshold":10,"pct":30}"#), now: Date())
        XCTAssertEqual(both.intro, "Sub"); XCTAssertEqual(both.storyDetail, "Story")
        XCTAssertEqual(both.eligibilityKey, "official.detailParity.eligible"); XCTAssertNil(both.pausedReason)
        XCTAssertEqual(both.collectiveTipKey, "official.detailParity.collective.tipConfigured")
        let storyOnly = OfficialEventDetailPresentation(event: try event(#","story":"Story","contractVersion":2,"pausedReason":" Synthetic reason ""#), now: Date())
        XCTAssertEqual(storyOnly.intro, "Story"); XCTAssertNil(storyOnly.storyDetail)
        XCTAssertEqual(storyOnly.eligibilityKey, "official.detailParity.notEligible"); XCTAssertEqual(storyOnly.pausedReason, "Synthetic reason")
        XCTAssertEqual(storyOnly.collectiveTipKey, "official.detailParity.collective.tipAbsent")
        let collective = try decode(OfficialCollectiveProgress.self, #"{"enabled":true,"current":3,"threshold":10,"pct":0}"#)
        XCTAssertEqual(collective.detailPercentText, "0%"); XCTAssertEqual(collective.detailCountText, "3 / 10")
        let unknown = try decode(OfficialCollectiveProgress.self, #"{"enabled":true}"#)
        XCTAssertEqual(unknown.detailPercentText, "--%"); XCTAssertEqual(unknown.detailCountText, "-- / --")
    }
    func testSyntheticFixtureCarriesCategoryAndThemeBinding() throws {
        let value = try decode(OfficialEvent.self, OfficialEventSyntheticFixtures.eventJSON)
        XCTAssertEqual(value.categoryKey, "official.detailParity.category.cityLight")
        XCTAssertEqual(value.missions[1].binding?.sourceRefID, 501)
        XCTAssertEqual(value.detailCTA, .roamArrival)
    }
}
