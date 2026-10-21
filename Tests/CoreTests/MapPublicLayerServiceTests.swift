import Foundation
import XCTest
@testable import QuestifyCore

@MainActor
final class MapPublicLayerServiceTests: XCTestCase {
    private final class MockTransport: HTTPTransport {
        var requests: [URLRequest] = []
        var handler: ((URLRequest) async throws -> (Data, Int))?

        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            guard let handler else { throw APIError.notConfigured }
            return try await handler(request)
        }
    }

    private func makeContext(accountID: Int = 7, epoch: UInt64 = 1, token: String = "token-user-7", role: String = "PLAYER") throws -> SearchMapContext {
        try SearchMapContext(accountID: accountID, epoch: epoch, token: token, role: role, viewerRevision: 1)
    }

    private func makeRuntimeContext(accountID: Int = 7, epoch: UInt64 = 1, token: String = "token-user-7", role: String = "PLAYER") throws -> RuntimeDependencyContext {
        let session = try PlayExperienceSession(accountID: accountID, epoch: epoch, namespace: "cn.questify.test", token: token, role: role)
        return RuntimeDependencyContext(
            market: .china,
            baseURL: URL(string: "https://api.example.com")!,
            role: role,
            session: session
        )
    }

    func testApprovalAndRouteDefaultClosedAndValidateExactContract() throws {
        let runtimeContext = try makeRuntimeContext()
        let approval = try MapPublicLayerReadApproval(context: runtimeContext, expiresAt: Date().addingTimeInterval(300))
        XCTAssertTrue(approval.matches(runtimeContext))

        let expired = RuntimeDependencyContext(
            market: .china,
            baseURL: URL(string: "https://api.example.com")!,
            role: "PLAYER",
            session: runtimeContext.session
        )
        XCTAssertThrowsError(try MapPublicLayerReadApproval(context: expired, expiresAt: Date().addingTimeInterval(-1)))

        let baseURL = URL(string: "https://api.example.com")!
        let session = try MapPublicLayerAdapter.open(
            viewerID: 7,
            datum: "GCJ-02",
            minLat: "31.210000",
            maxLat: "31.250000",
            minLng: "121.450000",
            maxLng: "121.490000",
            layers: ["roam_poi", "store", "activity", "theme", "story_node"],
            limit: 20
        )
        let issued = MapPublicLayerAdapter.request(session).request
        var validRequest = URLRequest(url: baseURL.appendingPathComponent("api/map/public-layers"))
        validRequest.httpMethod = "POST"
        validRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        validRequest.httpBody = Data(issued.body.utf8)

        let matched = MapPublicLayerReadRoute(request: validRequest, baseURL: baseURL)
        XCTAssertNotNil(matched)
        XCTAssertEqual(matched?.boundingBox.minLat, "31.21")
        XCTAssertEqual(matched?.boundingBox.maxLat, "31.25")
        XCTAssertEqual(matched?.layers, ["roam_poi", "store", "activity", "theme", "story_node"])
        XCTAssertEqual(matched?.limit, 20)
        XCTAssertNil(matched?.cursor)

        var smuggled = validRequest
        smuggled.httpBody = Data("{\"datum\":\"GCJ-02\",\"minLat\":31.21,\"maxLat\":31.25,\"minLng\":121.45,\"maxLng\":121.49,\"limit\":20,\"layers\":[\"store\"],\"extra\":true}".utf8)
        XCTAssertNil(MapPublicLayerReadRoute(request: smuggled, baseURL: baseURL))

        var wgsRequest = validRequest
        wgsRequest.httpBody = Data("{\"datum\":\"WGS84\",\"minLat\":31.21,\"maxLat\":31.25,\"minLng\":121.45,\"maxLng\":121.49,\"limit\":20,\"layers\":[\"store\"]}".utf8)
        XCTAssertNil(MapPublicLayerReadRoute(request: wgsRequest, baseURL: baseURL))
    }

    func testManualAreaAndConfirmedViewportRespectGCJ02AndNeverRequireDeviceLocation() throws {
        let coord = try XCTUnwrap(RoamCoordinate(latitude: 31.2304, longitude: 121.4737))
        let manualArea = RoamSearchArea(coordinate: coord, label: "人民广场")
        let box = try MapPublicLayerBoundingBox.aroundManualArea(manualArea)
        XCTAssertEqual(box.datum, .gcj02)
        XCTAssertEqual(box.minLat, "31.2104")
        XCTAssertEqual(box.maxLat, "31.2504")
        XCTAssertEqual(box.minLng, "121.4537")
        XCTAssertEqual(box.maxLng, "121.4937")

        let unconfirmedWGS = RuntimeLocationProjection.MapCenter(coordinate: coord, datum: .wgs84)
        XCTAssertThrowsError(try MapPublicLayerBoundingBox.fromConfirmedCenter(unconfirmedWGS))

        let confirmedGCJ = RuntimeLocationProjection.MapCenter(coordinate: coord, datum: .gcj02)
        let confirmedBox = try MapPublicLayerBoundingBox.fromConfirmedCenter(confirmedGCJ, latitudeSpan: 0.04, longitudeSpan: 0.04)
        XCTAssertEqual(confirmedBox.datum, .gcj02)
    }

    func testCoordinatorFullLifecyclePerLayerStatusSameCursorRetryPaginationDetailAndPurge() async throws {
        let transport = MockTransport()
        let config = try APIConfiguration(baseURL: URL(string: "https://api.example.com")!)
        let service = MapPublicLayerService(configuration: config, transport: transport)
        var currentCtx = try makeContext(accountID: 7, epoch: 1, token: "token-user-7")
        var approved = false
        let areaSelection = ManualMapAreaSelection()

        let coordinator = MapPublicLayerCoordinator(
            service: service,
            currentContext: { currentCtx },
            isApproved: { approved },
            manualAreaSelection: areaSelection
        )

        let coord = try XCTUnwrap(RoamCoordinate(latitude: 31.23, longitude: 121.47))
        let area = RoamSearchArea(coordinate: coord, label: "静安寺")

        // 1. Default closed when unapproved: no HTTP request sent.
        coordinator.loadManualArea(area)
        XCTAssertEqual(transport.requests.count, 0)
        XCTAssertEqual(coordinator.errorKey, "mapPublicLayers.notConfigured")
        XCTAssertNil(coordinator.session)

        // 2. Enable approval and return Page 1 where roam_poi FAILS, store succeeds, activity is empty OK,
        //    and theme + story_node are UNAVAILABLE.
        approved = true
        transport.handler = { request in
            let body = try XCTUnwrap(String(data: request.httpBody ?? Data(), encoding: .utf8))
            XCTAssertTrue(body.contains("\"datum\":\"GCJ-02\""))
            XCTAssertFalse(body.contains("\"cursor\""))
            let response: [String: Any] = [
                "code": 200,
                "data": [
                    "datum": "GCJ-02",
                    "aggregatedQueryEnabled": false,
                    "nextCursor": "cursor-page-2",
                    "layers": [
                        [
                            "sourceType": "roam_poi",
                            "status": "FAILED",
                            "reason": "SOURCE_FAILED",
                            "capabilities": ["read": true],
                            "items": []
                        ],
                        [
                            "sourceType": "store",
                            "status": "OK",
                            "capabilities": ["read": true],
                            "items": [
                                [
                                    "sourceType": "store",
                                    "sourceId": 56,
                                    "name": "成音咖啡馆",
                                    "latitude": "31.231",
                                    "longitude": "121.471",
                                    "visibilityVersion": "2026-04-01T10:00:00",
                                    "visualState": "open",
                                    "actions": ["navigate"]
                                ]
                            ]
                        ],
                        [
                            "sourceType": "activity",
                            "status": "OK",
                            "capabilities": ["read": true],
                            "items": []
                        ],
                        [
                            "sourceType": "theme",
                            "status": "UNAVAILABLE",
                            "reason": "THEME_NOT_PROVEN_PUBLIC",
                            "capabilities": ["read": false],
                            "items": []
                        ],
                        [
                            "sourceType": "story_node",
                            "status": "UNAVAILABLE",
                            "reason": "STORY_NODE_NOT_PROVEN_PUBLIC",
                            "capabilities": ["read": false],
                            "items": []
                        ]
                    ]
                ]
            ]
            return (try JSONSerialization.data(withJSONObject: response), 200)
        }

        coordinator.loadManualArea(area)
        while coordinator.isLoading { await Task.yield() }

        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(coordinator.pages.count, 5)
        XCTAssertEqual(coordinator.pages[0].status, .failed)
        XCTAssertEqual(coordinator.pages[1].status, .ok)
        XCTAssertEqual(coordinator.pages[2].status, .ok)
        XCTAssertTrue(coordinator.pages[2].isEmptySuccess)
        XCTAssertEqual(coordinator.pages[3].status, .unavailable)
        XCTAssertEqual(coordinator.pages[4].status, .unavailable)
        // Failed page retains initial nil cursor while keeping store's successful item.
        XCTAssertNil(coordinator.session?.cursor)
        XCTAssertTrue(coordinator.canRetry)
        XCTAssertFalse(coordinator.canLoadNextPage)
        XCTAssertEqual(coordinator.visibleReadyItems.map { "\($0.key.type.rawValue):\($0.key.id)" }, ["store:56"])
        XCTAssertEqual(coordinator.visibleReadyItems.first?.capabilities, [.navigate])

        // 3. Same-cursor retry succeeds for all readable layers and advances cursor to "cursor-page-2".
        transport.handler = { request in
            let body = try XCTUnwrap(String(data: request.httpBody ?? Data(), encoding: .utf8))
            XCTAssertFalse(body.contains("\"cursor\""))
            let response: [String: Any] = [
                "code": 200,
                "data": [
                    "datum": "GCJ-02",
                    "nextCursor": "cursor-page-2",
                    "layers": [
                        [
                            "sourceType": "roam_poi",
                            "status": "OK",
                            "capabilities": ["read": true],
                            "items": [
                                [
                                    "sourceType": "roam_poi",
                                    "sourceId": 7,
                                    "name": "静安古井",
                                    "latitude": "31.232",
                                    "longitude": "121.472",
                                    "visibilityVersion": "4100000007",
                                    "visualState": "found",
                                    "actions": []
                                ]
                            ]
                        ],
                        [
                            "sourceType": "store",
                            "status": "OK",
                            "capabilities": ["read": true],
                            "items": [
                                [
                                    "sourceType": "store",
                                    "sourceId": 56,
                                    "name": "成音咖啡馆",
                                    "latitude": "31.231",
                                    "longitude": "121.471",
                                    "visibilityVersion": "2026-04-01T10:00:00",
                                    "visualState": "open",
                                    "actions": ["navigate"]
                                ]
                            ]
                        ],
                        [
                            "sourceType": "activity",
                            "status": "OK",
                            "capabilities": ["read": true],
                            "items": [
                                [
                                    "sourceType": "activity",
                                    "sourceId": 16,
                                    "name": "周末城市漫游",
                                    "latitude": "31.233",
                                    "longitude": "121.473",
                                    "visibilityVersion": "2026-04-02T11:00:00",
                                    "visualState": "running",
                                    "actions": ["navigate"]
                                ]
                            ]
                        ],
                        [
                            "sourceType": "theme",
                            "status": "UNAVAILABLE",
                            "reason": "THEME_NOT_PROVEN_PUBLIC",
                            "capabilities": ["read": false],
                            "items": []
                        ],
                        [
                            "sourceType": "story_node",
                            "status": "UNAVAILABLE",
                            "reason": "STORY_NODE_NOT_PROVEN_PUBLIC",
                            "capabilities": ["read": false],
                            "items": []
                        ]
                    ]
                ]
            ]
            return (try JSONSerialization.data(withJSONObject: response), 200)
        }

        coordinator.retryFailedPage()
        while coordinator.isLoading { await Task.yield() }

        XCTAssertEqual(coordinator.session?.cursor, "cursor-page-2")
        XCTAssertFalse(coordinator.canRetry)
        XCTAssertTrue(coordinator.canLoadNextPage)
        XCTAssertEqual(
            coordinator.visibleReadyItems.map { "\($0.key.type.rawValue):\($0.key.id)" },
            ["roamPOI:7", "store:56", "registrableActivity:16"]
        )
        // Layer read or activity navigate never grants navigate/register on non-store items.
        let activityItem = try XCTUnwrap(coordinator.visibleReadyItems.first(where: { $0.key.type == .registrableActivity }))
        XCTAssertTrue(activityItem.capabilities.isEmpty)

        // 4. Open real detail for store, activity, and roamPOI and verify return preserves query, viewport, and selection.
        let storeKey = try MapSourceKey(type: .store, id: "56")
        let storeRoute = try XCTUnwrap(coordinator.openDetail(for: storeKey))
        XCTAssertEqual(storeRoute.target, .store(sourceID: 56, title: "成音咖啡馆", coordinate: RoamCoordinate(latitude: 31.231, longitude: 121.471), canNavigate: true))
        XCTAssertTrue(coordinator.acceptsDetailRoute(storeRoute))
        XCTAssertEqual(coordinator.selectedItemKey, storeKey)

        coordinator.returnFromDetail()
        XCTAssertNil(coordinator.activeDetailRoute)
        XCTAssertEqual(coordinator.selectedItemKey, storeKey)
        XCTAssertEqual(coordinator.session?.cursor, "cursor-page-2")
        XCTAssertEqual(coordinator.viewportSource?.manualArea, area)

        let activityKey = try MapSourceKey(type: .registrableActivity, id: "16")
        let activityRoute = try XCTUnwrap(coordinator.openDetail(for: activityKey))
        XCTAssertEqual(activityRoute.target, .activity(sourceID: 16, title: "周末城市漫游"))
        coordinator.returnFromDetail()

        let poiKey = try MapSourceKey(type: .roamPOI, id: "7")
        let poiRoute = try XCTUnwrap(coordinator.openDetail(for: poiKey))
        XCTAssertEqual(poiRoute.target, .roamPOI(sourceID: 7, title: "静安古井", origin: coord))
        coordinator.returnFromDetail()

        // 5. Load next page with "cursor-page-2" -> terminal page (nextCursor: null) and older visibilityVersion ignored.
        transport.handler = { request in
            let body = try XCTUnwrap(String(data: request.httpBody ?? Data(), encoding: .utf8))
            XCTAssertTrue(body.contains("\"cursor\":\"cursor-page-2\""))
            let response: [String: Any] = [
                "code": 200,
                "data": [
                    "datum": "GCJ-02",
                    "layers": [
                        ["sourceType": "roam_poi", "status": "OK", "items": []],
                        [
                            "sourceType": "store",
                            "status": "OK",
                            "items": [
                                [
                                    "sourceType": "store",
                                    "sourceId": 56,
                                    "name": "旧名字不应覆盖",
                                    "latitude": "31.231",
                                    "longitude": "121.471",
                                    "visibilityVersion": "2026-03-01T08:00:00",
                                    "visualState": "closed",
                                    "actions": []
                                ],
                                [
                                    "sourceType": "store",
                                    "sourceId": 88,
                                    "name": "新分页书店",
                                    "latitude": "31.234",
                                    "longitude": "121.474",
                                    "visibilityVersion": "2026-04-03T12:00:00",
                                    "visualState": "open",
                                    "actions": []
                                ]
                            ]
                        ],
                        ["sourceType": "activity", "status": "OK", "items": []],
                        ["sourceType": "theme", "status": "UNAVAILABLE", "reason": "THEME_NOT_PROVEN_PUBLIC", "items": []],
                        ["sourceType": "story_node", "status": "UNAVAILABLE", "reason": "STORY_NODE_NOT_PROVEN_PUBLIC", "items": []]
                    ]
                ]
            ]
            return (try JSONSerialization.data(withJSONObject: response), 200)
        }

        coordinator.loadNextPage()
        while coordinator.isLoading { await Task.yield() }

        XCTAssertTrue(coordinator.isComplete)
        XCTAssertFalse(coordinator.canLoadNextPage)
        let keptStore56 = try XCTUnwrap(coordinator.visibleReadyItems.first(where: { $0.key == storeKey }))
        XCTAssertEqual(keptStore56.title, "成音咖啡馆")
        XCTAssertEqual(keptStore56.capabilities, [.navigate])
        XCTAssertEqual(
            coordinator.visibleReadyItems.map { "\($0.key.type.rawValue):\($0.key.id)" },
            ["roamPOI:7", "store:56", "store:88", "registrableActivity:16"]
        )

        // 6. Account change immediately purges all state and invalidates detail routes.
        currentCtx = try makeContext(accountID: 99, epoch: 2, token: "token-user-99")
        XCTAssertFalse(coordinator.acceptsDetailRoute(poiRoute))
        XCTAssertNil(coordinator.session)
        XCTAssertTrue(coordinator.visibleReadyItems.isEmpty)
        XCTAssertNil(coordinator.selectedItemKey)
    }

    func testThemeAndStoryNodeDomainSeparationParentGateAndReturnToMap() async throws {
        let transport = MockTransport()
        let config = try APIConfiguration(baseURL: URL(string: "https://api.example.com")!)
        let service = MapPublicLayerService(configuration: config, transport: transport)
        let currentCtx = try makeContext(accountID: 7, epoch: 1, token: "token-user-7")
        let coordinator = MapPublicLayerCoordinator(
            service: service,
            currentContext: { currentCtx },
            isApproved: { true }
        )

        let coord = try XCTUnwrap(RoamCoordinate(latitude: 31.23, longitude: 121.47))
        let area = RoamSearchArea(coordinate: coord, label: "外滩")

        // 1. Both theme and story_node succeed with identical numeric sourceId=42 in distinct domains.
        transport.handler = { _ in
            let response: [String: Any] = [
                "code": 200,
                "data": [
                    "datum": "GCJ-02",
                    "nextCursor": "cursor-theme-story-2",
                    "layers": [
                        ["sourceType": "roam_poi", "status": "OK", "items": []],
                        ["sourceType": "store", "status": "OK", "items": []],
                        ["sourceType": "activity", "status": "OK", "items": []],
                        [
                            "sourceType": "theme",
                            "status": "OK",
                            "capabilities": ["read": true],
                            "items": [
                                [
                                    "sourceType": "theme",
                                    "sourceId": 42,
                                    "topicId": 42,
                                    "chapterId": 300,
                                    "nodeId": 9001,
                                    "name": "外滩暗影追踪",
                                    "topicName": "外滩暗影追踪",
                                    "chapterTitle": "第一章：序幕",
                                    "address": "中山东一路 18 号",
                                    "summary": "在百年钟楼下寻找失落的密电码",
                                    "latitude": "31.238",
                                    "longitude": "121.490",
                                    "visibilityVersion": "2026-04-05T10:05:00",
                                    "visualState": "selfPlay",
                                    "actions": []
                                ]
                            ]
                        ],
                        [
                            "sourceType": "story_node",
                            "status": "OK",
                            "capabilities": ["read": true],
                            "items": [
                                [
                                    "sourceType": "story_node",
                                    "sourceId": 42,
                                    "topicId": 42,
                                    "chapterId": 300,
                                    "nodeId": 42,
                                    "name": "钟楼暗格",
                                    "topicName": "外滩暗影追踪",
                                    "chapterTitle": "第一章：序幕",
                                    "address": "中山东一路 18 号二楼",
                                    "summary": "调查旧式铜钟背后的铭文",
                                    "latitude": "31.2385",
                                    "longitude": "121.4905",
                                    "visibilityVersion": "2026-04-05T10:05:00",
                                    "visualState": "unlocked",
                                    "actions": []
                                ]
                            ]
                        ]
                    ]
                ]
            ]
            return (try JSONSerialization.data(withJSONObject: response), 200)
        }

        coordinator.loadManualArea(area)
        while coordinator.isLoading { await Task.yield() }

        XCTAssertEqual(
            coordinator.visibleReadyItems.map { "\($0.key.type.rawValue):\($0.key.id)" },
            ["themeNode:42", "storyNode:42"]
        )

        let themeKey = try MapSourceKey(type: .themeNode, id: "42")
        let storyKey = try MapSourceKey(type: .storyNode, id: "42")
        XCTAssertNotEqual(themeKey, storyKey)

        let themeRoute = try XCTUnwrap(coordinator.openDetail(for: themeKey))
        let expectedThemeDest = try XCTUnwrap(
            MapPublicThemeDestination(
                topicID: 42,
                anchorNodeID: 9001,
                themeName: "外滩暗影追踪",
                address: "中山东一路 18 号",
                summary: "在百年钟楼下寻找失落的密电码"
            )
        )
        XCTAssertEqual(themeRoute.target, .theme(expectedThemeDest))
        coordinator.returnFromDetail()
        XCTAssertEqual(coordinator.selectedItemKey, themeKey)
        XCTAssertEqual(coordinator.session?.cursor, "cursor-theme-story-2")

        let storyRoute = try XCTUnwrap(coordinator.openDetail(for: storyKey))
        let expectedStoryDest = try XCTUnwrap(
            MapPublicStoryNodeDestination(
                nodeID: 42,
                topicID: 42,
                chapterID: 300,
                nodeName: "钟楼暗格",
                topicName: "外滩暗影追踪",
                chapterTitle: "第一章：序幕",
                address: "中山东一路 18 号二楼",
                summary: "调查旧式铜钟背后的铭文",
                coordinate: RoamCoordinate(latitude: 31.2385, longitude: 121.4905)
            )
        )
        XCTAssertEqual(storyRoute.target, .storyNode(expectedStoryDest))
        coordinator.returnFromDetail()
        XCTAssertEqual(coordinator.selectedItemKey, storyKey)
        XCTAssertEqual(coordinator.session?.cursor, "cursor-theme-story-2")

        // 2. If next page returns a story_node missing parent topicId/chapterId, the layer fails closed with STORY_NODE_PARENT_ABSENT
        //    and retains "cursor-theme-story-2" for same-cursor retry while keeping already-loaded items.
        transport.handler = { _ in
            let response: [String: Any] = [
                "code": 200,
                "data": [
                    "datum": "GCJ-02",
                    "nextCursor": "cursor-should-not-advance",
                    "layers": [
                        ["sourceType": "roam_poi", "status": "OK", "items": []],
                        ["sourceType": "store", "status": "OK", "items": []],
                        ["sourceType": "activity", "status": "OK", "items": []],
                        ["sourceType": "theme", "status": "OK", "items": []],
                        [
                            "sourceType": "story_node",
                            "status": "OK",
                            "capabilities": ["read": true],
                            "items": [
                                [
                                    "sourceType": "story_node",
                                    "sourceId": 99,
                                    "name": "缺失父主题节点",
                                    "latitude": "31.239",
                                    "longitude": "121.491",
                                    "visibilityVersion": "2026-04-05T10:10:00",
                                    "visualState": "unlocked",
                                    "actions": []
                                ]
                            ]
                        ]
                    ]
                ]
            ]
            return (try JSONSerialization.data(withJSONObject: response), 200)
        }

        coordinator.loadNextPage()
        while coordinator.isLoading { await Task.yield() }

        XCTAssertEqual(coordinator.pages.first(where: { $0.source == "story_node" })?.status, .failed)
        XCTAssertEqual(coordinator.pages.first(where: { $0.source == "story_node" })?.reason, "STORY_NODE_PARENT_ABSENT")
        XCTAssertEqual(coordinator.session?.cursor, "cursor-theme-story-2")
        XCTAssertTrue(coordinator.canRetry)
        XCTAssertTrue(coordinator.withheldItems.isEmpty)
        let missingParentItem = MapPublicWireItem(
            source: "story_node",
            sourceID: 99,
            name: "缺失父主题节点",
            latitude: "31.239",
            longitude: "121.491",
            visibilityVersion: "2026-04-05T10:10:00",
            visualState: "unlocked",
            actions: [],
            found: nil,
            pendingRedeem: nil,
            businessStatus: nil
        )
        var probeSession = try XCTUnwrap(coordinator.session)
        probeSession.pages = [MapPublicLayerPage(source: "story_node", status: .ok, reason: nil, read: true, items: [missingParentItem])]
        XCTAssertEqual(
            MapPublicLayerAdapter.withheld(in: probeSession),
            [MapPublicWithheldItem(source: "story_node", sourceID: 99, missing: [.parentTopic])]
        )
        XCTAssertEqual(
            coordinator.visibleReadyItems.map { "\($0.key.type.rawValue):\($0.key.id)" },
            ["themeNode:42", "storyNode:42"]
        )
    }
}
