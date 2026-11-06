import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only the two original anonymous official-event projections.
public enum OfficialPublicEventReadRoute {
    public static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              request.allHTTPHeaderFields?.keys.allSatisfy({ ["accept", "authorization"].contains($0.lowercased()) }) != false,
              request.value(forHTTPHeaderField: "Authorization").map(AuthRequestBuilder.isValidToken) != false,
              baseURL.scheme == "https", baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil,
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.fragment == nil else { return false }
        let list = baseURL.appendingPathComponent("api/official/events")
        if parts.path == list.path {
            var expected = URLComponents(url: list, resolvingAgainstBaseURL: false)!
            if let items = parts.queryItems {
                guard items.count == 1, items[0].name == "city", items[0].value != nil else { return false }
                expected.queryItems = items
            }
            return expected.url?.absoluteString.utf8.elementsEqual(url.absoluteString.utf8) == true
        }
        let prefix = list.path + "/"
        guard parts.path.hasPrefix(prefix), parts.query == nil,
              let id = Int(parts.path.dropFirst(prefix.count)), id > 0,
              String(id) == String(parts.path.dropFirst(prefix.count)) else { return false }
        return baseURL.appendingPathComponent("api/official/events/\(id)").absoluteString.utf8.elementsEqual(url.absoluteString.utf8)
    }
}

/// Reviewed public source; revocation is shared by root and scoped transports.
@MainActor public final class OfficialPublicEventReadSource {
    public let baseURL: URL
    public let namespace: String
    public let revision = UUID()
    public private(set) var isRevoked = false
    fileprivate let revocations = OfficialReadInvalidationSignal()
    public init(baseURL: URL, namespace: String) throws {
        guard baseURL.scheme == "https", baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil, !namespace.isEmpty,
              namespace == namespace.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw APIError.invalidConfiguration
        }
        self.baseURL = baseURL; self.namespace = namespace
    }
    public func revoke() {
        guard !isRevoked else { return }
        isRevoked = true; revocations.invalidate()
    }
    public func matches(baseURL: URL, namespace: String) -> Bool {
        !isRevoked && self.baseURL.absoluteString.utf8.elementsEqual(baseURL.absoluteString.utf8) &&
        self.namespace.utf8.elementsEqual(namespace.utf8)
    }
}

/// Local selection lifetime only. It never creates a source or grants a route.
/// Shared by the normal root and every transport clone; a removal/reselection has
/// a fresh revision even when it selects the same source object again.
@MainActor public final class OfficialPublicEventReadSelection {
    public private(set) var source: OfficialPublicEventReadSource?
    public private(set) var revision = UUID()
    public let invalidations = OfficialReadInvalidationSignal()
    private var sourceObservation: OfficialReadInvalidationSubscription?
    public init() {}
    public func select(_ source: OfficialPublicEventReadSource?) {
        guard self.source !== source else { return }
        sourceObservation?.cancel(); sourceObservation = nil
        self.source = source; revision = UUID()
        sourceObservation = source?.revocations.observe { [weak self, weak source] in
            guard let self, let source, self.source === source else { return }
            self.revision = UUID(); self.invalidations.invalidate()
        }
        invalidations.invalidate()
    }
    public func activeRevision(baseURL: URL, namespace: String) -> UUID? {
        guard source?.matches(baseURL: baseURL, namespace: namespace) == true else { return nil }
        return revision
    }
}
