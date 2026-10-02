import Foundation

/// Two independently loaded own-account domains. Only audited read routes exist here.
/// Inject the app's existing ephemeral/no-redirect transport; there is no default host.
public struct AccountCollectionService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func favorites(pageNumber: Int = 1, pageSize: Int = 10, token: String) async throws -> TopicPage {
        guard pageNumber > 0, (1...100).contains(pageSize) else { throw APIError.invalidRequest }
        let data = try await post("api/topic/like_list", fields: ["pageNum": String(pageNumber), "pageSize": String(pageSize)], token: token)
        let envelope = try decode(FavoritesEnvelope.self, data)
        return TopicPage(rows: envelope.rows, pageNumber: pageNumber, pageSize: pageSize)
    }
    public func coupons(keyword: String? = nil, token: String) async throws -> [AccountCollectionCoupon] {
        var fields: [String: String] = [:]
        if let keyword, !keyword.isEmpty { fields["keyword"] = keyword }
        let data = try await post("api/coupon/myrecvlist", fields: fields, token: token)
        return try decode(CouponsEnvelope.self, data).data
    }
    /// No safe metadata-detail endpoint is present in the source. Reread the owned collection
    /// without a keyword, then select the exact history ID. Never call qr-token to get metadata.
    public func coupon(id: Int, token: String) async throws -> AccountCollectionCoupon {
        guard id > 0 else { throw APIError.invalidRequest }
        let rows = try await coupons(token: token)
        let matches = rows.filter { $0.id == id }
        guard matches.count == 1, let match = matches.first else { throw AccountCollectionReadFailure.unavailable }
        return match
    }
    private func post(_ path: String, fields: [String: String], token: String) async throws -> Data {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: fields, token: token)
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else {
            if let envelope = try? JSONDecoder().decode(StatusEnvelope.self, from: data), let message = envelope.message {
                throw AccountCollectionReadFailure.rejected(code: envelope.code, message: message)
            }
            throw APIError.httpStatus(status)
        }
        let statusEnvelope = try decode(StatusEnvelope.self, data)
        if statusEnvelope.code == 401 { throw APIError.unauthorized }
        guard statusEnvelope.code == 200 else {
            throw AccountCollectionReadFailure.rejected(code: statusEnvelope.code, message: statusEnvelope.message)
        }
        return data
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw APIError.malformedResponse }
    }
    private struct StatusEnvelope: Decodable {
        let code: Int
        let message: String?
        enum CodingKeys: String, CodingKey { case code, msg }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Int.self, forKey: .code)
            message = try? c.decode(String.self, forKey: .msg)
        }
    }
    private struct CouponsEnvelope: Decodable { let data: [AccountCollectionCoupon] }
    private struct FavoritesEnvelope: Decodable {
        let rows: [TopicSummary]
        enum CodingKeys: String, CodingKey { case data }
        struct Page: Decodable { let rows: [TopicSummary] }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let array = try? c.decode([TopicSummary].self, forKey: .data) { rows = array }
            else { rows = try c.decode(Page.self, forKey: .data).rows }
        }
    }
}
