import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ApprovedTopicReviewCredentials: Equatable {
    public let session: ProjectEditSession
    fileprivate let token: String
    public init(session: ProjectEditSession, token: String) throws {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }; self.session = session; self.token = token
    }
}

@MainActor public protocol ApprovedTopicReviewServing: AnyObject {
    func isCurrent(session: ProjectEditSession) -> Bool
    func canPrepare(session: ProjectEditSession) -> Bool
    func canSubmit(session: ProjectEditSession) -> Bool
    func canReadStatus(session: ProjectEditSession) -> Bool
    func prepare(_ origin: ApprovedTopicReleaseReadTarget, session: ProjectEditSession) async throws -> ApprovedTopicReviewCapture
    func submit(_ record: ApprovedTopicReviewJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReviewReceipt
    func status(_ record: ApprovedTopicReviewJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReviewReceipt
}

/// Distinct exact read, submit and recovery capabilities; no draft, publish or player grant can stand in for these paths.
@MainActor public final class ApprovedTopicReviewClient: ApprovedTopicReviewServing, ApprovedTopicReviewObserving, ApprovedTopicReviewSourceChoosing {
    private let configuration: APIConfiguration
    private let approval: OperationEndpointApproval?
    private let transport: any HTTPTransport
    private let currentCredentials: () -> ApprovedTopicReviewCredentials?
    private let currentCapability: (String) -> Bool
    public init(configuration: APIConfiguration, approval: OperationEndpointApproval? = nil, transport: any HTTPTransport,
                currentCredentials: @escaping () -> ApprovedTopicReviewCredentials?, currentCapability: @escaping (String) -> Bool = { _ in true }) {
        self.configuration = configuration; self.approval = approval; self.transport = transport
        self.currentCredentials = currentCredentials; self.currentCapability = currentCapability
    }
    private func permits(_ path: String, session: ProjectEditSession) -> Bool {
        guard currentCapability(path), currentCredentials()?.session == session, let approval else { return false }
        return approval.allows(configuration: configuration, namespace: session.storageNamespace, accountID: session.accountID, path: path)
    }
    public func isCurrent(session: ProjectEditSession) -> Bool { canPrepare(session: session) || canSubmit(session: session) || canReadStatus(session: session) || canObserve(session: session) || canReadSources(session: session) }
    public func canReadSources(session: ProjectEditSession) -> Bool { permits(ApprovedTopicReviewPath.sources, session: session) }
    public func canPrepare(session: ProjectEditSession) -> Bool { permits(ApprovedTopicReviewPath.prepare, session: session) }
    public func canSubmit(session: ProjectEditSession) -> Bool { permits(ApprovedTopicReviewPath.submit, session: session) }
    public func canReadStatus(session: ProjectEditSession) -> Bool { permits(ApprovedTopicReviewPath.status, session: session) }
    public func canObserve(session: ProjectEditSession) -> Bool { permits(ApprovedTopicReviewPath.current, session: session) }
    public func observe(_ record: ApprovedTopicReviewJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReviewObservation {
        guard record.ownerKey == session.ownerKey, record.receipt != nil else { throw ApprovedTopicReleaseError.changedContext }
        _ = try ApprovedTopicReviewCommand.decode(.object(record.command.fields), capture: record.capture)
        let value = try await send(record.command.readSelectorFields, session: session, path: ApprovedTopicReviewPath.current)
        return try .decode(value, record: record)
    }
    public func prepare(_ origin: ApprovedTopicReleaseReadTarget, session: ProjectEditSession) async throws -> ApprovedTopicReviewCapture {
        try await prepare(origin, selections: [], session: session)
    }
    public func sources(_ origin: ApprovedTopicReleaseReadTarget, session: ProjectEditSession) async throws -> ApprovedMerchantReviewChoices {
        guard origin.ownerKey == session.ownerKey else { throw ApprovedTopicReleaseError.changedContext }
        let value = try await send(["topicId": .number(Decimal(origin.topicID)), "observedAuditTaskId": .number(Decimal(origin.auditTaskID))], session: session, path: ApprovedTopicReviewPath.sources)
        return try .decode(value, origin: origin, session: session)
    }
    public func prepare(_ origin: ApprovedTopicReleaseReadTarget, selections: [ApprovedMerchantReviewSource], session: ProjectEditSession) async throws -> ApprovedTopicReviewCapture {
        guard origin.ownerKey == session.ownerKey else { throw ApprovedTopicReleaseError.changedContext }
        if !selections.isEmpty { _ = try ApprovedMerchantReviewSource.decodeSelections(.array(selections.map(\.fields))) }
        var body: [String: ProjectEditJSON] = ["topicId": .number(Decimal(origin.topicID)), "observedAuditTaskId": .number(Decimal(origin.auditTaskID))]
        if !selections.isEmpty { body["sourceSelections"] = .array(selections.map(\.fields)) }
        let value = try await send(body, session: session, path: ApprovedTopicReviewPath.prepare)
        let capture = try ApprovedTopicReviewCapture.decode(value, topicID: origin.topicID, observedAuditTaskID: origin.auditTaskID)
        guard capture.selectedMerchantSources == selections, capture.selectedCover == nil || capture.selectedCover?.ownerMemberID == session.accountID else { throw ApprovedTopicReleaseError.invalidResponse }
        return capture
    }
    public func submit(_ record: ApprovedTopicReviewJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReviewReceipt {
        guard record.capture.coverBindingAllowsReview else { throw ApprovedTopicReleaseError.notConfigured }
        return try await receipt(record, session: session, path: ApprovedTopicReviewPath.submit)
    }
    public func status(_ record: ApprovedTopicReviewJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReviewReceipt {
        try await receipt(record, session: session, path: ApprovedTopicReviewPath.status)
    }
    private func receipt(_ record: ApprovedTopicReviewJournal.Record, session: ProjectEditSession, path: String) async throws -> ApprovedTopicReviewReceipt {
        guard record.ownerKey == session.ownerKey else { throw ApprovedTopicReleaseError.changedContext }
        _ = try ApprovedTopicReviewCommand.decode(.object(record.command.fields), capture: record.capture)
        let body = path == ApprovedTopicReviewPath.status ? record.command.readSelectorFields : record.command.fields
        let value = try await send(body, session: session, path: path)
        return try .decode(value, command: record.command)
    }
    private func send(_ body: [String: ProjectEditJSON], session: ProjectEditSession, path: String) async throws -> ProjectEditJSON {
        try Task.checkCancellation()
        guard permits(path, session: session), let credentials = currentCredentials(), credentials.session == session else { throw ApprovedTopicReleaseError.notConfigured }
        let encoded = try ApprovedTopicReviewRequestBody.encode(body, path: path)
        let request = try OperationAdapterHTTP.json(configuration: configuration, path: path, body: encoded, token: credentials.token)
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        // Late transport errors cannot invalidate or mutate a newer account or a revoked capability.
        guard currentCredentials() == credentials, permits(path, session: session) else { throw ApprovedTopicReleaseError.changedContext }
        if status == 401 { throw APIError.unauthorized }
        let envelope = try ApprovedTopicReleaseWire.envelope(data)
        if envelope["code"]?.integer == 401 { throw APIError.unauthorized }
        if status == 403 { throw ApprovedTopicReleaseError.forbidden }
        if status == 409 { throw ApprovedTopicReleaseError.changedReview }
        guard (200..<300).contains(status), envelope["code"]?.integer == 200, let value = envelope["data"] else { throw ApprovedTopicReleaseError.unavailable }
        return value
    }
}
