import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only offline transports with canned data should conform. Production writes use the
/// separate typed factory, exact target grants and durable coordinator journal.
public protocol ClubGovernanceOfflineTransport: HTTPTransport {}

public struct ClubGovernanceService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let offlineRisks: Set<String>
    private let productionTransport: ClubGovernanceProductionTransport?
    public var allowsOfflineWrites: Bool { !offlineRisks.isEmpty }
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport; offlineRisks = []; productionTransport = nil
    }
    public init(offlineConfiguration: APIConfiguration, offlineTransport: any ClubGovernanceOfflineTransport, risks: Set<ClubGovernanceRisk> = [.administrative]) {
        configuration = offlineConfiguration; transport = offlineTransport; offlineRisks = Set(risks.map(\.rawValue)); productionTransport = nil
    }
    init(productionConfiguration: APIConfiguration, productionTransport: ClubGovernanceProductionTransport) {
        configuration = productionConfiguration; transport = productionTransport; offlineRisks = []; self.productionTransport = productionTransport
    }
    @MainActor public func permits(_ command: ClubGovernanceCommand) -> Bool {
        offlineRisks.contains(command.operation.risk.rawValue) || productionTransport?.permits(command) == true
    }
    func request(path: String, fields: [String: ClubGovernanceValue], form: Bool, token: String) throws -> URLRequest {
        // This method is internal request construction only. Dispatch paths are closed enums.
        guard AuthRequestBuilder.isValidToken(token), !path.contains(".."), path.hasPrefix("api/") else { throw ClubGovernanceFailure.invalidRequest }
        if form {
            var formFields: [String: String] = [:]
            for (key, value) in fields { guard let text = value.text else { throw ClubGovernanceFailure.invalidRequest }; formFields[key] = text }
            return try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: formFields, token: token)
        }
        var request = try AuthRequestBuilder.makeFormRequest(url: configuration.baseURL.appendingPathComponent(path), fields: [:], token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        request.httpBody = try encoder.encode(fields)
        return request
    }
    private func post(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue], token: String, check: () throws -> Void) async throws -> ClubGovernanceValue {
        let fields = try operation.fields(scope: scope, options: options)
        let request = try request(path: operation.path, fields: fields, form: [.topicOverview, .members].contains(operation), token: token)
        try check()
        let (data, status) = try await transport.send(request)
        try check()
        let value = try Self.decode(data: data, status: status, mutation: false)
        return try ClubGovernanceValidation.validate(value, operation: operation, scope: scope)
    }
    public func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue] = [:], session: ClubGovernanceSession, check: () throws -> Void) async throws -> ClubGovernanceSnapshot {
        try check(); _ = try operation.fields(scope: scope, options: options)
        var permissions: ClubGovernancePermissions?
        if scope.clubID != nil {
            let raw = try await post(.access, scope: scope, options: [:], token: session.token, check: check)
            let access = try ClubGovernancePermissions(value: raw, scope: scope)
            var permitted = access.allows(operation.permission, scope: scope)
            if [.audienceCounts, .notificationStatus].contains(operation), scope.activityID != nil {
                permitted = permitted || access.allows("club:event:operate", scope: scope)
            }
            if operation == .notificationPreview {
                let eventAudience = ["REGISTERED", "WAITLIST", "NO_SHOW"].contains(options["audienceType"]?.string ?? "")
                permitted = access.allows(eventAudience ? "club:event:operate" : "club:notify:send", scope: scope)
            }
            guard permitted else { throw ClubGovernanceFailure.forbidden }
            permissions = access
            if operation == .access { return .init(operation: operation, scope: scope, permissions: access, value: raw) }
        } else if ![.hostStatus, .feed].contains(operation) { throw ClubGovernanceFailure.invalidRequest }
        var value = try await post(operation, scope: scope, options: options, token: session.token, check: check)
        if operation == .hostStatus {
            let account = try await AuthService(configuration: configuration, transport: transport).currentAccount(token: session.token)
            try check(); guard account.id == session.identity.accountID else { throw ClubGovernanceFailure.targetChanged }
            var fields = value.object ?? [:]; fields["accountID"] = .integer(account.id); fields["accountRole"] = .string(account.effectiveRole); value = .object(fields)
        }
        try check()
        return .init(operation: operation, scope: scope, permissions: permissions, value: value)
    }
    @MainActor func dispatch(_ command: ClubGovernanceCommand, session: ClubGovernanceSession, authorization: ClubGovernanceDispatchAuthorization? = nil, check: () throws -> Void) async throws -> ClubGovernanceValue {
        guard permits(command) else { throw ClubGovernanceFailure.notConfigured }
        let request: URLRequest
        if let productionTransport {
            guard let authorization else { throw ClubGovernanceFailure.notConfigured }
            request = try productionTransport.request(for: command, token: session.token, authorization: authorization)
        } else { request = try self.request(path: command.operation.path, fields: command.fields, form: [.chapterRecruit, .chapterFinish].contains(command.operation), token: session.token) }
        try check()
        // Once send starts, ANY ambiguous transport, cancellation or malformed receipt
        // may have committed. Never automatically repeat, replace the key, or reset it.
        let data: Data, status: Int
        do { (data, status) = try await transport.send(request) }
        catch { throw ClubGovernanceFailure.unknown(message: nil) }
        do { try check() } catch { throw ClubGovernanceFailure.unknown(message: nil) }
        if command.operation == .issueGroupCode,
           let body = try? JSONDecoder().decode(ClubGovernanceValue.self, from: data), body["code"].int != 200,
           let message = body["msg"].string, message.contains("权限") || message.contains("无权") {
            throw ClubGovernanceFailure.rejected(code: body["code"].int, message: message)
        }
        let value = try Self.decode(data: data, status: status, mutation: true)
        do {
            switch command.operation {
            case .createSeries, .updateSeries:
                try ClubGovernanceValidation.require(ClubGovernanceValidation.positive(value["id"]))
                if command.operation == .updateSeries { try ClubGovernanceValidation.require(value["id"].int == command.scope.seriesID) }
            case .correctAttendance: try ClubGovernanceValidation.require(ClubGovernanceValidation.positive(value["id"]))
            case .cancelOccurrence: try ClubGovernanceValidation.require(value["activityId"].int == command.scope.activityID && value["refundStatus"].string != nil)
            case .sendNotification: try ClubGovernanceValidation.campaign(value)
            case .retryNotification: try ClubGovernanceValidation.campaign(value, expectedID: command.scope.campaignID)
            case .saveTopicSettings: _ = try ClubGovernanceValidation.validate(value, operation: .topicSettings, scope: command.scope)
            case .endTopic:
                try ClubGovernanceValidation.require(ClubGovernanceValidation.count(value["refundedOrders"]) && ClubGovernanceValidation.count(value["manualOrders"]) && value["failedSessions"].array?.allSatisfy { $0.string != nil } == true)
            case .issueGroupCode:
                _ = try ClubGovernanceGroupCode(receipt: value, receivedAt: Date())
            default: break // Source methods acknowledge AjaxResult.code, not an invented receipt.
            }
        } catch { throw ClubGovernanceFailure.unknown(message: nil) }
        return ClubGovernanceValidation.sanitize(value)
    }
    static func decode(data: Data, status: Int, mutation: Bool) throws -> ClubGovernanceValue {
        let envelope = try? JSONDecoder().decode(ClubGovernanceValue.self, from: data)
        let code = envelope?["code"].int, message = envelope?["msg"].string
        if status == 401 || code == 401 { throw mutation ? ClubGovernanceFailure.rejected(code: 401, message: message) : .signedOut }
        if status == 403 || code == 403 || code == 2 { throw mutation ? ClubGovernanceFailure.rejected(code: code ?? status, message: message) : .forbidden }
        if status == 409 || code == 409 { throw ClubGovernanceFailure.conflict(message: message) }
        if (400..<500).contains(status) || (code.map { (400..<500).contains($0) } ?? false) { throw ClubGovernanceFailure.rejected(code: code ?? status, message: message) }
        guard (200..<300).contains(status), code == 200, let envelope else {
            if mutation { throw ClubGovernanceFailure.unknown(message: message) }
            if code != nil || !(200..<300).contains(status) { throw ClubGovernanceFailure.rejected(code: code ?? status, message: message) }
            throw ClubGovernanceFailure.malformed
        }
        return envelope["data"]
    }
}

