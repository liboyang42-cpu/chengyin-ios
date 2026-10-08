import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic transport only. These exercise the real reader, never business writes.
@available(macOS 14.0, *)
@MainActor final class CityPlayerReadRecoveryTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func approval() throws -> CityPlayerReadApproval {
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "city-recovery", token: "synthetic-7"))
        return try .init(context: context, regionID: "city-1", expiresAt: Date().addingTimeInterval(600))
    }
    private func reply(_ view: CityReadRoute.View, revision: Int = 1, season: String = "season-1",
                       empty: Bool = false, unpublished: Bool = false) throws -> (Data, Int) {
        let board: [String: Any] = ["gameId": "game-1", "boardId": "board-\(revision)", "regionId": "city-1",
            "seasonId": season, "rulesReleaseId": "release-\(revision)", "rulesHash": String(repeating: "a", count: 64),
            "lifecycle": "OPEN", "title": "Synthetic CITY", "revision": revision]
        var value: [String: Any] = ["contract": "CITY_PLAYER_READ_V1", "scope": "CITY", "status": "AVAILABLE", "board": board]
        switch view {
        case .current: value["participationStatus"] = "JOINED"; value["pointsStatus"] = "AVAILABLE"
        case .participation:
            value["participationStatus"] = "JOINED"
            value["participation"] = ["participationId": "participation-\(revision)", "membershipVersion": revision]
        case .points:
            let points: [[String: Any]] = empty ? [] : [["pointId": "point-\(revision)", "title": "Visible point", "latitude": 31, "longitude": 121, "mine": true]]
            value["points"] = points; value["complete"] = true
        }
        if unpublished { value = ["contract": "CITY_PLAYER_READ_V1", "scope": "CITY", "status": "NO_CURRENT_BOARD", "regionId": "city-1"] }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": value]), 200)
    }
    private func error(_ status: Int, _ code: String) throws -> (Data, Int) {
        (try JSONSerialization.data(withJSONObject: ["code": status, "errorCode": code]), status)
    }
    private func complete(revision: Int = 1, season: String = "season-1", empty: Bool = false) throws -> [(Data, Int)] {
        try [CityReadRoute.View.current, .participation, .points].map { try reply($0, revision: revision, season: season, empty: empty) }
    }
    private func views(_ wire: Wire) -> [CityReadRoute.View] {
        wire.requests.compactMap { CityReadRoute(request: $0, baseURL: base)?.view }
    }
    func testSnapshotChangeRestartsCurrentAndNeverMixesMembershipOrSeason() async throws {
        for stage in [CityReadRoute.View.current, .participation, .points] {
            let first: [(Data, Int)]
            switch stage {
            case .current: first = []
            case .participation: first = [try reply(.current)]
            case .points: first = [try reply(.current), try reply(.participation)]
            }
            let wire = Wire(first + [try error(409, "CITY_SNAPSHOT_CHANGED")] + (try complete(revision: 2, season: "season-2")))
            let reader = CityPlayerReader(approval: try approval(), transport: wire, isCurrent: { true })
            await reader.load()
            guard case .available(let value) = reader.state else { XCTFail("recovery did not publish"); continue }
            XCTAssertEqual(value.board.boardId, "board-2"); XCTAssertEqual(value.board.seasonId, "season-2")
            XCTAssertEqual(value.participation?.participationId, "participation-2")
            XCTAssertEqual(value.points?.map(\.pointId), ["point-2"])
            XCTAssertEqual(Array(views(wire).suffix(3)), [.current, .participation, .points])
            XCTAssertEqual(wire.requests.count, first.count + 4)
            for request in wire.requests.suffix(2) {
                let items = try XCTUnwrap(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems)
                XCTAssertEqual(items.first { $0.name == "boardId" }?.value, "board-2")
                XCTAssertEqual(items.first { $0.name == "seasonId" }?.value, "season-2")
                XCTAssertEqual(items.first { $0.name == "revision" }?.value, "2")
            }
        }
    }
    func testSecondSnapshotConflictStopsWithoutLoopOrPartialProjection() async throws {
        let conflict = try error(409, "CITY_SNAPSHOT_CHANGED")
        let wire = Wire([try reply(.current), try reply(.participation), conflict,
                         try reply(.current, revision: 2), conflict])
        let reader = CityPlayerReader(approval: try approval(), transport: wire, isCurrent: { true })
        await reader.load()
        XCTAssertEqual(reader.state, .unavailable); XCTAssertNil(reader.pointMapContext)
        XCTAssertEqual(views(wire), [.current, .participation, .points, .current, .participation])
        XCTAssertTrue(wire.replies.isEmpty)
    }
    func testRecoveryPreservesUnpublishedUnavailableAndVerifiedEmptyMeanings() async throws {
        for result in ["unpublished", "unavailable", "empty"] {
            let recovered: [(Data, Int)]
            switch result {
            case "unpublished": recovered = [try reply(.current, unpublished: true)]
            case "unavailable": recovered = [try error(503, "CITY_READ_UNAVAILABLE")]
            default: recovered = try complete(revision: 2, empty: true)
            }
            let wire = Wire([try reply(.current), try error(409, "CITY_SNAPSHOT_CHANGED")] + recovered)
            let reader = CityPlayerReader(approval: try approval(), transport: wire, isCurrent: { true })
            await reader.load()
            switch result {
            case "unpublished": XCTAssertEqual(reader.state, .notPublished)
            case "unavailable": XCTAssertEqual(reader.state, .unavailable)
            default: XCTAssertEqual(reader.pointMapContext?.points, [])
            }
        }
    }
    func testUnrelatedErrorsAreNeverAutomaticallyRetried() async throws {
        for response in [try error(503, "CITY_READ_UNAVAILABLE"), try error(409, "OTHER_CONFLICT"),
                         try error(200, "CITY_SNAPSHOT_CHANGED"), (Data("invalid".utf8), 200)] {
            let wire = Wire([response])
            let reader = CityPlayerReader(approval: try approval(), transport: wire, isCurrent: { true })
            await reader.load()
            XCTAssertEqual(reader.state, .unavailable); XCTAssertEqual(views(wire), [.current])
        }
    }
    func testSuspensionCancelsTransportAndForegroundReloadUsesNewSnapshot() async throws {
        let wire = Wire(try complete())
        let reader = CityPlayerReader(approval: try approval(), transport: wire, isCurrent: { true })
        await reader.load()
        let old = try XCTUnwrap(reader.pointMapContext)
        let selected = try XCTUnwrap(CityPointSelection(pointID: "point-1", rendered: old, current: old))
        let started = expectation(description: "in flight"), cancelled = expectation(description: "transport cancellation")
        wire.replies = try complete(revision: 2); wire.suspendNext = true
        wire.onSuspended = { started.fulfill() }; wire.onCancelled = { cancelled.fulfill() }
        let suspended = Task { await reader.load() }
        await fulfillment(of: [started], timeout: 2)
        reader.cancel()
        XCTAssertEqual(reader.state, .unavailable); XCTAssertNil(selected.point(in: reader.pointMapContext))
        await fulfillment(of: [cancelled], timeout: 2); await suspended.value
        wire.replies = try complete(revision: 2)
        await reader.load()
        XCTAssertEqual(reader.pointMapContext?.snapshot.board.revision, 2)
        XCTAssertNotEqual(reader.pointMapContext?.readID, old.readID)
        XCTAssertNil(selected.point(in: reader.pointMapContext))
    }
    func testSupersedingLoadCancelsOldRequestWithoutClearingNewResult() async throws {
        let wire = Wire([try reply(.current)])
        let started = expectation(description: "old in flight"), cancelled = expectation(description: "old cancelled")
        wire.suspendNext = true; wire.onSuspended = { started.fulfill() }; wire.onCancelled = { cancelled.fulfill() }
        let reader = CityPlayerReader(approval: try approval(), transport: wire, isCurrent: { true })
        let old = Task { await reader.load() }; await fulfillment(of: [started], timeout: 2)
        wire.replies = try complete(revision: 2); await reader.load()
        await fulfillment(of: [cancelled], timeout: 2); await old.value
        XCTAssertEqual(reader.pointMapContext?.snapshot.board.revision, 2)
        XCTAssertEqual(views(wire), [.current, .current, .participation, .points])
    }
    func testCallerCancellationReachesTransportAndDoesNotSignOut() async throws {
        let wire = Wire([try reply(.current)]), started = expectation(description: "in flight")
        let cancelled = expectation(description: "cancelled"); var signOuts = 0
        wire.suspendNext = true; wire.onSuspended = { started.fulfill() }; wire.onCancelled = { cancelled.fulfill() }
        let reader = CityPlayerReader(approval: try approval(), transport: wire, isCurrent: { true }, onUnauthorized: { signOuts += 1 })
        let operation = Task { await reader.load() }; await fulfillment(of: [started], timeout: 2)
        operation.cancel(); await fulfillment(of: [cancelled], timeout: 2); await operation.value
        XCTAssertEqual(reader.state, .unavailable); XCTAssertEqual(signOuts, 0); XCTAssertEqual(wire.requests.count, 1)
    }
    func testRevokedOrChangedOwnerCannotResumeOrRetryOldSnapshot() async throws {
        for transition in ["revoke", "expire", "owner", "cancel"] {
            let wire = Wire([try error(409, "CITY_SNAPSHOT_CHANGED")]), lease = try approval()
            let started = expectation(description: "conflict in flight"); var current = true
            wire.pauseNext = true; wire.onSuspended = { started.fulfill() }
            let reader = CityPlayerReader(approval: lease, transport: wire, isCurrent: { current })
            let operation = Task { await reader.load() }; await fulfillment(of: [started], timeout: 2)
            switch transition {
            case "revoke": lease.revoke()
            case "expire": lease.expireIfNeeded(now: lease.expiresAt)
            case "owner": current = false
            default: reader.cancel()
            }
            wire.finishPause(); await operation.value
            XCTAssertEqual(reader.state, .unavailable); XCTAssertEqual(wire.requests.count, 1)
            if transition != "cancel" { await reader.load(); XCTAssertEqual(wire.requests.count, 1) }
        }
    }
    func testLateUnauthorizedAfterReplacementCannotSignOutOrOverwriteNewRead() async throws {
        let wire = Wire([try error(401, "AUTH_REQUIRED")]), started = expectation(description: "late response")
        var signOuts = 0
        wire.pauseNext = true; wire.onSuspended = { started.fulfill() }
        let reader = CityPlayerReader(approval: try approval(), transport: wire, isCurrent: { true }, onUnauthorized: { signOuts += 1 })
        let old = Task { await reader.load() }; await fulfillment(of: [started], timeout: 2)
        reader.cancel(); wire.replies = try complete(revision: 2); await reader.load()
        wire.finishPause(); await old.value
        XCTAssertEqual(signOuts, 0); XCTAssertEqual(reader.pointMapContext?.snapshot.board.revision, 2)
    }
    func testDefaultOffAndAlreadyCancelledTasksNeverDispatch() async throws {
        let wire = Wire([])
        let disabled = CityPlayerReader(approval: nil, transport: wire, isCurrent: { true })
        await disabled.load(); XCTAssertTrue(wire.requests.isEmpty)
        let reader = CityPlayerReader(approval: try approval(), transport: wire, isCurrent: { true })
        let task = Task { await reader.load() }
        task.cancel(); await task.value
        XCTAssertEqual(reader.state, .unavailable); XCTAssertTrue(wire.requests.isEmpty)
    }
    @MainActor private final class Wire: HTTPTransport {
        var replies: [(Data, Int)]
        var requests: [URLRequest] = []
        var suspendNext = false, pauseNext = false
        var onSuspended: (() -> Void)?, onCancelled: (() -> Void)?
        private var paused: CheckedContinuation<Void, Never>?
        init(_ replies: [(Data, Int)]) { self.replies = replies }
        func finishPause() { let value = paused; paused = nil; value?.resume() }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            guard !replies.isEmpty else { XCTFail("unexpected additional request"); throw APIError.invalidRequest }
            let response = replies.removeFirst()
            if suspendNext {
                suspendNext = false; onSuspended?()
                do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                catch { onCancelled?(); throw error }
            }
            if pauseNext {
                pauseNext = false
                await withCheckedContinuation { paused = $0; onSuspended?() }
            }
            return response
        }
    }
}
