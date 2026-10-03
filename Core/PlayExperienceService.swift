import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PlayExperienceCapability: Hashable {
    case directorCommands, reads, runPersistence, classicCompletion, hints, leader, advanced, playerCommands, circle, preference, tags, mediaUpload, thoughtClaims
}
public enum PlayCompletionEvidence: Codable, Equatable {
    case answer(String)
    case scan(String)
    /// Provider must return GCJ-02 for the source CN arrive contract. No conversion guess.
    case location(longitude: Double, latitude: Double, coordinateSystem: String)
    case photo(uploadedURL: String)
    case sensor(type: String, payload: [String: PlayWireValue])
    var path: String {
        switch self { case .answer: return "answer"; case .scan: return "checkin"; case .location: return "arrive"; case .photo: return "photo"; case .sensor: return "sensor-result" }
    }
}
/// Dormant production adapter; enabling a capability is an integration acceptance gate,
/// not user consent. Only fake transports are enabled by this migration's fixtures.
public struct PlayExperienceService {
    let configuration: APIConfiguration
    let transport: any HTTPTransport
    public let enabled: Set<PlayExperienceCapability>
    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabled: Set<PlayExperienceCapability> = []) {
        self.configuration = configuration; self.transport = transport; self.enabled = enabled
    }
    public func nodes(scope: PlaySessionScope, token: String) async throws -> PlayExperienceDocument {
        let document: PlayExperienceDocument = try await request("api/play/nodes", query: scopeFields(scope), capability: .reads, token: token).decoded()
        if case .topic(let id) = scope, let returnedID = document.base.topicID, returnedID != id { throw PlayExperienceError.malformed }
        return document
    }
    public func route(scope: PlaySessionScope, token: String) async throws -> PlayRouteState {
        let raw = try await request("api/play/route-state", query: scopeFields(scope), capability: .reads, token: token)
        let route: PlayRouteState = try (raw["routeState"].object == nil ? raw : raw["routeState"]).decoded()
        if route.isBranch {
            guard route.nodeStates.values.allSatisfy({ ["HIDDEN", "DISCOVERED_LOCKED", "PLAYABLE", "COMPLETED"].contains($0) }) else { throw PlayExperienceError.malformed }
        }
        return route
    }
    /// Raw payload entry remains useful for sealed in-process fixture recording only.
    /// Network-capable transports require the coordinator's one-shot durable attempt.
    public func complete(scope: PlaySessionScope, nodeID: Int, evidence: PlayCompletionEvidence, advance: PlayRouteAdvance?, token: String) async throws -> PlayWireValue {
        let request = try completionRequest(scope: scope, nodeID: nodeID, evidence: evidence, advance: advance, token: token, boundary: UUID().uuidString)
        return try await send(request, capability: .classicCompletion)
    }
    func completionRequest(scope: PlaySessionScope, nodeID: Int, evidence: PlayCompletionEvidence, advance: PlayRouteAdvance?, token: String, boundary: String) throws -> URLRequest {
        guard nodeID > 0 else { throw APIError.invalidRequest }
        var fields = try scopeFields(scope)
        fields["nodeId"] = String(nodeID)
        switch evidence {
        case .answer(let answer):
            guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidRequest }
            fields["answer"] = answer
        case .scan(let code):
            guard !code.isEmpty else { throw APIError.invalidRequest }
            // Source checkin resolves node from code; never invent a nodeId argument.
            fields.removeValue(forKey: "nodeId"); fields["code"] = code
        case .location(let longitude, let latitude, let coordinateSystem):
            guard coordinateSystem == "GCJ02", longitude.isFinite, latitude.isFinite,
                  abs(longitude) <= 180, abs(latitude) <= 90 else { throw APIError.invalidRequest }
            fields["longitude"] = String(longitude); fields["latitude"] = String(latitude)
        case .photo(let url):
            guard Self.validHTTPS(url) else { throw APIError.invalidRequest }
            fields["picUrl"] = url
        case .sensor(let type, let payload):
            guard ["still", "steps", "audio_clip"].contains(type), !payload.isEmpty else { throw APIError.invalidRequest }
            var json = scopeJSON(scope); json["nodeId"] = .int(nodeID); json["sensorType"] = .string(type); json["payload"] = .object(payload)
            if let advance { json["routeActionId"] = .string(advance.actionID); json["expectedRouteVersion"] = .int(advance.expectedVersion) }
            return try makeRequest("api/play/sensor-result", json: json, token: token)
        }
        fields.merge(advance?.fields ?? [:]) { _, new in new }
        return try makeRequest("api/play/" + evidence.path, form: fields, token: token, boundary: boundary)
    }
    public func hint(scope: PlaySessionScope, nodeID: Int, level: Int?, token: String) async throws -> PlayHintReceipt {
        guard nodeID > 0 else { throw APIError.invalidRequest }
        var fields: [String: String] = ["nodeId": String(nodeID)]
        let path: String
        if let level {
            guard (1...2).contains(level) else { throw APIError.invalidRequest }
            fields.merge(try scopeFields(scope)) { _, new in new }; fields["level"] = String(level)
            path = "api/play/puzzle/hint"
        } else { path = "api/play/hint/unlock" }
        return try PlayHintReceipt(await request(path, form: fields, capability: .hints, token: token))
    }
    public func reveal(scope: PlaySessionScope, nodeID: Int, advance: PlayRouteAdvance?, token: String) async throws -> PlayWireValue {
        guard nodeID > 0 else { throw APIError.invalidRequest }
        var fields = try scopeFields(scope); fields["nodeId"] = String(nodeID)
        fields.merge(advance?.fields ?? [:]) { _, new in new }
        return try await request("api/play/puzzle/reveal", form: fields, capability: .hints, token: token)
    }
    public func ending(scope: PlaySessionScope, token: String) async throws -> PlayEndingDocument {
        try await request("api/play/ending", query: scopeFields(scope), capability: .reads, token: token).decoded()
    }
    public func leaderboard(scope: PlaySessionScope, token: String) async throws -> PlayCompanionLeaderboard {
        try PlayCompanionLeaderboard(await request("api/play/leaderboard", query: scopeFields(scope), capability: .reads, token: token))
    }
    public func teamProgress(activityID: Int, token: String) async throws -> PlayLeadProgress {
        guard activityID > 0 else { throw APIError.invalidRequest }
        return try PlayLeadProgress(await request("api/club/lead/team-progress", query: ["activityId": String(activityID)], capability: .reads, token: token))
    }
    public func lead(activityID: Int, action: PlayLeadAction, text: String?, token: String) async throws {
        guard activityID > 0 else { throw APIError.invalidRequest }
        var fields = ["activityId": String(activityID)]
        if action == .broadcast {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw APIError.invalidRequest }
            fields["text"] = text
        }
        if action == .editTime {
            guard let text, !text.isEmpty else { throw APIError.invalidRequest }
            _ = try await request("api/club/lead/edit-ops", json: ["activityId": .int(activityID), "startDate": .string(text)], capability: .leader, token: token)
        } else {
            _ = try await request("api/club/lead/" + action.rawValue, form: fields, capability: .leader, token: token)
        }
    }
    public func readPaused(scope: PlaySessionScope, token: String) async throws -> PlayPausedRead {
        try PlayPausedRead(await request("api/play/run-session", query: scopeFields(scope), capability: .reads, token: token))
    }
    public func pausedList(token: String) async throws -> [PlayContinueRun] {
        let raw = try await request("api/play/run-session/list", capability: .reads, token: token)
        guard let rows = raw.array else { throw PlayExperienceError.malformed }
        return rows.compactMap(PlayContinueRun.init)
    }
    public func savePaused(scope: PlaySessionScope, record: PlayPausedRecord, token: String) async throws {
        _ = try await send(pausedRequest(scope: scope, record: record, savedAt: record.savedAt, token: token), capability: .runPersistence)
    }
    public func clearPaused(scope: PlaySessionScope, savedAt: Int64, token: String) async throws {
        _ = try await send(pausedRequest(scope: scope, record: nil, savedAt: savedAt, token: token), capability: .runPersistence)
    }
    func pausedRequest(scope: PlaySessionScope, record: PlayPausedRecord?, savedAt: Int64, token: String) throws -> URLRequest {
        guard savedAt > 0 else { throw APIError.invalidRequest }
        var fields = try scopeFields(scope); fields["savedAt"] = String(savedAt)
        if let record { fields["elapsedSeconds"] = String(record.elapsedSeconds) }
        return try makeRequest("api/play/run-session/" + (record == nil ? "clear" : "save"), form: fields, token: token)
    }
    @MainActor func dispatch(_ attempt: PlayPreparedDispatch) async throws -> PlayWireValue {
        guard attempt.baseURL.absoluteString.utf8.elementsEqual(configuration.baseURL.absoluteString.utf8) else { throw PlayExperienceError.persistenceUnavailable }
        return try await send(attempt.request, capability: attempt.capability, attempt: attempt)
    }
    public func operatingSystem(topicID: Int, token: String) async throws -> PlayWireValue {
        guard topicID > 0 else { throw APIError.invalidRequest }
        let raw = try await request("api/play/os/\(topicID)", capability: .reads, token: token)
        guard raw["topicId"].tolerantInteger == topicID else { throw PlayExperienceError.malformed }
        return raw
    }
    public func revokeTag(tagID: Int, token: String) async throws -> PlayWireValue {
        guard tagID > 0 else { throw APIError.invalidRequest }
        let raw = try await request("api/play/tag/\(tagID)/revoke", postWithoutBody: true, capability: .tags, token: token)
        guard raw["id"].tolerantInteger == tagID, raw["status"].text == "REVOKED" else { throw PlayExperienceError.malformed }
        return raw
    }
    func scopeFields(_ scope: PlaySessionScope) throws -> [String: String] {
        guard scope.isValid else { throw APIError.invalidRequest }; return scope.fields
    }
    func scopeJSON(_ scope: PlaySessionScope) -> [String: PlayWireValue] {
        switch scope { case .activity(let id): return ["activityId": .int(id)]; case .topic(let id): return ["topicId": .int(id)] }
    }
    static func validHTTPS(_ value: String) -> Bool {
        guard let url = URLComponents(string: value), url.scheme == "https", url.host?.isEmpty == false, url.user == nil, url.password == nil else { return false }
        return true
    }
    /// One source request only. There is deliberately no retry or URLSession fallback.
    func request(_ path: String, query: [String: String] = [:], form: [String: String]? = nil,
                 json: [String: PlayWireValue]? = nil, postWithoutBody: Bool = false,
                 capability: PlayExperienceCapability, token: String) async throws -> PlayWireValue {
        try await send(makeRequest(path, query: query, form: form, json: json, postWithoutBody: postWithoutBody, token: token), capability: capability)
    }
    private func makeRequest(_ path: String, query: [String: String] = [:], form: [String: String]? = nil,
                             json: [String: PlayWireValue]? = nil, postWithoutBody: Bool = false,
                             token: String, boundary: String = UUID().uuidString) throws -> URLRequest {
        // Restrict every segment before URL construction: dot/semicolon/backslash/encoded
        // aliases must not bypass the protected-route comparison after server normalization.
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.first == "api", segments.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy {
                  (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
              } }),
              AuthRequestBuilder.isValidToken(token), !(form != nil && json != nil) else { throw APIError.invalidRequest }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !query.isEmpty {
            var components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }; request.url = components.url
        }
        if let form {
            request = try AuthRequestBuilder.makeFormRequest(url: request.url!, fields: form, token: token, boundary: boundary)
        } else if let json {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            // Re-encoding an exact reviewed retry must not reorder dictionary keys.
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            request.httpBody = try encoder.encode(json)
        } else { request.httpMethod = postWithoutBody ? "POST" : "GET" }
        return request
    }
    @MainActor private func send(_ request: URLRequest, capability: PlayExperienceCapability, attempt: PlayPreparedDispatch? = nil) async throws -> PlayWireValue {
        guard enabled.contains(capability) else { throw PlayExperienceError.disabled }
        guard let url = request.url, var route = URLComponents(url: url, resolvingAgainstBaseURL: false) else { throw APIError.invalidRequest }
        route.query = nil; route.fragment = nil
        let protected = ["answer", "checkin", "arrive", "photo", "sensor-result", "run-session/save", "run-session/clear"].contains { configuration.baseURL.appendingPathComponent("api/play/" + $0) == route.url }
        if capability == .classicCompletion || capability == .runPersistence {
            guard protected else { throw PlayExperienceError.persistenceUnavailable }
        }
        if protected {
            if let attempt { try await attempt.consume(request: request, transport: transport) }
            else { guard transport is PlayRecoveryRecordingTransport else { throw PlayExperienceError.persistenceUnavailable } }
        } else if attempt != nil { throw PlayExperienceError.persistenceUnavailable }
        try attempt?.checkLifetime()
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        try attempt?.checkLifetime()
        let envelope = try? JSONDecoder().decode(PlayWireValue.self, from: data)
        let code = envelope?["code"].tolerantInteger
        if status == 401 || code == 401 { throw PlayExperienceError.unauthorized }
        // A transport error or malformed envelope cannot prove a write was rejected.
        guard (200..<300).contains(status) else { throw PlayExperienceError.unknownResult }
        guard let code else { throw PlayExperienceError.malformed }
        guard code == 200 else { throw PlayExperienceError.rejected(code, envelope?["msg"].text) }
        return envelope?["data"] ?? .null
    }
}
