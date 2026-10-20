import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Mini-program app.js loadFeatureFlags: POST /api/config/features (anonymous, token optional,
/// 6 s timeout) on every launch, after sign-in and when the account changes. Only an exact
/// JSON true enables a flag; anything else stays off. A response that arrives after the
/// account or token changed is discarded.
public struct LaunchFeatureFlags: Equatable {
    public static let knownKeys = ["drops", "roamDemoPois", "finishNearbyRoute", "clubMembership", "roamNpcEvent", "roamNpcChat",
                                   "shopNpcChat", "shopNpcVoice", "shopNpcVoiceAvailable", "merchantNpcChat", "communityPostRead", "communityPostWrite"]
    public let enabled: Set<String>
    public static let allOff = LaunchFeatureFlags(enabled: [])
    public init(enabled: Set<String>) { self.enabled = enabled.intersection(Self.knownKeys) }
    public func isOn(_ key: String) -> Bool { enabled.contains(key) }

    public static func decode(_ data: Data) throws -> LaunchFeatureFlags {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = root["code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID(), code.intValue == 200 else {
            throw APIError.malformedResponse
        }
        guard let values = root["data"] as? [String: Any] else { return .allOff }
        let on = values.compactMap { key, value -> String? in
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID(), number.boolValue else { return nil }
            return key
        }
        return LaunchFeatureFlags(enabled: Set(on))
    }
}

public enum LaunchFeatureFlagsOutcome: Equatable {
    case loaded(LaunchFeatureFlags)
    /// Endpoint not on the reviewed allowlist, no configuration, or a failed/late read: all flags off.
    case unavailable
}

public final class LaunchFeatureFlagsReader {
    public static let path = "api/config/features"
    private let configuration: APIConfiguration?
    private let transport: HTTPTransport?
    private let approved: Bool
    private let currentIdentity: () -> String?

    /// `approved` must come from the reviewed per-market endpoint allowlist; it is false today.
    public init(configuration: APIConfiguration?, transport: HTTPTransport?, approved: Bool, currentIdentity: @escaping () -> String?) {
        self.configuration = configuration; self.transport = transport; self.approved = approved; self.currentIdentity = currentIdentity
    }

    public static func request(baseURL: URL, token: String?) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 6)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, AuthRequestBuilder.isValidToken(token) { request.setValue(token, forHTTPHeaderField: "Authorization") }
        return request
    }

    public func load(token: String?) async -> LaunchFeatureFlagsOutcome {
        guard approved, let configuration, let transport else { return .unavailable }
        let identity = currentIdentity()
        do {
            let (data, status) = try await transport.send(Self.request(baseURL: configuration.baseURL, token: token))
            guard status == 200, currentIdentity() == identity else { return .unavailable }
            return .loaded(try LaunchFeatureFlags.decode(data))
        } catch { return .unavailable }
    }
}
