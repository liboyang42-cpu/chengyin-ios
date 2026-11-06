import XCTest
@testable import Questify

/// J7 read-only slice: real calendar model, session access and service, fake HTTP only.
@MainActor final class ClubEventCalendarHTTPJourneyTests: XCTestCase {
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var active = true, failTopics = false
        var topicStatus = 200
        var afterRequest: ((URLRequest) -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-calendar-token")
            let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Int])
            afterRequest?(request)
            switch request.url?.path {
            case "/native/api/club/access/me":
                XCTAssertEqual(fields, ["clubId": 81])
                return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": ["active": active,
                    "club": ["id": 81], "permissions": [String](), "roleCodes": [String]()]]), 200)
            case "/native/api/club/topics":
                XCTAssertEqual(fields, ["id": 81])
                if failTopics { throw URLError(.timedOut) }
                if topicStatus != 200 { return (Data(#"{"code":401}"#.utf8), topicStatus) }
                return (Data(#"{"code":200,"data":[{"id":91,"name":"Synthetic event","startDate":"2028-02-29"}]}"#.utf8), 200)
            default: XCTFail("Unexpected route, including any mutation"); throw APIError.invalidRequest
            }
        }
        var paths: [String] { requests.compactMap { $0.url?.path } }
    }
    @MainActor private final class Harness {
        let wire = Wire()
        var session: ClubGovernanceSession?
        var viewerRevision: UInt64 = 1
        var expired: [ClubReadIdentity] = []
        let service: ClubGovernanceService
        lazy var access = ClubGovernanceSessionAccess(service: service, currentSession: { self.session },
            viewerRevision: { self.viewerRevision }, onUnauthorized: { self.expired.append($0) })
        init() throws {
            session = try .init(accountID: 7, epoch: 1, token: "synthetic-calendar-token", storageNamespace: "calendar-http-test")
            service = ClubGovernanceService(configuration: try .init(baseURL: URL(string: "https://club.example.test/native/")!), transport: wire)
        }
        var context: ClubGovernanceReadContext {
            .init(operation: .topics, scope: .init(clubID: 81), identity: access.identity,
                viewerRevision: viewerRevision, authorizationGeneration: access.authorizationGeneration, accessIdentity: ObjectIdentifier(access))
        }
    }
    func testActiveMembershipReadPrecedesCalendarAndDoesNotEnableWrites() async throws {
        let h = try Harness(), model = ClubEventCalendarReadModel(), context = h.context
        await model.load(context, access: h.access)
        XCTAssertEqual(h.wire.paths, ["/native/api/club/access/me", "/native/api/club/topics"])
        XCTAssertEqual(model.snapshot?.events.map(\.id), [91]); XCTAssertTrue(model.canSelect(context, access: h.access))
        XCTAssertNil(model.failure); XCTAssertFalse(h.access.allowsOfflineWrites)
        XCTAssertEqual(model.reportSnapshot?.scope.clubID, 81)
    }
    func testRefreshFailureClearsSelectionAndRetryRepeatsPermissionRead() async throws {
        let h = try Harness(), model = ClubEventCalendarReadModel(), context = h.context
        await model.load(context, access: h.access)
        h.wire.failTopics = true
        await model.load(context, access: h.access)
        XCTAssertNil(model.snapshot); XCTAssertNil(model.reportSnapshot); XCTAssertNotNil(model.failure)
        XCTAssertFalse(model.canSelect(context, access: h.access))
        h.wire.failTopics = false
        await model.load(context, access: h.access)
        XCTAssertEqual(model.snapshot?.events.map(\.id), [91]); XCTAssertNil(model.failure)
        XCTAssertEqual(h.wire.paths, Array(repeating: ["/native/api/club/access/me", "/native/api/club/topics"], count: 3).flatMap { $0 })
    }
    func testMembershipRevocationStopsBeforeTopicsAndRemovesPreviouslyAcceptedEvents() async throws {
        let h = try Harness(), model = ClubEventCalendarReadModel(), context = h.context
        await model.load(context, access: h.access); h.wire.active = false
        await model.load(context, access: h.access)
        XCTAssertEqual(model.failure, .forbidden); XCTAssertNil(model.snapshot); XCTAssertNil(model.activityOverview)
        XCTAssertFalse(model.canSelect(context, access: h.access)); XCTAssertTrue(h.expired.isEmpty)
        XCTAssertEqual(h.wire.paths, ["/native/api/club/access/me", "/native/api/club/topics", "/native/api/club/access/me"])
    }
    func testCurrentAccount401IsReportedForOnlyCapturedIdentity() async throws {
        let h = try Harness(), model = ClubEventCalendarReadModel(), context = h.context
        h.wire.topicStatus = 401
        await model.load(context, access: h.access)
        XCTAssertEqual(h.expired, [try XCTUnwrap(context.identity)])
        XCTAssertEqual(model.failure, .signedOut); XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.canSelect(context, access: h.access)); XCTAssertEqual(h.wire.requests.count, 2)
    }
    func testOldAccountLate401CannotExpireReplacementOrPublishCalendar() async throws {
        let h = try Harness(), model = ClubEventCalendarReadModel(), context = h.context
        let replacement = try ClubGovernanceSession(accountID: 8, epoch: 2, token: "replacement-token", storageNamespace: "calendar-http-test")
        h.wire.topicStatus = 401
        h.wire.afterRequest = { request in
            if request.url?.lastPathComponent == "topics" { h.session = replacement; h.viewerRevision += 1 }
        }
        await model.load(context, access: h.access)
        XCTAssertEqual(h.session?.identity.accountID, 8); XCTAssertTrue(h.expired.isEmpty)
        XCTAssertNil(model.snapshot); XCTAssertNil(model.failure); XCTAssertFalse(model.canSelect(context, access: h.access))
        await model.load(context, access: h.access)
        XCTAssertEqual(h.wire.requests.count, 2)
    }
    func testSuspendedVisitDropsHTTPReplyAndResumeRequiresExplicitFreshRead() async throws {
        let h = try Harness(), model = ClubEventCalendarReadModel(), context = h.context
        h.wire.afterRequest = { request in if request.url?.lastPathComponent == "topics" { model.suspend() } }
        await model.load(context, access: h.access)
        XCTAssertNil(model.snapshot); XCTAssertFalse(model.canSelect(context, access: h.access))
        await model.load(context, access: h.access); XCTAssertEqual(h.wire.requests.count, 2)
        h.wire.afterRequest = nil; model.resume()
        XCTAssertNil(model.snapshot); XCTAssertEqual(h.wire.requests.count, 2)
        await model.load(context, access: h.access)
        XCTAssertEqual(model.snapshot?.events.map(\.id), [91]); XCTAssertEqual(h.wire.requests.count, 4)
    }
}
