import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Defense in depth over the scoped runtime transport: registration/create is shared by
/// activity signup, but this adapter only permits the audited topic ownerType=1 body.
@MainActor public final class TopicSelfPlayRuntimeTransport: HTTPTransport {
    private let baseURL: URL
    private let transport: any HTTPTransport
    public init(baseURL: URL, transport: any HTTPTransport) { self.baseURL = baseURL; self.transport = transport }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        guard Self.validates(request, baseURL: baseURL) else { throw APIError.invalidRequest }
        return try await transport.send(request)
    }
    public static func validates(_ request: URLRequest, baseURL: URL) -> Bool {
        guard request.httpMethod == "POST", let url = request.url, url.query == nil, url.fragment == nil, let data = request.httpBody else { return false }
        let forms = ["api/topic/info-to-user", "api/registration/info", "api/registration/pay/app"]
        if forms.contains(where: { url == baseURL.appendingPathComponent($0) }) {
            guard let text = String(data: data, encoding: .utf8), let items = URLComponents(string: "?" + text)?.queryItems,
                  items.count == 1, items[0].name == "id", let raw = items[0].value, let id = Int(raw), id > 0, raw == String(id) else { return false }
            return true
        }
        guard request.value(forHTTPHeaderField: "Content-Type")?.lowercased().hasPrefix("application/json") == true,
              let body = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: data) else { return false }
        if url == baseURL.appendingPathComponent("api/registration/create") {
            guard Set(body.keys) == ["ownerType", "ownerId", "realName", "phone", "isUsePoint", "payChannel", "requestId"],
                  body["ownerType"]?.integer == 1, body["isUsePoint"]?.integer == 0, body["payChannel"]?.text == "APP",
                  let id = body["ownerId"]?.integer.flatMap(SelfPlayTopicID.init(rawValue:)),
                  let name = body["realName"]?.text, let phone = body["phone"]?.text, let key = body["requestId"]?.text else { return false }
            return (try? TopicSelfPlayIntent(topic: id, realName: name, phone: phone, requestID: key)) != nil
        }
        guard body["docType"]?.text == "activity_host_data_sharing", body["scene"]?.text == "activity_signup" else { return false }
        if url == baseURL.appendingPathComponent("api/compliance/consents/latest") { return Set(body.keys) == ["docType", "scene"] }
        if url == baseURL.appendingPathComponent("api/compliance/consents") {
            return Set(body.keys) == ["docType", "scene", "eventType", "requestId"] && body["eventType"]?.text == "AGREE" && body["requestId"]?.text?.isEmpty == false
        }
        return false
    }
}
