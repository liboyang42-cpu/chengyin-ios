import Foundation

extension AppCompositionRoot {
    func makeOwnerDraftBrowser(context: RuntimeDependencyContext, transport: any HTTPTransport,
                               current: @escaping () -> RuntimeDependencyContext?,
                               onUnauthorized: @escaping (RuntimeDependencyContext) -> Void) -> OwnerDraftBrowser? {
        guard let reviewed, let api = reviewed.regional.apiConfiguration,
              let approval = ownerDraftReadApproval(context), approval.matches(context),
              context.market == reviewed.regional.market,
              context.baseURL.absoluteString.utf8.elementsEqual(api.baseURL.absoluteString.utf8),
              context.session.namespace.utf8.elementsEqual(reviewed.storageScope.service.utf8),
              ContentDraftContextFence.matches(current(), context) else { return nil }
        let lease = ContentDraftSessionLease(context: context, current: current)
        let reader = ContentDraftService(api: api, transport: transport, lease: lease,
                                         grant: approval.grant, onUnauthorized: onUnauthorized)
        return OwnerDraftBrowser(reader: reader, lease: lease)
    }
}

/// Exactly the existing owner list/restore form shapes. No page/cursor contract is documented.
/// This second transport boundary rejects mutation paths, extra fields and owner overrides.
enum OwnerDraftReadRoute {
    case list, restore
    init?(url: URL, baseURL: URL) {
        if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(ContentDraftRoute.list.path).absoluteString.utf8) { self = .list }
        else if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(ContentDraftRoute.restore.path).absoluteString.utf8) { self = .restore }
        else { return nil }
    }
    func accepts(_ request: URLRequest) -> Bool {
        guard request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded; charset=utf-8",
              let body = request.httpBody, body.count <= 128, let text = String(data: body, encoding: .utf8) else { return false }
        switch self {
        case .list: return text == "scope=" || text == "business_type=ACTIVITY&scope=" || text == "business_type=TOPIC&scope="
        case .restore:
            let prefix = "draft_id=", suffix = "&scope="
            guard text.hasPrefix(prefix), text.hasSuffix(suffix), text.count > prefix.count + suffix.count else { return false }
            let value = String(text.dropFirst(prefix.count).dropLast(suffix.count))
            guard let id = Int64(value), id > 0 else { return false }
            return String(id) == value
        }
    }
}
