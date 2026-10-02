import Foundation

/// Concrete adapter delegates to the established multipart/envelope transport; no new
/// receipt endpoint and no URLSession fallback. Capabilities are individually off.
public struct JourneyContentService {
    private let api: PlayExperienceService
    public let readsEnabled: Bool; public let checksEnabled: Bool; public let collectEnabled: Bool
    public init(configuration: APIConfiguration, transport: any HTTPTransport,
                readsEnabled: Bool = false, checksEnabled: Bool = false, collectEnabled: Bool = false) {
        self.readsEnabled = readsEnabled; self.checksEnabled = checksEnabled; self.collectEnabled = collectEnabled
        api = PlayExperienceService(configuration: configuration, transport: transport,
                                    enabled: [.reads, .classicCompletion])
    }
    public func encounter(topicID: Int, nodeID: Int, token: String) async throws -> JourneyCheckProblem? {
        guard readsEnabled else { throw PlayExperienceError.disabled }
        guard topicID > 0, nodeID > 0 else { throw APIError.invalidRequest }
        return JourneyCheckProblem(encounter: try await api.request("api/play/encounter",
            query: ["topicId": String(topicID), "nodeId": String(nodeID)], capability: .reads, token: token))
    }
    public func act(_ review: JourneyCheckReview) async throws -> JourneyCheckReceipt {
        guard checksEnabled else { throw PlayExperienceError.disabled }
        guard review.topicID > 0, review.nodeID > 0, !review.checkID.isEmpty else { throw APIError.invalidRequest }
        return try JourneyCheckReceipt(await api.request("api/play/check/" + review.action.rawValue,
            form: ["topicId": String(review.topicID), "nodeId": String(review.nodeID), "checkId": review.checkID],
            capability: .classicCompletion, token: review.session.token))
    }
    public func companion(scope: PlaySessionScope, token: String) async throws -> String? {
        guard readsEnabled else { throw PlayExperienceError.disabled }
        guard scope.isValid else { throw APIError.invalidRequest }
        let raw = try await api.request("api/play/companionLine", query: scope.fields, capability: .reads, token: token)
        let line = (raw["line"].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }
    public func collect(topicID: Int?, egg: JourneyEgg, token: String) async throws {
        guard collectEnabled else { throw PlayExperienceError.disabled }
        var fields = ["eggId": String(egg.id), "content": egg.text]
        if let topicID, topicID > 0 { fields["topicId"] = String(topicID) }
        // Envelope success only: there is no reward/points payload to project.
        _ = try await api.request("api/play/egg/collect", form: fields, capability: .classicCompletion, token: token)
    }
}
