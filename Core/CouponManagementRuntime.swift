import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independently reviewed leases. Authentication and merchant access never manufacture them.
/// Callers must revoke replaced leases; every dispatch also reselects the current lease.
@MainActor @Observable public final class CouponManagementReadApproval {
    public let context: RuntimeDependencyContext
    public let merchantID: Int
    public let endpoints: OperationEndpointApproval
    public let commandProtocol: CouponCommandProtocolApproval?
    public let revision = UUID()
    public let expiresAt: Date
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, merchantID: Int, expiresAt: Date, commandProtocol: CouponCommandProtocolApproval? = nil) throws {
        guard context.market == .china, merchantID > 0, expiresAt > Date(), expiresAt.timeIntervalSinceNow <= 86_400 else { throw APIError.invalidConfiguration }
        guard commandProtocol == nil || commandProtocol?.matches(context, merchantID: merchantID) == true else { throw APIError.invalidConfiguration }
        self.commandProtocol = commandProtocol
        endpoints = try .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID,
            paths: ["api/merchant/access/me", "api/merchant/marketing-home", "api/coupon/mypublishlist"])
        self.context = context; self.merchantID = merchantID; self.expiresAt = expiresAt
    }
    public func revoke() { isRevoked = true }
    public func expireIfNeeded(now: Date = Date()) { if now >= expiresAt { revoke() } }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        !isRevoked && Date() < expiresAt && ContentDraftContextFence.matches(self.context, context) &&
            (commandProtocol == nil || commandProtocol?.matches(context, merchantID: merchantID) == true)
    }
}
@MainActor @Observable public final class CouponManagementWriteApproval {
    public enum Action: String, Hashable, CaseIterable { case publish, stop }
    public let context: RuntimeDependencyContext
    public let merchantID: Int
    public let endpoints: OperationEndpointApproval
    public let actions: Set<Action>
    public let revision = UUID()
    public let expiresAt: Date
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, merchantID: Int, actions: Set<Action>, expiresAt: Date) throws {
        guard context.market == .china, merchantID > 0, !actions.isEmpty, expiresAt > Date(), expiresAt.timeIntervalSinceNow <= 86_400 else { throw APIError.invalidConfiguration }
        endpoints = try .init(baseURL: context.baseURL, namespace: context.session.namespace, accountID: context.session.accountID,
            paths: Set(actions.map { "api/coupon/" + $0.rawValue }))
        self.context = context; self.merchantID = merchantID; self.actions = actions; self.expiresAt = expiresAt
    }
    public func revoke() { isRevoked = true }
    public func expireIfNeeded(now: Date = Date()) { if now >= expiresAt { revoke() } }
    public func matches(_ context: RuntimeDependencyContext, merchantID: Int, path: String) -> Bool {
        let action = Action(rawValue: String(path.split(separator: "/").last ?? ""))
        return !isRevoked && Date() < expiresAt && self.merchantID == merchantID &&
            ContentDraftContextFence.matches(self.context, context) && action.map(actions.contains) == true &&
            ["/api/coupon/publish", "/api/coupon/stop"].contains(path)
    }
}

