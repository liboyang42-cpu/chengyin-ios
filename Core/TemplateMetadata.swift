import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only the two dictionaries used by the basic template metadata selectors.
public enum TemplateMetadataKind: String, CaseIterable, Hashable {
    case players = "app_template_players"
    case duration = "app_template_duration"
}

/// Exact server values and labels. Array order and duplicate rows remain meaningful.
public struct TemplateMetadataOption: Decodable, Equatable {
    public let value: String
    public let label: String
    public init(value: String, label: String) {
        self.value = value; self.label = label
    }
    enum CodingKeys: String, CodingKey {
        case value = "dictValue", label = "dictLabel"
    }
    /// Project only a supported signed 32-bit integer, without alternate spellings;
    /// reading an unsupported option must never rewrite an existing draft value.
    public var losslessDurationMinutes: Int? {
        guard let minutes = Int32(value), String(minutes) == value else { return nil }
        return Int(minutes)
    }
}

/// A required array distinguishes a genuine empty dictionary from malformed data.
struct TemplateMetadataEnvelope: Decodable {
    let data: [TemplateMetadataOption]
}

/// Metadata alone accepts the server's numeric or canonical string status codes.
/// Decoding status separately keeps authorization precedence independent of rows.
struct TemplateMetadataStatusEnvelope: Decodable {
    let code: Int
    enum CodingKeys: String, CodingKey { case code }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let integer = try? container.decode(Int.self, forKey: .code) {
            code = integer
        } else {
            let text = try container.decode(String.self, forKey: .code)
            guard let integer = Int(text), String(integer) == text else { throw APIError.malformedResponse }
            code = integer
        }
    }
}

/// Exact canonical native request shapes; this value grants no read permission.
public struct TemplateMetadataReadRoute {
    public let kind: TemplateMetadataKind
    public init?(request: URLRequest, baseURL: URL) {
        let expected = baseURL.appendingPathComponent("api/common/dict")
        guard let url = request.url,
              Data(url.absoluteString.utf8) == Data(expected.absoluteString.utf8),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let body = request.httpBody else { return nil }
        let prefix = "multipart/form-data; boundary="
        guard let contentType = request.value(forHTTPHeaderField: "Content-Type"),
              contentType.hasPrefix(prefix) else { return nil }
        let boundary = String(contentType.dropFirst(prefix.count))
        guard (1...70).contains(boundary.utf8.count),
              boundary.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }) else { return nil }
        for candidate in TemplateMetadataKind.allCases {
            guard let canonical = try? AuthRequestBuilder.makeFormRequest(url: expected,
                fields: ["dictType": candidate.rawValue], token: nil, boundary: boundary) else { continue }
            if canonical.httpBody == body { kind = candidate; return }
        }
        return nil
    }
}
