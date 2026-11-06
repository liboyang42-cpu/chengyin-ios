import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only the exact original bounded snapshot GET through existing underlying transport. No generic allowlist expansion.
@MainActor public final class CityCurrentSnapshotScopedTransport: HTTPTransport {
    private let api: APIConfiguration
    private let selection: CityCurrentSnapshotRuntimeSelection
    private let underlying: any HTTPTransport
    private let currentContext: () -> RuntimeDependencyContext?
    private let currentRevision: () -> UInt64
    private let currentSelection: () -> CityCurrentSnapshotRuntimeSelection?
    private let unauthorized: () -> Void
    public init(configuration: APIConfiguration, selection: CityCurrentSnapshotRuntimeSelection, underlying: any HTTPTransport,
                currentContext: @escaping () -> RuntimeDependencyContext?, currentRevision: @escaping () -> UInt64,
                currentSelection: @escaping () -> CityCurrentSnapshotRuntimeSelection?, unauthorized: @escaping () -> Void = {}) {
        api = configuration; self.selection = selection; self.underlying = underlying
        self.currentContext = currentContext; self.currentRevision = currentRevision; self.currentSelection = currentSelection; self.unauthorized = unauthorized
    }
    private func check(_ issued: CityCurrentSnapshotReadGrant) throws {
        try Task.checkCancellation()
        guard currentSelection() === selection, selection.matches(currentContext(), revision: currentRevision()),
              selection.issued() === issued, !issued.isRevoked,
              api.baseURL.absoluteString.utf8.elementsEqual(selection.context.baseURL.absoluteString.utf8) else { throw APIError.notConfigured }
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard let issued = selection.issued() else { throw APIError.notConfigured }
        try check(issued); try validate(request)
        let response: (Data, Int)
        do { response = try await underlying.send(request) }
        catch { try check(issued); throw error }
        try check(issued)
        var code: Int?
        if response.0.count <= 1_048_576, let object = try? JSONSerialization.jsonObject(with: response.0), let body = object as? [String: Any] { code = body["code"] as? Int }
        if response.1 == 401 || code == 401 { unauthorized() }
        return response
    }
    private func validate(_ request: URLRequest) throws {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              !request.httpShouldHandleCookies, request.value(forHTTPHeaderField: "Cookie") == nil,
              let token = request.value(forHTTPHeaderField: "Authorization"), token.utf8.elementsEqual(selection.context.session.token.utf8),
              let url = request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.fragment == nil,
              let items = components.queryItems else { throw APIError.notConfigured }
        components.query = nil
        guard components.url?.absoluteString == api.baseURL.appendingPathComponent("api/city-game/state/snapshot").absoluteString else { throw APIError.notConfigured }
        let q = selection.scope.query
        let expected: [String: String] = ["regionId": q.regionID, "boardId": q.boardID, "seasonId": q.seasonID,
            "rulesReleaseId": q.rulesReleaseID, "revision": String(q.revision), "south": q.south, "west": q.west,
            "north": q.north, "east": q.east, "datum": q.datum, "zoom": String(q.zoom), "layers": q.layers.joined(separator: ","), "limit": String(q.limit)]
        guard items.count == expected.count, Set(items.map(\.name)) == Set(expected.keys),
              items.allSatisfy({ item in guard let value = item.value, let original = expected[item.name] else { return false }; return value.utf8.elementsEqual(original.utf8) }) else { throw APIError.notConfigured }
    }
}
