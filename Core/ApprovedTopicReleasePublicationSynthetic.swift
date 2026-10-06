#if DEBUG
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Test-only server state. All bytes pass through the real publication client; no network or backend approval is performed.
@MainActor public final class ApprovedTopicReleasePublicationSynthetic: ApprovedTopicReleasePublishing {
    public enum Scenario: Equatable { case ready, unknownOnce }
    @MainActor private final class Wire: HTTPTransport {
        let scenario: Scenario
        var requests: [URLRequest] = []
        var stored: [String: ([String: ProjectEditJSON], ProjectEditJSON)] = [:]
        var sentUnknown = false
        var beforeReply: (() -> Void)?
        init(scenario: Scenario, beforeReply: (() -> Void)?) { self.scenario = scenario; self.beforeReply = beforeReply }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            guard request.httpMethod == "POST", let path = request.url?.path,
                  path == "/api/approved-topic-release/v1/publish" || path == "/api/approved-topic-release/v1/status",
                  let body = request.httpBody, let command = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: body),
                  Set(command.keys) == ["topicId", "auditTaskId", "auditTaskVersion", "auditSnapshotHash", "expectedHeadRevision", "requestId", "expectedManifestHash"],
                  let requestID = command["requestId"]?.text, UUID(uuidString: requestID) != nil else { throw APIError.invalidRequest }
            requests.append(request)
            if let prior = stored[requestID] {
                guard prior.0 == command else { return try response(nil, status: 409) }; return try response(prior.1)
            }
            guard path.hasSuffix("/publish") else { return try response(nil, status: 409) }
            let value: ProjectEditJSON = .object(["releaseId": .number(Decimal(501 + stored.count)), "topicId": command["topicId"]!, "sourceConfigVersion": .number(1),
                "auditTaskId": command["auditTaskId"]!, "auditRecordId": .number(81), "auditTaskVersion": command["auditTaskVersion"]!, "schemaVersion": .number(1),
                "manifestHash": command["expectedManifestHash"]!, "auditSnapshotHash": command["auditSnapshotHash"]!, "currentlyApproved": .bool(true)])
            stored[requestID] = (command, value)
            if scenario == .unknownOnce, !sentUnknown { sentUnknown = true; return try response(nil, status: 503) }
            beforeReply?(); beforeReply = nil
            return try response(value)
        }
        private func response(_ value: ProjectEditJSON?, status: Int = 200) throws -> (Data, Int) {
            var fields: [String: ProjectEditJSON] = ["code": .number(Decimal(status))]; if let value { fields["data"] = value }
            return (try JSONEncoder().encode(fields), status)
        }
    }
    private let wire: Wire
    private let client: ApprovedTopicReleasePublicationClient
    public var publishCount: Int { wire.requests.filter { $0.url?.path.hasSuffix("/publish") == true }.count }
    public var statusCount: Int { wire.requests.filter { $0.url?.path.hasSuffix("/status") == true }.count }
    public var allocatedCount: Int { wire.stored.count }
    public var requestIDs: [String] { wire.requests.compactMap { request in
        guard let body = request.httpBody, let object = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: body) else { return nil }; return object["requestId"]?.text
    } }
    public init(session: ProjectEditSession, scenario: Scenario = .ready, beforeReply: (() -> Void)? = nil, currentSession: @escaping () -> ProjectEditSession?) throws {
        let wire = Wire(scenario: scenario, beforeReply: beforeReply); self.wire = wire
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: session.storageNamespace, accountID: session.accountID,
            paths: [ApprovedTopicReleasePublicationPath.publish, ApprovedTopicReleasePublicationPath.status])
        client = .init(configuration: configuration, approval: approval, transport: wire, currentCredentials: {
            currentSession().flatMap { try? .init(session: $0, token: "synthetic-publication-token") }
        })
    }
    public func isCurrent(session: ProjectEditSession) -> Bool { client.isCurrent(session: session) }
    public func canPublish(session: ProjectEditSession) -> Bool { client.canPublish(session: session) }
    public func canCheckStatus(session: ProjectEditSession) -> Bool { client.canCheckStatus(session: session) }
    public func publish(_ record: ApprovedTopicReleasePublicationJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReleasePublicationReceipt { try await client.publish(record, session: session) }
    public func status(_ record: ApprovedTopicReleasePublicationJournal.Record, session: ProjectEditSession) async throws -> ApprovedTopicReleasePublicationReceipt { try await client.status(record, session: session) }
}
#endif
