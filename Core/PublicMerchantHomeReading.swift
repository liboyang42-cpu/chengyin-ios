import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public protocol PublicMerchantHomeReading {
    var scope: UUID { get }
    var isConfigured: Bool { get }
    var isOfflineExample: Bool { get }
    func home(_ target: PublicMerchantHomeTarget) async throws -> PublicMerchantHome
}
@MainActor public struct DisabledPublicMerchantHomeReader: PublicMerchantHomeReading {
    public let scope = UUID()
    public let isConfigured = false
    public let isOfflineExample = false
    public init() {}
    public func home(_ target: PublicMerchantHomeTarget) async throws -> PublicMerchantHome { throw PublicMerchantHomeFailure.notConfigured }
}
/// Explicit transport injection only; never constructs a URLSession or loads media.
@MainActor public struct PublicMerchantHomeHTTPReader: PublicMerchantHomeReading {
    public let scope: UUID
    public let isConfigured = true
    public let isOfflineExample: Bool
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport, scope: UUID = UUID(), isOfflineExample: Bool = false) {
        self.configuration = configuration; self.transport = transport; self.scope = scope; self.isOfflineExample = isOfflineExample
    }
    public func home(_ target: PublicMerchantHomeTarget) async throws -> PublicMerchantHome {
        do {
            try Task.checkCancellation()
            var request = URLRequest(url: configuration.baseURL.appendingPathComponent("api/merchant/public-home"))
            request.httpMethod = "POST"
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpShouldHandleCookies = false
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: target.fields)
            let (data, status) = try await transport.send(request)
            try Task.checkCancellation()
            guard (200..<300).contains(status) else { throw PublicMerchantHomeFailure.retryable }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.code == 200 else {
                // Exact source predicate; HTTP 404/403 and unrelated messages do not prove invisibility.
                if envelope.msg == "商家不存在或未开放" { throw PublicMerchantHomeFailure.unavailable }
                throw PublicMerchantHomeFailure.retryable
            }
            let home = try envelope.home ?? JSONDecoder().decode(PublicMerchantHome.self, from: Data("{}".utf8))
            // Never substitute requested IDs for IDs missing from the returned public profile.
            return home
        } catch is CancellationError { throw CancellationError() }
        catch let failure as PublicMerchantHomeFailure { throw failure }
        catch { throw PublicMerchantHomeFailure.retryable }
    }
    private struct Envelope: Decodable {
        let code: Int
        let msg: String?
        let home: PublicMerchantHome?
        enum CodingKeys: String, CodingKey { case code, msg, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(Int.self, forKey: .code)
            msg = try c.decodeIfPresent(String.self, forKey: .msg)
            home = code == 200 ? try c.decodeIfPresent(PublicMerchantHome.self, forKey: .data) : nil
        }
    }
}
