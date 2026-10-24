import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Read-only character card routes. This is not permission for PlayReadRoute or other Play GETs.
public struct CharacterCardReadRoute: Equatable {
    public static let paths: Set<String> = [Endpoint.character.rawValue, Endpoint.rpgStatus.rawValue]
    public enum Endpoint: String, CaseIterable {
        case character = "api/play/character"
        case rpgStatus = "api/play/rpg/status"
    }
    public let endpoint: Endpoint
    public let topicID: Int
    public let activityID: Int?

    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let url = request.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.user == nil, components.password == nil, components.fragment == nil,
              let items = components.queryItems, (1...2).contains(items.count) else { return nil }
        var topic: Int?
        var activity: Int?
        var seen = Set<String>()
        for item in items {
            guard seen.insert(item.name).inserted, let value = item.value,
                  let id = Int(value), id > 0, String(id) == value else { return nil }
            switch item.name {
            case "topicId": topic = id
            case "activityId": activity = id
            default: return nil
            }
        }
        guard let topic else { return nil }
        guard let endpoint = Endpoint.allCases.first(where: { candidate in
            var query = [URLQueryItem(name: "topicId", value: String(topic))]
            if let activity { query.append(URLQueryItem(name: "activityId", value: String(activity))) }
            query.sort { $0.name < $1.name }
            var canonical = URLComponents(url: baseURL.appendingPathComponent(candidate.rawValue), resolvingAgainstBaseURL: false)
            canonical?.queryItems = query
            return canonical?.url?.absoluteString == url.absoluteString
        }) else { return nil }
        if endpoint == .character, activity != nil { return nil }
        if endpoint == .rpgStatus, activity == nil { return nil }
        self.endpoint = endpoint
        self.topicID = topic
        self.activityID = activity
    }

    public func isApproved(configuration: RuntimeDependencyConfiguration?, context: RuntimeDependencyContext) -> Bool {
        guard let configuration, configuration.playReadApprovalID != nil else { return false }
        return configuration.matches(context) && configuration.play.contains(.reads)
            && configuration.endpoints.paths.isSuperset(of: Self.paths)
    }
}
