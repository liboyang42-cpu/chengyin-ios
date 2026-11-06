import Foundation

/// Ephemeral original issuance receipt. Never serialized or rendered as raw text.
public struct ClubGovernanceGroupCode {
    public let imageURL: URL
    public let inlinePNG: Data?
    public let code: String
    public let receivedAt: Date
    public let expiresAt: Date
    public let clubID: Int?
    public let activityID: Int?
    public init(receipt: ClubGovernanceValue, receivedAt: Date, expectedClubID: Int? = nil, expectedActivityID: Int? = nil) throws {
        guard let text = receipt["qrcodeUrl"].string, let url = URL(string: text),
              let code = receipt["code"].string, !code.isEmpty, code.utf8.count <= 16_384 else { throw ClubGovernanceFailure.malformed }
        if text.hasPrefix("data:") { inlinePNG = try ClubGroupCodeImage.inlinePNG(text) }
        else {
            guard let parts = URLComponents(string: text), parts.scheme == "https", let host = parts.host,
                  !host.isEmpty, parts.user == nil, parts.password == nil else { throw ClubGovernanceFailure.malformed }
            inlinePNG = nil // Legacy/offline media path only; live issuer supplies inline PNG.
        }
        let ttl: Int
        if receipt["ttlMs"] == .null { ttl = Self.defaultTTLMilliseconds }
        else if let explicit = receipt["ttlMs"].int, explicit > 0, explicit <= Self.defaultTTLMilliseconds { ttl = explicit }
        else { throw ClubGovernanceFailure.malformed }
        let ttlExpiry = receivedAt.addingTimeInterval(Double(ttl) / 1000)
        if receipt["expiresAt"] == .null { expiresAt = ttlExpiry }
        else {
            guard let milliseconds = receipt["expiresAt"].int, milliseconds > 0 else { throw ClubGovernanceFailure.malformed }
            expiresAt = min(ttlExpiry, Date(timeIntervalSince1970: Double(milliseconds) / 1000))
        }
        clubID = receipt["clubId"].int; activityID = receipt["activityId"].int
        guard expiresAt > receivedAt,
              expectedClubID == nil || clubID == expectedClubID,
              expectedActivityID == nil || activityID == expectedActivityID else { throw ClubGovernanceFailure.targetChanged }
        self.imageURL = url; self.code = code; self.receivedAt = receivedAt
    }
    public static let defaultTTLMilliseconds = 300_000
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
        guard code.isActive(at: now) else { throw ClubGovernanceFailure.invalidRequest }
        if let bytes = code.inlinePNG { return bytes }
        guard let transport else { throw ClubGovernanceFailure.notConfigured }
        guard code.isActive(at: now), let host = code.imageURL.host, approvedHosts.contains(host.lowercased()) else { throw ClubGovernanceFailure.invalidRequest }
        var request = URLRequest(url: code.imageURL); request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, status) = try await transport.send(request)
        guard (200..<300).contains(status), !data.isEmpty, data.count <= ClubGroupCodeImage.maximumBytes else { throw ClubGovernanceFailure.malformed }
        try ClubGroupCodeImage.validatePNG(data)
        return data
    }
}
