import Foundation

/// Only independently approved, fixed HTTPS support destinations can become an app link.
/// No provider is implied by WeChat's open-type=contact; production starts unconfigured.
public struct ParticipationSupportConfiguration: Equatable {
    public let name: String
    public let url: URL
    public init(name: String, url: URL, approvedURLs: Set<URL>) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", parts.host?.isEmpty == false,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              approvedURLs.contains(url) else { throw APIError.invalidConfiguration }
        self.name = name; self.url = url
    }
}
