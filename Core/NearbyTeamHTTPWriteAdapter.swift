import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Supply fresh source reads for the exact reviewed account/team/applicant. Route IDs never grant a role.
public struct NearbyTeamWriteEvidence: Equatable {
    public let session: NearbyTeamSession
    public let team: NearbyTeam?
    public let applicant: NearbyApplicant?
    public let application: NearbyMyApplication?
    public init(session: NearbyTeamSession, team: NearbyTeam?, applicant: NearbyApplicant? = nil, application: NearbyMyApplication? = nil) {
        self.session = session; self.team = team; self.applicant = applicant; self.application = application
    }
    func validates(_ review: NearbyTeamReview, now: Date) -> Bool {
        guard session.valid, session == review.session, team == review.team, applicant == review.applicant, application == review.application else { return false }
        let action = review.action
        if let team, team.id != action.teamID { return false }
        if let application, application.id != action.teamID { return false }
        switch action {
        case .apply: return team?.viewerStatus == .none && team?.viewerHasTicket == true
        case .withdraw:
            if let team { return team.viewerStatus == .pending }
            return application?.status == .pending
        case .handle(_, let id, _):
            guard team?.viewerStatus == .leader, applicant?.id == id else { return false }
            if let expiry = applicant?.applyExpireTime?.date() { return expiry > now }; return true
        }
    }
}
@MainActor public protocol NearbyTeamWriting: AnyObject {
    var configured: Bool { get }
    func submit(_ review: NearbyTeamReview) async -> NearbyWriteResult
}
public struct NearbyTeamDispatchRecord: Codable, Equatable {
    public enum Phase: String, Codable { case prepared, dispatched, acknowledged }
    public let operationID: UUID
    public let ownerKey: String
    public let targetKey: String
    public var phase: Phase
    public init(operationID: UUID, ownerKey: String, targetKey: String, phase: Phase = .prepared) { self.operationID = operationID; self.ownerKey = ownerKey; self.targetKey = targetKey; self.phase = phase }
}
@MainActor public protocol NearbyTeamDispatchJournal: AnyObject {
    func read(owner: String, target: String) throws -> NearbyTeamDispatchRecord?
    func write(_ record: NearbyTeamDispatchRecord) throws
    func remove(_ record: NearbyTeamDispatchRecord) throws
}
/// No tokens, names, coordinates, message contents or expiry values are persisted.
@MainActor public final class NearbyTeamDefaultsDispatchJournal: NearbyTeamDispatchJournal {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults) { self.defaults = defaults }
    private func key(_ owner: String, _ target: String) -> String {
        "questify.nearby.dispatch.v1." + Data("\(owner.utf8.count):\(owner):\(target)".utf8).base64EncodedString()
    }
    public func read(owner: String, target: String) throws -> NearbyTeamDispatchRecord? {
        guard let object = defaults.object(forKey: key(owner, target)) else { return nil }
        guard let data = object as? Data, let record = try? JSONDecoder().decode(NearbyTeamDispatchRecord.self, from: data), record.ownerKey == owner, record.targetKey == target else { throw NearbyTeamFailure.contract }
        return record
    }
    public func write(_ record: NearbyTeamDispatchRecord) throws {
        if let previous = try read(owner: record.ownerKey, target: record.targetKey), previous.operationID != record.operationID { throw NearbyTeamFailure.stale }
        let data = try JSONEncoder().encode(record); defaults.set(data, forKey: key(record.ownerKey, record.targetKey))
        guard defaults.data(forKey: key(record.ownerKey, record.targetKey)) == data else { throw NearbyTeamFailure.contract }
    }
    public func remove(_ record: NearbyTeamDispatchRecord) throws {
        guard try read(owner: record.ownerKey, target: record.targetKey) == record else { throw NearbyTeamFailure.stale }
        defaults.removeObject(forKey: key(record.ownerKey, record.targetKey))
        guard try read(owner: record.ownerKey, target: record.targetKey) == nil else { throw NearbyTeamFailure.contract }
    }
}
/// Executable dormant adapter. Neither endpoints nor tokens imply permission: approval defaults to nil.
/// AppSession never installs this adapter by default. Injected HTTPTransport tests make no real calls.
@MainActor public final class NearbyTeamHTTPWriteAdapter: NearbyTeamWriting {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let approval: OperationEndpointApproval?
    private let journal: any NearbyTeamDispatchJournal
    private let currentSession: () -> NearbyTeamSession?
    private let token: (NearbyTeamSession) -> String?
    private let freshEvidence: (NearbyTeamReview) async throws -> NearbyTeamWriteEvidence
    private let now: () -> Date
    private var inFlight: Set<String> = []
    public var configured: Bool { approval != nil }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, approval: OperationEndpointApproval? = nil,
                journal: any NearbyTeamDispatchJournal, currentSession: @escaping () -> NearbyTeamSession?,
                token: @escaping (NearbyTeamSession) -> String?,
                freshEvidence: @escaping (NearbyTeamReview) async throws -> NearbyTeamWriteEvidence, now: @escaping () -> Date = Date.init) {
        self.configuration = configuration; self.transport = transport; self.approval = approval; self.journal = journal
        self.currentSession = currentSession; self.token = token; self.freshEvidence = freshEvidence; self.now = now
    }
    static func ownerKey(configuration: APIConfiguration, session: NearbyTeamSession) -> String {
        let components = [configuration.baseURL.absoluteString, session.region, session.namespace, String(session.accountID)]
        return components.map { "\($0.utf8.count):\($0)" }.joined(separator: "|")
    }
    static func targetKey(_ action: NearbyTeamAction) -> String {
        switch action {
        case .apply(let team): return "apply:\(team.rawValue)"
        case .withdraw(let team): return "withdraw:\(team.rawValue)"
        // Approve and reject share a lock: the opposite decision must not race/replay the same applicant.
        case .handle(let team, let applicant, _): return "handle:\(team.rawValue):\(applicant.rawValue)"
        }
    }
    public func submit(_ review: NearbyTeamReview) async -> NearbyWriteResult {
        let session = review.session
        let owner = Self.ownerKey(configuration: configuration, session: session), target = Self.targetKey(review.action)
        let operationKey = owner + "|" + target
        guard !inFlight.contains(operationKey) else { return .unknown }
        let descriptor: NearbyTeamRequest
        do { descriptor = try .action(review.action) } catch { return .notSent }
        guard let approval, session.valid, descriptor.mutation, descriptor.method == "POST",
              ["/api/team/apply", "/api/team/withdraw", "/api/team/handle"].contains(descriptor.path),
              approval.allows(configuration: configuration, namespace: session.namespace, accountID: session.accountID, path: String(descriptor.path.dropFirst())) else { return .notSent }
        inFlight.insert(operationKey); defer { inFlight.remove(operationKey) }
        var record = NearbyTeamDispatchRecord(operationID: review.id, ownerKey: owner, targetKey: target)
        let request: URLRequest
        do {
            // Existing prepared, dispatched or acknowledged records all fail closed on restart/replay.
            if try journal.read(owner: owner, target: target) != nil { return .unknown }
        } catch { return .unknown }
        do {
            try check(session)
            let evidence = try await freshEvidence(review); try check(session)
            guard evidence.validates(review, now: now()), let credential = token(session), AuthRequestBuilder.isValidToken(credential) else { return .notSent }
            request = try OperationAdapterHTTP.json(configuration: configuration, path: String(descriptor.path.dropFirst()), body: descriptor.body ?? Data(), token: credential)
            try check(session)
        } catch { return .notSent }
        do {
            // Recheck after the evidence await: another adapter instance may have dispatched meanwhile.
            if try journal.read(owner: owner, target: target) != nil { return .unknown }
            try journal.write(record); try check(session)
            guard try journal.read(owner: owner, target: target) == record else { return .unknown }
            record.phase = .dispatched; try journal.write(record)
            guard try journal.read(owner: owner, target: target) == record else { return .unknown }
            try check(session)
        } catch { return .unknown }
        do {
            let (data, status) = try await transport.send(request)
            try check(session)
            let outcome = NearbyTeamService.decodeWrite(.init(status: status, data: data), action: review.action, synthetic: false)
            switch outcome {
            case .acknowledged:
                record.phase = .acknowledged; try journal.write(record)
            case .rejected:
                try journal.remove(record) // A valid business-rejection envelope proves no acknowledged change.
            default: break
            }
            return outcome
        } catch { return .unknown }
    }
    private func check(_ session: NearbyTeamSession) throws {
        try Task.checkCancellation(); guard currentSession() == session else { throw NearbyTeamFailure.stale }
    }
}
