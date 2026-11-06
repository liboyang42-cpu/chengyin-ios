import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only the two original read operations. Personal scope is the existing empty
/// ProjectEditOwner raw value, not an invented MY scope or merchant identity.
public enum ProjectAuthorInputReadRoute: Equatable {
    case support, template(Int)
    public var path: String {
        switch self { case .support: return NativeRuntimeStructureAuthorInputs.supportPath
        case .template: return NativeRuntimeStructureAuthorInputs.templatePath }
    }
    public var method: String { self == .support ? "GET" : "POST" }
    public var businessRoute: BusinessRuntimeRoute { get throws { try .init(method: method, path: path) } }
    public init?(request: URLRequest, baseURL: URL) {
        guard !request.httpShouldHandleCookies, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              let url = request.url, url.query == nil, url.fragment == nil,
              url.user == nil, url.password == nil else { return nil }
        if url == baseURL.appendingPathComponent(NativeRuntimeStructureAuthorInputs.supportPath) {
            guard request.httpMethod == "GET", request.httpBody == nil else { return nil }; self = .support; return
        }
        guard url == baseURL.appendingPathComponent(NativeRuntimeStructureAuthorInputs.templatePath),
              request.httpMethod == "POST", let body = request.httpBody, body.count <= 1024,
              let type = request.value(forHTTPHeaderField: "Content-Type"),
              type.hasPrefix("multipart/form-data; boundary="), let text = String(data: body, encoding: .utf8) else { return nil }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n"
        let middle = "\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"scope\"\r\n\r\n"
        let suffix = "\r\n--\(boundary)--\r\n"
        guard text.hasPrefix(prefix), text.hasSuffix(suffix), text.count >= prefix.count + suffix.count else { return nil }
        let fields = text.dropFirst(prefix.count).dropLast(suffix.count).components(separatedBy: middle)
        guard fields.count == 2, let id = Int(fields[0]), id > 0, String(id) == fields[0],
              fields[1] == ProjectEditOwner.personal.rawValue,
              let canonical = try? AuthRequestBuilder.makeFormRequest(url: url,
                fields: ["id": fields[0], "scope": ProjectEditOwner.personal.rawValue], token: nil, boundary: boundary),
              canonical.httpBody == body else { return nil }
        self = .template(id)
    }
}
