import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class JourneyRoleProjectionTests: XCTestCase {
    private func content(_ role: String) -> PlayWireValue { .object(["roleId": .string(role), "title": .string(role + " title"), "body": .string(role + " private body"), "items": .array([.object(["label": .string("Clue"), "text": .string(role + " detail")])])]) }
    private func encounter(_ role: PlayWireValue, node: Int = 34) -> PlayWireValue { .object(["nodeId": .int(node), "runId": .integer(100), "stateVersion": .integer(2), "roleView": role]) }
    func testAssignedAAndBAcceptOnlyTheirSingleServerView() throws {
        for role in ["A", "B"] {
            let projection = try XCTUnwrap(JourneyRoleProjection(encounter: encounter(.object(["role": .string(role), "views": .array([content(role)]), "otherRoleLabel": .string("Partner")])), expectedNodeID: 34))
            XCTAssertEqual(projection.assignment.rawValue, role); XCTAssertEqual(projection.views.map(\.roleID), [role]); XCTAssertEqual(projection.otherRoleLabel, "Partner")
        }
    }
    func testSoloIsOnlyServerModeAllowingBothViews() throws {
        let projection = try XCTUnwrap(JourneyRoleProjection(encounter: encounter(.object(["role": .string("SOLO"), "views": .array([content("A"), content("B")])])), expectedNodeID: 34))
        XCTAssertEqual(projection.assignment, .solo); XCTAssertEqual(Set(projection.views.map(\.roleID)), ["A", "B"])
    }
    func testAssignedRoleCannotContainOppositeOrExtraView() {
        for rows in [[content("B")], [content("A"), content("B")], [content("A"), content("A")], []] {
            XCTAssertThrowsError(try JourneyRoleProjection(encounter: encounter(.object(["role": .string("A"), "views": .array(rows)])), expectedNodeID: 34))
        }
    }
    func testMissingAssignmentRequiresNoViewsAndDoesNotInferRole() throws {
        let projection = try XCTUnwrap(JourneyRoleProjection(encounter: encounter(.object(["roleMissing": .bool(true), "views": .array([])])), expectedNodeID: 34))
        XCTAssertEqual(projection.assignment, .missing); XCTAssertTrue(projection.views.isEmpty); XCTAssertNil(projection.otherRoleLabel)
        XCTAssertThrowsError(try JourneyRoleProjection(encounter: encounter(.object(["roleMissing": .bool(true), "views": .array([content("A")])])), expectedNodeID: 34))
        XCTAssertThrowsError(try JourneyRoleProjection(encounter: encounter(.object(["roleMissing": .bool(true), "role": .string("A"), "views": .array([])])), expectedNodeID: 34))
    }
    func testUnknownAndTranslatedRoleValuesReject() {
        for role in ["a", "角色A", "LEADER", "missing", ""] {
            XCTAssertThrowsError(try JourneyRoleProjection(encounter: encounter(.object(["role": .string(role), "views": .array([content("A")])])), expectedNodeID: 34))
        }
    }
    func testPublicCreatorRoleViewsCannotBecomePlayerContent() throws {
        let raw: PlayWireValue = .object(["roleViews": .object(["enabled": .bool(true), "views": .array([content("A"), content("B")])])])
        XCTAssertNil(try JourneyRoleProjection(encounter: raw, expectedNodeID: 34))
    }
    func testRoleProjectionRequiresBoundNodeRunAndVersion() {
        let role: PlayWireValue = .object(["role": .string("A"), "views": .array([content("A")])])
        XCTAssertThrowsError(try JourneyRoleProjection(encounter: encounter(role, node: 35), expectedNodeID: 34))
        for key in ["nodeId", "runId", "stateVersion"] {
            var raw = encounter(role).object!; raw.removeValue(forKey: key)
            XCTAssertThrowsError(try JourneyRoleProjection(encounter: .object(raw), expectedNodeID: 34))
        }
        var raw = encounter(role).object!; raw["runId"] = .integer(0); XCTAssertThrowsError(try JourneyRoleProjection(encounter: .object(raw), expectedNodeID: 34))
    }
    func testMissingRoleFieldIsAnOptionalAugmentation() throws { XCTAssertNil(try JourneyRoleProjection(encounter: .object([:]), expectedNodeID: 34)) }
    func testSoloMustContainExactlyABOnce() {
        for rows in [[content("A")], [content("A"), content("A")], [content("A"), content("B"), content("B")]] {
            XCTAssertThrowsError(try JourneyRoleProjection(encounter: encounter(.object(["role": .string("SOLO"), "views": .array(rows)])), expectedNodeID: 34))
        }
    }
    func testTextAndItemLimitsRejectMalformedPayloads() {
        var view = content("A").object!; view["body"] = .string(String(repeating: "🎨", count: 101))
        XCTAssertThrowsError(try JourneyRoleProjection(encounter: encounter(.object(["role": .string("A"), "views": .array([.object(view)])])), expectedNodeID: 34))
        view = content("A").object!; view["items"] = .array(Array(repeating: .object(["label": .string("Clue"), "text": .string("Detail")]), count: 9))
        XCTAssertThrowsError(try JourneyRoleProjection(encounter: encounter(.object(["role": .string("A"), "views": .array([.object(view)])])), expectedNodeID: 34))
    }
    func testUnknownFieldsAreNotRetainedOrRendered() throws {
        var view = content("A").object!; view["secretOtherView"] = content("B")
        let projection = try XCTUnwrap(JourneyRoleProjection(encounter: encounter(.object(["role": .string("A"), "views": .array([.object(view)]), "advancedConfigJson": .string("private")])), expectedNodeID: 34))
        XCTAssertEqual(projection.views.count, 1); XCTAssertEqual(projection.views[0].body, "A private body")
    }
}

