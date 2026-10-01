import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct AuthRequestBuilder {
    public let configuration: APIConfiguration
    public init(configuration: APIConfiguration) { self.configuration = configuration }

    /// Existing Flutter AuthApi uses multipart FormData, and a raw Authorization token.
    public func make(_ endpoint: AuthEndpoint, fields: [String: String] = [:],
                     token: String? = nil, boundary: String = UUID().uuidString) throws -> URLRequest {
        guard !boundary.isEmpty, boundary.count <= 70,
              boundary.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }),
              fields.keys.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") } }),
              fields.values.allSatisfy({ !$0.contains(boundary) }) else { throw APIError.invalidRequest }
        if let token, token.isEmpty || token.contains("\r") || token.contains("\n") {
            throw APIError.invalidRequest
        }
        var request = URLRequest(url: configuration.url(for: endpoint))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue(token, forHTTPHeaderField: "Authorization") }
        // userInfo has no body in the source contract.
        if endpoint != .userInfo {
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var body = ""
            for key in fields.keys.sorted() {
                body += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(key)\"\r\n\r\n\(fields[key]!)\r\n"
            }
            body += "--\(boundary)--\r\n"
            request.httpBody = Data(body.utf8)
        }
        return request
    }
}
