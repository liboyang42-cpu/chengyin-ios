import Foundation

/// Routes the existing professional editor only after its independent exact project capability.
/// Content validation, ownership, current baseline and the durable submission lock stay in the service/server.
enum ProjectEditCompositionRoute {
    case home, detail, create, update, storyCreate, storyUpdate
    var feature: BusinessRuntimeFeature { switch self { case .home, .detail: return .projectRead; default: return .projectWrite } }
    var path: String {
        switch self {
        case .home: return "api/publish/home"
        case .detail: return "api/topic/edit-detail"
        case .create: return "api/topic/create"
        case .update: return "api/topic/update"
        case .storyCreate: return ProjectEditStoryContract.createPath
        case .storyUpdate: return ProjectEditStoryContract.updatePath
        }
    }
    init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "POST", request.httpBodyStream == nil, let url = request.url,
              url.query == nil, url.fragment == nil, let bytes = request.httpBody else { return nil }
        switch url.absoluteString {
        case baseURL.appendingPathComponent("api/publish/home").absoluteString: self = .home
        case baseURL.appendingPathComponent("api/topic/edit-detail").absoluteString: self = .detail
        case baseURL.appendingPathComponent("api/topic/create").absoluteString: self = .create
        case baseURL.appendingPathComponent("api/topic/update").absoluteString: self = .update
        case baseURL.appendingPathComponent(ProjectEditStoryContract.createPath).absoluteString: self = .storyCreate
        case baseURL.appendingPathComponent(ProjectEditStoryContract.updatePath).absoluteString: self = .storyUpdate
        default: return nil
        }
        if case .detail = self {
            guard Self.acceptsDetail(request, body: bytes) else { return nil }; return
        }
        guard request.value(forHTTPHeaderField: "Content-Type") == "application/json" else { return nil }
        if case .home = self { guard bytes == Data("{}".utf8) else { return nil }; return }
        // Existing bounded parser rejects duplicate keys, malformed UTF-8 and excessive nesting before decoding.
        guard let fields = try? ApprovedTopicReleaseWire.envelope(bytes), let scope = fields["scope"]?.text,
              ProjectEditOwner(rawValue: scope) != nil else { return nil }
        let allowed = Set(ProjectEditContract.whitelist + ProjectEditContract.topicCarryOver + ["id", "startDate", "endDate", "productType", "collaboratorIds", "openMerchantPool", "openClubPool", "publishToCreative", "clubId", "recruitDeadline", "chapters", "tickets"])
        guard Set(fields.keys).isSubset(of: allowed) else { return nil }
        switch self {
        case .create, .storyCreate: guard fields["id"] == nil else { return nil }
        case .update, .storyUpdate: guard let id = fields["id"]?.integer, id > 0 else { return nil }
        default: return nil
        }
        // WHITELIST updates select V2 from a freshly verified server baseline inside ProjectEditHTTPService.
        if Set(fields.keys).isSubset(of: Set(ProjectEditContract.whitelist + ["id"])) {
            guard fields["id"] != nil, fields["name"]?.text != nil else { return nil }; return
        }
        guard (try? ProjectEditStoryContract.path(payload: fields, baseline: nil)) == path,
              (try? ProjectEditStoryContract.validatePayload(fields)) != nil else { return nil }
    }
    private static func acceptsDetail(_ request: URLRequest, body: Data) -> Bool {
        let typePrefix = "multipart/form-data; boundary="
        guard body.count <= 1024, let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix(typePrefix),
              let text = String(data: body, encoding: .utf8), let url = request.url else { return false }
        let boundary = String(type.dropFirst(typePrefix.count))
        let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n"
        let middle = "\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"scope\"\r\n\r\n"
        let suffix = "\r\n--\(boundary)--\r\n"
        guard text.hasPrefix(prefix), text.hasSuffix(suffix), text.count >= prefix.count + suffix.count else { return false }
        let pieces = text.dropFirst(prefix.count).dropLast(suffix.count).components(separatedBy: middle)
        guard pieces.count == 2, let id = Int(pieces[0]), id > 0, String(id) == pieces[0], ProjectEditOwner(rawValue: pieces[1]) != nil,
              let canonical = try? AuthRequestBuilder.makeFormRequest(url: url, fields: ["id": pieces[0], "scope": pieces[1]], token: nil, boundary: boundary) else { return false }
        return canonical.httpBody == body
    }
}
