import XCTest
@testable import Questify

@MainActor
final class MapPublicLayerAppIntegrationTests: XCTestCase {
    private static let base = "https://example.test/native"
    private let areaA = RoamSearchArea(coordinate: RoamCoordinate(latitude: 31.23, longitude: 121.47)!, label: "人民广场")
    private let areaB = RoamSearchArea(coordinate: RoamCoordinate(latitude: 31.30, longitude: 121.50)!, label: "五角场")

    private func deployment(_ grants: Set<ReviewedAppDeployment.ReadGrant> = [.manualMap, .publicMapLayers]) throws -> ReviewedAppDeployment {
        try .init(
            market: .china,
            baseURL: Self.base,
            approvedBaseURLs: [.china: [Self.base]],
            verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.map-public-layers",
            realm: "fixture",
            reads: grants
        )
    }

    private func makeSession(
        _ wire: PublicLayerWire,
        approvals: PublicLayerApprovals,
        grants: Set<ReviewedAppDeployment.ReadGrant> = [.manualMap, .publicMapLayers]
    ) throws -> AppSession {
        let suite = "map-public-layers-" + UUID().uuidString
        let vault = Vault()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

        let root = AppCompositionRoot(
            deployment: .reviewed(try deployment(grants)),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire },
            manualMapReadApproval: { approvals.manualApproval($0) },
            mapPublicLayerReadApproval: { approvals.publicLayerApproval($0) }
        )
        let device = DeviceSpy(onCall: { wire.deviceLocationCalls += 1 })
        return AppSession(
            composition: root,
            runtimeDependencies: .init(location: device),
            roamLiveDependencies: .init(makeLocation: { wire.deviceLocationCalls += 1; return device })
        )
    }

    private func signIn(_ session: AppSession, phone: String = "10000000000") async {
        if session.account != nil { await session.logout() }
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: phone, code: "123456")
        XCTAssertNotNil(session.account)
    }

    func testDefaultClosedWithoutPublicLayerApprovalOrSignedInSession() async throws {
        let wire = PublicLayerWire()
        let approvals = PublicLayerApprovals()
        approvals.publicLayerEnabled = false
        let session = try makeSession(wire, approvals: approvals)

        let coordinator = try XCTUnwrap(session.searchMapReader.publicLayerCoordinator)
        XCTAssertFalse(coordinator.isConfigured)
        coordinator.loadManualArea(areaA)
        XCTAssertTrue(wire.requests.isEmpty)
        XCTAssertEqual(coordinator.errorKey, "mapPublicLayers.signInRequired")

        await signIn(session)
        wire.requests = []
        XCTAssertFalse(coordinator.isConfigured)
        coordinator.loadManualArea(areaA)
        XCTAssertTrue(wire.requests.isEmpty)
        XCTAssertEqual(coordinator.errorKey, "mapPublicLayers.notConfigured")
        XCTAssertEqual(wire.deviceLocationCalls, 0)
    }

    func testEndToEndCompositionFlowAndInFlightRetirementAndAccountPurge() async throws {
        let wire = PublicLayerWire()
        let approvals = PublicLayerApprovals()
        let session = try makeSession(wire, approvals: approvals)
        await signIn(session)
        wire.requests = []

        let coordinator = try XCTUnwrap(session.searchMapReader.publicLayerCoordinator)
        XCTAssertTrue(coordinator.isConfigured)
        XCTAssertTrue(coordinator.isAuthenticated)

        // 1. Load manual area -> Page 1 with FAILED roam_poi, OK store, UNAVAILABLE theme & story_node.
        wire.publicLayerResponse = [
            "code": 200,
            "data": [
                "datum": "GCJ-02",
                "aggregatedQueryEnabled": false,
                "nextCursor": "cursor-2",
                "layers": [
                    ["sourceType": "roam_poi", "status": "FAILED", "reason": "SOURCE_FAILED", "capabilities": ["read": true], "items": []],
                    [
                        "sourceType": "store",
                        "status": "OK",
                        "capabilities": ["read": true],
                        "items": [
                            [
                                "sourceType": "store",
                                "sourceId": 56,
                                "name": "成音桌游馆",
                                "latitude": "31.2305",
                                "longitude": "121.4705",
                                "visibilityVersion": "2026-04-01T10:00:00",
                                "visualState": "open",
                                "actions": ["navigate"]
                            ]
                        ]
                    ],
                    ["sourceType": "activity", "status": "OK", "capabilities": ["read": true], "items": []],
                    ["sourceType": "theme", "status": "UNAVAILABLE", "reason": "THEME_NOT_PROVEN_PUBLIC", "capabilities": ["read": false], "items": []],
                    ["sourceType": "story_node", "status": "UNAVAILABLE", "reason": "STORY_NODE_NOT_PROVEN_PUBLIC", "capabilities": ["read": false], "items": []]
                ]
            ]
        ]

        coordinator.loadManualArea(areaA)
        while coordinator.isLoading { await Task.yield() }

        XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/native/api/map/public-layers"])
        XCTAssertEqual(wire.deviceLocationCalls, 0)
        XCTAssertNil(coordinator.session?.cursor)
        XCTAssertTrue(coordinator.canRetry)
        XCTAssertEqual(coordinator.visibleReadyItems.map { "\($0.key.type.rawValue):\($0.key.id)" }, ["store:56"])

        // 2. Retry failed page on same cursor -> all readable layers OK -> cursor advances to "cursor-2".
        wire.publicLayerResponse = [
            "code": 200,
            "data": [
                "datum": "GCJ-02",
                "nextCursor": "cursor-2",
                "layers": [
                    [
                        "sourceType": "roam_poi",
                        "status": "OK",
                        "capabilities": ["read": true],
                        "items": [
                            [
                                "sourceType": "roam_poi",
                                "sourceId": 7,
                                "name": "人民公园碑亭",
                                "latitude": "31.231",
                                "longitude": "121.471",
                                "visibilityVersion": "4100000007",
                                "visualState": "pending_redeem",
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
                                "name": "成音桌游馆",
                                "latitude": "31.2305",
                                "longitude": "121.4705",
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
                                "name": "城市解谜赛",
                                "latitude": "31.232",
                                "longitude": "121.472",
                                "visibilityVersion": "2026-04-02T11:00:00",
                                "visualState": "running",
                                "actions": []
                            ]
                        ]
                    ],
                    ["sourceType": "theme", "status": "UNAVAILABLE", "reason": "THEME_NOT_PROVEN_PUBLIC", "capabilities": ["read": false], "items": []],
                    ["sourceType": "story_node", "status": "UNAVAILABLE", "reason": "STORY_NODE_NOT_PROVEN_PUBLIC", "capabilities": ["read": false], "items": []]
                ]
            ]
        ]

        coordinator.retryFailedPage()
        while coordinator.isLoading { await Task.yield() }

        XCTAssertEqual(coordinator.session?.cursor, "cursor-2")
        XCTAssertTrue(coordinator.canLoadNextPage)

        // 3. Navigate to real detail and return: active query, viewport, and selection remain intact.
        let storeKey = try MapSourceKey(type: .store, id: "56")
        let route = try XCTUnwrap(coordinator.openDetail(for: storeKey))
        XCTAssertTrue(coordinator.acceptsDetailRoute(route))
        coordinator.returnFromDetail()
        XCTAssertNil(coordinator.activeDetailRoute)
        XCTAssertEqual(coordinator.selectedItemKey, storeKey)
        XCTAssertEqual(coordinator.session?.cursor, "cursor-2")
        XCTAssertEqual(coordinator.viewportSource?.manualArea, areaA)

        // 4. Logout immediately purges all public-layer state.
        await session.logout()
        XCTAssertFalse(coordinator.acceptsDetailRoute(route))
        XCTAssertNil(coordinator.session)
        XCTAssertTrue(coordinator.visibleReadyItems.isEmpty)
        XCTAssertNil(coordinator.selectedItemKey)
        XCTAssertEqual(wire.deviceLocationCalls, 0)
    }

    @MainActor
    private final class PublicLayerApprovals {
        var manualEnabled = true
        var publicLayerEnabled = true
        var retainedManual: ManualMapReadApproval?
        var retainedPublic: MapPublicLayerReadApproval?

        func manualApproval(_ context: RuntimeDependencyContext) -> ManualMapReadApproval? {
            guard manualEnabled else { return nil }
            if retainedManual?.matches(context) != true {
                retainedManual = try? .init(context: context, expiresAt: Date().addingTimeInterval(3600))
            }
            return retainedManual
        }

        func publicLayerApproval(_ context: RuntimeDependencyContext) -> MapPublicLayerReadApproval? {
            guard publicLayerEnabled else { return nil }
            if retainedPublic?.matches(context) != true {
                retainedPublic = try? .init(context: context, expiresAt: Date().addingTimeInterval(3600))
            }
            return retainedPublic
        }
    }

    @MainActor
    private final class DeviceSpy: RoamDeviceLocationProviding {
        let onCall: () -> Void
        init(onCall: @escaping () -> Void) { self.onCall = onCall }
        func currentFix() async throws -> RoamDeviceFix { onCall(); throw APIError.notConfigured }
        func stop() { onCall() }
    }

    @MainActor
    private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }

    @MainActor
    private final class PublicLayerWire: HTTPTransport {
        var requests: [URLRequest] = []
        var accountID = 7
        var role = "player"
        var deviceLocationCalls = 0
        var publicLayerResponse: [String: Any] = ["code": 200, "data": ["datum": "GCJ-02", "layers": []]]

        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let path = request.url!.path
            if path.hasSuffix("/api/login/phone") {
                let json = "{\"code\":200,\"token\":\"synthetic-\(accountID)\",\"data\":{\"id\":\(accountID),\"role\":\"\(role)\"}}"
                return (Data(json.utf8), 200)
            } else if path.hasSuffix("/api/userInfo") {
                let json = "{\"code\":200,\"appUser\":{\"id\":\(accountID),\"role\":\"\(role)\"}}"
                return (Data(json.utf8), 200)
            } else if path.hasSuffix("/api/logout") {
                return (Data("{\"code\":200}".utf8), 200)
            } else if path.hasSuffix("/api/map/public-layers") {
                return (try JSONSerialization.data(withJSONObject: publicLayerResponse), 200)
            }
            return (Data("{\"code\":200}".utf8), 200)
        }
    }
}
