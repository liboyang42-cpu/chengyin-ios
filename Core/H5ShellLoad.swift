import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Builds the one-time POST into the platform shell. The body is only the nonce.
/// A different host, a non-HTTPS URL, or a main token is not loaded.
public enum H5ShellLoad {
    public static func request(shellURL: URL, launch: H5LaunchDescription) -> URLRequest? {
        guard shellURL.scheme == "https", shellURL.user == nil, shellURL.password == nil,
              let origin = URL(string: launch.parentOrigin),
              origin.scheme == "https", origin.host == shellURL.host, origin.port == shellURL.port else { return nil }
        var request = URLRequest(url: shellURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        guard let nonce = launch.nonce.addingPercentEncoding(withAllowedCharacters: .alphanumerics), !nonce.isEmpty else {
            return nil
        }
        request.httpBody = Data("nonce=\(nonce)".utf8)
        return request
    }

    public static func allowsNavigation(to url: URL, shellURL: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil
            && url.host == shellURL.host && url.port == shellURL.port
    }
}
