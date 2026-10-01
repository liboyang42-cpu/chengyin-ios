import Foundation

public enum APIError: Error, Equatable {
    case notConfigured, invalidConfiguration, invalidRequest, malformedResponse
    case unauthorized, httpStatus(Int), businessCode(Int)
}

/// No production default: callers must explicitly supply an approved endpoint.
public struct APIConfiguration {
    public let baseURL: URL
    public init(baseURL: URL) throws {
        guard let parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              parts.scheme == "https", let host = parts.host, !host.isEmpty,
              !host.lowercased().hasSuffix(".invalid"), host.lowercased() != "invalid",
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              !parts.path.split(separator: "/").contains("..") else {
            throw APIError.invalidConfiguration
        }
        self.baseURL = baseURL
    }
    public func url(for endpoint: AuthEndpoint) -> URL {
        baseURL.appendingPathComponent(endpoint.rawValue)
    }
}

public enum AuthEndpoint: String {
    case password = "api/login"
    case wechatApp = "api/login/wechat/app"
    case apple = "api/login/apple"
    case smsSend = "api/sms/send"
    case phone = "api/login/phone"
    case userInfo = "api/userInfo"
    case logout = "api/logout"
    // No refresh or Google/Facebook route is invented without a verified server contract.
}
