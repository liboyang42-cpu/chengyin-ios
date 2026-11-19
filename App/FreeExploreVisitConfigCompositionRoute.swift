import Foundation

/// FE-STORY 7.10 author 「到访方式」 at the composition fence: exactly
/// `GET api/topic/free-explore/visit-config?topicId=<id>` (read) and the JSON
/// `POST {nodeId, visitCheck, visitRadius}` (write). Anything else is not this route.
/// Author ownership and the 300–500 m rule stay on the server.
enum FreeExploreVisitConfigCompositionRoute {
    case read, write
    var feature: BusinessRuntimeFeature { self == .read ? .freeExploreVisitConfigRead : .freeExploreVisitConfigWrite }
    var exact: BusinessRuntimeRoute {
        get throws {
            switch self {
            case .read: return try BusinessRuntimeRoute.get(FreeExplorationVisitConfigService.path)
            case .write: return try BusinessRuntimeRoute.post(FreeExplorationVisitConfigService.path)
            }
        }
    }
    init?(request: URLRequest, baseURL: URL) {
        guard request.httpBodyStream == nil, let url = request.url, url.fragment == nil,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.user == nil, parts.password == nil else { return nil }
        let items = parts.queryItems; parts.query = nil
        guard parts.url == baseURL.appendingPathComponent(FreeExplorationVisitConfigService.path) else { return nil }
        switch request.httpMethod {
        case "GET":
            guard request.httpBody == nil, let items, items.count == 1, items[0].name == "topicId",
                  let text = items[0].value, let id = Int(text), id > 0, String(id) == text else { return nil }
            self = .read
        case "POST":
            guard items == nil, request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                  let body = request.httpBody, body.count <= 256,
                  let fields = try? JSONDecoder().decode([String: PlayWireValue].self, from: body),
                  Set(fields.keys) == ["nodeId", "visitCheck", "visitRadius"],
                  let node = fields["nodeId"]?.tolerantInteger, node > 0,
                  let check = fields["visitCheck"]?.text.flatMap(PlayVisitCheck.init(rawValue:)) else { return nil }
            // Local precheck shape only; the server is the judge of the value.
            let radius = fields["visitRadius"]
            if check == .gps { guard let value = radius?.tolerantInteger, value > 0 else { return nil } }
            else { guard radius == .null else { return nil } }
            self = .write
        default: return nil
        }
    }
}
