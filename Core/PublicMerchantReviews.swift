import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct PublicMerchantReviewPage: Decodable, Equatable {
    public let mode: String
    public let pageNum: Int
    public let pageSize: Int
    public let total: Int
    public let hasMore: Bool
    public let averageRating: Double?
    public let eligibility: Eligibility
    public let items: [Item]
    public struct Eligibility: Decodable, Equatable {
        public let canCreate: Bool
        public let reasonCode: String
        public let registrationId: Int?
    }
    public struct Item: Decodable, Equatable, Identifiable {
        public let id: Int
        public let rating: Int
        public let content: String?
        public let imageUrls: [String]
        public let authorNickname: String?
        public let authorAvatar: String?
        public let verifiedRedemption: Bool
        public let status: String
        public let merchantReply: String?
        public let repliedAt: String?
        public let createTime: String?
        public let version: Int
        public let canReply: Bool
        public let canReport: Bool
        public let canEditReply: Bool?
    }
    public func validate(page: Int, size: Int) throws {
        guard mode == "public", pageNum == page, pageSize == size, page > 0, size > 0,
              total >= 0, items.count <= size, page <= Int.max / size else { throw PublicMerchantHomeFailure.retryable }
        let loaded = (page - 1) * size + items.count
        guard loaded <= total, hasMore == (loaded < total), averageRating == nil || (1...5).contains(averageRating!),
              eligibility.registrationId == nil || eligibility.registrationId! > 0,
              !eligibility.canCreate || eligibility.registrationId != nil,
              eligibility.canCreate == (eligibility.reasonCode == "ELIGIBLE") else { throw PublicMerchantHomeFailure.retryable }
        for item in items {
            guard item.id > 0, (1...5).contains(item.rating), item.version >= 0,
                  item.status == "VISIBLE", item.imageUrls.count <= 9,
                  !item.canReply || (item.merchantReply ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw PublicMerchantHomeFailure.retryable
            }
            for image in item.imageUrls {
                guard let url = URL(string: image.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", !(url.host ?? "").isEmpty else { throw PublicMerchantHomeFailure.retryable }
            }
        }
    }
}
@MainActor public protocol PublicMerchantReviewReading {
    var scope: UUID { get }
    var isConfigured: Bool { get }
    var isOfflineExample: Bool { get }
    func page(_ target: PublicMerchantReviewTarget, page: Int) async throws -> PublicMerchantReviewPage
}
@MainActor public struct DisabledPublicMerchantReviewReader: PublicMerchantReviewReading {
    public let scope = UUID()
    public let isConfigured = false
    public let isOfflineExample = false
    public init() {}
    public func page(_ target: PublicMerchantReviewTarget, page: Int) async throws -> PublicMerchantReviewPage { throw PublicMerchantHomeFailure.notConfigured }
}
/// Anonymous public read. Owner identity is intentionally absent from the row-scoped query.
/// Authenticated eligibility and public write flows remain the merchant-business owner's integration boundary.
@MainActor public struct PublicMerchantReviewHTTPReader: PublicMerchantReviewReading {
    public let scope: UUID
    public let isConfigured = true
    public let isOfflineExample: Bool
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let session: PublicMerchantReviewSession?
    public init(configuration: APIConfiguration, transport: any HTTPTransport, scope: UUID = UUID(), isOfflineExample: Bool = false, session: PublicMerchantReviewSession? = nil) {
        self.configuration = configuration; self.transport = transport; self.scope = scope; self.isOfflineExample = isOfflineExample; self.session = session
    }
    public func page(_ target: PublicMerchantReviewTarget, page: Int) async throws -> PublicMerchantReviewPage {
        guard page > 0, page <= Int.max / 20 else { throw PublicMerchantHomeFailure.invalid }
        if let session, session.realm != configuration.baseURL.absoluteString { throw PublicMerchantHomeFailure.invalid }
        do {
            try Task.checkCancellation()
            var components = URLComponents(url: configuration.baseURL.appendingPathComponent("api/merchant/reviews/public"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "merchantRowId", value: String(target.merchantRowID.rawValue)),
                                     URLQueryItem(name: "pageNum", value: String(page)), URLQueryItem(name: "pageSize", value: "20")]
            guard let url = components.url else { throw PublicMerchantHomeFailure.invalid }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"; request.timeoutInterval = 20; request.httpShouldHandleCookies = false
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let session { request.setValue(session.token, forHTTPHeaderField: "Authorization") }
            let (data, status) = try await transport.send(request)
            try Task.checkCancellation()
            guard (200..<300).contains(status) else { throw PublicMerchantHomeFailure.retryable }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.code == 200, let value = envelope.data else { throw PublicMerchantHomeFailure.retryable }
            try value.validate(page: page, size: 20)
            return value
        } catch is CancellationError { throw CancellationError() }
        catch let error as PublicMerchantHomeFailure { throw error }
        catch { throw PublicMerchantHomeFailure.retryable }
    }
    private struct Envelope: Decodable {
        let code: Int
        let data: PublicMerchantReviewPage?
        enum CodingKeys: String, CodingKey { case code, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Int.self, forKey: .code)
            data = code == 200 ? try c.decode(PublicMerchantReviewPage.self, forKey: .data) : nil
        }
    }
}
