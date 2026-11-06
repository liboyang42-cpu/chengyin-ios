import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

private final class EntryRecordingTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var response: (Data, Int)
    init(_ json: String, status: Int = 200) { response = (Data(json.utf8), status) }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return response }
}

/// Mini-program pages/roam/index 开始漫游 peek: `GET /api/roam/entry/nearby {lat,lng,radius:3000}` plus
/// `utils/roam-entry-map.js` activityView. Synthetic rows only.
@MainActor final class RoamEntryNearbyTests: XCTestCase {
    private let base = URL(string: "https://entry-nearby.example/native")!
    private var area: RoamSearchArea { .init(coordinate: RoamCoordinate(latitude: 31.2, longitude: 121.4)!, label: "Selected area") }
    private func envelope(_ items: String, radius: Int = 3000) -> Data { Data(#"{"code":200,"data":{"radius":\#(radius),"items":[\#(items)]}}"#.utf8) }
    private func teams(_ json: String) throws -> [NearbyTeam] { try JSONDecoder().decode([NearbyTeam].self, from: Data(json.utf8)) }
    private func context() throws -> RuntimeDependencyContext {
        RuntimeDependencyContext(market: .china, baseURL: base, role: "player", session: try .init(accountID: 81, epoch: 1, namespace: "synthetic", token: "synthetic-entry"))
    }

    func testRequestIsTheSourceGetWithManualCentreAndFixedRadius() throws {
        let request = try RoamEntryNearbyRoute.request(baseURL: base, area: area, token: "synthetic-entry")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        let parts = try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertTrue(parts.path.hasSuffix("/api/roam/entry/nearby"))
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") }), ["lat": "31.2", "lng": "121.4", "radius": "3000"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertThrowsError(try RoamEntryNearbyRoute.request(baseURL: base, area: area, token: ""))
    }

    func testDecodeKeepsActivityAndTopicDropsHangoutAndMapsServerFields() throws {
        let rows = try RoamEntryNearbyRoute.decode(envelope(#"""
        {"kind":"activity","id":7,"topicId":3,"productType":2,"name":"A","picUrl":"https://img.example/a.jpg","viewerHasTicket":true,"latitude":"31.2","longitude":121.4,"addressName":"Lane","distance":1530,"startDate":"2099-01-01 09:00:00","endDate":"2099-01-01 18:00:00"},
        {"kind":"topic","id":7,"name":"T","viewerHasTicket":0},
        {"kind":"hangout","id":9,"title":"Retired"}
        """#), status: 200)
        XCTAssertEqual(rows.map(\.id), ["activity-7", "topic-7"])
        XCTAssertEqual(rows[0].coverURL, "https://img.example/a.jpg")
        XCTAssertTrue(rows[0].viewerHasTicket); XCTAssertFalse(rows[1].viewerHasTicket)
        XCTAssertEqual(rows[0].linkedTopicID, 3); XCTAssertEqual(rows[1].linkedTopicID, 7)
        XCTAssertEqual(rows[0].coordinate, RoamCoordinate(latitude: 31.2, longitude: 121.4))
    }

    func testEnvelopeFailuresAreTypedAndNeverEmpty() throws {
        XCTAssertThrowsError(try RoamEntryNearbyRoute.decode(Data(), status: 401)) { XCTAssertEqual($0 as? APIError, .unauthorized) }
        XCTAssertThrowsError(try RoamEntryNearbyRoute.decode(Data(), status: 403)) { XCTAssertEqual($0 as? APIError, .httpStatus(403)) }
        XCTAssertThrowsError(try RoamEntryNearbyRoute.decode(Data(#"{"code":401}"#.utf8), status: 200)) { XCTAssertEqual($0 as? APIError, .unauthorized) }
        XCTAssertThrowsError(try RoamEntryNearbyRoute.decode(Data(#"{"code":500,"msg":"x"}"#.utf8), status: 200)) { XCTAssertEqual($0 as? APIError, .businessCode(500)) }
        for raw in [#"{"code":200}"#, #"{"code":200,"data":{}}"#, #"{"code":200,"data":{"items":null,"radius":3000}}"#] {
            XCTAssertThrowsError(try RoamEntryNearbyRoute.decode(Data(raw.utf8), status: 200))
        }
        XCTAssertThrowsError(try RoamEntryNearbyRoute.decode(envelope("", radius: 1000), status: 200))
        XCTAssertThrowsError(try RoamEntryNearbyRoute.decode(envelope(#"{"kind":"activity","id":1},{"kind":"activity","id":1}"#), status: 200))
        XCTAssertEqual(try RoamEntryNearbyRoute.decode(envelope(""), status: 200), [])
    }

    func testPeekStatesFollowSourceOrder() throws {
        XCTAssertEqual(RoamEntryPeekState(error: APIError.unauthorized), .login)
        XCTAssertEqual(RoamEntryPeekState(error: APIError.httpStatus(403)), .denied)
        XCTAssertEqual(RoamEntryPeekState(error: APIError.businessCode(403)), .denied)
        XCTAssertEqual(RoamEntryPeekState(error: APIError.notConfigured), .unavailable)
        XCTAssertEqual(RoamEntryPeekState(error: APIError.httpStatus(503)), .failed)
        XCTAssertEqual(RoamEntryPeekState(activities: [], teams: []), .empty)
    }

    func testActivityViewLinksTeamsByTopicOrActivityAndCountsMembers() throws {
        let rows = try RoamEntryNearbyRoute.decode(envelope(#"{"kind":"activity","id":901,"topicId":801,"productType":1,"name":"A","distance":1550,"startDate":"2099-01-01 09:00:00","endDate":"2099-01-01 18:00:00"}"#), status: 200)
        let linked = try teams(#"[{"teamId":1,"activityId":901,"joinedCount":2,"maxMembers":4,"viewerHasTicket":true},{"teamId":2,"topicId":801,"joinedCount":1,"maxMembers":3},{"teamId":3,"activityId":999,"joinedCount":5},{"teamId":4,"activityId":901,"joinedCount":1}]"#)
        let card = RoamEntryActivityCard(activity: rows[0], teams: linked, now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertFalse(card.ended)
        XCTAssertEqual(card.recruitingCount, 3)
        XCTAssertEqual(card.participantCount, 4)
        XCTAssertEqual(card.teams.map(\.teamID.rawValue), [1, 2], "Only the first two linked teams are listed")
        XCTAssertTrue(card.registered, "A linked team ticket counts as registered, as in the source")
        XCTAssertNil(card.primaryKey, "Registered and open: only 发起组队")
        XCTAssertEqual(card.distanceKilometers, 1.6)
        XCTAssertEqual(card.tagKey, "roam.w208.entry.tag.city")
        XCTAssertEqual(card.destination, .topic(801), "A linked topic opens before the activity, as openEntryActivityDetail")
    }

    func testEndedActivityHidesTeamsAndOffersDetail() throws {
        let rows = try RoamEntryNearbyRoute.decode(envelope(#"{"kind":"activity","id":5,"productType":2,"name":"Old","startDate":"2020-01-01 09:00:00","endDate":"2020-01-01 18:00:00"}"#), status: 200)
        let card = RoamEntryActivityCard(activity: rows[0], teams: try teams(#"[{"teamId":1,"activityId":5,"joinedCount":2}]"#), now: Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertTrue(card.ended)
        XCTAssertTrue(card.teams.isEmpty)
        XCTAssertEqual(card.primaryKey, "roam.w208.entry.viewDetail")
        XCTAssertEqual(card.destination, .activity(5))
        XCTAssertEqual(card.tagKey, "roam.w208.entry.tag.free")
        let open = RoamEntryActivityCard(activity: rows[0], teams: [], now: Date(timeIntervalSince1970: 1_500_000_000))
        XCTAssertFalse(open.ended); XCTAssertEqual(open.primaryKey, "roam.w208.entry.register")
    }

    func testIndependentApprovalAndUnapprovedReaderSendsNothing() async throws {
        let c = try context()
        let good = try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 81, paths: [RoamEntryNearbyRoute.path])
        let access = try RoamEntryNearbyReadAccess(context: c, approval: good)
        XCTAssertTrue(access.matches(c))
        for paths in [Set<String>(), ["api/roam/hangout/nearby"], [RoamEntryNearbyRoute.path, "api/team/nearby"]] {
            XCTAssertThrowsError(try RoamEntryNearbyReadAccess(context: c, approval: try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 81, paths: paths)))
        }
        let selection = ManualMapAreaSelection(); selection.select(area)
        let transport = EntryRecordingTransport(String(decoding: envelope(""), as: UTF8.self))
        let unapproved = RoamEntryNearbyReader(configuration: try APIConfiguration(baseURL: base), transport: transport,
            current: { c }, viewerRevision: { 0 }, area: { selection.snapshot }, access: { _ in nil })
        XCTAssertFalse(unapproved.isConfigured)
        do { _ = try await unapproved.entryNearby(); XCTFail("No approval must not read") } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(transport.requests.isEmpty)
        let approved = RoamEntryNearbyReader(configuration: try APIConfiguration(baseURL: base), transport: transport,
            current: { c }, viewerRevision: { 0 }, area: { selection.snapshot }, access: { _ in access })
        XCTAssertTrue(approved.isConfigured)
        let rows = try await approved.entryNearby()
        XCTAssertEqual(rows, [])
        XCTAssertEqual(transport.requests.count, 1)
        access.revoke(); XCTAssertFalse(approved.isConfigured)
    }

    func testFixtureScenariosAndPassportTilesAndRecoveryBanner() async throws {
        let content = try await RoamEntryNearbyFixtureReader(scenario: .content).entryNearby()
        XCTAssertEqual(content.map(\.id), ["activity-901", "topic-802"])
        do { _ = try await RoamEntryNearbyFixtureReader(scenario: .denied).entryNearby(); XCTFail() } catch { XCTAssertEqual(RoamEntryPeekState(error: error), .denied) }
        XCTAssertEqual(RoamPassportHome.Tile.allCases.filter(\.isNew), [.goals, .capsule])
        XCTAssertEqual(RoamPassportHome.Play.allCases.filter(\.isClosed), [.event])
        XCTAssertNil(RoamPassportHome.Tile.history.subtitleKey)
        XCTAssertEqual(RoamPassportHome.Tile.badge.subtitleKey, "roam.w208.passport.tile.badge.sub")
        let empty = try RoamPassportHome(records: [])
        XCTAssertEqual(empty.count(.history), 0); XCTAssertEqual(empty.count(.stamp), 0); XCTAssertNil(empty.count(.goals))
        XCTAssertEqual(RoamHomeRecoveryBanner(status: .finishPending), .needsCheck)
        XCTAssertEqual(RoamHomeRecoveryBanner(status: .unfinished), .recovered)
        XCTAssertNil(RoamHomeRecoveryBanner(status: .none)); XCTAssertNil(RoamHomeRecoveryBanner(status: .unavailable))
    }

    func testPassportToolsSessionReaderNeedsItsOwnApproval() async throws {
        let c = try context()
        let scope = try RoamHistoryScope(market: "cn", deployment: base, accountID: 81)
        let session = try RoamExperienceSession(scope: scope, epoch: 1, token: "synthetic-entry")
        let transport = EntryRecordingTransport(#"{"code":200}"#)
        let reader = RoamPassportToolsSessionReader(configuration: try APIConfiguration(baseURL: base), transport: transport,
            currentSession: { session }, current: { c }, access: { _ in nil })
        XCTAssertFalse(reader.isConfigured)
        XCTAssertEqual(reader.identity, session.identity)
        do { _ = try await reader.monthlyRecap(.init(month: "2026-09")); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(transport.requests.isEmpty)
        let approval = try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 81, paths: Set(RoamPassportToolsService.paths))
        XCTAssertNoThrow(try RoamPassportToolsReadAccess(context: c, approval: approval))
        XCTAssertThrowsError(try RoamPassportToolsReadAccess(context: c, approval: try OperationEndpointApproval(baseURL: base, namespace: "synthetic", accountID: 81, paths: ["api/monthly-recap"])))
        let signedOut = RoamPassportToolsSessionReader(configuration: try APIConfiguration(baseURL: base), transport: transport,
            currentSession: { nil }, current: { c }, access: { _ in try? RoamPassportToolsReadAccess(context: c, approval: approval) })
        do { _ = try await signedOut.monthlyRecap(.init(month: "2026-09")); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
}
