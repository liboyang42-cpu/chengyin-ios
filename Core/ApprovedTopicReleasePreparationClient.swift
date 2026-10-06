import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ApprovedTopicReleaseCredentials: Equatable {
    public let session: ProjectEditSession
    fileprivate let token: String
    public init(session: ProjectEditSession, token: String) throws {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.session = session; self.token = token
    }
}

public struct ApprovedTopicReleaseReadTarget: Equatable {
    public let topicID: Int
    public let auditTaskID: Int
    public let operationID: UUID
    public let ownerKey: String
    public init?(pending: ProjectEditPending, session: ProjectEditSession) {
        guard pending.ownerKey == session.ownerKey, pending.hasConsistentAcknowledgment,
              pending.serverAcknowledged == true, let acknowledgment = pending.bundleAcknowledgment,
              pending.completedTopicID == acknowledgment.topicID,
              (pending.payload["productType"]?.integer ?? pending.baseline?.draft.product.rawValue) == ProjectEditProduct.city.rawValue,
              (pending.payload["scope"]?.text ?? pending.baseline?.draft.owner.rawValue) == ProjectEditOwner.personal.rawValue,
              let task = acknowledgment.auditTaskID, task > 0,
              acknowledgment.reviewState == "PENDING" || acknowledgment.reviewState == "ESCALATED" else { return nil }
        topicID = acknowledgment.topicID; auditTaskID = task; operationID = pending.operationID; ownerKey = session.ownerKey
    }
    @MainActor public init?(pending: ProjectEditPending, session: ProjectEditSession, reviewSnapshot: ApprovedTopicReviewJournal.Snapshot) {
        guard let original = Self(pending: pending, session: session), reviewSnapshot.ownerKey == original.ownerKey, reviewSnapshot.topicID == original.topicID,
              reviewSnapshot.current == nil || reviewSnapshot.current?.receipt != nil else { return nil }
        topicID = original.topicID; operationID = original.operationID; ownerKey = original.ownerKey
        if let receipt = reviewSnapshot.receipt(for: original) { auditTaskID = receipt.auditTaskID }
        else { auditTaskID = original.auditTaskID }
    }
}

@MainActor public protocol ApprovedTopicReleasePreparing: AnyObject {
    func isCurrent(session: ProjectEditSession) -> Bool
    func prepare(_ target: ApprovedTopicReleaseReadTarget, session: ProjectEditSession) async throws -> ApprovedTopicReleasePreparation
}

/// Exact future /prepare capability only. Existing project/publishing grants cannot authorize it.
@MainActor public final class ApprovedTopicReleasePreparationClient: ApprovedTopicReleasePreparing {
    public static let path = ApprovedTopicReleasePaths.prepare
    private let configuration: APIConfiguration
    private let approval: OperationEndpointApproval?
    private let transport: any HTTPTransport
    private let currentCredentials: () -> ApprovedTopicReleaseCredentials?
    public init(configuration: APIConfiguration, approval: OperationEndpointApproval? = nil,
                transport: any HTTPTransport, currentCredentials: @escaping () -> ApprovedTopicReleaseCredentials?) {
        self.configuration = configuration; self.approval = approval; self.transport = transport; self.currentCredentials = currentCredentials
    }
    public func isCurrent(session: ProjectEditSession) -> Bool {
        guard let credentials = currentCredentials(), credentials.session == session, let approval else { return false }
        return approval.allows(configuration: configuration, namespace: session.storageNamespace, accountID: session.accountID, path: Self.path)
    }
    private func check(_ credentials: ApprovedTopicReleaseCredentials) throws {
        try Task.checkCancellation()
        guard currentCredentials() == credentials, isCurrent(session: credentials.session) else { throw ApprovedTopicReleaseError.changedContext }
    }
    public func prepare(_ target: ApprovedTopicReleaseReadTarget, session: ProjectEditSession) async throws -> ApprovedTopicReleasePreparation {
        guard isCurrent(session: session), let credentials = currentCredentials(), credentials.session == session,
              target.ownerKey == session.ownerKey else { throw ApprovedTopicReleaseError.notConfigured }
        try check(credentials)
        let body: [String: ProjectEditJSON] = ["topicId": .number(Decimal(target.topicID)), "auditTaskId": .number(Decimal(target.auditTaskID))]
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: Self.path, body: JSONEncoder().encode(body), token: credentials.token)
        let (data, status) = try await transport.send(request)
        // A late 401/403 is inspected only after the owned task and exact credentials
        // are still current. This client never logs out or mutates a newer account.
        try check(credentials)
        if status == 401 { throw APIError.unauthorized }
        let envelope = try ApprovedTopicReleaseWire.envelope(data)
        if envelope["code"]?.integer == 401 { throw APIError.unauthorized }
        if status == 403 { throw ApprovedTopicReleaseError.forbidden }
        if status == 409 { throw ApprovedTopicReleaseError.changedReview }
        guard (200..<300).contains(status), envelope["code"]?.integer == 200 else { throw ApprovedTopicReleaseError.unavailable }
        guard let value = envelope["data"] else { throw ApprovedTopicReleaseError.invalidResponse }
        let prepared = try ApprovedTopicReleasePreparation.decode(value, topicID: target.topicID, auditTaskID: target.auditTaskID)
        guard prepared.selectedCover == nil || prepared.selectedCover?.ownerMemberID == session.accountID else { throw ApprovedTopicReleaseError.invalidResponse }
        return prepared
    }
}

/// A single captured presentation owns its actual permission/read task. Closing is
/// synchronous cancellation, and a queued second load never replaces the first task.
@MainActor public final class ApprovedTopicReleaseReadFlow {
    public enum State: Equatable {
        case idle, loading, ready(ApprovedTopicReleasePreparation), failed(ApprovedTopicReleaseError), unauthorized, closed
    }
    public let id = UUID()
    public let target: ApprovedTopicReleaseReadTarget
    public let session: ProjectEditSession
    public private(set) var state: State = .idle
    private let source: any ApprovedTopicReleasePreparing
    private let stillCurrent: () -> Bool
    private var requestID: UUID?
    private var ownedTask: Task<ApprovedTopicReleasePreparation, Error>?
    public init(target: ApprovedTopicReleaseReadTarget, session: ProjectEditSession,
                source: any ApprovedTopicReleasePreparing, stillCurrent: @escaping () -> Bool) {
        self.target = target; self.session = session; self.source = source; self.stillCurrent = stillCurrent
    }
    public var isCurrent: Bool { state != .closed && stillCurrent() && source.isCurrent(session: session) }
    public func load() async {
        guard state != .loading, state != .closed else { return }
        guard isCurrent else { state = .failed(.notConfigured); return }
        let request = UUID(); requestID = request; state = .loading
        let task = Task { [source, target, session] in try await source.prepare(target, session: session) }
        ownedTask = task
        defer { if requestID == request { ownedTask = nil; requestID = nil } }
        do {
            let value = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard requestID == request else { return }
            guard !task.isCancelled, !Task.isCancelled, isCurrent else { close(); return }
            state = .ready(value)
        } catch {
            guard requestID == request else { return }
            guard !task.isCancelled, !Task.isCancelled, isCurrent else { close(); return }
            if error as? APIError == .unauthorized { state = .unauthorized }
            else { state = .failed(error as? ApprovedTopicReleaseError ?? .unavailable) }
        }
    }
    public func close() {
        ownedTask?.cancel(); ownedTask = nil; requestID = nil; state = .closed
    }
}
