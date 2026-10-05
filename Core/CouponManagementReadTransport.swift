import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Ephemeral credentials supplied by the existing auth owner. Never persisted in a lock or draft.
public struct CouponManagementReadCredentials: Equatable {
    public let session: CouponManagementSession
    let token: String
    public init(session: CouponManagementSession, token: String) throws {
        guard AuthRequestBuilder.isValidToken(token) else { throw CouponManagementError.signedOut }
        self.session = session; self.token = token
    }
}
/// Read-only bridge to the established approved configuration and no-redirect HTTP transport.
/// Even an explicitly enabled coordinator cannot use this transport for mutations.
@MainActor public final class CouponManagementHTTPReadTransport: CouponManagementTransport {
    public let isSynthetic = false
    private let configuration: APIConfiguration
    private let http: any HTTPTransport
    private let credentials: () -> CouponManagementReadCredentials?
    public init(configuration: APIConfiguration, http: any HTTPTransport, credentials: @escaping () -> CouponManagementReadCredentials?) {
        self.configuration = configuration; self.http = http; self.credentials = credentials
    }
    public func send(_ descriptor: CouponManagementRequest, session: CouponManagementSession) async throws -> (Data, Int) {
        guard !descriptor.mutates, descriptor.path == "/api/coupon/mypublishlist", case .multipart(let fields) = descriptor.body,
              fields["scope"] == "MERCHANT", Set(fields.keys).isSubset(of: ["keyword", "scope"]) else { throw CouponManagementError.unavailable }
        guard let captured = credentials(), captured.session == session else { throw CouponManagementError.signedOut }
        try Task.checkCancellation()
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/coupon/mypublishlist"), fields: fields, token: captured.token)
        let response = try await http.send(request)
        try Task.checkCancellation()
        guard credentials() == captured else { throw CouponManagementError.changed }
        return response
    }
}

/// Exact dormant source write adapter. No host wires its default-off grant in this delivery.
/// Tests inject fake HTTPTransport. A second adapter-level grant is required for coordination.
@MainActor public final class CouponManagementHTTPDormantTransport: CouponManagementTransport {
    public let isSynthetic = false
    private let configuration: APIConfiguration
    private let http: any HTTPTransport
    private let credentials: () -> CouponManagementReadCredentials?
    private let dormantWritesEnabled: Bool
    public init(configuration: APIConfiguration, http: any HTTPTransport, dormantWritesEnabled: Bool = false, credentials: @escaping () -> CouponManagementReadCredentials?) {
        self.configuration = configuration; self.http = http; self.dormantWritesEnabled = dormantWritesEnabled; self.credentials = credentials
    }
    public func send(_ descriptor: CouponManagementRequest, session: CouponManagementSession) async throws -> (Data, Int) {
        guard let captured = credentials(), captured.session == session else { throw CouponManagementError.signedOut }
        if descriptor.mutates {
            guard dormantWritesEnabled else { throw CouponManagementError.unavailable }
            switch (descriptor.path, descriptor.body) {
            case ("/api/coupon/publish", .json(let data)):
                guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      Set(value.keys).isSubset(of: ["scope", "name", "description", "startTime", "endTime", "publishCount", "couponType"]),
                      value["scope"] as? String == "MERCHANT",
                      let name = value["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      let count = value["publishCount"] as? Int, count > 0,
                      let type = value["couponType"] as? Int, (0...3).contains(type),
                      let start = value["startTime"] as? String, let end = value["endTime"] as? String,
                      let startDate = CouponValidityTime.parse(start), let endDate = CouponValidityTime.parse(end), endDate > startDate,
                      value["description"] == nil || value["description"] is String else { throw CouponManagementError.invalid }
            case ("/api/coupon/stop", .multipart(let fields)):
                guard let raw = fields["couponId"], let id = Int(raw), id > 0,
                      fields == ["couponId": String(id), "scope": "MERCHANT"] else { throw CouponManagementError.invalid }
            default: throw CouponManagementError.unavailable
            }
        } else {
            guard descriptor.path == "/api/coupon/mypublishlist", case .multipart(let fields) = descriptor.body,
                  fields["scope"] == "MERCHANT", Set(fields.keys).isSubset(of: ["keyword", "scope"]) else { throw CouponManagementError.unavailable }
        }
        try Task.checkCancellation()
        let payload = try descriptor.encodedBody(boundary: "CouponNative-" + UUID().uuidString)
        let path = String(descriptor.path.dropFirst())
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: captured.token)
        request.setValue(payload.contentType, forHTTPHeaderField: "Content-Type"); request.httpBody = payload.data
        let response = try await http.send(request)
        try Task.checkCancellation()
        guard credentials() == captured else { throw CouponManagementError.changed }
        return response
    }
}

/// Host approval cannot be reused across an account, deployment, namespace or endpoint.
public final class CouponManagementApprovedReadTransport: HTTPTransport {
    private let configuration: APIConfiguration
    private let approval: OperationEndpointApproval
    private let transport: any HTTPTransport
    private let currentSession: @MainActor () -> CouponManagementSession?
    public init(configuration: APIConfiguration, approval: OperationEndpointApproval, transport: any HTTPTransport, currentSession: @escaping @MainActor () -> CouponManagementSession?) {
        self.configuration = configuration; self.approval = approval; self.transport = transport; self.currentSession = currentSession
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let path = "api/coupon/mypublishlist"
        guard request.httpMethod == "POST", request.url == configuration.baseURL.appendingPathComponent(path),
              let session = await currentSession(),
              approval.allows(configuration: configuration, namespace: session.namespace, accountID: session.accountID, path: path) else { throw CouponManagementError.unavailable }
        let result = try await transport.send(request)
        guard await currentSession() == session else { throw CouponManagementError.changed }
        return result
    }
}
