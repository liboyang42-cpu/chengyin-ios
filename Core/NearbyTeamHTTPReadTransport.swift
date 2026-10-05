import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Scoped injected reader only. Writes use the separately granted NearbyTeamHTTPWriteAdapter, never this transport.
@MainActor public final class NearbyTeamHTTPReadTransport: NearbyTeamReadTransport {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let approval: OperationEndpointApproval
    private let currentSession: () -> NearbyTeamSession?
    private let token: (NearbyTeamSession) -> String?
    public init(configuration: APIConfiguration, transport: any HTTPTransport, approval: OperationEndpointApproval,
                currentSession: @escaping () -> NearbyTeamSession?, token: @escaping (NearbyTeamSession) -> String?) {
        self.configuration = configuration; self.transport = transport; self.approval = approval; self.currentSession = currentSession; self.token = token
    }
    public func sendRead(_ descriptor: NearbyTeamRequest, session: NearbyTeamSession) async throws -> NearbyTeamResponse {
        let methods = ["/api/team/nearby": "GET", "/api/team/applications": "POST", "/api/team/my-applications": "POST"]
        guard !descriptor.mutation, session.valid, methods[descriptor.path] == descriptor.method,
              approval.allows(configuration: configuration, namespace: session.namespace, accountID: session.accountID, path: String(descriptor.path.dropFirst())) else { throw NearbyTeamFailure.unconfigured }
        try Task.checkCancellation()
        guard currentSession() == session else { throw NearbyTeamFailure.stale }
        guard let token = token(session), AuthRequestBuilder.isValidToken(token) else { throw NearbyTeamFailure.unauthorized }
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(String(descriptor.path.dropFirst())), resolvingAgainstBaseURL: false)
        if !descriptor.query.isEmpty { components?.queryItems = descriptor.query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        guard let url = components?.url else { throw NearbyTeamFailure.invalidRequest }
        var request = URLRequest(url: url); request.httpMethod = descriptor.method; request.httpBody = descriptor.body
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        guard currentSession() == session else { throw NearbyTeamFailure.stale }
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation(); guard currentSession() == session else { throw NearbyTeamFailure.stale }
        return .init(status: status, data: data)
    }
}
