import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import QuestifyCore

/// Client recovery tests. The wire below is the candidate W13 contract at
/// 02870381b988ada5fb5d6e54bd23f72dafeae50f; the frozen backend
/// 58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4 does not contain this route.
/// These tests do not establish deployment or real-backend readiness.
@MainActor
final class MapPublicLayerLaunchTests: XCTestCase {
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var pending: [CheckedContinuation<(Data, Int), Error>] = []

        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            return try await withCheckedThrowingContinuation { pending.append($0) }
        }

        func reply(_ index: Int, _ data: Data, status: Int = 200) {
            pending[index].resume(returning: (data, status))
        }

        func fail(_ index: Int, _ error: Error = APIError.httpStatus(503)) {
            pending[index].resume(throwing: error)
        }
    }

    private let baseURL = URL(string: "https://example.test/native")!

    private func context(account: Int = 7, epoch: UInt64 = 1) throws -> SearchMapContext {
        try SearchMapContext(accountID: account, epoch: epoch, token: "test-session", role: "PLAYER",
                             viewerRevision: epoch, manualMapApprovalRevision: UUID())
    }

    private func opened(layers: [String] = ["store"], limit: Int = 20) throws -> MapPublicLayerSession {
        try MapPublicLayerAdapter.open(viewerID: 7, datum: "GCJ-02", minLat: "31.2000", maxLat: "31.25",
                                       minLng: "121.40", maxLng: "121.50", layers: layers, limit: limit)
    }

    private func store(_ id: Int) -> [String: Any] {
        ["sourceType": "store", "sourceId": id, "name": "Store \(id)",
         "latitude": "31.23", "longitude": "121.47", "visibilityVersion": "2026-11-04T10:00:00",
         "visualState": "open", "actions": ["navigate"]]
    }

    private func layer(_ source: String = "store", status: String = "OK", read: Bool = true,
                       items: [[String: Any]] = []) -> [String: Any] {
        ["sourceType": source, "status": status, "capabilities": ["read": read], "items": items]
    }

    private func page(_ layers: [[String: Any]], cursor: String? = nil, envelope: Bool = false) throws -> Data {
        let payload: [String: Any] = ["datum": "GCJ-02", "aggregatedQueryEnabled": false,
                                     "layers": layers, "nextCursor": cursor.map { $0 as Any } ?? NSNull()]
        return try JSONSerialization.data(withJSONObject: envelope ? ["code": 200, "data": payload] : payload)
    }

    private func accept(_ session: MapPublicLayerSession, _ data: Data) throws -> MapPublicLayerSession {
        let issued = MapPublicLayerAdapter.request(session)
        guard case .applied(let updated) = MapPublicLayerAdapter.accept(issued.session, request: issued.request, json: data) else {
            throw APIError.malformedResponse
        }
        return updated
    }

    private func settle(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<1000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Request did not reach the expected state", file: file, line: line)
    }

    private func makeService(_ wire: Wire) throws -> MapPublicLayerService {
        MapPublicLayerService(configuration: try APIConfiguration(baseURL: baseURL), transport: wire)
    }

    func testBBoxLimitsLayerOrderAndRequestCanonicalization() async throws {
        let session = try opened(layers: ["store", "roam_poi", "theme", "story_node"])
        let request = MapPublicLayerAdapter.request(session).request
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(request.body.utf8)) as? [String: Any])
        XCTAssertEqual(body["layers"] as? [String], session.layers)
        XCTAssertEqual(body["minLat"] as? Double, 31.2)
        XCTAssertEqual(session.minLng, "121.4")
        XCTAssertNil(body["viewerID"])
        XCTAssertNil(body["aggregatedQueryEnabled"])
        XCTAssertThrowsError(try opened(layers: ["store", "store"]))
        XCTAssertThrowsError(try opened(layers: ["sideQuest"]))
        XCTAssertThrowsError(try opened(limit: 51))
        XCTAssertThrowsError(try MapPublicLayerBoundingBox(minLat: "32", maxLat: "31", minLng: "121", maxLng: "122"))
        XCTAssertThrowsError(try MapPublicLayerBoundingBox(minLat: "31", maxLat: "33", minLng: "121", maxLng: "122"))
        XCTAssertThrowsError(try MapPublicLayerBoundingBox(minLat: "31", maxLat: "32", minLng: "179", maxLng: "-179"))
        XCTAssertThrowsError(try MapPublicLayerBoundingBox(minLat: "31", maxLat: "32", minLng: "121", maxLng: "122", datum: .wgs84))
    }

    func testFailedPageRetriesSameCursorWithoutDiscardingOtherLayers() async throws {
        var session = try accept(opened(layers: ["store", "activity"]), page([
            layer(items: [store(7)]), layer("activity")
        ], cursor: "page-2"))
        session = try accept(session, page([
            layer(status: "FAILED"), layer("activity")
        ]))
        XCTAssertEqual(session.cursor, "page-2")
        XCTAssertFalse(session.complete)
        XCTAssertEqual(MapPublicLayerAdapter.readyItems(in: session).map(\.key.id), ["7"])
        let retry = MapPublicLayerAdapter.request(session)
        XCTAssertEqual(retry.request.cursor, "page-2")
        XCTAssertTrue(retry.request.body.contains("\"cursor\":\"page-2\""))
        session = try accept(session, page([
            layer(items: [store(7), store(8)]), layer("activity")
        ]))
        XCTAssertTrue(session.complete)
        XCTAssertEqual(MapPublicLayerAdapter.readyItems(in: session).map(\.key.id), ["7", "8"])
    }

    func testUnavailableAndExplicitReadRevocationCannotResurrectCachedItems() async throws {
        for status in ["UNAVAILABLE", "FAILED", "OK"] {
            var session = try accept(opened(), page([layer(items: [store(7)])], cursor: "page-2"))
            session = try accept(session, page([layer(status: status, read: false)]))
            XCTAssertTrue(session.pages[0].items.isEmpty, status)
            XCTAssertTrue(MapPublicLayerAdapter.readyItems(in: session).isEmpty, status)
            session = try accept(session, page([layer(items: [store(8)])]))
            XCTAssertEqual(MapPublicLayerAdapter.readyItems(in: session).map(\.key.id), ["8"], status)
        }
        var session = try accept(opened(), page([layer(items: [store(7)])], cursor: "page-2"))
        // UNAVAILABLE retires cached rows even when a legacy payload omits capabilities.
        session = try accept(session, page([["sourceType": "store", "status": "UNAVAILABLE", "items": []]]))
        XCTAssertTrue(session.pages[0].items.isEmpty)
    }

    func testCursorStallOversizedPageAndReorderedLayersDoNotAdvanceSession() async throws {
        let session = try accept(opened(layers: ["store", "activity"], limit: 1), page([
            layer(items: [store(7)]), layer("activity")
        ], cursor: "page-2"))
        let issued = MapPublicLayerAdapter.request(session)
        for data in [
            try page([layer(), layer("activity")], cursor: "page-2"),
            try page([layer(items: [store(8), store(9)]), layer("activity")]),
            try page([layer("activity"), layer()])
        ] {
            XCTAssertEqual(MapPublicLayerAdapter.accept(issued.session, request: issued.request, json: data), .rejected(.payloadRejected))
        }
        let replacement = try MapPublicLayerAdapter.replace(issued.session, viewerID: 8, datum: "GCJ-02",
            minLat: "31.2", maxLat: "31.25", minLng: "121.4", maxLng: "121.5", layers: ["store", "activity"], limit: 1)
        XCTAssertEqual(MapPublicLayerAdapter.accept(replacement, request: issued.request, json: try page([layer(), layer("activity")])), .stale)
        XCTAssertEqual(session.cursor, "page-2")
    }

    func testFormalServiceValidatesBodyAndDoesNotTreatMalformedEnvelopeAsBareSuccess() async throws {
        let wire = Wire()
        let service = try makeService(wire)
        let valid = MapPublicLayerAdapter.request(try opened()).request
        let forged = MapPublicLayerRequest(attempt: valid.attempt, viewerID: valid.viewerID,
            fingerprint: valid.fingerprint, cursor: nil, body: "{\"datum\":\"WGS84\"}")
        do {
            _ = try await service.fetchPublicLayers(forged, token: "test-session")
            XCTFail("Invalid wire body was sent")
        } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(wire.requests.isEmpty)

        let task = Task { try await service.fetchPublicLayers(valid, token: "test-session") }
        await settle { wire.pending.count == 1 }
        XCTAssertEqual(wire.requests[0].url?.path, "/native/api/map/public-layers")
        XCTAssertEqual(wire.requests[0].httpMethod, "POST")
        XCTAssertEqual(wire.requests[0].value(forHTTPHeaderField: "Authorization"), "test-session")
        wire.reply(0, Data("{\"code\":\"401\",\"datum\":\"GCJ-02\",\"layers\":[]}".utf8))
        do { _ = try await task.value; XCTFail("Malformed envelope accepted") }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }

    func testCoordinatorPurgesOnObservedAccountChangeAndApprovalLoss() async throws {
        let wire = Wire()
        var current = try context()
        var approved = true
        let coordinator = MapPublicLayerCoordinator(service: try makeService(wire), currentContext: { current }, isApproved: { approved })
        let box = try MapPublicLayerBoundingBox(minLat: "31.2", maxLat: "31.25", minLng: "121.4", maxLng: "121.5")
        coordinator.loadAuthorizedViewport(box, layers: ["store"])
        await settle { wire.pending.count == 1 }
        wire.reply(0, try page([layer(items: [store(7)])], envelope: true))
        await settle { !coordinator.isLoading }
        let key = try MapSourceKey(type: .store, id: "7")
        let oldRoute = try XCTUnwrap(coordinator.openDetail(for: key))
        approved = false
        XCTAssertTrue(coordinator.visibleReadyItems.isEmpty)
        XCTAssertNil(coordinator.session)
        XCTAssertNil(coordinator.activeDetailRoute)
        approved = true
        coordinator.loadAuthorizedViewport(box, layers: ["store"])
        await settle { wire.pending.count == 2 }
        wire.reply(1, try page([layer(items: [store(7)])], envelope: true))
        await settle { !coordinator.isLoading }
        XCTAssertFalse(coordinator.acceptsDetailRoute(oldRoute))
        current = try context(account: 8, epoch: 2)
        XCTAssertTrue(coordinator.visibleReadyItems.isEmpty)
        XCTAssertNil(coordinator.session)
        XCTAssertFalse(coordinator.canLoadNextPage)
    }

    func testApprovalRevokedDuringTransportFailurePurgesInsteadOfOfferingRetry() async throws {
        let wire = Wire()
        let current = try context()
        var approved = true
        let coordinator = MapPublicLayerCoordinator(service: try makeService(wire), currentContext: { current }, isApproved: { approved })
        let box = try MapPublicLayerBoundingBox(minLat: "31.2", maxLat: "31.25", minLng: "121.4", maxLng: "121.5")
        coordinator.loadAuthorizedViewport(box, layers: ["store"])
        await settle { wire.pending.count == 1 }
        approved = false
        wire.fail(0)
        await settle { !coordinator.isLoading }
        // Inspect stored state before any derived getter can perform the purge for us.
        XCTAssertNil(coordinator.session)
        XCTAssertFalse(coordinator.transportFailed)
        XCTAssertFalse(coordinator.canRetry)
    }

    func testManualAreaChangeRetiresPendingSuccessAndFailure() async throws {
        for fail in [false, true] {
            let wire = Wire()
            let current = try context()
            let selection = ManualMapAreaSelection()
            let coordinator = MapPublicLayerCoordinator(service: try makeService(wire), currentContext: { current },
                isApproved: { true }, manualAreaSelection: selection)
            let area = RoamSearchArea(coordinate: try XCTUnwrap(RoamCoordinate(latitude: 31.23, longitude: 121.47)), label: "Manual")
            coordinator.loadManualArea(area, layers: ["store"])
            await settle { wire.pending.count == 1 }
            selection.select(nil)
            if fail { wire.fail(0) }
            else { wire.reply(0, try page([layer(items: [store(7)])], envelope: true)) }
            await settle { !coordinator.isLoading }
            XCTAssertNil(coordinator.session)
            XCTAssertTrue(coordinator.visibleReadyItems.isEmpty)
        }
    }

    func testTransportCancellationSettlesAndAllowsSamePageRetry() async throws {
        let wire = Wire()
        let current = try context()
        let coordinator = MapPublicLayerCoordinator(service: try makeService(wire), currentContext: { current }, isApproved: { true })
        let box = try MapPublicLayerBoundingBox(minLat: "31.2", maxLat: "31.25", minLng: "121.4", maxLng: "121.5")
        coordinator.loadAuthorizedViewport(box, layers: ["store"])
        await settle { wire.pending.count == 1 }
        wire.reply(0, try page([layer(items: [store(7)])], cursor: "page-2", envelope: true))
        await settle { !coordinator.isLoading }
        coordinator.loadNextPage()
        await settle { wire.pending.count == 2 }
        wire.fail(1, CancellationError())
        await settle { !coordinator.isLoading }
        XCTAssertTrue(coordinator.canRetry)
        XCTAssertEqual(coordinator.visibleReadyItems.map(\.key.id), ["7"])
        coordinator.retryFailedPage()
        await settle { wire.pending.count == 3 }
        XCTAssertEqual(wire.requests[1].httpBody, wire.requests[2].httpBody)
        wire.reply(2, try page([layer(items: [store(8)])], envelope: true))
        await settle { !coordinator.isLoading }
        XCTAssertTrue(coordinator.isComplete)
        XCTAssertEqual(coordinator.visibleReadyItems.map(\.key.id), ["7", "8"])
    }

    func testCoordinatorTreatsHTTPAndBusinessDenialAsRevocation() async throws {
        for (status, code) in [(401, 200), (200, 401), (403, 200), (200, 403)] {
            let wire = Wire()
            let current = try context()
            let coordinator = MapPublicLayerCoordinator(service: try makeService(wire), currentContext: { current }, isApproved: { true })
            let box = try MapPublicLayerBoundingBox(minLat: "31.2", maxLat: "31.25", minLng: "121.4", maxLng: "121.5")
            coordinator.loadAuthorizedViewport(box, layers: ["store"])
            await settle { wire.pending.count == 1 }
            wire.reply(0, try page([layer(items: [store(7)])], cursor: "page-2", envelope: true))
            await settle { !coordinator.isLoading }
            XCTAssertEqual(coordinator.visibleReadyItems.count, 1)
            coordinator.loadNextPage()
            await settle { wire.pending.count == 2 }
            wire.reply(1, try JSONSerialization.data(withJSONObject: ["code": code]), status: status)
            await settle { !coordinator.isLoading }
            XCTAssertNil(coordinator.session)
            XCTAssertTrue(coordinator.visibleReadyItems.isEmpty)
            XCTAssertFalse(coordinator.canRetry)
        }
    }

    func testCallerLateRequestCannotFinishNewRequestAndDenialClearsCachedPins() async throws {
        let wire = Wire()
        var current = try context()
        let reader = SearchMapSessionReader(service: SearchMapService(configuration: try APIConfiguration(baseURL: baseURL), transport: wire), currentContext: { current })
        let caller = MapPublicLayerCaller(reader: reader, activity: { _ in "" })
        caller.noteAccount(7)
        let first = MapPublicLayerCaller.Query(viewerID: 7, minLat: "31.2", maxLat: "31.25", minLng: "121.4", maxLng: "121.5", layers: ["store"], limit: 20)
        var second = first
        second.minLat = "31.21"
        let oldTask = Task { await caller.submit(first) }
        await settle { wire.pending.count == 1 }
        let newTask = Task { await caller.submit(second) }
        await settle { wire.pending.count == 2 }
        wire.reply(0, try page([layer(items: [store(7)])], envelope: true))
        await oldTask.value
        XCTAssertTrue(caller.loading)
        XCTAssertTrue(caller.ready.isEmpty)
        wire.reply(1, try page([layer(items: [store(8)])], cursor: "page-2", envelope: true))
        await newTask.value
        XCTAssertEqual(caller.ready.map(\.key.id), ["8"])
        let next = Task { await caller.nextPage() }
        await settle { wire.pending.count == 3 }
        wire.reply(2, Data("{\"code\":401}".utf8))
        await next.value
        XCTAssertNil(caller.session)
        XCTAssertTrue(caller.ready.isEmpty)
        XCTAssertEqual(caller.failure, .unauthorized)

        let reload = Task { await caller.submit(first) }
        await settle { wire.pending.count == 4 }
        wire.reply(3, try page([layer(items: [store(7)])], envelope: true))
        await reload.value
        var invalid = first
        invalid.minLat = "invalid"
        await caller.submit(invalid)
        XCTAssertTrue(caller.ready.isEmpty)
        XCTAssertNil(caller.session)
        XCTAssertEqual(wire.requests.count, 4)

        let finalReload = Task { await caller.submit(first) }
        await settle { wire.pending.count == 5 }
        wire.reply(4, try page([layer(items: [store(7)])], envelope: true))
        await finalReload.value
        current = try context(account: 7, epoch: 2)
        XCTAssertTrue(caller.ready.isEmpty)
        XCTAssertNil(caller.session)
    }
}