public struct ClubGovernanceSession: Equatable {
    public let identity: ClubReadIdentity
    public let storageNamespace: String
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String, storageNamespace: String = "") throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw ClubGovernanceFailure.signedOut }
        identity = .init(accountID: accountID, epoch: epoch); self.token = token; self.storageNamespace = storageNamespace
    }
}

@MainActor public protocol ClubGovernanceAccess: AnyObject {
    var identity: ClubReadIdentity? { get }
    var isConfigured: Bool { get }
    var storageNamespace: String { get }
    var allowsOfflineWrites: Bool { get }
    var authorizationGeneration: UUID? { get }
    var journalRealm: String { get }
    func canDispatch(_ command: ClubGovernanceCommand) -> Bool
    func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot
    func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue
    func send(_ review: ClubGovernanceReview, check: () throws -> Void) async throws -> ClubGovernanceValue
    func send(_ review: ClubGovernanceReview, authorization: ClubGovernanceDispatchAuthorization, check: () throws -> Void) async throws -> ClubGovernanceValue
}
public extension ClubGovernanceAccess {
    var authorizationGeneration: UUID? { nil }
    var journalRealm: String { storageNamespace }
    func send(_ review: ClubGovernanceReview, check: () throws -> Void) async throws -> ClubGovernanceValue {
        guard allowsOfflineWrites else { throw ClubGovernanceFailure.notConfigured }; try check(); return try await send(review)
    }
    func send(_ review: ClubGovernanceReview, authorization: ClubGovernanceDispatchAuthorization, check: () throws -> Void) async throws -> ClubGovernanceValue {
        try authorization.consume(review); try check(); return try await send(review)
    }
    func canDispatch(_ command: ClubGovernanceCommand) -> Bool { allowsOfflineWrites }
}
@MainActor public final class ClubGovernanceSessionAccess: ClubGovernanceAccess {
    private let service: ClubGovernanceService?
    private let currentSession: () -> ClubGovernanceSession?
    private let productionService: (ClubGovernanceCommand) -> ClubGovernanceService?
    private let runtimeContext: () -> RuntimeDependencyContext?
    private var observedContext: RuntimeDependencyContext?
    private var contextGeneration = UUID()
    public var authorizationGeneration: UUID? {
        let context = runtimeContext()
        if observedContext != context { observedContext = context; contextGeneration = UUID() }
        return context == nil ? nil : contextGeneration
    }
    public var journalRealm: String {
        guard let context = runtimeContext() else { return storageNamespace }
        return "\(context.market)|\(context.baseURL.absoluteString)|\(context.session.namespace)"
    }
    public func canDispatch(_ command: ClubGovernanceCommand) -> Bool {
        if allowsOfflineWrites { return service?.permits(command) == true }
        return productionService(command)?.permits(command) == true
    }
    private let onUnauthorized: (ClubReadIdentity) -> Void
    public var identity: ClubReadIdentity? { currentSession()?.identity }
    public var isConfigured: Bool { service != nil }
    public var storageNamespace: String { currentSession()?.storageNamespace ?? "" }
    public var allowsOfflineWrites: Bool { service?.allowsOfflineWrites == true }
    public init(service: ClubGovernanceService?, currentSession: @escaping () -> ClubGovernanceSession?, productionService: @escaping (ClubGovernanceCommand) -> ClubGovernanceService? = { _ in nil }, runtimeContext: @escaping () -> RuntimeDependencyContext? = { nil }, onUnauthorized: @escaping (ClubReadIdentity) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        self.productionService = productionService; self.runtimeContext = runtimeContext
    }
    private func check(_ snapshot: ClubGovernanceSession) throws {
        try Task.checkCancellation(); guard currentSession() == snapshot else { throw CancellationError() }
    }
    public func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue] = [:]) async throws -> ClubGovernanceSnapshot {
        guard let service else { throw ClubGovernanceFailure.notConfigured }
        guard let session = currentSession() else { throw ClubGovernanceFailure.signedOut }
        do { return try await service.read(operation, scope: scope, options: options, session: session) { try self.check(session) } }
        catch { try check(session); if (error as? ClubGovernanceFailure) == .signedOut || (error as? APIError) == .unauthorized { onUnauthorized(session.identity) }; throw error }
    }
    public func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { try await send(review, check: {}) }
    public func send(_ review: ClubGovernanceReview, check: () throws -> Void) async throws -> ClubGovernanceValue {
        guard allowsOfflineWrites else { throw ClubGovernanceFailure.notConfigured }
        return try await sendReviewed(review, check: check)
    }
    public func send(_ review: ClubGovernanceReview, authorization: ClubGovernanceDispatchAuthorization, check: () throws -> Void) async throws -> ClubGovernanceValue {
        try authorization.consume(review)
        return try await sendReviewed(review, authorization: authorization, check: check)
    }
    private func sendReviewed(_ review: ClubGovernanceReview, authorization: ClubGovernanceDispatchAuthorization? = nil, check reviewCheck: () throws -> Void) async throws -> ClubGovernanceValue {
        try reviewCheck()
        let selected = allowsOfflineWrites ? service : (productionService(review.command) ?? service)
        guard let service = selected, service.permits(review.command) else { throw ClubGovernanceFailure.notConfigured }
        guard let session = currentSession(), session.identity == review.identity, session.storageNamespace == review.storageNamespace else { throw ClubGovernanceFailure.staleReview }
        guard authorizationGeneration == review.authorizationGeneration else { throw ClubGovernanceFailure.staleReview }
        let command = review.command
        let snapshot = try await service.read(command.operation.reviewRead, scope: command.scope, options: command.reviewOptions, session: session) { try self.check(session); try reviewCheck() }
        try command.validateReview(snapshot, accountID: session.identity.accountID ?? 0)
        guard snapshot == review.snapshot else { throw ClubGovernanceFailure.staleReview }
        if [.createSeries, .updateSeries, .assignRole].contains(command.operation) {
            let members = try await service.read(.members, scope: command.scope, session: session) { try self.check(session); try reviewCheck() }
            let target = command.fields[command.operation == .assignRole ? "targetMemberId" : "defaultLeadMemberId"]?.int
            guard members == review.supportingMembers, let target, (members.value.array ?? []).contains(where: { $0["memberId"].int == target && (command.operation != .assignRole || $0["isOwner"] == .bool(false)) }) else { throw ClubGovernanceFailure.targetChanged }
        }
        guard authorizationGeneration == review.authorizationGeneration else { throw ClubGovernanceFailure.staleReview }
        do { return try await service.dispatch(command, session: session, authorization: authorization) { try self.check(session); try reviewCheck() } }
        catch {
            if currentSession() == session, let failure = error as? ClubGovernanceFailure, case .rejected(let code, _) = failure, code == 401 { onUnauthorized(session.identity) }
            throw error
        }
    }
}
