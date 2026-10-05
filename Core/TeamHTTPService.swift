import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Dormant source-backed JSON adapter. No join-mode setter or remote receipt is invented.
/// The caller must persist the exact local operation identity before invoking submit.
@MainActor public final class TeamHTTPService: TeamServing {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let reader: TeamReadOnlyService
    private let approval: OperationEndpointApproval?
    private let journal: any TeamPendingJournal
    private let currentSession: () -> TeamSession?
    public var authority: TeamServiceAuthority { approval == nil ? .readOnly : .approved }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, approval: OperationEndpointApproval? = nil,
                journal: any TeamPendingJournal, currentSession: @escaping () -> TeamSession?,
                creationLoader: ((Int, TeamSession) async throws -> TeamCreationContext)? = nil) {
        self.configuration = configuration; self.transport = transport; self.approval = approval
        self.journal = journal; self.currentSession = currentSession
        reader = TeamReadOnlyService(configuration: configuration, transport: transport, currentSession: currentSession, creationLoader: creationLoader)
    }
    private func check(_ session: TeamSession) throws {
        try Task.checkCancellation()
        guard currentSession() == session else { throw TeamFailure.stale }
    }
    public func myTeams(session: TeamSession) async throws -> [OwnedTeam] { try await reader.myTeams(session: session) }
    public func detail(_ lookup: TeamLookup, session: TeamSession) async throws -> TeamDetail { try await reader.detail(lookup, session: session) }
    public func creationContext(ownerID: Int, session: TeamSession) async throws -> TeamCreationContext { try await reader.creationContext(ownerID: ownerID, session: session) }
    public func receipt(operationID: UUID, session: TeamSession) async throws -> TeamWriteOutcome? { nil }
    public func submit(_ action: TeamAction, operationID: UUID, session: TeamSession) async -> TeamWriteOutcome {
        let request: URLRequest
        do {
            let contract = try TeamWriteContract(action)
            let path = String(contract.path.dropFirst())
            guard let approval, approval.allows(configuration: configuration, namespace: session.storageNamespace, accountID: session.accountID, path: path) else { return .notSent }
            try check(session)
            let expected = TeamPendingRecord(operationID: operationID, ownerKey: session.ownerKey, targetKey: action.targetKey)
            guard let persisted = try journal.pending(ownerKey: session.ownerKey, targetKey: action.targetKey), persisted.operationID == expected.operationID else { return .notSent }
            if persisted.dispatchStarted == true { return .unknown }
            guard persisted == expected else { return .notSent }
            if case .create(let context, _, _) = action {
                let fresh = try await creationContext(ownerID: context.ownerID, session: session)
                guard fresh == context, fresh.eligible else { return .notSent }
            } else if let lookup = action.lookup {
                let fresh = try await detail(lookup, session: session)
                guard action.isAllowed(detail: fresh) else { return .notSent }
            } else { return .notSent }
            try check(session)
            let body: [String: Any] = contract.fields.mapValues { value in
                switch value { case .integer(let number): return number as Any; case .text(let text): return text as Any }
            }
            request = try OperationAdapterHTTP.json(configuration: configuration, path: path, body: JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), token: session.token)
            try check(session)
            guard try journal.pending(ownerKey: session.ownerKey, targetKey: action.targetKey) == expected else { return .unknown }
            var dispatched = expected; dispatched.dispatchStarted = true
            try journal.write(dispatched)
        } catch { return .notSent }
        do {
            let (data, status) = try await transport.send(request)
            try check(session)
            return Self.decodeAcknowledgment(data, status: status, action: action, operationID: operationID)
        } catch { return .unknown }
    }
    static func decodeAcknowledgment(_ data: Data, status: Int, action: TeamAction, operationID: UUID) -> TeamWriteOutcome {
        let envelope = try? OperationAdapterHTTP.envelope(data)
        if status == 401 || status == 403 { return .rejected }
        guard (200..<300).contains(status), let code = envelope?["code"]?.integer else { return .unknown }
        guard code == 200 else { return .rejected }
        let teamID: Int
        if case .create = action {
            guard let id = OperationAdapterHTTP.positiveID(envelope?["data"]?.object?["teamId"]) else { return .unknown }
            teamID = id
        } else {
            guard let id = action.teamID, id > 0 else { return .unknown }; teamID = id
        }
        // This confirms only acknowledgment of the request, never a synthesized roster/status.
        return .acknowledged(operationID: operationID, teamID: teamID)
    }
}
