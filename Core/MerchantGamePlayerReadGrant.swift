import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Player-only extraction of the existing c447 MerchantAuthoringEndpointGrant contract.
/// Possessing a store role, publication or write grant never creates this read approval.
public struct MerchantGamePlayerReadGrant: Equatable {
    public let market: RegionalMarket
    public let endpoints: OperationEndpointApproval
    public init(market: RegionalMarket, endpoints: OperationEndpointApproval) {
        self.market = market; self.endpoints = endpoints
    }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        market == context.market && endpoints.baseURL == context.baseURL &&
        endpoints.namespace == context.session.namespace && endpoints.accountID == context.session.accountID
    }
    public static let playerPaths: Set<String> = [
        "api/merchant/authoring/player/{merchantId}/game",
        "api/merchant/authoring/player/{merchantId}/requests/{requestId}"
    ]
    public func allows(configuration: APIConfiguration, namespace: String, accountID: Int, path: String) -> Bool {
        guard let template = Self.template(path) else { return false }
        return endpoints.allows(configuration: configuration, namespace: namespace, accountID: accountID, path: template)
    }
    static func template(_ path: String) -> String? {
        let mappings = [
            ("^api/merchant/authoring/player/[1-9][0-9]{0,17}/game$", "api/merchant/authoring/player/{merchantId}/game"),
            ("^api/merchant/authoring/player/[1-9][0-9]{0,17}/requests/[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$", "api/merchant/authoring/player/{merchantId}/requests/{requestId}")
        ]
        return mappings.first(where: { path.range(of: $0.0, options: .regularExpression) != nil })?.1
    }
    // Original published projection whitelist; no authoring models are imported.
    static let publicFactKeys: Set<String> = ["store_knowledge", "service_information", "canonical_plot", "allowed_variables", "approved_branches", "accessibility_alternative", "offline_alternative", "fail_exit", "business_segment", "duration_minutes", "headcount", "noise_limit", "photo_limit"]
}

/// Only the existing player GET shapes, extracted from MerchantAuthoringTransportRoute.
/// Recognizing a shape does not authorize dispatch; the host must recheck the grant.
public struct MerchantGamePlayerReadRoute: Equatable {
    public let path: String
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              !request.httpShouldHandleCookies, request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              let url = request.url, url.query == nil, url.fragment == nil else { return nil }
        let prefix = baseURL.appendingPathComponent("api/merchant/authoring/player").absoluteString + "/"
        guard url.absoluteString.hasPrefix(prefix) else { return nil }
        let path = "api/merchant/authoring/player/" + String(url.absoluteString.dropFirst(prefix.count))
        guard MerchantGamePlayerReadGrant.template(path) != nil,
              baseURL.appendingPathComponent(path).absoluteString == url.absoluteString else { return nil }
        self.path = path
    }
}
