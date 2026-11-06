import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Dedicated reviewed-composition transport. Generic app transport remains unchanged/default-deny.
/// Original requests only; no wildcard, automatic grant, endpoint rewrite, retries or command/body regeneration.
@MainActor public final class CityParticipationScopedTransport: HTTPTransport {
    private let api: APIConfiguration
    private let grants: CityParticipationRuntimeGrants
    private let underlying: any HTTPTransport
    private let currentContext: () -> RuntimeDependencyContext?
    private let currentRevision: () -> UInt64
    private let currentGrants: () -> CityParticipationRuntimeGrants?
    private let unauthorized: () -> Void
    public init(configuration: APIConfiguration, grants: CityParticipationRuntimeGrants, underlying: any HTTPTransport,
                currentContext: @escaping () -> RuntimeDependencyContext?, currentRevision: @escaping () -> UInt64,
                currentGrants: @escaping () -> CityParticipationRuntimeGrants?, unauthorized: @escaping () -> Void = {}) {
        api = configuration; self.grants = grants; self.underlying = underlying
        self.currentContext = currentContext; self.currentRevision = currentRevision; self.currentGrants = currentGrants; self.unauthorized = unauthorized
    }
    private func current() throws {
        try Task.checkCancellation()
        guard currentGrants() === grants, grants.matches(currentContext(),revision:currentRevision()),
              api.baseURL.absoluteString.utf8.elementsEqual(grants.context.baseURL.absoluteString.utf8) else { throw APIError.notConfigured }
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try current()
        let permit = try authorize(request)
        try permit(); try current()
        let response: (Data,Int)
        do { response = try await underlying.send(request) }
        catch { try current(); try permit(); throw error }
        try current(); try permit()
        var envelopeCode: Int?
        if response.0.count <= 1_048_576, let object = try? JSONSerialization.jsonObject(with:response.0),
           let dictionary = object as? [String:Any] { envelopeCode = dictionary["code"] as? Int }
        if response.1 == 401 || envelopeCode == 401 { unauthorized() }
        return response
    }
    private func authorize(_ request: URLRequest) throws -> () throws -> Void {
        guard let url = request.url, var components = URLComponents(url:url,resolvingAgainstBaseURL:false),
              components.user == nil, components.password == nil, components.fragment == nil,
              request.httpBodyStream == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField:"Cookie") == nil,
              let token = request.value(forHTTPHeaderField:"Authorization"), token.utf8.elementsEqual(grants.context.session.token.utf8) else { throw APIError.notConfigured }
        let query = components.queryItems, hasQuery = components.percentEncodedQuery != nil
        components.query = nil
        guard let clean = components.url?.absoluteString else { throw APIError.notConfigured }
        let prefix = api.baseURL.appendingPathComponent("api/city-game/team-participation").absoluteString
        let scope = grants.scope
        func fields(_ keys: Set<String>) throws -> [String:String] {
            guard let query, query.count == keys.count, Set(query.map(\.name)) == keys,
                  query.allSatisfy({$0.value != nil}) else { throw APIError.notConfigured }
            return Dictionary(uniqueKeysWithValues:query.map{($0.name,$0.value!)})
        }
        if request.httpMethod == "GET", request.httpBody == nil, clean == prefix + "/state" {
            let f = try fields(["regionId"])
            guard f["regionId"] == grants.regionID else { throw APIError.notConfigured }
            let requested = try CityParticipationReadScope(market:scope.session.market,baseURL:scope.session.baseURL,
                namespace:scope.session.namespace,accountID:scope.session.accountID,epoch:scope.session.epoch,token:scope.token,regionID:grants.regionID)
            guard let issued = grants.state(requested), issued.scope == requested, !issued.isRevoked else { throw APIError.notConfigured }
            return { [grants] in guard grants.state(requested) === issued, !issued.isRevoked else { throw APIError.notConfigured } }
        }
        if request.httpMethod == "GET", request.httpBody == nil, clean == prefix + "/invite" {
            let f = try fields(["regionId","code"])
            guard f["regionId"] == grants.regionID, let code = f["code"], CityParticipationInvitationReader.uuid(code),
                  let issued = grants.invitation(scope,region:grants.regionID,code:code), issued.scope == scope,
                  issued.regionID == grants.regionID, issued.code == code, !issued.isRevoked else { throw APIError.notConfigured }
            return { [grants] in guard grants.invitation(scope,region:grants.regionID,code:code) === issued, !issued.isRevoked else { throw APIError.notConfigured } }
        }
        if request.httpMethod == "GET", request.httpBody == nil, !hasQuery, clean.hasPrefix(prefix + "/request/") {
            let id = String(clean.dropFirst((prefix + "/request/").count))
            guard CityParticipationCommand.id(id) else { throw APIError.notConfigured }
            let reference = try CityOriginalReceiptReference(session:scope.session,domain:.participation,requestID:id)
            guard let issued = grants.receipt(reference), issued.reference == reference, !issued.isRevoked else { throw APIError.notConfigured }
            return { [grants] in guard grants.receipt(reference) === issued, !issued.isRevoked else { throw APIError.notConfigured } }
        }
        if request.httpMethod == "POST", clean == prefix + "/command", !hasQuery,
           request.value(forHTTPHeaderField:"Content-Type") == "application/json", let bytes = request.httpBody, bytes.count <= 4096,
           let command = try? JSONDecoder().decode(CityParticipationCommand.self,from:bytes),
           (try? command.wireBytes()) == bytes, command.regionId == grants.regionID,
           let issued = grants.command(scope), issued.scope == scope, issued.bytes == bytes, !issued.isRevoked {
            return { [grants] in guard grants.command(scope) === issued, !issued.isRevoked, issued.bytes == bytes else { throw APIError.notConfigured } }
        }
        throw APIError.notConfigured
    }
}
