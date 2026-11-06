import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Original advanced/R5 writer, fenced to the current PLAN operation instance.
@MainActor public final class PlaySharedPlanAdvancedTransport: HTTPTransport {
    private let underlying: any HTTPTransport, flow: PlaySharedPlanLifecycle, ticket: PlaySharedPlanOperationTicket
    private let topicID: Int
    private var advancedSessionID: Int?
    public init(underlying: any HTTPTransport, flow: PlaySharedPlanLifecycle, ticket: PlaySharedPlanOperationTicket, topicID: Int) {
        self.underlying = underlying; self.flow = flow; self.ticket = ticket; self.topicID = topicID
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await flow.validateOperation(ticket)
        guard let url = request.url else { throw PlayExperienceError.staleSession }
        let path = url.path, body = request.httpBody.flatMap { try? JSONDecoder().decode(PlayWireValue.self, from: $0) }
        if path.hasSuffix("/api/play/advanced/start") {
            guard body?["nodeId"].integer == ticket.nodeID, body?["topicId"].integer == topicID,
                  body?["activityId"].integer == ticket.activityID else { throw PlayExperienceError.staleSession }
        } else if path.hasSuffix("/api/play/advanced/action") {
            guard let advancedSessionID, body?["sessionId"].integer == advancedSessionID else { throw PlayExperienceError.staleSession }
        } else if path.hasSuffix("/api/play/advanced/state") {
            guard let advancedSessionID, URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "sessionId" })?.value == String(advancedSessionID) else { throw PlayExperienceError.staleSession }
        } else if path.hasSuffix("/api/play/advanced/leaderboard") {
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard request.httpMethod == "GET", query.first(where: { $0.name == "nodeId" })?.value == String(ticket.nodeID),
                  query.first(where: { $0.name == "topicId" })?.value == String(topicID),
                  query.first(where: { $0.name == "activityId" })?.value == String(ticket.activityID) else { throw PlayExperienceError.staleSession }
        } else { throw PlayExperienceError.disabled }
        let reply = try await underlying.send(request)
        if PlayExperienceService.isAuthenticationFailure(reply) { flow.operationAuthenticationRevoked(); throw APIError.unauthorized }
        try await flow.validateOperation(ticket)
        if !path.hasSuffix("/api/play/advanced/leaderboard"), (200..<300).contains(reply.1), reply.0.count <= 1_048_576,
           let raw = try? JSONDecoder().decode(PlayWireValue.self, from: reply.0), raw["code"].integer == 200 {
            let value = raw["data"]
            guard value["nodeId"].integer == ticket.nodeID, value["topicId"].integer == topicID,
                  value["activityId"].integer == ticket.activityID,
                  value["ownerType"].integer == 2, value["ownerId"].integer == ticket.teamID,
                  let id = value["sessionId"].integer, id > 0, advancedSessionID == nil || advancedSessionID == id else { throw PlayExperienceError.staleSession }
            advancedSessionID = id
        }
        return reply
    }
}