/// Strict canonical existing read shapes. The list endpoint may maintain expired server status.
public enum CouponManagementReadRoute {
    case access, marketingHome, published
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "POST", request.url?.query == nil, request.url?.fragment == nil,
              request.httpBodyStream == nil, request.value(forHTTPHeaderField: "Accept") == "application/json" else { return nil }
        func exact(_ path: String) -> Bool { request.url?.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(path).absoluteString.utf8) == true }
        if exact("api/merchant/access/me") || exact("api/merchant/marketing-home") {
            guard request.httpBody == nil, request.value(forHTTPHeaderField: "Content-Type") == nil else { return nil }
            self = exact("api/merchant/access/me") ? .access : .marketingHome
            return
        }
        guard exact("api/coupon/mypublishlist"),
              let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix("multipart/form-data; boundary="),
              let body = request.httpBody, body.count <= 16_384,
              let text = String(data: body, encoding: .utf8) else { return nil }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        // Parse only enough to reconstruct and byte-compare the two allowed canonical shapes.
        let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\"keyword\"\r\n\r\n"
        var keyword: String?
        if text.hasPrefix(prefix), let end = text.range(of: "\r\n--\(boundary)", range: text.index(text.startIndex, offsetBy: prefix.count)..<text.endIndex) {
            keyword = String(text[text.index(text.startIndex, offsetBy: prefix.count)..<end.lowerBound])
            guard keyword?.isEmpty == false else { return nil }
        }
        guard let wire = try? CouponManagementContract.published(keyword: keyword).encodedBody(boundary: boundary),
              wire.contentType == type, wire.data == body else { return nil }
        self = .published
    }
}
public struct CouponManagementWire: Codable, Equatable {
    public let contentType: String
    public let data: Data
    public init(request: CouponManagementRequest) throws {
        let encoded = try request.encodedBody(boundary: "CouponNative-" + UUID().uuidString)
        contentType = encoded.contentType; data = encoded.data
    }
}
/// Ordinary send remains read-only. Only the coordinator can mint dispatch authorization.
@MainActor public protocol CouponManagementConfirmedHTTPTransport: HTTPTransport {
    func sendConfirmed(_ request: URLRequest, authorization: CouponManagementDispatchAuthorization) async throws -> (Data, Int)
}
@MainActor protocol CouponManagementReviewedTransport: CouponManagementTransport {
    func permitsAction(_ action: CouponManagementWriteApproval.Action) -> Bool
    func sendReviewed(_ descriptor: CouponManagementRequest, session: CouponManagementSession, authorization: CouponManagementDispatchAuthorization) async throws -> (Data, Int)
}
@MainActor public final class CouponManagementRuntimeTransport: CouponManagementTransport, CouponManagementReviewedTransport {
    public let isSynthetic = false
    private let configuration: APIConfiguration
    private let http: any CouponManagementConfirmedHTTPTransport
    private let credentials: () -> CouponManagementReadCredentials?
    private let actions: Set<CouponManagementWriteApproval.Action>
    private let commandProtocol: CouponCommandProtocolApproval?
    public init(configuration: APIConfiguration, http: any CouponManagementConfirmedHTTPTransport, actions: Set<CouponManagementWriteApproval.Action> = [], commandProtocol: CouponCommandProtocolApproval? = nil, credentials: @escaping () -> CouponManagementReadCredentials?) {
        self.configuration = configuration; self.http = http; self.actions = actions; self.commandProtocol = commandProtocol; self.credentials = credentials
    }
    var canRecoverCommands: Bool { commandProtocol.map { $0.matches($0.context, merchantID: $0.merchantID) } == true && credentials() != nil }
    func prepareCommand(record: CouponManagementPending, session: CouponManagementSession, permission: CouponPublisherPermission) throws -> CouponCommandIdentity? {
        guard commandProtocol != nil else { return nil }
        try requireCommandProtocol(session: session, merchantID: permission.merchantID)
        return try CouponCommandIdentity(record: record, session: session, permission: permission)
    }
    private func requireCommandProtocol(session: CouponManagementSession, merchantID: Int?) throws {
        guard let approval = commandProtocol, let merchantID,
              approval.context.baseURL == configuration.baseURL,
              approval.context.session.accountID == session.accountID, approval.context.session.namespace == session.namespace,
              approval.context.session.epoch == session.epoch,
              approval.matches(approval.context, merchantID: merchantID), credentials()?.session == session else { throw CouponManagementError.unavailable }
    }
    func readCommand(_ record: CouponManagementPending, session: CouponManagementSession, permission: CouponPublisherPermission) async throws -> CouponManagementOutcome {
        guard let command = record.command, let captured = credentials(), captured.session == session else { throw CouponManagementError.unavailable }
        try command.validate(record: record, session: session, permission: permission)
        try requireCommandProtocol(session: session, merchantID: command.merchantID)
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/coupon/command-receipt"),
            fields: ["requestId": command.requestID, "merchantId": String(command.merchantID), "scope": "MERCHANT"], token: captured.token)
        let (data, status) = try await http.send(request)
        try Task.checkCancellation()
        try requireCommandProtocol(session: session, merchantID: command.merchantID)
        guard credentials() == captured else { throw CouponManagementError.changed }
        return CouponCommandReceipt.outcome(data, status: status, record: record)
    }
    func permitsAction(_ action: CouponManagementWriteApproval.Action) -> Bool { actions.contains(action) && credentials() != nil }
    public func send(_ descriptor: CouponManagementRequest, session: CouponManagementSession) async throws -> (Data, Int) {
        guard !descriptor.mutates else { throw CouponManagementError.unavailable }
        return try await CouponManagementHTTPReadTransport(configuration: configuration, http: http, credentials: credentials).send(descriptor, session: session)
    }
    func sendReviewed(_ descriptor: CouponManagementRequest, session: CouponManagementSession, authorization: CouponManagementDispatchAuthorization) async throws -> (Data, Int) {
        guard let captured = credentials(), captured.session == session, authorization.session == session,
              authorization.record.request == descriptor,
              permitsAction(authorization.record.request.path == "/api/coupon/publish" ? .publish : .stop) else { throw CouponManagementError.changed }
        if let command = authorization.record.command {
            try requireCommandProtocol(session: session, merchantID: command.merchantID)
            try command.validate(record: authorization.record, session: session, permission: authorization.permission)
        } else if commandProtocol != nil { throw CouponManagementError.unavailable }
        let request = try authorization.makeRequest(configuration: configuration, credentials: captured)
        let result = try await http.sendConfirmed(request, authorization: authorization)
        if let command = authorization.record.command { try requireCommandProtocol(session: session, merchantID: command.merchantID) }
        guard credentials() == captured, !Task.isCancelled else { throw CouponManagementError.changed }
        return result
    }
}
/// Snapshot fingerprint is local, not a monotonic server authorization version or quota proof.
@MainActor public final class CouponMerchantPublisherAuthorizer: CouponPublisherAuthorizing {
    private let service: MerchantBusinessService
    private let configuration: APIConfiguration
    private let http: any HTTPTransport
    private let commandProtocol: CouponCommandProtocolApproval?
    private let context: RuntimeDependencyContext
    private let merchantID: Int
    private let current: () -> CouponManagementSession?
    public init(configuration: APIConfiguration, http: any HTTPTransport, context: RuntimeDependencyContext, merchantID: Int, commandProtocol: CouponCommandProtocolApproval? = nil, current: @escaping () -> CouponManagementSession?) {
        service = .init(configuration: configuration, readTransport: http)
        self.configuration = configuration; self.http = http; self.commandProtocol = commandProtocol
        self.context = context; self.merchantID = merchantID; self.current = current
    }
    public func freshPermission(session: CouponManagementSession) async throws -> CouponPublisherPermission {
        guard current() == session else { throw CouponManagementError.changed }
        let access = try await service.access(token: context.session.token)
        guard current() == session, !Task.isCancelled else { throw CouponManagementError.changed }
        guard access.merchantID == merchantID, access.permissions.contains("merchant:coupon:manage"),
              ["MERCHANT_OWNER", "MERCHANT_MANAGER", "MERCHANT_MARKETING"].contains(access.role) else { throw CouponManagementError.forbidden }
        var ownerMemberID: Int?
        if let approval = commandProtocol {
            guard approval.matches(context, merchantID: merchantID), access.permissions.contains("merchant:coop:manage") else { throw CouponManagementError.forbidden }
            let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/merchant/coop-profile"), fields: [:], token: context.session.token, includesBody: false)
            let (data, status) = try await http.send(request)
            guard current() == session, !Task.isCancelled, approval.matches(context, merchantID: merchantID) else { throw CouponManagementError.changed }
            ownerMemberID = try CouponCommandOwnerIdentity.decode(data, status: status, merchantID: access.merchantID)
            // Do not accept an owner response across a role/permission or merchant switch.
            let after = try await service.access(token: context.session.token)
            guard after == access, current() == session, !Task.isCancelled, approval.matches(context, merchantID: merchantID) else { throw CouponManagementError.changed }
        }
        let values = [String(access.merchantID), access.role] + access.permissions.sorted() + (ownerMemberID.map { [String($0)] } ?? [])
        let revision = values.map { "\($0.utf8.count):\($0)" }.joined()
        return .init(revision: revision, mayPublish: true, merchantID: merchantID, ownerMemberID: ownerMemberID)
    }
}

@MainActor public enum CouponManagementRuntimeIdentity {
    public static func session(context: RuntimeDependencyContext, viewerRevision: UInt64, read: CouponManagementReadApproval?, write: CouponManagementWriteApproval?) -> CouponManagementSession? {
        let revision = "\(viewerRevision)|\(context.role)|\(read?.revision.uuidString ?? "off")|\(write?.revision.uuidString ?? "off")"
        return try? .init(accountID: context.session.accountID, namespace: context.session.namespace, epoch: context.session.epoch, authorizationRevision: revision)
    }
}
