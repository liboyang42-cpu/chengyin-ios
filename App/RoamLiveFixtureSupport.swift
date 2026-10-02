#if DEBUG
import Foundation

/// Offline-only, selected by the existing DEBUG UI-test host. No transport or OS provider exists here.
@MainActor final class RoamLiveFixture {
    let controller: RoamLiveSessionController
    init(failReveal: Bool = false) {
        let scope = try! RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.com/synthetic-live/")!, accountID: 901)
        let service = RoamLiveFixtureService(identity: RoamExperienceIdentity(scope: scope, epoch: 1), failReveal: failReveal)
        let storage = RoamLiveFixtureStorage(), location = RoamLiveFixtureLocation()
        controller = RoamLiveSessionController(service: service, location: location, journal: RoamLiveJournal(storage: storage),
            history: RoamHistoryStore(storage: storage, currentScope: { scope }), key: { String(repeating: "f", count: 32) })
    }
}
@MainActor private final class RoamLiveFixtureStorage: RoamHistoryDataStoring {
    private var values: [String: Data] = [:]
    func read(key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws { values[key] = data }
}
@MainActor private final class RoamLiveFixtureLocation: RoamDeviceLocationProviding {
    func currentFix() async throws -> RoamDeviceFix { try RoamDeviceFix(coordinate: RoamCoordinate(latitude: 31.2, longitude: 121.4)!, accuracyMeters: 10, measuredAt: Date(), datum: .gcj02) }
    func stop() {}
}
@MainActor private final class RoamLiveFixtureService: RoamLiveServing {
    let identity: RoamExperienceIdentity?
    let isAvailable = true, presenceAvailable = true
    private var failReveal: Bool
    private var finished = false
    init(identity: RoamExperienceIdentity, failReveal: Bool) { self.identity = identity; self.failReveal = failReveal }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }
    func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt {
        if failReveal { failReveal = false; throw APIError.httpStatus(503) }
        return try decode(RoamLiveRevealReceipt.self, #"{"sessionId":"901","newlyRevealed":0}"#)
    }
    func fact(key: String) async throws -> RoamSessionFact {
        let settlement = finished ? #", "resultComplete":true,"result":{"tileXp":0,"poiXp":0,"totalXp":0,"newTiles":0,"newPois":0,"tilesEver":0,"sessionShops":0}"# : ""
        return try decode(RoamSessionFact.self, "{\"state\":\"\(finished ? "FINISHED" : "ACTIVE")\",\"sessionId\":901,\"clientSessionKey\":\"\(key)\"\(settlement)}")
    }
    func places(fix: RoamDeviceFix) async throws -> [RoamPlace] { [] }
    func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode] { [] }
    func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt { throw APIError.invalidRequest }
    func shopVisit(sessionID: Int, sourceType: Int, sourceID: Int, fix: RoamDeviceFix) async throws -> RoamLiveShopReceipt { throw APIError.invalidRequest }
    func presence(sessionID: Int, fix: RoamDeviceFix, explorationPercent: Int) async throws {}
    func finish(sessionID: Int, poiIDs: [Int], distanceMeters: Int) async throws { finished = true }
}
#endif
