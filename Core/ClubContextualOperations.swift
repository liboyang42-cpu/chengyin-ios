import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ClubOpsTimeRequest: Equatable, Encodable {
    public let activityId: Int
    /// Server wall time, explicitly Asia/Shanghai; never an assumed UTC conversion.
    public let startDate: String
    public init(activityID: Int, startDate: String) throws {
        guard activityID > 0, Self.date(startDate) != nil else { throw APIError.invalidRequest }
        activityId = activityID; self.startDate = startDate.replacingOccurrences(of: "T", with: " ")
    }
    public static func formatter() -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"; f.isLenient = false; return f
    }
    public static func submissionTime(_ date: Date) -> String {
        let f = formatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date) + ":00"
    }
    public static func date(_ raw: String) -> Date? {
        let f = formatter(), normalized = raw.replacingOccurrences(of: "T", with: " ")
        guard normalized.count == 19, let date = f.date(from: normalized), f.string(from: date) == normalized else { return nil }; return date
    }
}
public struct ClubOpsTimeSession: Equatable {
    public let identity: ClubReadIdentity
    public let accountID: Int
    public let realm: String
    let token: String
    public private(set) var runtimeContext: RuntimeDependencyContext?
    public init(accountID: Int, epoch: UInt64, realm: String, token: String) throws {
        guard accountID > 0, !realm.isEmpty, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        identity = .init(accountID: accountID, epoch: epoch); self.accountID = accountID; self.realm = realm; self.token = token
    }
    public init(context: RuntimeDependencyContext) throws {
        try self.init(accountID: context.session.accountID, epoch: context.session.epoch,
                      realm: context.baseURL.absoluteString, token: context.session.token)
        runtimeContext = context
    }
    var replayOwnerKey: String {
        let namespace = runtimeContext?.session.namespace ?? ""
        return "\(realm.utf8.count):\(realm)|\(namespace.utf8.count):\(namespace)|\(accountID)"
    }

}
public enum ClubOpsTimeFailure: Error, Equatable { case disabled, rejected, unknown, stale, malformed }
@MainActor public protocol ClubOpsTimeServing {
    var isConfigured: Bool { get }
    var requiresDurableJournal: Bool { get }
    var session: ClubOpsTimeSession? { get }
    func read(activityID: Int, session: ClubOpsTimeSession) async throws -> String
    func save(_ request: ClubOpsTimeRequest, session: ClubOpsTimeSession) async throws
    func save(_ request: ClubOpsTimeRequest, session: ClubOpsTimeSession, authorization: ContextualOperationAuthorization) async throws
}
extension ClubOpsTimeServing {
    public var requiresDurableJournal: Bool { false }
    public func save(_ request: ClubOpsTimeRequest, session: ClubOpsTimeSession, authorization: ContextualOperationAuthorization) async throws {
        try await save(request, session: session)
    }
}
@MainActor public struct ClubOpsTimeHTTPService: ClubOpsTimeServing {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let current: () -> ClubOpsTimeSession?
    public let isConfigured: Bool
    public var session: ClubOpsTimeSession? { current() }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, enabled: Bool = false, current: @escaping () -> ClubOpsTimeSession?) {
        self.configuration = configuration; self.transport = transport; self.isConfigured = enabled; self.current = current
    }
    private func check(_ session: ClubOpsTimeSession) throws {
        guard isConfigured else { throw ClubOpsTimeFailure.disabled }
        guard current() == session, session.realm == configuration.baseURL.absoluteString, !Task.isCancelled else { throw ClubOpsTimeFailure.stale }
    }
    public func read(activityID: Int, session: ClubOpsTimeSession) async throws -> String {
        try check(session); guard activityID > 0 else { throw APIError.invalidRequest }
        let request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/activity/info"), fields: ["id": String(activityID)], token: session.token)
        let (data, status) = try await transport.send(request); try check(session)
        let value = try JSONDecoder().decode(ClubGovernanceValue.self, from: data)
        guard (200..<300).contains(status), value["code"].int == 200, value["data"]["id"].int == activityID,
              let date = value["data"]["startDate"].string, ClubOpsTimeRequest.date(date) != nil else { throw ClubOpsTimeFailure.malformed }
        return date
    }
    public func save(_ request: ClubOpsTimeRequest, session: ClubOpsTimeSession) async throws {
        try check(session)
        var http = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent("api/club/lead/edit-ops"), fields: [:], token: session.token)
        http.setValue("application/json", forHTTPHeaderField: "Content-Type"); http.httpBody = try JSONEncoder().encode(request)
        do {
            let (data, status) = try await transport.send(http)
            guard current() == session, !Task.isCancelled else { throw ClubOpsTimeFailure.unknown }
            let value = try JSONDecoder().decode(ClubGovernanceValue.self, from: data)
            guard (200..<300).contains(status), let code = value["code"].int else { throw ClubOpsTimeFailure.unknown }
            guard code == 200 else { throw ClubOpsTimeFailure.rejected }
        } catch let error as ClubOpsTimeFailure { throw error }
        catch { throw ClubOpsTimeFailure.unknown }
    }
}
public enum ClubOpsTimeState: Equatable { case idle, saving, acknowledged, rejected, unknown }
/// The host retains this per activity. A readback is a server fact, never proof that an
/// uncertain write did not execute; unknown remains locked and has no retry-write button.
@MainActor public final class ClubOpsTimeCoordinator {
    public let activityID: Int
    public let service: any ClubOpsTimeServing
    private var states: [String: ClubOpsTimeState] = [:]
    private let journal: (any OperationPendingJournal)?
    private var targetKey: String { "club-start-time|\(activityID)" }
    public var state: ClubOpsTimeState {
        guard let session = service.session else { return .idle }
        if states[session.replayOwnerKey] == .saving { return .saving }
        do { if try journal?.pending(ownerKey: session.replayOwnerKey, targetKey: targetKey) != nil { return .unknown } }
        catch { return .unknown }
        return states[session.replayOwnerKey] ?? .idle
    }
    public var canSave: Bool { service.isConfigured && (!service.requiresDurableJournal || journal != nil) && service.session != nil && ![.saving, .unknown].contains(state) }
    public init(activityID: Int, service: any ClubOpsTimeServing, journal: (any OperationPendingJournal)? = nil) {
        self.activityID = activityID; self.service = service; self.journal = journal
    }
    public func save(_ request: ClubOpsTimeRequest, expected: ClubOpsTimeSession) async {
        guard canSave, service.session == expected, request.activityId == activityID else { return }
        let account = expected.replayOwnerKey
        let record = OperationPendingRecord(ownerKey: account, targetKey: targetKey)
        do { try journal?.write(record) } catch { return }
        states[account] = .saving
        do {
            let authorization = ContextualOperationAuthorization(command: .clubTime(request), owner: expected.replayOwnerKey) {
                guard let journal = self.journal else { return false }
                return try journal.pending(ownerKey: record.ownerKey, targetKey: record.targetKey) == record
            }
            try await service.save(request, session: expected, authorization: authorization)
            states[account] = service.session == expected && !Task.isCancelled ? .acknowledged : .unknown
        }
        catch let error as ClubOpsTimeFailure {
            switch error { case .disabled, .stale: states[account] = .idle; case .rejected: states[account] = .rejected; default: states[account] = .unknown }
        } catch { states[account] = .unknown }
        if states[account] != .unknown {
            do { try journal?.clear(record) } catch { states[account] = .unknown }
        }
    }
}
@MainActor public final class ClubOpsTimeHost {
    private let service: any ClubOpsTimeServing
    private var owners: [Int: ClubOpsTimeCoordinator] = [:]
    private let journal: (any OperationPendingJournal)?
    public init(service: any ClubOpsTimeServing, journal: (any OperationPendingJournal)? = nil) { self.service = service; self.journal = journal }
    public func coordinator(activityID: Int) -> ClubOpsTimeCoordinator {
        if let owner = owners[activityID] { return owner }
        let owner = ClubOpsTimeCoordinator(activityID: activityID, service: service, journal: journal); owners[activityID] = owner; return owner
    }
}
