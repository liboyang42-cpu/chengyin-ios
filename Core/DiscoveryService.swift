import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Explicitly configured and transport-injected read-only discovery requests.
public struct DiscoveryService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration
        self.transport = transport
    }
    public func banners(token: String? = nil) async throws -> [DiscoveryBanner] {
        let data = try await post("api/common/banner", fields: ["showType": "1", "linkType": "0"], token: token)
        return try decode(DiscoveryArrayEnvelope<DiscoveryBanner>.self, data).data
    }
    public func categories(type: Int? = nil, token: String? = nil) async throws -> [DiscoveryCategory] {
        var fields = ["parentid": "0"] // Required by the retained contract, even for root categories.
        if let type { fields["type"] = String(type) }
        let data = try await post("api/category/list", fields: fields, token: token)
        return try decode(DiscoveryArrayEnvelope<DiscoveryCategory>.self, data).data
    }
    public func templateMetadataDictionary(kind: TemplateMetadataKind, token: String? = nil) async throws -> [TemplateMetadataOption] {
        let data = try await post("api/common/dict", fields: ["dictType": kind.rawValue], token: token, templateMetadata: true)
        return try decode(TemplateMetadataEnvelope.self, data).data
    }
    public func templateHome(token: String? = nil) async throws -> DiscoveryTemplateHome {
        let data = try await post("api/template/homeData", fields: nil, token: token)
        return try decode(DiscoveryValueEnvelope<DiscoveryTemplateHome>.self, data).data
    }
    public func playTemplates(keyword: String? = nil, packType: DiscoveryPackType? = nil,
                              token: String? = nil) async throws -> [DiscoveryPlayTemplate] {
        // Intentionally no category filter: Flutter documents categoryId/category_id mismatch.
        var fields: [String: String] = [:]
        if let keyword, !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields["keyword"] = keyword }
        if let packType { fields["pack_type"] = String(packType.rawValue) }
        let data = try await post("api/template/list", fields: fields, token: token)
        return try decode(DiscoveryRowsEnvelope<DiscoveryPlayTemplate>.self, data).rows
    }
    public func topicTemplates(token: String? = nil) async throws -> [DiscoveryTopicTemplate] {
        let data = try await post("api/template/topic-template/list", fields: nil, token: token)
        return try decode(DiscoveryRowsEnvelope<DiscoveryTopicTemplate>.self, data).rows
    }
    public func publicTopicTemplate(id: Int, token: String? = nil) async throws -> PublicTopicTemplateDetail {
        guard id > 0 else { throw APIError.invalidRequest }
        let data = try await post("api/template/topic-template/info", fields: ["id": String(id)], token: token, templateDetail: true)
        let detail = try decode(DiscoveryValueEnvelope<PublicTopicTemplateDetail>.self, data).data
        guard detail.id == id else { throw APIError.malformedResponse }
        return detail
    }
    public func playTemplate(id: Int, token: String? = nil) async throws -> DiscoveryPlayTemplate {
        guard id > 0 else { throw APIError.invalidRequest }
        let data = try await post("api/template/info", fields: ["id": String(id)], token: token, templateDetail: true)
        let detail = try decode(DiscoveryValueEnvelope<DiscoveryPlayTemplate>.self, data).data
        guard detail.id == id else { throw APIError.malformedResponse }
        return detail
    }
    private func post(_ path: String, fields: [String: String]?, token: String?,
                      templateDetail: Bool = false, templateMetadata: Bool = false) async throws -> Data {
        var request = try AuthRequestBuilder.makeFormRequest(
            url: configuration.baseURL.appendingPathComponent(path), fields: fields ?? [:], token: token)
        if fields == nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }
        let (data, status) = try await transport.send(request)
        // Check gateway status and envelope code before payload decoding, including detail refusals.
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        if templateMetadata {
            let status = try decode(TemplateMetadataStatusEnvelope.self, data)
            if status.code == 401 { throw APIError.unauthorized }
            guard status.code == 200 else { throw APIError.businessCode(status.code) }
            return data
        }
        let envelope = try decode(DiscoveryStatusEnvelope.self, data)
        if envelope.code == 401 { throw APIError.unauthorized }
        guard envelope.code == 200 else {
            if templateDetail { throw DiscoveryTemplateUnavailable(message: envelope.msg) }
            throw APIError.businessCode(envelope.code)
        }
        return data
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch let error as APIError { throw error }
        catch { throw APIError.malformedResponse }
    }
}

private struct DiscoveryStatusEnvelope: Decodable {
    let code: Int
    let msg: String?
    enum CodingKeys: String, CodingKey { case code, msg }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decode(Int.self, forKey: .code)
        // Auth precedence must not depend on an optional server message being well-formed.
        msg = try? c.decode(String.self, forKey: .msg)
    }
}
private struct DiscoveryValueEnvelope<T: Decodable>: Decodable { let data: T }
private struct DiscoveryArrayEnvelope<T: Decodable>: Decodable {
    let data: [T]
    enum CodingKeys: String, CodingKey { case data }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decodeIfPresent([T].self, forKey: .data) ?? []
    }
}
private struct DiscoveryRowsEnvelope<T: Decodable>: Decodable {
    let rows: [T]
    enum CodingKeys: String, CodingKey { case data }
    private struct Page: Decodable { let rows: [T]? }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.contains(.data), try !c.decodeNil(forKey: .data) else { rows = []; return }
        if let list = try? c.decode([T].self, forKey: .data) { rows = list; return }
        rows = try c.decode(Page.self, forKey: .data).rows ?? []
    }
}
