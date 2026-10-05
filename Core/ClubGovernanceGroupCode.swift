import Foundation

/// Ephemeral issuance receipt. No serialization, URL fetching, automatic renewal or
/// redemption. The issue endpoint mutates a short-lived credential and stays gated.
public struct ClubGovernanceGroupCode {
    public let imageURL: URL
    public let code: String
    public let receivedAt: Date
    public let expiresAt: Date
    public init(receipt: ClubGovernanceValue, receivedAt: Date) throws {
        guard let text = receipt["qrcodeUrl"].string, let parts = URLComponents(string: text), parts.scheme == "https", let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil, let url = parts.url,
              let code = receipt["code"].string, !code.isEmpty, let ttl = receipt["ttlMs"].int, ttl > 0 else { throw ClubGovernanceFailure.malformed }
        self.imageURL = url; self.code = code; self.receivedAt = receivedAt; self.expiresAt = receivedAt.addingTimeInterval(Double(ttl) / 1000)
    }
    public func isActive(at now: Date) -> Bool { now >= receivedAt && now < expiresAt }
}

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// No credentials are forwarded to the QR image host. Live media is hard-off.
public struct ClubGovernanceGroupCodeMediaService {
    private let transport: (any HTTPTransport)?
    private let approvedHosts: Set<String>
    public init() { transport = nil; approvedHosts = [] }
    public init(offlineTransport: any ClubGovernanceOfflineTransport, approvedFixtureHosts: Set<String>) {
        transport = offlineTransport; approvedHosts = Set(approvedFixtureHosts.map { $0.lowercased() })
    }
    public func imageBytes(_ code: ClubGovernanceGroupCode, now: Date) async throws -> Data {
        guard let transport else { throw ClubGovernanceFailure.notConfigured }
        guard code.isActive(at: now), let host = code.imageURL.host, approvedHosts.contains(host.lowercased()) else { throw ClubGovernanceFailure.invalidRequest }
        var request = URLRequest(url: code.imageURL); request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, status) = try await transport.send(request)
        guard (200..<300).contains(status), !data.isEmpty, data.count <= 10 * 1024 * 1024 else { throw ClubGovernanceFailure.malformed }
        return data
    }
}
