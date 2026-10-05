import Foundation

/// Only the two canonical read shapes emitted by WorkshopOwnedService. An approved
/// owner never authorizes an owner override, purchase, claim, package or installation.
struct WorkshopOwnedReadRoute {
    init?(request: URLRequest, baseURL: URL) {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded; charset=utf-8",
              let body = request.httpBody,
              request.value(forHTTPHeaderField: "Content-Length") == String(body.count),
              request.cachePolicy == .reloadIgnoringLocalCacheData,
              request.value(forHTTPHeaderField: "Cache-Control") == "no-store",
              request.value(forHTTPHeaderField: "Pragma") == "no-cache" else { return nil }
        switch url.absoluteString {
        case baseURL.appendingPathComponent("api/workshop/owned/list").absoluteString:
            guard body.isEmpty else { return nil }
        case baseURL.appendingPathComponent("api/workshop/owned/detail").absoluteString:
            guard let text = String(data: body, encoding: .utf8), text.hasPrefix("claim_id="),
                  WorkshopOwnedWire.identifier(String(text.dropFirst("claim_id=".count))) else { return nil }
        default: return nil
        }
    }
}
