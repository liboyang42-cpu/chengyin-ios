import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Conform only for canned offline transports. Production has no enabling flag.
public protocol ClubOwnerRefundOfflineTransport: HTTPTransport {}
public struct ClubOwnerRefundService {
    private let configuration: APIConfiguration
    private let offline: (any ClubOwnerRefundOfflineTransport)?
    public var canDispatchOffline: Bool { offline != nil }
    public init(configuration: APIConfiguration) { self.configuration = configuration; offline = nil }
    public init(offlineConfiguration: APIConfiguration, offlineTransport: any ClubOwnerRefundOfflineTransport) { configuration = offlineConfiguration; offline = offlineTransport }
    public func request(registrationID: Int, token: String) throws -> URLRequest {
        guard registrationID > 0, AuthRequestBuilder.isValidToken(token) else { throw ClubOwnerRefundFailure.invalid }
        return try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/registration/cancel-by-owner"), fields: ["id": String(registrationID)], token: token)
    }
    public func cancel(registrationID: Int, token: String, check: () throws -> Void) async throws -> ClubOwnerRefundReceipt {
        // Must fail before request creation, transport, or token use in production.
        guard let offline else { throw ClubOwnerRefundFailure.disabled }
        let request = try request(registrationID: registrationID, token: token)
        try check(); try Task.checkCancellation()
        let result: (Data, Int)
        do { result = try await offline.send(request) }
        catch { throw ClubOwnerRefundFailure.unknown }
        do { try check(); try Task.checkCancellation() } catch { throw ClubOwnerRefundFailure.unknown }
        let envelope = try? JSONDecoder().decode(ClubGovernanceValue.self, from: result.0)
        let code = envelope?["code"].int
        // No dispatched HTTP/business failure is source-proven to mean “not executed”.
        // This includes 408/499, authentication replies, 5xx and malformed envelopes.
        let message = envelope?["msg"].string.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500)) }
        guard (200..<300).contains(result.1), code == 200, let envelope else {
            throw ClubOwnerRefundFailure.unconfirmed(message: message)
        }
        do { return try ClubOwnerRefundReceipt(value: envelope["data"], message: message, registrationID: registrationID) }
        catch { throw ClubOwnerRefundFailure.unconfirmed(message: message) }
    }
}
@MainActor public protocol ClubOwnerRefundAccess: AnyObject {
    var identity: ClubReadIdentity? { get }
    var namespace: String { get }
    var canDispatchOffline: Bool { get }
    var canDispatch: Bool { get }
    var authorizationGeneration: UUID? { get }
    func evidence(_ target: ClubOwnerRefundTarget) async throws -> ClubOwnerRefundEvidence
    func send(_ review: ClubOwnerRefundReview) async throws -> ClubOwnerRefundReceipt
}
public extension ClubOwnerRefundAccess {
    var canDispatch: Bool { canDispatchOffline }
    var authorizationGeneration: UUID? { nil }
}
/// Default shipping composition has only a reader. There is no token, transport or write adapter.
@MainActor public final class ClubOwnerRefundReadOnlyAccess: ClubOwnerRefundAccess {
    private let governance: any ClubGovernanceAccess
    public init(governance: any ClubGovernanceAccess) { self.governance = governance }
    public var identity: ClubReadIdentity? { governance.identity }
    public var namespace: String { governance.storageNamespace }
    public let canDispatchOffline = false
    public func evidence(_ target: ClubOwnerRefundTarget) async throws -> ClubOwnerRefundEvidence {
        let snapshot = try await governance.read(.checkin, scope: target.scope, options: [:])
        return try ClubOwnerRefundEvidence(snapshot: snapshot, target: target)
    }
    public func send(_ review: ClubOwnerRefundReview) async throws -> ClubOwnerRefundReceipt { throw ClubOwnerRefundFailure.disabled }
}
