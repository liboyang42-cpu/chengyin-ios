import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The two reviewed, authenticated progress reads used by the activity/topic entry.
/// A runtime `.reads` grant is not permission for arbitrary GETs or other Play APIs.
public struct PlayReadRoute: Equatable {
    public enum Endpoint: String, CaseIterable {
        case nodes = "api/play/nodes"
        case routeState = "api/play/route-state"
    }
    public let endpoint: Endpoint
    public let scope: PlaySessionScope

    /// Compare the complete canonical URL after parsing one positive decimal scope.
    /// Reject aliases, extra/duplicate scopes, encoded names/values, foreign origins,
    /// path variants, credentials, fragments, bodies and non-GET methods.
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.fragment == nil,
              let items = components.queryItems, items.count == 1, let item = items.first,
              let value = item.value, let id = Int(value), id > 0, String(id) == value else { return nil }
        switch item.name {
        case "activityId": scope = .activity(id)
        case "topicId": scope = .topic(id)
        default: return nil
        }
        guard let endpoint = Endpoint.allCases.first(where: { endpoint in
            var canonical = URLComponents(url: baseURL.appendingPathComponent(endpoint.rawValue), resolvingAgainstBaseURL: false)
            canonical?.queryItems = [URLQueryItem(name: item.name, value: value)]
            return canonical?.url?.absoluteString == url.absoluteString
        }) else { return nil }
        self.endpoint = endpoint
    }

    public func isApproved(configuration: RuntimeDependencyConfiguration?, context: RuntimeDependencyContext) -> Bool {
        guard let configuration, configuration.playReadApprovalID != nil else { return false }
        return configuration.matches(context) && configuration.play.contains(.reads)
            && configuration.endpoints.paths.contains(endpoint.rawValue)
    }
}
