import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// All reads and writes recheck the captured account, credential, epoch, deployment and endpoint grant.
@MainActor public final class RoamLiveService: RoamLiveServing {
    private let api: APIConfiguration
    private let approval: RoamLiveApproval?
    private let transport: any HTTPTransport
    private let currentSession: () -> RoamExperienceSession?
    private let captured: RoamExperienceSession?
    public var identity: RoamExperienceIdentity? { currentSession()?.identity }
    public var isAvailable: Bool { captured != nil && currentSession() == captured && captured.map { approval?.allows($0.identity, api: api) == true } == true }
    public var presenceAvailable: Bool { isAvailable && approval?.presence == true && approval?.endpoints.paths.contains("api/roam/presence") == true }
    public init(api: APIConfiguration, approval: RoamLiveApproval? = nil, transport: any HTTPTransport,
                currentSession: @escaping () -> RoamExperienceSession?) {
        self.api = api; self.approval = approval; self.transport = transport; self.currentSession = currentSession; captured = currentSession()
    }
    public func reveal(sessionID: Int?, clientSessionKey: String, tiles: [String]) async throws -> RoamLiveRevealReceipt {
        guard clientSessionKey.count == 32, clientSessionKey.allSatisfy({ "0123456789abcdef".contains($0) }),
              (1...200).contains(tiles.count), tiles.allSatisfy({ $0.count == 7 && RoamExperienceMath.isValidTile($0) }) else { throw APIError.invalidRequest }
        var fields = try RoamExperienceMutation.reveal(sessionID: sessionID ?? 0, tiles: tiles).fields()
        fields["clientSessionKey"] = clientSessionKey
        let result = try RoamMutationReceiptDecoder.value(RoamLiveRevealReceipt.self, from: await post("api/roam/reveal", fields: fields))
        guard sessionID == nil || result.sessionId == sessionID, result.newlyRevealed <= tiles.count else { throw APIError.malformedResponse }
        return result
    }
    public func fact(key: String) async throws -> RoamSessionFact {
        let query = RoamRecoveryQuery.clientSessionKey(key); try query.validate()
        let data = try await execute("api/roam/session", fields: query.fields, get: true)
        let result = try RoamMutationReceiptDecoder.value(RoamSessionFact.self, from: data)
        guard query.matches(result) else { throw APIError.malformedResponse }; return result
    }
    public func places(fix: RoamDeviceFix) async throws -> [RoamPlace] {
        try validate(fix)
        let data = try await execute("api/roam/pois", fields: ["lat": String(fix.coordinate.latitude), "lng": String(fix.coordinate.longitude), "radius": "3000"], get: true)
        return try RoamMutationReceiptDecoder.value([RoamPlace].self, from: data).filter(\.isSupported)
    }
    public func registeredShops(fix: RoamDeviceFix) async throws -> [RoamRouteNode] {
        try validate(fix)
        let data = try await post("api/map/nearby", fields: ["latitude": String(fix.coordinate.latitude), "longitude": String(fix.coordinate.longitude), "radius": "800", "limit": "20"])
        // This endpoint's id is the registration-merchant row; nodeId/topicId must never be submitted as sourceId.
        return try RoamMutationReceiptDecoder.value([RoamRouteNode].self, from: data).filter { $0.id > 0 && $0.coordinate != nil }
    }
    public func discover(sessionID: Int, poiID: Int, fix: RoamDeviceFix) async throws -> RoamLiveDiscoveryReceipt {
        try validate(fix)
        let result = try RoamMutationReceiptDecoder.value(RoamLiveDiscoveryReceipt.self, from: await mutation(.discover(sessionID: sessionID, poiID: poiID, fix: fix)))
        guard result.poiId == poiID else { throw APIError.malformedResponse }; return result
    }
    public func shopVisit(sessionID: Int, sourceType: Int, sourceID: Int, fix: RoamDeviceFix) async throws -> RoamLiveShopReceipt {
        try validate(fix)
        return try RoamMutationReceiptDecoder.value(RoamLiveShopReceipt.self, from: await mutation(.shopVisit(sessionID: sessionID, sourceType: sourceType, sourceID: sourceID, fix: fix)))
    }
    public func presence(sessionID: Int, fix: RoamDeviceFix, explorationPercent: Int) async throws {
        guard presenceAvailable else { throw RoamLiveFailure.unavailable }; try validate(fix)
        _ = try await mutation(.presence(sessionID: sessionID, fix: fix, explorationPercent: explorationPercent))
    }
    public func finish(sessionID: Int, poiIDs: [Int], distanceMeters: Int) async throws {
        _ = try await mutation(.finish(sessionID: sessionID, poiIDs: poiIDs, distanceMeters: distanceMeters))
        // Even a success envelope is followed by GET /session; it is never a local reward receipt.
    }
    private func validate(_ fix: RoamDeviceFix) throws {
        guard fix.datum == .gcj02, fix.accuracyMeters <= 80, (-2...30).contains(Date().timeIntervalSince(fix.measuredAt)) else { throw RoamLiveFailure.locationQuality }
    }
    private func mutation(_ mutation: RoamExperienceMutation) async throws -> Data { try await post(mutation.path, fields: mutation.fields()) }
    private func post(_ path: String, fields: [String: String]) async throws -> Data { try await execute(path, fields: fields, get: false) }
    private func execute(_ path: String, fields: [String: String], get: Bool) async throws -> Data {
        guard isAvailable, let captured, approval?.endpoints.paths.contains(path) == true else { throw RoamLiveFailure.unavailable }
        try Task.checkCancellation()
        var request: URLRequest
        if get {
            var url = URLComponents(url: api.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
            url.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
            guard let endpoint = url.url else { throw APIError.invalidRequest }
            request = URLRequest(url: endpoint); request.httpMethod = "GET"
            request.setValue(captured.mutationToken, forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        } else { request = try AuthRequestBuilder.makeFormRequest(url: api.baseURL.appendingPathComponent(path), fields: fields, token: captured.mutationToken) }
        let (data, status) = try await transport.send(request)
        guard currentSession() == captured else { throw RoamLiveFailure.staleIdentity }
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        _ = try RoamMutationReceiptDecoder.status(data); return data
    }
}
