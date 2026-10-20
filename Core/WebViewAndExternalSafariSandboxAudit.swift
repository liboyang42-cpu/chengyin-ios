import Foundation

/// Security policy descriptor for an in-app web or external Safari container (`SFSafariViewController` / `WKWebView`),
/// verifying HTTPS-only App Transport Security (`NSAllowsArbitraryLoads == false`), JavaScript bridge isolation
/// for untrusted origins, and zero auth-token query parameter leakage in external URLs.
public struct WebContainerSecurityPolicy: Sendable, Equatable, Identifiable {
    public let id: String
    public let containerKind: String
    public let enforcesHTTPSOnlyATS: Bool
    public let disablesJSBridgeForUntrustedHosts: Bool
    public let stripsAuthTokensFromExternalURLQuery: Bool

    public init(
        id: String? = nil,
        containerKind: String,
        enforcesHTTPSOnlyATS: Bool,
        disablesJSBridgeForUntrustedHosts: Bool,
        stripsAuthTokensFromExternalURLQuery: Bool
    ) {
        self.id = id ?? containerKind
        self.containerKind = containerKind
        self.enforcesHTTPSOnlyATS = enforcesHTTPSOnlyATS
        self.disablesJSBridgeForUntrustedHosts = disablesJSBridgeForUntrustedHosts
        self.stripsAuthTokensFromExternalURLQuery = stripsAuthTokensFromExternalURLQuery
    }

    public var isCompliant: Bool {
        enforcesHTTPSOnlyATS
            && disablesJSBridgeForUntrustedHosts
            && stripsAuthTokensFromExternalURLQuery
    }
}

/// Pure, self-contained audit of `SFSafariViewController` / `WKWebView` HTTPS-only ATS enforcement,
/// JavaScript bridge isolation for untrusted hosts, and external URL auth-token query stripping.
public struct WebViewAndExternalSafariSandboxAudit: Sendable, Equatable {
    public static let forbiddenQueryTokenKeys: Set<String> = [
        "token",
        "access_token",
        "auth_token",
        "authorization",
        "bearer",
        "session_token",
        "jwt"
    ]

    public static let canonicalPolicies: [WebContainerSecurityPolicy] = [
        WebContainerSecurityPolicy(
            id: "legal-and-privacy-policy-reader",
            containerKind: "legal-and-privacy-policy-reader",
            enforcesHTTPSOnlyATS: true,
            disablesJSBridgeForUntrustedHosts: true,
            stripsAuthTokensFromExternalURLQuery: true
        ),
        WebContainerSecurityPolicy(
            id: "merchant-external-campaign-preview",
            containerKind: "merchant-external-campaign-preview",
            enforcesHTTPSOnlyATS: true,
            disablesJSBridgeForUntrustedHosts: true,
            stripsAuthTokensFromExternalURLQuery: true
        ),
        WebContainerSecurityPolicy(
            id: "help-center-and-faq-viewer",
            containerKind: "help-center-and-faq-viewer",
            enforcesHTTPSOnlyATS: true,
            disablesJSBridgeForUntrustedHosts: true,
            stripsAuthTokensFromExternalURLQuery: true
        )
    ]

    public static func evaluate(
        policies: [WebContainerSecurityPolicy] = canonicalPolicies
    ) -> (totalContainers: Int, compliantContainers: Int, isWebSandboxSafe: Bool) {
        let total = policies.count
        let compliant = policies.filter(\.isCompliant).count
        let isSafe = total > 0 && compliant == total
        return (totalContainers: total, compliantContainers: compliant, isWebSandboxSafe: isSafe)
    }

    public static func isHTTPSOnlyURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https",
              let host = url.host, !host.isEmpty else {
            return false
        }
        return true
    }

    public static func containsAuthTokenInQuery(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return false
        }
        for item in queryItems {
            if forbiddenQueryTokenKeys.contains(item.name.lowercased()) {
                return true
            }
        }
        return false
    }
}
