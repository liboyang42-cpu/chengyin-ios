import XCTest
@testable import QuestifyCore

final class RoamRetainedReadTests: XCTestCase {
    private final class ReaderMarker {}
    private let reader = ReaderMarker()
    private let lease = UUID()
    private let time = Date(timeIntervalSince1970: 1_800_000_000)
    private func scope(layer: RoamLayer = .places, radius: Int = 3000, query: String = "", identity: RoamReadIdentity? = nil,
                       placeFilter: RoamPlaceFilter = .all, eventFilter: RoamEventFilter = .all,
                       area: RoamSearchArea? = nil) throws -> RoamRetainedRead.Scope {
        try XCTUnwrap(.init(readerID: ObjectIdentifier(reader),
            identity: identity ?? .init(accountID: 7, epoch: 1, role: "player", viewerRevision: 1, areaRevision: 1, manualMapApprovalRevision: lease),
            area: area ?? .init(coordinate: .init(latitude: 1, longitude: 2)!, label: "Manual"),
            layer: layer, radius: radius, query: query, placeFilter: placeFilter, eventFilter: eventFilter, isConfigured: true))
    }
    private func place(_ id: Int = 1) throws -> RoamMapItem {
        .place(try JSONDecoder().decode(RoamPlace.self, from: Data("{\"id\":\(id),\"name\":\"Synthetic place\",\"type\":1,\"lat\":1,\"lng\":2}".utf8)))
    }
    private func seeded(_ scope: RoamRetainedRead.Scope) throws -> RoamRetainedRead {
        var state = RoamRetainedRead()
        let ticket = try XCTUnwrap(state.begin(scope: scope))
        XCTAssertTrue(state.finish(ticket, items: [try place()], readAt: time))
        return state
    }
    func testSameQueryRefreshAndTransientFailureRetainReadOnlyRowsAndReceiptTime() throws {
        let scope = try scope(); var state = try seeded(scope)
        let before = try XCTUnwrap(state.snapshot(in: scope)); XCTAssertFalse(before.isRetained)
        let ticket = try XCTUnwrap(state.begin(scope: scope))
        let during = try XCTUnwrap(state.snapshot(in: scope)); XCTAssertTrue(during.isRetained)
        XCTAssertEqual(during.items, before.items); XCTAssertEqual(during.readAt, time)
        state.fail(ticket, error: APIError.httpStatus(503))
        XCTAssertEqual(state.snapshot(in: scope), during)
        let retry = try XCTUnwrap(state.begin(scope: scope))
        XCTAssertTrue(state.finish(retry, items: [try place(2)], readAt: time.addingTimeInterval(10)))
        XCTAssertEqual(state.snapshot(in: scope)?.items.map(\.id), ["place-2"])
        XCTAssertEqual(state.snapshot(in: scope)?.readAt, time.addingTimeInterval(10))
        XCTAssertEqual(state.snapshot(in: scope)?.isRetained, false)
    }
    func testFirstFailureHasNoInventedEmptyAndSuccessEmptyReplacesPreviousRows() throws {
        let scope = try scope(); var state = RoamRetainedRead()
        let first = try XCTUnwrap(state.begin(scope: scope))
        state.fail(first, error: URLError(.notConnectedToInternet))
        XCTAssertNil(state.snapshot(in: scope))
        state = try seeded(scope)
        let empty = try XCTUnwrap(state.begin(scope: scope))
        XCTAssertTrue(state.finish(empty, items: [], readAt: time))
        XCTAssertEqual(state.snapshot(in: scope)?.items, [])
        XCTAssertEqual(state.snapshot(in: scope)?.isRetained, false)
    }
    func test401403ConfigurationMalformedAndUnknownFailuresClearInsteadOfRetain() throws {
        let scope = try scope()
        let errors: [Error] = [APIError.unauthorized, APIError.httpStatus(401), APIError.httpStatus(403),
            APIError.businessCode(401), APIError.businessCode(403), APIError.notConfigured, APIError.invalidConfiguration,
            APIError.invalidRequest, APIError.malformedResponse, APIError.httpStatus(404), APIError.businessCode(499),
            URLError(.userAuthenticationRequired), CancellationError()]
        for error in errors {
            var state = try seeded(scope); let ticket = try XCTUnwrap(state.begin(scope: scope))
            state.fail(ticket, error: error); XCTAssertNil(state.snapshot(in: scope), String(describing: error))
        }
    }
    func testOnlyExplicitTransientFailuresMayRetain() {
        let errors: [Error] = [APIError.httpStatus(408), APIError.httpStatus(429), APIError.httpStatus(500),
                               APIError.businessCode(503), URLError(.timedOut), URLError(.networkConnectionLost)]
        for error in errors {
            XCTAssertTrue(RoamRetainedRead.isTransient(error))
        }
        XCTAssertFalse(RoamRetainedRead.isTransient(APIError.businessCode(200)))
    }
    func testAccountSessionRoleViewerLeaseAndAreaRevisionsInvalidateSnapshot() throws {
        let original = try scope()
        let identities = [RoamReadIdentity(accountID: 8, epoch: 1, role: "player", viewerRevision: 1, areaRevision: 1, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 2, role: "player", viewerRevision: 1, areaRevision: 1, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 1, role: "merchant", viewerRevision: 1, areaRevision: 1, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 1, role: "player", viewerRevision: 2, areaRevision: 1, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 1, role: "player", viewerRevision: 1, areaRevision: 2, manualMapApprovalRevision: lease),
            .init(accountID: 7, epoch: 1, role: "player", viewerRevision: 1, areaRevision: 1, manualMapApprovalRevision: nil),
            .init(accountID: 7, epoch: 1, role: "player", viewerRevision: 1, areaRevision: 1, manualMapApprovalRevision: UUID())]
        for identity in identities {
            var state = try seeded(original); let ticket = try XCTUnwrap(state.begin(scope: original)); let changed = try scope(identity: identity)
            XCTAssertNil(state.snapshot(in: changed)); state.retainOnly(scope: changed)
            XCTAssertFalse(state.finish(ticket, items: [try place()], readAt: time))
            XCTAssertNil(state.snapshot(in: original))
        }
    }
    func testLayerRadiusLocalFiltersQueryAndAreaAreExactRetentionScope() throws {
        let original = try scope()
        let changes = [try scope(layer: .routes), try scope(radius: 1000), try scope(query: "new"),
                       try scope(placeFilter: .merchant), try scope(eventFilter: .activity),
                       try scope(area: .init(coordinate: .init(latitude: 2, longitude: 3)!, label: "Elsewhere"))]
        for changed in changes {
            var state = try seeded(original); XCTAssertNil(state.snapshot(in: changed))
            _ = state.begin(scope: changed); XCTAssertNil(state.snapshot(in: changed)); XCTAssertNil(state.snapshot(in: original))
        }
    }
    func testPlayerCoordinatesNeverSurviveRefreshOrFailedRefresh() throws {
        let scope = try scope(layer: .players)
        let player = try JSONDecoder().decode(RoamPlayer.self, from: Data(#"{"memberId":1,"nickname":"Synthetic player","lat":1,"lng":2,"explorePct":0,"shops":0,"elapsedSec":0}"#.utf8))
        var state = RoamRetainedRead()
        let first = try XCTUnwrap(state.begin(scope: scope))
        XCTAssertTrue(state.finish(first, items: [.player(player)], readAt: time))
        let ticket = try XCTUnwrap(state.begin(scope: scope)); XCTAssertNil(state.snapshot(in: scope))
        state.fail(ticket, error: APIError.httpStatus(503)); XCTAssertNil(state.snapshot(in: scope))
    }
    func testOlderSuccessFailureAndCancellationCannotReplaceLatestRead() throws {
        let scope = try scope(); var state = try seeded(scope)
        let older = try XCTUnwrap(state.begin(scope: scope)), newer = try XCTUnwrap(state.begin(scope: scope))
        XCTAssertTrue(state.finish(newer, items: [try place(2)], readAt: time.addingTimeInterval(1)))
        XCTAssertFalse(state.finish(older, items: [try place(3)], readAt: time.addingTimeInterval(2)))
        state.fail(older, error: APIError.unauthorized); state.cancel(older)
        XCTAssertEqual(state.snapshot(in: scope)?.items.map(\.id), ["place-2"])
        let cancelled = try XCTUnwrap(state.begin(scope: scope)); state.cancel(cancelled)
        XCTAssertNil(state.snapshot(in: scope))
    }
    func testDepartureInvalidScopeAndCrossLayerPayloadFailClosed() throws {
        let scope = try scope(); var state = try seeded(scope)
        state.clear(); XCTAssertNil(state.snapshot(in: scope))
        _ = state.begin(scope: nil); XCTAssertNil(state.snapshot(in: nil))
        let wrongScope = try self.scope(layer: .routes)
        let wrong = try XCTUnwrap(state.begin(scope: wrongScope))
        XCTAssertFalse(state.finish(wrong, items: [try place()], readAt: time))
        XCTAssertNil(state.snapshot(in: wrongScope))
    }
}