private final class RoleViewFakeHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    var body = #"{"code":200,"data":{"nodeId":34,"runId":100,"stateVersion":1,"roleView":{"role":"A","views":[{"roleId":"A","title":"Own title","body":"Own body","items":[]}]}}}"#
    var status = 200
    var fail = false
    var beforeResponse: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeResponse?(); if fail { throw URLError(.networkConnectionLost) }
        return (Data(body.utf8), status)
    }
}
@MainActor final class JourneyRoleCoordinatorTests: XCTestCase {
    private func owner(_ epoch: UInt64 = 1) throws -> PlayExperienceSession { try .init(accountID: 7, epoch: epoch, namespace: "CN.role-fixture", token: "fixture-token") }
    private func service(_ http: RoleViewFakeHTTP, enabled: Bool = true) throws -> JourneyContentService { .init(configuration: try APIConfiguration(baseURL: URL(string: "https://fixture.example")!), transport: http, readsEnabled: enabled) }
    func testDefaultOffNeverMakesRequest() async throws {
        let http = RoleViewFakeHTTP(), session = try owner()
        let model = JourneyRoleViewCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try service(http, enabled: false), currentSession: { session })
        await model.load(); XCTAssertTrue(http.requests.isEmpty); XCTAssertNil(model.projection); XCTAssertEqual(model.status, .idle)
    }
    func testActivityQueryIsReadOnlyAndBoundToExactScope() async throws {
        let http = RoleViewFakeHTTP(); let result = try await service(http).roleView(scope: .activity(5), topicID: 12, nodeID: 34, token: "fixture-token")
        XCTAssertEqual(result?.assignment, .a)
        let request = try XCTUnwrap(http.requests.first); XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/api/play/encounter"); XCTAssertNil(request.httpBody)
        let fields = Dictionary(uniqueKeysWithValues: try XCTUnwrap(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(fields, ["activityId": "5", "topicId": "12", "nodeId": "34"])
    }
    func testTopicQueryDoesNotFabricateActivityAndMismatchedTopicNeverReads() async throws {
        let http = RoleViewFakeHTTP(), api = try service(http)
        _ = try await api.roleView(scope: .topic(12), topicID: 12, nodeID: 34, token: "fixture-token")
        XCTAssertFalse(http.requests[0].url?.query?.contains("activityId") ?? true)
        do { _ = try await api.roleView(scope: .topic(99), topicID: 12, nodeID: 34, token: "fixture-token"); XCTFail() } catch {}
        XCTAssertEqual(http.requests.count, 1)
    }
    func testSingleLoadCloseClearsThenReopenReadsAgain() async throws {
        let http = RoleViewFakeHTTP(), session = try owner()
        let model = JourneyRoleViewCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try service(http), currentSession: { session })
        await model.load(); await model.load(); XCTAssertEqual(http.requests.count, 1); XCTAssertNotNil(model.projection)
        model.dismiss(); XCTAssertNil(model.projection); XCTAssertEqual(model.status, .closed)
        await model.load(); XCTAssertEqual(http.requests.count, 2); XCTAssertNotNil(model.projection)
        model.close(); XCTAssertNil(model.projection); XCTAssertEqual(model.status, .idle)
    }
    func testAccountChangeErasesPrivateContent() async throws {
        let http = RoleViewFakeHTTP(); var session: PlayExperienceSession? = try owner()
        let model = JourneyRoleViewCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try service(http), currentSession: { session })
        await model.load(); session = try owner(2); model.synchronize(); XCTAssertNil(model.projection); XCTAssertEqual(model.status, .idle)
    }
    func testAccountChangeDuringReadDiscardsReply() async throws {
        let http = RoleViewFakeHTTP(); var session: PlayExperienceSession? = try owner()
        let model = JourneyRoleViewCoordinator(scope: .activity(5), topicID: 12, nodeID: 34, service: try service(http), currentSession: { session })
        http.beforeResponse = { session = nil }; await model.load(); XCTAssertNil(model.projection); XCTAssertEqual(model.status, .idle)
    }
    func testCloseDuringReadDiscardsReply() async throws {
        let http = RoleViewFakeHTTP(), session = try owner()
        let model = JourneyRoleViewCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try service(http), currentSession: { session })
        http.beforeResponse = { model.close() }; await model.load(); XCTAssertNil(model.projection); XCTAssertEqual(model.status, .idle)
    }
    func testMalformedOppositeRoleCannotExposeEitherSide() async throws {
        let http = RoleViewFakeHTTP(), session = try owner()
        http.body = #"{"code":200,"data":{"nodeId":34,"runId":100,"stateVersion":1,"roleView":{"role":"A","views":[{"roleId":"B","body":"Must not render"}]}}}"#
        let model = JourneyRoleViewCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try service(http), currentSession: { session })
        await model.load(); XCTAssertNil(model.projection); XCTAssertEqual(model.status, .unavailable)
    }
    func testMissingAssignmentIsReadableButNeverClientAssigned() async throws {
        let http = RoleViewFakeHTTP(), session = try owner()
        http.body = #"{"code":200,"data":{"nodeId":34,"runId":100,"stateVersion":1,"roleView":{"roleMissing":true,"views":[]}}}"#
        let model = JourneyRoleViewCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try service(http), currentSession: { session })
        await model.load(); XCTAssertEqual(model.projection?.assignment, .missing); XCTAssertEqual(model.status, .ready); XCTAssertTrue(model.projection?.views.isEmpty == true)
    }
    func testReadFailureIsLocalAndExplicitRefreshCanRecover() async throws {
        let http = RoleViewFakeHTTP(), session = try owner(); http.fail = true
        let model = JourneyRoleViewCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try service(http), currentSession: { session })
        await model.load(); await model.load(); XCTAssertEqual(http.requests.count, 1); XCTAssertEqual(model.status, .unavailable)
        http.fail = false; await model.refresh(); XCTAssertEqual(http.requests.count, 2); XCTAssertEqual(model.status, .ready)
    }
    func testUnauthorizedClearsAndExpiresOnlyCapturedSession() async throws {
        let http = RoleViewFakeHTTP(); var session: PlayExperienceSession? = try owner(); let captured = session; var expired: PlayExperienceSession?
        http.status = 401
        let model = JourneyRoleViewCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try service(http), currentSession: { session }, onUnauthorized: { expired = $0; session = nil })
        await model.load(); XCTAssertEqual(expired, captured); XCTAssertNil(model.projection)
    }
    func testParentRunAndVersionRejectStaleProjection() async throws {
        let http = RoleViewFakeHTTP(), session = try owner()
        let model = JourneyRoleViewCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try service(http), currentSession: { session })
        await model.load(expectedRunID: 101, minimumStateVersion: 1); XCTAssertNil(model.projection); XCTAssertEqual(model.status, .unavailable)
        await model.load(expectedRunID: 100, minimumStateVersion: 2); XCTAssertNil(model.projection); XCTAssertEqual(model.status, .unavailable)
        await model.load(expectedRunID: 100, minimumStateVersion: 1); XCTAssertNotNil(model.projection)
    }
    func testRunContextChangeForcesFreshReadInsteadOfCachedRole() async throws {
        let http = RoleViewFakeHTTP(), session = try owner()
        let model = JourneyRoleViewCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try service(http), currentSession: { session })
        await model.load(expectedRunID: 100, minimumStateVersion: 1); XCTAssertEqual(http.requests.count, 1)
        http.body = http.body.replacingOccurrences(of: "\"runId\":100", with: "\"runId\":101")
        await model.load(expectedRunID: 101, minimumStateVersion: 1); XCTAssertEqual(http.requests.count, 2); XCTAssertEqual(model.projection?.runID, 101)
        model.dismiss(); await model.refresh(); XCTAssertEqual(model.projection?.runID, 101)
    }

}
