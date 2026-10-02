import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol SquareReportOfflineTransport: HTTPTransport {}
public enum SquareReportMutationGrant: Equatable { case disabled, reviewedInjection }

/// All production reads/writes default OFF. The offline initializer accepts only
/// a canned transport marker. No UI selection can grant live mutation authority.
public struct SquareReportService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public let readsEnabled: Bool
    public let writesEnabled: Bool
    public let synthetic: Bool
    public init(configuration: APIConfiguration, transport: any HTTPTransport, readsEnabled: Bool = false,
                grant: SquareReportMutationGrant = .disabled) {
        self.configuration = configuration; self.transport = transport; self.readsEnabled = readsEnabled
        writesEnabled = grant == .reviewedInjection; synthetic = false
    }
    public init(offlineConfiguration: APIConfiguration, transport: any SquareReportOfflineTransport) {
        configuration = offlineConfiguration; self.transport = transport
        readsEnabled = true; writesEnabled = true; synthetic = true
    }
    func request(path: String, method: String = "GET", token: String, body: [String: SquareGovernanceJSON]? = nil) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw SquareReportFailure.signedOut }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = method; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpShouldHandleCookies = false
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            request.httpBody = try encoder.encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
    private func read(path: String, token: String, check: () throws -> Void) async throws -> SquareGovernanceJSON {
        guard readsEnabled else { throw SquareReportFailure.disabled }
        let request = try request(path: path, token: token)
        try Task.checkCancellation(); try check()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation(); try check()
        return try Self.decode(data, status: status, mutation: false)
    }
    public func policy(token: String, check: () throws -> Void) async throws -> SquareReportPolicy {
        let raw = try await read(path: "api/v1/community/capabilities", token: token, check: check)
        return try .init(raw: raw["reporting"])
    }
    public func receipt(id: Int, token: String, check: () throws -> Void) async throws -> SquareReportReceipt {
        guard id > 0 else { throw SquareReportFailure.invalid }
        let raw = try await read(path: "api/community-trust/reports/\(id)", token: token, check: check)
        return try .init(raw: raw)
    }
    func command(_ review: SquareReportReview, token: String) throws -> URLRequest {
        // The server requires a nonempty description and rejects all attachments.
        // Policy version and code are inseparable parts of the reviewed intent.
        try request(path: "api/v1/community/reports", method: "POST", token: token, body: [
            "targetType": .string(review.snapshot.target.type), "targetId": .integer(review.snapshot.target.id),
            "reasonCode": .string(review.reason.id), "policyVersion": .string(review.snapshot.policy.version),
            "description": .string(review.description), "evidenceAssetIds": .array([]), "requestId": .string(review.requestID)
        ])
    }
    func submit(_ review: SquareReportReview, token: String, check: () throws -> Void) async throws -> SquareReportReceipt {
        guard writesEnabled else { throw SquareReportFailure.disabled }
        let request = try command(review, token: token)
        try Task.checkCancellation(); try check()
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) }
        catch { throw SquareReportFailure.unknown }
        do { try Task.checkCancellation(); try check() } catch { throw SquareReportFailure.unknown }
        let raw = try Self.decode(data, status: status, mutation: true)
        guard let receipt = try? SquareReportReceipt(raw: raw), receipt.matches(review) else { throw SquareReportFailure.unknown }
        return receipt
    }
    static func decode(_ data: Data, status: Int, mutation: Bool) throws -> SquareGovernanceJSON {
        guard let raw = try? JSONDecoder().decode(SquareGovernanceJSON.self, from: data), let code = raw["code"].int else {
            throw mutation ? SquareReportFailure.unknown : .malformed
        }
        if status == 401 || code == 401 { throw SquareReportFailure.signedOut }
        guard (200..<300).contains(status) else { throw mutation ? SquareReportFailure.unknown : .malformed }
        guard code == 200 else { throw SquareReportFailure.rejected(code) }
        return raw["data"]
    }
}
