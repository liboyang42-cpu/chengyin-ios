import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact two list requests emitted by the existing ticket-wallet service. This is not
/// an endpoint-prefix grant: order lists, details, pagination and writes are excluded.
public enum TicketWalletListReadRoute: Int, Equatable, CaseIterable {
    case route = 1, activity = 2
    public init?(request: URLRequest, baseURL: URL) {
        guard baseURL.scheme == "https", baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil,
              let url = request.url, url.query == nil, url.fragment == nil,
              url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent("api/registration/list").absoluteString.utf8),
              request.httpMethod == "POST", request.httpBodyStream == nil,
              let body = request.httpBody, body.count <= 512,
              let text = String(data: body, encoding: .utf8),
              let type = request.value(forHTTPHeaderField: "Content-Type"),
              type.hasPrefix("multipart/form-data; boundary=") else { return nil }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        guard !boundary.isEmpty, boundary.count <= 70,
              boundary.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\"owner_type\"\r\n\r\n"
        let suffix = "\r\n--\(boundary)--\r\n"
        guard text.hasPrefix(prefix), text.hasSuffix(suffix), text.count > prefix.count + suffix.count else { return nil }
        let raw = String(text.dropFirst(prefix.count).dropLast(suffix.count))
        guard raw == "1" || raw == "2", let value = Int(raw),
              let lane = Self(rawValue: value),
              let canonical = try? AuthRequestBuilder.makeFormRequest(url: url,
                fields: ["owner_type": raw], token: nil, boundary: boundary),
              canonical.httpBody == body else { return nil }
        self = lane
    }

    /// Defense in depth before the existing display DTO discards memberId. A successful
    /// mixed/unknown-owner lane is rejected as a whole; no private rows are filtered into
    /// an apparently complete success. HTTP/business/401 failures retain existing meaning.
    public func validateResponse(_ response: (Data, Int), expectedAccountID: Int) throws {
        guard expectedAccountID > 0 else { throw APIError.invalidRequest }
        guard (200..<300).contains(response.1) else { return }
        let envelope: OwnershipEnvelope
        do { envelope = try JSONDecoder().decode(OwnershipEnvelope.self, from: response.0) }
        catch { throw APIError.malformedResponse }
        guard envelope.code == 200 else { return }
        guard envelope.rows.allSatisfy({ $0.id > 0 && $0.memberId == expectedAccountID &&
            $0.memberId > 0 && $0.ownerType == rawValue }) else { throw APIError.malformedResponse }
    }
    private struct OwnedRow: Decodable {
        let id: Int
        let memberId: Int
        let ownerType: Int
    }
    private struct OwnershipPage: Decodable { let rows: [OwnedRow] }
    private struct OwnershipEnvelope: Decodable {
        let code: Int
        let rows: [OwnedRow]
        enum CodingKeys: String, CodingKey { case code, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Int.self, forKey: .code)
            // Do not let an unrelated malformed payload obscure a current 401/business error.
            guard code == 200 else { rows = []; return }
            // Existing wallet semantics define absent/null data as empty, not a network fallback.
            guard c.contains(.data), try !c.decodeNil(forKey: .data) else { rows = []; return }
            if let array = try? c.decode([OwnedRow].self, forKey: .data) { rows = array }
            else { rows = try c.decode(OwnershipPage.self, forKey: .data).rows }
        }
    }
}
