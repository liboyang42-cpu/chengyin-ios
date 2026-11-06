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
/// Original four project writers through the source-backed exact-request producer.
/// Historical local-only UUIDs never become server receipts or automatic retries.
@MainActor public final class ProjectEditHTTPService: ProjectEditServing {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let owner: ProjectEditOwner
    private let approval: OperationEndpointApproval?
    private let store: ProjectEditLocalStore?
    private let currentCredentials: () -> ProjectEditCredentials?
    private func allows(_ path: String) -> Bool {
        guard let approval, let credentials = currentCredentials(), store != nil else { return false }
        return approval.allows(configuration: configuration, namespace: credentials.session.storageNamespace, accountID: credentials.session.accountID, path: path)
    }
    public var supportsRequestReadback: Bool { allows(ProjectEditRequestContract.readPath) }
    public var supportsPostProcessingResume: Bool { allows(ProjectEditRequestContract.resumePostProcessingPath) }
    public var supportsRequestRetry: Bool { allows(ProjectEditRequestContract.submitPath) }
    public var authority: ProjectEditServiceAuthority { supportsRequestRetry ? .approved : .readOnly }

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
        var dispatched = operation
        let request: URLRequest
        do {
            try check(credentials)
            guard let persisted = try store.pending(session: session, identity: operation.identity), persisted.operationID == operation.operationID else { return .notSent }
            if persisted.dispatchStarted == true { return .unknown }
            guard persisted == operation else { return .notSent }
            let fresh = try await preflight(topicID: operation.identity.topicID, session: session)
            try check(credentials)
            if operation.identity.topicID == nil {
                guard ProjectEditSubmissionIntent.from(payload: operation.payload) == .saveCloudDraft || fresh.capability.allowsCreate else { return .notSent }
            } else {
                guard let baseline = operation.baseline, fresh.snapshot == baseline,
                      ProjectChapterRecruitmentCarryOver.matchesFresh(fresh.snapshot, baseline: baseline) else { return .notSent }
            }
            if let id = operation.identity.topicID {
                guard operation.payload["id"]?.integer == id, operation.payload["publishToCreative"] == nil || operation.payload["publishToCreative"] == .number(0) else { return .notSent }
            } else if operation.payload["id"] != nil { return .notSent }
            let intent = ProjectEditSubmissionIntent.from(payload: operation.payload)
            if intent != .ordinary {
                guard operation.payload["publishToCreative"] == .number(0), operation.baseline?.scope == .full,
                      operation.identity.topicID == nil || operation.baseline?.isServerDraft == true else { return .notSent }
                if intent == .submitServerDraft { guard operation.identity.topicID != nil, operation.baseline?.isServerDraft == true else { return .notSent } }
            }
            try ProjectEditStoryContract.validatePayload(operation.payload, baseline: operation.baseline)
            guard approval.allows(configuration: configuration, namespace: session.storageNamespace, accountID: session.accountID, path: ProjectEditRequestContract.submitPath) else { return .notSent }
            let envelope = try ProjectEditRequestContract.Submit(operationID: operation.operationID, originalPath: path, payload: operation.payload)
            dispatched.serverRequest = envelope
            request = try OperationAdapterHTTP.json(configuration: configuration, path: ProjectEditRequestContract.submitPath, body: JSONEncoder().encode(envelope), token: credentials.token)
            try check(credentials)
            guard try store.pending(session: session, identity: operation.identity) == operation else { return .unknown }
            dispatched.dispatchStarted = true
            try store.savePending(dispatched, session: session)
        } catch { return .notSent }
        do {
            // Saving may invoke a provider callback. Recheck the exact durable command
            // and current owner immediately before dispatch; never downgrade its marker.
            try check(credentials)
            guard let saved = try store.pending(session: session, identity: dispatched.identity),
                  ProjectEditLocalStore.exactPending(saved, dispatched) else { return .unknown }
            let (data, status) = try await transport.send(request)
            try check(credentials)
            guard let saved = try store.pending(session: session, identity: dispatched.identity),
                  ProjectEditLocalStore.exactPending(saved, dispatched) else { return .unknown }
            return Self.decodeRequestReceipt(data, status: status, operation: dispatched)
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
        // UUID alone cannot establish the immutable body, owner or original path. Legacy callers stay unknown.
        nil
    }
    private func exactRequest(_ operation: ProjectEditPending, session: ProjectEditSession) throws -> ProjectEditRequestContract.Submit {
        guard operation.ownerKey == session.ownerKey, operation.dispatchStarted == true,
              let envelope = operation.serverRequest, let store,
              let persisted = try store.pending(session: session, identity: operation.identity), ProjectEditLocalStore.exactPending(persisted, operation),
              let path = try? ProjectEditStoryContract.path(payload: operation.payload, baseline: operation.baseline),
              envelope.matches(operationID: operation.operationID, originalPath: path, payload: operation.payload),
              operation.payload["scope"] == .string(owner.rawValue) else { throw ProjectEditError.invalidContract }
        return envelope
    }
    public func terminalReceipt(operation: ProjectEditPending, session: ProjectEditSession) async throws -> ProjectEditWriteOutcome? {
        let envelope = try exactRequest(operation, session: session)
        guard let approval, approval.allows(configuration: configuration, namespace: session.storageNamespace, accountID: session.accountID, path: ProjectEditRequestContract.readPath),
              let credentials = currentCredentials(), credentials.session == session else { throw ProjectEditError.notConfigured }
        try check(credentials)
        let body = ProjectEditRequestContract.Read(envelope: envelope, scope: owner.rawValue)
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: ProjectEditRequestContract.readPath, body: JSONEncoder().encode(body), token: credentials.token)
        let (data, status) = try await transport.send(request); try check(credentials)
        _ = try exactRequest(operation, session: session)
        return Self.decodeRequestReceipt(data, status: status, operation: operation)
    }
    /// Read the original dispatched request; UNKNOWN is not proof it was not sent.
    /// Explicit rejection still returns to the caller's original edit/review flow.
    /// New submissions and acknowledged post-processing keep their separate paths.
    public func retrySameRequest(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome {
        do {
            _ = try exactRequest(operation, session: session)
            guard supportsRequestReadback else { return .unknown }
            return try await terminalReceipt(operation: operation, session: session) ?? .unknown
        } catch { return .unknown }
    }
    public func resumePostProcessing(_ operation: ProjectEditPending, session: ProjectEditSession) async -> ProjectEditWriteOutcome {
        do {
            let envelope = try exactRequest(operation, session: session)
            guard operation.serverRequestCommitted == true, operation.postProcessing?.canResume == true, supportsPostProcessingResume,
                  let credentials = currentCredentials(), credentials.session == session else { return .unknown }
            try check(credentials)
            let body = ProjectEditRequestContract.Read(envelope: envelope, scope: owner.rawValue)
            let request = try OperationAdapterHTTP.json(configuration: configuration, path: ProjectEditRequestContract.resumePostProcessingPath, body: JSONEncoder().encode(body), token: credentials.token)
            let (data, status) = try await transport.send(request); try check(credentials)
            _ = try exactRequest(operation, session: session)
            return Self.decodeRequestReceipt(data, status: status, operation: operation)
        } catch { return .unknown }
    }
    static func decodeRequestReceipt(_ data: Data, status: Int, operation: ProjectEditPending) -> ProjectEditWriteOutcome {
        guard (200..<300).contains(status), let envelope = try? ApprovedTopicReleaseWire.envelope(data), envelope["code"]?.integer == 200,
              let body = envelope["data"]?.object, let sent = operation.serverRequest,
              body["protocolVersion"]?.text == sent.protocolVersion, body["requestId"]?.text == sent.requestId,
              body["originalPath"]?.text == sent.originalPath, body["payloadSHA256"]?.text == sent.payloadSHA256 else { return .unknown }
        if body["state"]?.text == "REJECTED" { return .rejected }
        guard body["state"]?.text == "COMMITTED", ["NOT_RECONCILED", "TRACKED", "UNAVAILABLE"].contains(body["postProcessing"]?.text ?? "") else { return .unknown }
        var processing: ProjectEditPostProcessingReceipt?
        if body["postProcessing"]?.text == "TRACKED", let value = body["processing"],
           let encoded = try? JSONEncoder().encode(value), let decoded = try? JSONDecoder().decode(ProjectEditPostProcessingReceipt.self, from: encoded),
           decoded.protocolVersion == "original-project-postprocess-v1", decoded.requestID == sent.requestId, decoded.payloadSHA256 == sent.payloadSHA256 {
            processing = decoded
        }
        if sent.originalPath == ProjectEditStoryContract.createPath || sent.originalPath == ProjectEditStoryContract.updatePath {
            guard let bundle = try? ProjectEditBundleAcknowledgment.decode(body["originalResult"], expectedTopicID: operation.identity.topicID) else { return .unknown }
            // A matched request identity cannot turn a contradictory original result into a cloud-save fact.
            if operation.payload["saveDraft"] == .number(1), bundle.reviewState != "DRAFT" || bundle.published { return .unknown }
            if operation.payload["saveDraft"] == .number(0), bundle.reviewState == "DRAFT" { return .unknown }
            if let processing { return .postProcessingReceipt(operationID: operation.operationID, topicID: bundle.topicID, bundle: bundle, receipt: processing) }
            return .committedReceipt(operationID: operation.operationID, topicID: bundle.topicID, bundle: bundle)
        }
        guard let topic = OperationAdapterHTTP.positiveID(body["originalResult"]), operation.identity.topicID == nil || operation.identity.topicID == topic else { return .unknown }
        if let processing { return .postProcessingReceipt(operationID: operation.operationID, topicID: topic, bundle: nil, receipt: processing) }
        return .committedReceipt(operationID: operation.operationID, topicID: topic, bundle: nil)
    }

}
