import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ApprovedTopicReleasePublicationPath {
    public static let publish = "api/approved-topic-release/v1/publish"
    public static let status = "api/approved-topic-release/v1/status"
}
public struct ApprovedTopicReleasePublicationCredentials: Equatable {
    public let session: ProjectEditSession
    fileprivate let token: String
    public init(session: ProjectEditSession, token: String) throws {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }; self.session = session; self.token = token
    }
}
@MainActor public protocol ApprovedTopicReleasePublishing: AnyObject {
    func isCurrent(session: ProjectEditSession) -> Bool
    func canPublish(session: ProjectEditSession) -> Bool
    func canCheckStatus(session: ProjectEditSession) -> Bool
    func publish(_ record: ApprovedTopicReleasePublicationJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReleasePublicationReceipt
    func status(_ record: ApprovedTopicReleasePublicationJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReleasePublicationReceipt
}

/// Separate exact approvals for publication and status. No mutation is inferred from a read grant.
@MainActor public final class ApprovedTopicReleasePublicationClient: ApprovedTopicReleasePublishing {
    private let configuration: APIConfiguration
    private let approval: OperationEndpointApproval?
    private let transport: any HTTPTransport
    private let currentCredentials: () -> ApprovedTopicReleasePublicationCredentials?
    private let currentCapability: (String) -> Bool
    public init(configuration: APIConfiguration, approval: OperationEndpointApproval? = nil, transport: any HTTPTransport,
                currentCredentials: @escaping () -> ApprovedTopicReleasePublicationCredentials?, currentCapability: @escaping (String) -> Bool = { _ in true }) {
        self.configuration = configuration; self.approval = approval; self.transport = transport; self.currentCredentials = currentCredentials; self.currentCapability = currentCapability
    }
    private func permits(_ path: String, session: ProjectEditSession) -> Bool {
        guard currentCapability(path), currentCredentials()?.session == session, let approval else { return false }
        return approval.allows(configuration: configuration, namespace: session.storageNamespace, accountID: session.accountID, path: path)
    }
    public func isCurrent(session: ProjectEditSession) -> Bool { canPublish(session: session) || canCheckStatus(session: session) }
    public func canPublish(session: ProjectEditSession) -> Bool { permits(ApprovedTopicReleasePublicationPath.publish, session: session) }
    public func canCheckStatus(session: ProjectEditSession) -> Bool { permits(ApprovedTopicReleasePublicationPath.status, session: session) }
    public func publish(_ record: ApprovedTopicReleasePublicationJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReleasePublicationReceipt {
        try await send(record, session: session, path: ApprovedTopicReleasePublicationPath.publish)
    }
    public func status(_ record: ApprovedTopicReleasePublicationJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReleasePublicationReceipt {
        try await send(record, session: session, path: ApprovedTopicReleasePublicationPath.status)
    }
    private func send(_ record: ApprovedTopicReleasePublicationJournal.Record, session: ProjectEditSession, path: String) async throws -> ApprovedTopicReleasePublicationReceipt {
        try Task.checkCancellation()
        guard permits(path, session: session), let credentials = currentCredentials(), credentials.session == session else { throw ApprovedTopicReleaseError.notConfigured }
        _ = try ApprovedTopicReleasePublishCommand.decode(.object(record.command.fields), prepared: record.prepared)
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: path, body: JSONEncoder().encode(record.command.fields), token: credentials.token)
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard currentCredentials() == credentials, permits(path, session: session) else { throw ApprovedTopicReleaseError.changedContext }
        let envelope = try ApprovedTopicReleaseWire.envelope(data)
        if status == 401 || envelope["code"]?.integer == 401 { throw APIError.unauthorized }
        if status == 403 { throw ApprovedTopicReleaseError.forbidden }
        if status == 409 { throw ApprovedTopicReleaseError.changedReview }
        guard (200..<300).contains(status), envelope["code"]?.integer == 200, let receipt = envelope["data"] else { throw ApprovedTopicReleaseError.unavailable }
        return try .decode(receipt, command: record.command, prepared: record.prepared)
    }
}

/// Presentation-scoped publisher. Every HTTP result, including errors, is fenced;
/// the exact persisted intent survives close, sign-out, cancellation and unknown outcomes.
@MainActor public final class ApprovedTopicReleasePublishFlow {
    public struct Confirmation: Identifiable {
        public let id = UUID()
        public let prepared: ApprovedTopicReleasePreparation
        fileprivate let snapshot: ApprovedTopicReleasePublicationJournal.Snapshot
    }
    public struct Claim {
        public let id = UUID()
        fileprivate let snapshot: ApprovedTopicReleasePublicationJournal.Snapshot
    }
    public enum State: Equatable {
        case idle, reviewing, sending, unconfirmed, known(ApprovedTopicReleasePublicationReceipt), unavailable, closed
    }
    public let id = UUID()
    public let session: ProjectEditSession
    public let topicID: Int
    public private(set) var state: State = .idle
    public private(set) var confirmation: Confirmation?
    public private(set) var snapshot: ApprovedTopicReleasePublicationJournal.Snapshot?
    private let source: any ApprovedTopicReleasePublishing
    private let journal: ApprovedTopicReleasePublicationJournal
    private let stillCurrent: () -> Bool
    private var claimID: UUID?
    private var requestID: UUID?
    private var ownedTask: Task<ApprovedTopicReleasePublicationReceipt, Error>?
    public init(session: ProjectEditSession, topicID: Int, source: any ApprovedTopicReleasePublishing,
                journal: ApprovedTopicReleasePublicationJournal, stillCurrent: @escaping () -> Bool) {
        self.session = session; self.topicID = topicID; self.source = source; self.journal = journal; self.stillCurrent = stillCurrent
    }
    public var isCurrent: Bool { state != .closed && stillCurrent() && source.isCurrent(session: session) }
    public var canPublish: Bool { isCurrent && source.canPublish(session: session) }
    public var canCheckStatus: Bool { isCurrent && source.canCheckStatus(session: session) && snapshot?.current != nil && ownedTask == nil && claimID == nil && confirmation == nil }
    public var canRetryExact: Bool {
        canPublish && ownedTask == nil && confirmation == nil && claimID == nil && snapshot?.current != nil && snapshot?.current?.receipt == nil
    }
    public func reload() {
        guard isCurrent, ownedTask == nil, confirmation == nil, claimID == nil else { return }
        do { snapshot = try journal.read(session: session, topicID: topicID); updateFromSnapshot() }
        catch { state = .unavailable }
    }
    private func updateFromSnapshot() {
        if let receipt = snapshot?.current?.receipt { state = .known(receipt) }
        else { state = snapshot?.current == nil ? .idle : .unconfirmed }
    }
    public func canReview(_ prepared: ApprovedTopicReleasePreparation) -> Bool {
        guard canPublish, ownedTask == nil, claimID == nil, confirmation == nil, state != .unavailable, let snapshot else { return false }
        return journal.canBegin(prepared, expected: snapshot)
    }
    public func review(_ prepared: ApprovedTopicReleasePreparation) -> Confirmation? {
        guard canPublish, prepared.topicID == topicID, ownedTask == nil, claimID == nil, confirmation == nil else { return nil }
        reload()
        guard canReview(prepared), let snapshot else { return nil }
        let original = Confirmation(prepared: prepared, snapshot: snapshot); confirmation = original; state = .reviewing; return original
    }
    public func cancel(_ original: Confirmation) {
        guard confirmation?.id == original.id else { return }; confirmation = nil; updateFromSnapshot()
    }
    /// A queued Confirm uses this exact original confirmation. The durable command is written synchronously before returning a claim.
    public func claim(_ original: Confirmation) -> Claim? {
        guard confirmation?.id == original.id, canPublish, ownedTask == nil, claimID == nil else { return nil }
        do {
            let persisted = try journal.begin(original.prepared, expected: original.snapshot, session: session)
            let claim = Claim(snapshot: persisted); snapshot = persisted; confirmation = nil; claimID = claim.id; state = .unconfirmed; return claim
        } catch { confirmation = nil; state = .unavailable; return nil }
    }
    public func submit(_ original: Claim) async {
        guard claimID == original.id, snapshot == original.snapshot, ownedTask == nil else { return }
        guard canPublish else { close(); return }
        claimID = nil
        await perform(original.snapshot, publication: true)
    }
    /// Explicit recovery uses the original persisted command, even if the new /prepare read changed.
    public func checkStatus(_ original: ApprovedTopicReleasePublicationJournal.Snapshot) async {
        guard canCheckStatus, snapshot == original else { return }; await perform(original, publication: false)
    }
    public func retryExact(_ original: ApprovedTopicReleasePublicationJournal.Snapshot) async {
        guard canRetryExact, snapshot == original else { return }
        await perform(original, publication: true)
    }
    private func perform(_ original: ApprovedTopicReleasePublicationJournal.Snapshot, publication: Bool) async {
        guard isCurrent, ownedTask == nil, let record = original.current else { return }
        do { guard try journal.read(session: session, topicID: topicID) == original else { state = .unavailable; return } }
        catch { state = .unavailable; return }
        let request = UUID(); requestID = request; state = .sending
        let task = Task { [source, session] in
            if publication { return try await source.publish(record, session: session) }
            return try await source.status(record, session: session)
        }
        ownedTask = task
        defer { if requestID == request { ownedTask = nil; requestID = nil } }
        do {
            let receipt = try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
            guard requestID == request else { return }
            guard !Task.isCancelled, !task.isCancelled, isCurrent else { close(); return }
            // Persistence failure leaves the old exact intent for status recovery; no successful local state is invented.
            snapshot = try journal.record(receipt, expected: original, session: session); updateFromSnapshot()
        } catch {
            guard requestID == request else { return }
            guard !Task.isCancelled, !task.isCancelled, isCurrent else { close(); return }
            state = .unconfirmed
        }
    }
    public func close() {
        ownedTask?.cancel(); ownedTask = nil; requestID = nil; claimID = nil; confirmation = nil; state = .closed
    }
}
