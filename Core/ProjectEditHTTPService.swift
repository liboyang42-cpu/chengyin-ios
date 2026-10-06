import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ProjectEditCredentials: Equatable {
    public let session: ProjectEditSession
    fileprivate let token: String
    public init(session: ProjectEditSession, token: String) throws {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.session = session; self.token = token
    }
}
/// Legacy Flutter routes plus source-backed conditional mini-editor V2 story routes. Unknown submissions are never retried or reconciled by
/// a guessed endpoint. The local UUID is only for review/persistence, never sent as idempotency.
@MainActor public final class ProjectEditHTTPService: ProjectEditServing {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let owner: ProjectEditOwner
    private let approval: OperationEndpointApproval?
    private let store: ProjectEditLocalStore?
    private let currentCredentials: () -> ProjectEditCredentials?
    public var authority: ProjectEditServiceAuthority { approval == nil || store == nil ? .readOnly : .approved }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, owner: ProjectEditOwner,
                approval: OperationEndpointApproval? = nil, store: ProjectEditLocalStore? = nil, currentCredentials: @escaping () -> ProjectEditCredentials?) {
        self.configuration = configuration; self.transport = transport; self.owner = owner
        self.approval = approval; self.store = store; self.currentCredentials = currentCredentials
    }
    private func check(_ credentials: ProjectEditCredentials) throws {
        try Task.checkCancellation()
        guard currentCredentials() == credentials else { throw ProjectEditError.changedSession }
    }
    public func preflight(topicID: Int?, session: ProjectEditSession) async throws -> ProjectEditPreflight {
        guard let credentials = currentCredentials(), credentials.session == session else { throw ProjectEditError.changedSession }
        try check(credentials)
        if let topicID {
            guard topicID > 0 else { throw ProjectEditError.invalidContract }
            let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/topic/edit-detail"), fields: ["id": String(topicID), "scope": owner.rawValue], token: credentials.token)
            let (data, status) = try await transport.send(request); try check(credentials)
            try Self.validateRead(data, status: status)
            let snapshot = try ProjectEditContract.decodeEditDetail(data, expectedTopicID: topicID, owner: owner)
            return .init(capability: .init(canProPublish: false, remaining: nil), snapshot: snapshot)
        }
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: "api/publish/home", body: Data("{}".utf8), token: credentials.token)
        let (data, status) = try await transport.send(request); try check(credentials)
        try Self.validateRead(data, status: status)
        let envelope = try OperationAdapterHTTP.envelope(data)
        guard let body = envelope["data"]?.object else { throw ProjectEditError.invalidContract }
        let permission = body["permission"]?.object ?? [:], quota = body["quota"]?.object ?? [:]
        // Source absent permission defaults to allowed; deployment approval remains independent.
        let canProPublish = permission["canProPublish"] != .bool(false)
        let remaining = quota["themesRemaining"]?.integer
        if let raw = quota["themesRemaining"], raw != .null, remaining == nil { throw ProjectEditError.invalidContract }
        return .init(capability: .init(canProPublish: canProPublish, remaining: remaining), snapshot: nil)
    }
    private static func validateRead(_ data: Data, status: Int) throws {
        let envelope = try? OperationAdapterHTTP.envelope(data)
        if status == 401 || envelope?["code"]?.integer == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status), envelope?["code"]?.integer == 200 else { throw ProjectEditError.invalidContract }
    }
    public func submit(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome {
        // An already-started request stays unknown even if a later version selects a different path.
        if operation.ownerKey == session.ownerKey, let store,
           let persisted = try? store.pending(session: session, identity: operation.identity),
           persisted.operationID == operation.operationID, persisted.dispatchStarted == true { return .unknown }
        guard let path = try? ProjectEditStoryContract.path(payload: operation.payload, baseline: operation.baseline) else { return .notSent }
        guard let approval, let store, approval.allows(configuration: configuration, namespace: session.storageNamespace, accountID: session.accountID, path: path),
              let credentials = currentCredentials(), credentials.session == session,
              operation.ownerKey == session.ownerKey, operation.payload["scope"] == .string(owner.rawValue) else { return .notSent }
        let request: URLRequest
        do {
            try check(credentials)
            guard let persisted = try store.pending(session: session, identity: operation.identity), persisted.operationID == operation.operationID else { return .notSent }
            if persisted.dispatchStarted == true { return .unknown }
            guard persisted == operation else { return .notSent }
            let fresh = try await preflight(topicID: operation.identity.topicID, session: session)
            try check(credentials)
            if operation.identity.topicID == nil {
                guard fresh.capability.allowsCreate else { return .notSent }
            } else {
                guard let baseline = operation.baseline, fresh.snapshot == baseline else { return .notSent }
            }
            if let id = operation.identity.topicID {
                guard operation.payload["id"]?.integer == id, operation.payload["publishToCreative"] == nil || operation.payload["publishToCreative"] == .number(0) else { return .notSent }
            } else if operation.payload["id"] != nil { return .notSent }
            try ProjectEditStoryContract.validatePayload(operation.payload, baseline: operation.baseline)
            request = try OperationAdapterHTTP.json(configuration: configuration, path: path, body: JSONEncoder().encode(operation.payload), token: credentials.token)
            try check(credentials)
            guard try store.pending(session: session, identity: operation.identity) == operation else { return .unknown }
            var dispatched = operation; dispatched.dispatchStarted = true
            try store.savePending(dispatched, session: session)
        } catch { return .notSent }
        do {
            let (data, status) = try await transport.send(request)
            try check(credentials)
            return Self.decodeAcknowledgment(data, status: status, operation: operation)
        } catch { return .unknown }
    }
    static func decodeAcknowledgment(_ data: Data, status: Int, operation: ProjectEditPending) -> ProjectEditWriteOutcome {
        let envelope = try? OperationAdapterHTTP.envelope(data)
        if status == 401 || status == 403 { return .rejected }
        guard (200..<300).contains(status), let code = envelope?["code"]?.integer else { return .unknown }
        guard code == 200 else { return .rejected }
        guard let path = try? ProjectEditStoryContract.path(payload: operation.payload, baseline: operation.baseline) else { return .unknown }
        if path == ProjectEditStoryContract.createPath || path == ProjectEditStoryContract.updatePath {
            guard let acknowledgment = try? ProjectEditBundleAcknowledgment.decode(envelope?["data"], expectedTopicID: operation.identity.topicID) else { return .unknown }
            return .bundleAcknowledged(operationID: operation.operationID, acknowledgment: acknowledgment)
        }
        let topicID: Int
        if let existing = operation.identity.topicID { topicID = existing }
        else { guard let created = OperationAdapterHTTP.positiveID(envelope?["data"]) else { return .unknown }; topicID = created }
        return .acknowledged(operationID: operation.operationID, topicID: topicID)
    }
    public func terminalReceipt(operationID: UUID, session: ProjectEditSession) async throws -> ProjectEditWriteOutcome? {
        // Flutter defines no reconciliation/idempotency contract. Do not manufacture one.
        nil
    }
}
