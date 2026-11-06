import XCTest
@testable import QuestifyCore

@MainActor final class RoamNearbyEventsRestoredEntryTests: XCTestCase {
    private func rows(_ id: Int = 71) throws -> [RoamEntryActivity] {
        try JSONDecoder().decode([RoamEntryActivity].self, from: Data("[{\"id\":\(id),\"kind\":\"activity\",\"topicId\":81,\"name\":\"Synthetic activity\"}]".utf8))
    }
    private func card(_ model: RoamNearbyEventsEntryState, _ reader: Reader) throws -> RoamEntryActivityCard {
        guard case .loaded(let cards) = model.visibleState(reader: reader) else { throw APIError.malformedResponse }
        return try XCTUnwrap(cards.first)
    }
    func testLoadedCardsRequireCurrentLoginGrantAndManualCentreImmediately() async throws {
        for change in ["login", "grant", "area", "city", "revision"] {
            let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
            await model.load(reader: reader)
            let row = try card(model, reader), scope = model.loadedScope, readID = model.readID
            let selected = try XCTUnwrap(model.selection(card: row, rendered: scope, readID: readID, reader: reader))
            switch change {
            case "login": reader.isSignedIn = false
            case "grant": reader.isConfigured = false
            case "area": reader.searchArea = nil
            case "city": reader.searchArea = .init(coordinate: RoamCoordinate(latitude: 31, longitude: 121)!, label: "Other")
            default: reader.readKey = "new-revision"
            }
            XCTAssertNil(model.selection(card: row, rendered: scope, readID: readID, reader: reader), change)
            XCTAssertFalse(selected.mayRemainOpen(in: RoamNearbyEventsEntryScope(reader: reader)), change)
            if case .loaded = model.visibleState(reader: reader) { XCTFail(change) }
        }
    }
    func testNoCentreOrApprovalOrLoginNeverDispatchesNorReadsDeviceLocation() async throws {
        for change in ["login", "grant", "area"] {
            let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
            switch change {
            case "login": reader.isSignedIn = false
            case "grant": reader.isConfigured = false
            default: reader.searchArea = nil
            }
            await model.load(reader: reader)
            XCTAssertEqual(reader.calls, 0); XCTAssertNil(model.loadedScope)
        }
    }
    func testEntryKeepsSourceTopicRouteAndMapEventKeepsExactActivityID() async throws {
        let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
        await model.load(reader: reader)
        XCTAssertEqual(try card(model, reader).destination, .topic(81))
        let event = try JSONDecoder().decode(RoamEvent.self, from: Data(#"{"id":71,"topicId":81,"kind":"activity","name":"Synthetic"}"#.utf8))
        XCTAssertEqual(RoamEventDestination(event: event), .activity(71))
    }
    func testDetailReturnKeepsSameSelectionAndDoesNotReadAgain() async throws {
        let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
        await model.load(reader: reader)
        let row = try card(model, reader)
        let selected = try XCTUnwrap(model.selection(card: row, rendered: model.loadedScope, readID: model.readID, reader: reader))
        XCTAssertTrue(selected.mayRemainOpen(in: RoamNearbyEventsEntryScope(reader: reader)))
        XCTAssertEqual(try card(model, reader), row); XCTAssertEqual(reader.calls, 1)
    }
    func testRefreshRetiresOldTapEvenWhenIdenticalRowsReturn() async throws {
        let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
        await model.load(reader: reader)
        let old = try card(model, reader), oldScope = model.loadedScope, oldID = model.readID
        await model.load(reader: reader)
        XCTAssertNil(model.selection(card: old, rendered: oldScope, readID: oldID, reader: reader))
        XCTAssertNotNil(model.selection(card: old, rendered: model.loadedScope, readID: model.readID, reader: reader))
        XCTAssertEqual(reader.calls, 2)
    }
    func testCurrentDeniedRefreshRemovesOldCardsAndExplicitRetryRecovers() async throws {
        let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
        await model.load(reader: reader); reader.error = APIError.httpStatus(403)
        await model.load(reader: reader)
        XCTAssertEqual(model.visibleState(reader: reader), .denied)
        reader.error = nil; await model.load(reader: reader)
        XCTAssertEqual(try card(model, reader).activity.sourceID, 71)
    }
    func testHeldActivityResponseCannotRestoreOldCityOrABARevision() async throws {
        for failure in [false, true] {
            let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
            reader.hold = true; let held = expectation(description: "entry held"); reader.onHeld = { held.fulfill() }
            let task = Task { await model.load(reader: reader) }
            await fulfillment(of: [held], timeout: 2)
            reader.readKey = "city-A-B-A-revision"
            reader.finish(failure ? .failure(APIError.unauthorized) : .success(reader.rows))
            await task.value
            XCTAssertNil(model.loadedScope); XCTAssertEqual(model.visibleState(reader: reader), .loading)
        }
    }
    func testHeldTeamSuccessOrFailureCannotRestoreRevokedCards() async throws {
        for failed in [false, true] {
            let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
            let held = expectation(description: "teams held")
            var pending: CheckedContinuation<[NearbyTeam]?, Never>?
            let task = Task { await model.load(reader: reader, teams: { _ in
                await withCheckedContinuation { pending = $0; held.fulfill() }
            }) }
            await fulfillment(of: [held], timeout: 2)
            reader.isConfigured = false; pending?.resume(returning: failed ? nil : [])
            await task.value
            XCTAssertNil(model.loadedScope); XCTAssertEqual(model.visibleState(reader: reader), .unavailable)
        }
    }
    func testNewRefreshWinsOverOldHeldReply() async throws {
        let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
        reader.hold = true; let held = expectation(description: "old read"); reader.onHeld = { held.fulfill() }
        let old = Task { await model.load(reader: reader) }; await fulfillment(of: [held], timeout: 2)
        reader.hold = false; reader.rows = try rows(72); await model.load(reader: reader)
        reader.finish(.success(try rows(71))); await old.value
        XCTAssertEqual(try card(model, reader).activity.sourceID, 72)
    }
    func testLeaveCancelsLateResultAndReentryReadsFresh() async throws {
        let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
        reader.hold = true; let held = expectation(description: "leaving"); reader.onHeld = { held.fulfill() }
        let task = Task { await model.load(reader: reader) }; await fulfillment(of: [held], timeout: 2)
        model.cancel(); reader.finish(.success(reader.rows)); await task.value
        XCTAssertNil(model.loadedScope)
        reader.hold = false; await model.load(reader: reader)
        XCTAssertEqual(try card(model, reader).activity.sourceID, 71); XCTAssertEqual(reader.calls, 2)
    }

    func testActivitiesAreNavigableBeforeOptionalTeamsCompleteAndFailureIsNotEmptySuccess() async throws {
        let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
        let held = expectation(description: "optional teams held")
        var pending: CheckedContinuation<[NearbyTeam]?, Never>?
        let task = Task { await model.load(reader: reader, teams: { _ in
            await withCheckedContinuation { pending = $0; held.fulfill() }
        }) }
        await fulfillment(of: [held], timeout: 2)
        let row = try card(model, reader)
        XCTAssertEqual(model.visibleTeamState(reader: reader), .loading)
        let selected = try XCTUnwrap(model.selection(card: row, rendered: model.loadedScope, readID: model.readID, reader: reader))
        pending?.resume(returning: nil); await task.value
        XCTAssertEqual(try card(model, reader), row)
        XCTAssertEqual(model.visibleTeamState(reader: reader), .failed)
        XCTAssertTrue(selected.mayRemainOpen(in: RoamNearbyEventsEntryScope(reader: reader)))
        XCTAssertEqual(reader.calls, 1, "Returning from detail does not implicitly fetch the activity again")
    }

    func testExplicitRetryRecoversTeamsButCurrentActivityDenialRemovesEverything() async throws {
        let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
        await model.load(reader: reader, teams: { _ in nil })
        XCTAssertEqual(model.visibleTeamState(reader: reader), .failed)
        let old = try card(model, reader), scope = model.loadedScope, readID = model.readID
        let teams = try JSONDecoder().decode([NearbyTeam].self, from: Data(#"[{"teamId":9,"activityId":71,"joinedCount":2,"maxMembers":4}]"#.utf8))
        await model.load(reader: reader, teams: { _ in teams })
        XCTAssertEqual(model.visibleTeamState(reader: reader), .loaded)
        XCTAssertEqual(try card(model, reader).recruitingCount, 1)
        XCTAssertNil(model.selection(card: old, rendered: scope, readID: readID, reader: reader))
        reader.error = APIError.httpStatus(403)
        var teamCalls = 0
        await model.load(reader: reader, teams: { _ in teamCalls += 1; return teams })
        XCTAssertEqual(model.visibleState(reader: reader), .denied)
        XCTAssertEqual(model.visibleTeamState(reader: reader), .notRequested)
        XCTAssertEqual(teamCalls, 0)
    }

    func testEmptyActivitiesDoNotRequireOrInventTeamRead() async throws {
        let reader = Reader(rows: []), model = RoamNearbyEventsEntryState()
        var calls = 0
        await model.load(reader: reader, teams: { _ in calls += 1; return nil })
        XCTAssertEqual(model.visibleState(reader: reader), .empty)
        XCTAssertEqual(model.visibleTeamState(reader: reader), .notRequested)
        XCTAssertEqual(calls, 0)
        reader.rows = try rows(); await model.load(reader: reader)
        XCTAssertEqual(model.visibleTeamState(reader: reader), .notRequested)
        XCTAssertEqual(try card(model, reader).recruitingCount, 0)
    }

    func testTeamEnrichmentRetiresTheEarlierRenderedTap() async throws {
        let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
        let held = expectation(description: "enrichment")
        var pending: CheckedContinuation<[NearbyTeam]?, Never>?
        let task = Task { await model.load(reader: reader, teams: { _ in
            await withCheckedContinuation { pending = $0; held.fulfill() }
        }) }
        await fulfillment(of: [held], timeout: 2)
        let row = try card(model, reader), scope = model.loadedScope, oldRead = model.readID
        pending?.resume(returning: []); await task.value
        XCTAssertEqual(model.visibleTeamState(reader: reader), .loaded)
        XCTAssertNil(model.selection(card: row, rendered: scope, readID: oldRead, reader: reader))
        XCTAssertNotNil(model.selection(card: row, rendered: model.loadedScope, readID: model.readID, reader: reader))
    }

    func testLateTeamReplyCannotReplaceNewReadOrKeepCancelledActivityVisible() async throws {
        for replace in [false, true] { for failure in [false, true] {
            let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
            let held = expectation(description: "retired teams")
            var pending: CheckedContinuation<[NearbyTeam]?, Never>?
            let task = Task { await model.load(reader: reader, teams: { _ in
                await withCheckedContinuation { pending = $0; held.fulfill() }
            }) }
            await fulfillment(of: [held], timeout: 2)
            if replace { reader.rows = try rows(72); await model.load(reader: reader) }
            else { task.cancel() }
            pending?.resume(returning: failure ? nil : []); await task.value
            XCTAssertEqual(model.visibleTeamState(reader: reader), .notRequested)
            if replace { XCTAssertEqual(try card(model, reader).activity.sourceID, 72) }
            else { XCTAssertNil(model.loadedScope); XCTAssertEqual(model.visibleState(reader: reader), .loading) }
        } }
    }

    func testTeamWarningAndActivityAreHiddenImmediatelyOnScopeLoss() async throws {
        for change in ["login", "grant", "area", "city", "revision"] {
            let reader = Reader(rows: try rows()), model = RoamNearbyEventsEntryState()
            await model.load(reader: reader, teams: { _ in nil })
            XCTAssertEqual(model.visibleTeamState(reader: reader), .failed)
            switch change {
            case "login": reader.isSignedIn = false
            case "grant": reader.isConfigured = false
            case "area": reader.searchArea = nil
            case "city": reader.searchArea = .init(coordinate: RoamCoordinate(latitude: 31, longitude: 121)!, label: "Other")
            default: reader.readKey = "city-A-B-A-revision"
            }
            XCTAssertEqual(model.visibleTeamState(reader: reader), .notRequested, change)
            if case .loaded = model.visibleState(reader: reader) { XCTFail(change) }
        }
    }
    @MainActor private final class Reader: RoamEntryNearbyReading {
        var isConfigured = true, isSignedIn = true
        let isOfflineExample = true
        var readKey = "synthetic-account-1-area-1-approval-1"
        var searchArea: RoamSearchArea? = .init(coordinate: RoamCoordinate(latitude: 30, longitude: 120)!, label: "Selected")
        var rows: [RoamEntryActivity], calls = 0, hold = false
        var error: Error?, onHeld: (() -> Void)?
        var pending: CheckedContinuation<[RoamEntryActivity], Error>?
        init(rows: [RoamEntryActivity]) { self.rows = rows }
        func entryNearby() async throws -> [RoamEntryActivity] {
            calls += 1
            if hold { return try await withCheckedThrowingContinuation { pending = $0; onHeld?() } }
            if let error { throw error }; return rows
        }
        func finish(_ result: Result<[RoamEntryActivity], Error>) { let p = pending; pending = nil; p?.resume(with: result) }
    }
}

@MainActor extension RoamNearbyEventsRestoredEntryTests {
    func testCurrentInvalidSourceIDsCannotBecomeSuccessfulEmptyButRetiredKindsRemainHidden() throws {
        func envelope(_ rows: String) -> Data {
            Data(#"{"code":200,"data":{"radius":3000,"items":[\#(rows)]}}"#.utf8)
        }
        for raw in [#"{"kind":"activity","id":0}"#, #"{"kind":"topic","id":-1}"#,
                    #"{"kind":"activity"}"#, #"{"kind":"topic","id":"invalid"}"#] {
            XCTAssertThrowsError(try RoamEntryNearbyRoute.decode(envelope(raw), status: 200)) {
                XCTAssertEqual($0 as? APIError, .malformedResponse)
            }
        }
        XCTAssertEqual(try RoamEntryNearbyRoute.decode(envelope(#"{"kind":"hangout","id":0}"#), status: 200), [])
        XCTAssertEqual(try RoamEntryNearbyRoute.decode(envelope(#"{"kind":"activity","id":71},{"kind":"topic","id":81}"#), status: 200).map(\.id), ["activity-71", "topic-81"])
    }
}
