import Foundation

/// Only the two canonical read shapes emitted by WorkshopPurchasedService. An approved
/// paid metadata grant never authorizes checkout, a FREE claim, protected content or installation.
struct WorkshopPurchasedReadRoute {
    init?(request: URLRequest, baseURL: URL) {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              request.httpMethod == "POST", request.httpBodyStream == nil, request.value(forHTTPHeaderField: "Transfer-Encoding") == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded; charset=utf-8",
              let body = request.httpBody,
              request.value(forHTTPHeaderField: "Content-Length") == String(body.count),
              request.cachePolicy == .reloadIgnoringLocalCacheData,
              request.value(forHTTPHeaderField: "Cache-Control") == "no-store",
              request.value(forHTTPHeaderField: "Pragma") == "no-cache" else { return nil }
        switch url.absoluteString {
        case baseURL.appendingPathComponent("api/workshop/purchased/list").absoluteString:
            if !body.isEmpty {
                guard let text = String(data: body, encoding: .utf8), text.hasPrefix("before_order_line_id=") else { return nil }
                let raw = String(text.dropFirst("before_order_line_id=".count))
                guard raw.range(of: #"\A[1-9][0-9]{0,18}\z"#, options: .regularExpression) != nil,
                      let value = Int64(raw), value > 0 else { return nil }
            }
        case baseURL.appendingPathComponent("api/workshop/purchased/detail").absoluteString:
            guard let text = String(data: body, encoding: .utf8), text.hasPrefix("license_id="),
                  WorkshopPurchasedWire.license(String(text.dropFirst("license_id=".count))) else { return nil }
        default: return nil
        }
    }
}
