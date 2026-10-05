import Foundation

/// Local persistence identity, not server authorization or evidence of physical isolation.
/// Exact reviewed endpoint, deployment realm, market and native bundle must all agree.
/// Never derive this scope from language, an account ID or a client-supplied request header.
public struct RegionalSessionStorageScope: Equatable {
    public let market: RegionalMarket
    public let service: String
    private let endpoint: String
    public var restoreBlockedKey: String { service + ".preventRestore" }

    public init(configuration: RegionalConfiguration, bundleIdentifier: String?, realm: String?) throws {
        guard let endpoint = configuration.apiConfiguration?.baseURL.absoluteString,
              let bundleIdentifier, Self.validComponent(bundleIdentifier),
              let realm, Self.validComponent(realm) else {
            throw APIError.invalidConfiguration
        }
        market = configuration.market
        self.endpoint = endpoint
        // Length-prefix each UTF-8 component so delimiters cannot create collisions.
        // This is an identifier, not encryption; it contains no token or account data.
        let components = [bundleIdentifier, market.rawValue, endpoint, realm]
        let identity = components.map { "\($0.utf8.count):\($0)" }.joined()
        service = "questify.session.v2." + Data(identity.utf8).base64EncodedString()
    }

    /// A service may only use the endpoint/market that created this local vault scope.
    /// Bundle and realm remain bound in the immutable service identity above.
    public func matches(configuration: RegionalConfiguration) -> Bool {
        market == configuration.market && endpoint == configuration.apiConfiguration?.baseURL.absoluteString
    }

    private static func validComponent(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && !value.contains("$(") &&
        value.utf8.allSatisfy { (0x21...0x7e).contains($0) }
    }
}
