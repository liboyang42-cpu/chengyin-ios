import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// BK-PRIVACY: an earlier successful read is never a lasting grant. Media fetched for a
/// post whose fresh read is now denied must not keep rendering from a local cache.
@MainActor public protocol SquareWorkspaceMediaEviction: AnyObject {
    func evict(_ urls: Set<URL>)
}
/// Removes only the exact cached responses for the revoked post's media URLs.
@MainActor public final class SquareWorkspaceURLCacheEviction: SquareWorkspaceMediaEviction {
    private let cache: URLCache
    public init(cache: URLCache = .shared) { self.cache = cache }
    public func evict(_ urls: Set<URL>) {
        for url in urls { cache.removeCachedResponse(for: URLRequest(url: url)) }
    }
}

extension SquareWorkspaceFailure {
    /// Source detail answers `AjaxResult{code:404,"帖文不存在或不可见"}` for deleted,
    /// withdrawn or no-longer-authorized posts. Timeouts and malformed bodies are not
    /// revocations and never clear anything beyond the transient display.
    static func isRevocation(_ error: Error) -> Bool { (error as? SquareWorkspaceFailure) == .rejected(404) }
}

extension SquareWorkspacePost {
    /// The source policy (`canView`) hides DELETED from its author too. A stale backend
    /// that still projects it is treated like the business 404 it is meant to return.
    var isDeletedProjection: Bool { lane == .communityV1 && lifecycle == "DELETED" }

    /// Absolute http(s) media URLs carried by this projection; relative object keys are ignored.
    var cachedMediaURLs: Set<URL> {
        guard let root = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return [] }
        let p = (root["post"] as? [String: Any]) ?? root
        var values: [String] = []
        for row in (root["media"] as? [[String: Any]]) ?? [] {
            for key in ["derived_object_key", "derivedObjectKey", "url", "coverUrl", "cover_url", "thumbnailUrl"] {
                if let value = row[key] as? String { values.append(value) }
            }
        }
        if let pics = p["pics"] as? String { values += pics.split(separator: ";").map(String.init) }
        if let pics = p["pics"] as? [String] { values += pics }
        return SquareWorkspaceMedia.absoluteURLs(values)
    }
}

extension SquareWorkspaceMedia {
    static func absoluteURLs(_ values: [String]) -> Set<URL> {
        Set(values.compactMap { value in
            guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
            return url
        })
    }
}
