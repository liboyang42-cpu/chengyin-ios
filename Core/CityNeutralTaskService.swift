import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CityNeutralTaskError: Error, Equatable { case disabled, stale, malformed, unknown, server(Int, String) }
public enum CityNeutralTaskAction: String, Codable { case accept = "ACCEPT", submit = "SUBMIT" }

/// Independent reviewed deployment grant. Login, player role and board visibility never create it.
@available(macOS 14.0, *) @MainActor @Observable public final class CityNeutralTaskApproval {
    public let context: RuntimeDependencyContext
    public let regionID: String
    public let allowsWrite: Bool
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, regionID: String, allowsWrite: Bool = false, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.role == context.session.role, ["player", "club", "merchant"].contains(context.role), context.session.accountID > 0,
              AuthRequestBuilder.isValidToken(context.session.token), CityReadRoute.validID(regionID),
              expiresAt > Date(), expiresAt.timeIntervalSinceNow <= 86400 else { throw CityNeutralTaskError.disabled }
        self.context = context; self.regionID = regionID; self.allowsWrite = allowsWrite; self.expiresAt = expiresAt
    }
    public func revoke() { revoked = true }
    public func matches(_ live: RuntimeDependencyContext) -> Bool { !revoked && Date() < expiresAt && ContentDraftContextFence.matches(context, live) && context.session == live.session }
}
public struct CityNeutralTaskDefinition: Codable, Equatable {
    public struct Option: Codable, Equatable, Identifiable { public let id, label: String }
    public let taskId, title, type, access, arrivalRequirement, scope, question: String
    public let options: [Option]
    public let maxAttempts, pointCost, pointReward, actionCost: Int
    var valid: Bool {
        CityReadRoute.validID(taskId) && !title.isEmpty && title.count <= 160 && !question.isEmpty && question.count <= 1000 &&
        type == "QA_PICK" && access == "REMOTE_NEUTRAL" && arrivalRequirement == "NONE" && scope == "TEAM_ROUND" &&
        pointCost == 0 && pointReward == 0 && actionCost == 0 && (1...20).contains(maxAttempts) &&
        (2...8).contains(options.count) && Set(options.map(\.id)).count == options.count &&
        options.allSatisfy { CityReadRoute.validID($0.id) && !$0.label.isEmpty && $0.label.count <= 160 }
    }
}
public struct CityNeutralTaskResult: Codable, Equatable {
    public let resultId, outcome, requestId, createdAt, verifier: String
    public let attemptNumber: Int
}
public struct CityNeutralTask: Codable, Equatable, Identifiable {
    public let definition: CityNeutralTaskDefinition
    public let status: String
    public let version: Int64
    public let attempts: Int
    public let instanceId, acceptedAt: String?
    public let result: CityNeutralTaskResult?
    public var id: String { definition.taskId }
}
public struct CityNeutralTaskSnapshot: Decodable, Equatable {
    public let contract, scope, status: String
    public let writeApproved: Bool
    public let binding: CityNeutralTaskBinding?
    public let teamId, sessionId: String?
    public let teamVersion: Int64?
    public let tasks: [CityNeutralTask]
    public let arrivalProof, ownershipEffect, pointsEffect: String?
}
public struct CityNeutralTaskCommand: Codable, Equatable {
    public let requestId, regionId, teamId, contentHash, taskId: String
    public let kind: CityNeutralTaskAction
    public let expectedTeamVersion, releaseId, expectedVersion: Int64
    public let instanceId, optionId: String?
    public init(id: UUID, kind: CityNeutralTaskAction, binding: CityNeutralTaskBinding, teamId: String, teamVersion: Int64, task: CityNeutralTask, optionId: String?) {
        requestId = id.uuidString; regionId = binding.regionId; self.teamId = teamId; contentHash = binding.contentHash
        taskId = task.id; self.kind = kind; expectedTeamVersion = teamVersion; releaseId = binding.releaseId
        expectedVersion = task.version; instanceId = kind == .submit ? task.instanceId : nil; self.optionId = kind == .submit ? optionId : nil
    }
}
public struct CityNeutralTaskReceipt: Equatable {
    public let requestId: String
    public let succeeded: Bool
    public let errorCode: String?
    /// The immutable task snapshot recorded by this request, never today's task state.
    public let task: CityNeutralTask?
}

/// Three exact routes, with a separate deployment approval. No point-task or normal PlayTeam fallback.
@available(macOS 14.0, *) @MainActor public struct CityNeutralTaskRoute {
    public let write: Bool
    public let regionID: String?
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpBodyStream == nil, let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.fragment == nil, parts.user == nil, parts.password == nil else { return nil }
        let prefix = baseURL.appendingPathComponent("api/city-game/neutral-tasks").absoluteString
        if request.httpMethod == "GET", request.httpBody == nil {
            if let items = parts.queryItems, items.count == 1, items[0].name == "regionId", let region = items[0].value, CityReadRoute.validID(region) {
                var canonical = URLComponents(string: prefix + "/state")!; canonical.queryItems = [.init(name: "regionId", value: region)]
                guard canonical.url == url else { return nil }; write = false; regionID = region; return
            }
            if parts.query == nil, let id = UUID(uuidString: url.lastPathComponent), url.absoluteString == prefix + "/request/" + id.uuidString { write = false; regionID = nil; return }
        }
        if request.httpMethod == "POST", url.absoluteString == prefix + "/command", parts.query == nil,
           request.value(forHTTPHeaderField: "Content-Type") == "application/json", let data = request.httpBody, data.count <= 4096,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String:Any], let command = try? JSONDecoder().decode(CityNeutralTaskCommand.self, from: data) {
            var keys: Set<String> = ["requestId", "regionId", "kind", "releaseId", "contentHash", "teamId", "expectedTeamVersion", "taskId", "expectedVersion"]
            if command.kind == .submit { keys.formUnion(["instanceId", "optionId"]) }
            guard Set(object.keys) == keys, UUID(uuidString: command.requestId)?.uuidString == command.requestId,
                  CityReadRoute.validID(command.regionId), CityReadRoute.validID(command.taskId), Self.serverID(command.teamId),
                  command.releaseId > 0, command.expectedTeamVersion > 0, command.expectedVersion >= 0,
                  [command.releaseId, command.expectedTeamVersion, command.expectedVersion].allSatisfy({ $0 <= 9_007_199_254_740_991 }),
                  command.contentHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
            if command.kind == .accept { guard command.expectedVersion == 0, command.instanceId == nil, command.optionId == nil else { return nil } }
            else { guard command.expectedVersion > 0, Self.serverID(command.instanceId ?? ""), CityReadRoute.validID(command.optionId ?? "") else { return nil } }
            write = true; regionID = command.regionId; return
        }
        return nil
    }
    static func serverID(_ id: String) -> Bool { UUID(uuidString: id)?.uuidString.lowercased() == id }
}
@available(macOS 14.0, *) @MainActor public final class CityNeutralTaskTransport: HTTPTransport {
    private let approval: CityNeutralTaskApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selected: (RuntimeDependencyContext) -> CityNeutralTaskApproval?
    public init(approval: CityNeutralTaskApproval, underlying: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?, selected: @escaping (RuntimeDependencyContext) -> CityNeutralTaskApproval?) {
        self.approval = approval; self.underlying = underlying; self.current = current; self.selected = selected
    }
    public func isCurrent() -> Bool { guard let live = current(), approval.matches(live), let selected = selected(live) else { return false }; return selected.revision == approval.revision && selected.matches(live) }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent(), !request.httpShouldHandleCookies, request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Authorization") == approval.context.session.token,
              let route = CityNeutralTaskRoute(request: request, baseURL: approval.context.baseURL),
              route.regionID == nil || route.regionID == approval.regionID, !route.write || approval.allowsWrite else { throw CityNeutralTaskError.disabled }
        let result = try await underlying.send(request)
        try Task.checkCancellation(); guard isCurrent() else { throw CityNeutralTaskError.stale }; return result
    }
}
@available(macOS 14.0, *) @MainActor public final class CityNeutralTaskService {
    public let approval: CityNeutralTaskApproval
    public let transport: CityNeutralTaskTransport
    public let board: CityReadBoard
    public init(approval: CityNeutralTaskApproval, transport: CityNeutralTaskTransport, board: CityReadBoard) { self.approval = approval; self.transport = transport; self.board = board }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let errorCode: String?; let data: T? }
    private struct Header: Decodable { let code: Int }
    private struct ReceiptData: Decodable {
        let requestId, requestStatus: String
        let contract, scope: String?
        let task: CityNeutralTask?
    }
    public func state() async throws -> CityNeutralTaskSnapshot {
        let (data, status) = try await execute("state", query: [.init(name: "regionId", value: approval.regionID)])
        try authorizeHeader(data)
        let envelope = try JSONDecoder().decode(Envelope<CityNeutralTaskSnapshot>.self, from: data)
        if status == 401 || envelope.code == 401 { throw APIError.unauthorized }
        if envelope.code == 403 { throw CityNeutralTaskError.server(403, envelope.errorCode ?? "FORBIDDEN") }
        guard status == 200, envelope.code == 200, let value = envelope.data else { throw CityNeutralTaskError.server(status, envelope.errorCode ?? "UNAVAILABLE") }
        try validate(value); return value
    }
    public func submit(_ command: CityNeutralTaskCommand) async throws {
        let (_, status) = try await execute("command", body: JSONEncoder().encode(command))
        if status == 401 { throw APIError.unauthorized }
        // Never trust a local success flag. Read the durable original request after every POST outcome.
    }
    public func receipt(_ id: UUID) async throws -> CityNeutralTaskReceipt {
        let (data, status) = try await execute("request/" + id.uuidString)
        try authorizeHeader(data)
        let envelope = try JSONDecoder().decode(Envelope<ReceiptData>.self, from: data)
        guard status != 401, envelope.code != 401 else { throw APIError.unauthorized }
        guard envelope.code != 403 else { throw CityNeutralTaskError.server(403, envelope.errorCode ?? "FORBIDDEN") }
        guard let receipt = envelope.data, receipt.requestId == id.uuidString, receipt.requestStatus == "COMPLETE", envelope.code == status else { throw CityNeutralTaskError.unknown }
        if status == 200 {
            guard receipt.contract == "CITY_NEUTRAL_TASK_V1", receipt.scope == "CITY", let task = receipt.task else { throw CityNeutralTaskError.malformed }
            try CityNeutralTaskResultRecovery.validate(task, requestID: receipt.requestId)
        } else if receipt.task != nil { throw CityNeutralTaskError.malformed }
        return .init(requestId: receipt.requestId, succeeded: status == 200, errorCode: envelope.errorCode, task: receipt.task)
    }
    func validate(_ value: CityNeutralTaskSnapshot) throws {
        guard value.contract == "CITY_NEUTRAL_TASK_V1", value.scope == "CITY" else { throw CityNeutralTaskError.malformed }
        if value.status == "JOIN_REQUIRED" {
            guard !value.writeApproved, value.binding == nil, value.teamId == nil, value.sessionId == nil, value.tasks.isEmpty else { throw CityNeutralTaskError.malformed }; return
        }
        guard ["AVAILABLE", "TEAM_NOT_READY"].contains(value.status), let binding = value.binding, binding.valid,
              binding.regionId == approval.regionID, binding.regionId == board.regionId, binding.boardId == board.boardId, binding.seasonId == board.seasonId,
              let team = value.teamId, CityNeutralTaskRoute.serverID(team), let version = value.teamVersion, version > 0, version <= 9_007_199_254_740_991,
              value.arrivalProof == "NOT_PROVIDED", value.ownershipEffect == "NONE", value.pointsEffect == "NONE",
              value.tasks.count <= 50, Set(value.tasks.map(\.id)).count == value.tasks.count else { throw CityNeutralTaskError.malformed }
        if value.status == "AVAILABLE" { guard let session = value.sessionId, CityNeutralTaskRoute.serverID(session) else { throw CityNeutralTaskError.malformed } }
        else if value.writeApproved { throw CityNeutralTaskError.malformed }
        for task in value.tasks {
            guard task.definition.valid, task.version >= 0, task.version <= 9_007_199_254_740_991, (0...task.definition.maxAttempts).contains(task.attempts) else { throw CityNeutralTaskError.malformed }
            if task.status == "NOT_ACCEPTED" {
                guard task.version == 0, task.attempts == 0, task.instanceId == nil, task.result == nil else { throw CityNeutralTaskError.malformed }; continue
            }
            guard ["ACTIVE", "PASSED", "EXHAUSTED"].contains(task.status), task.version == Int64(task.attempts) + 1,
                  let instance = task.instanceId, CityNeutralTaskRoute.serverID(instance), let time = task.acceptedAt, !time.isEmpty else { throw CityNeutralTaskError.malformed }
            if task.status == "ACTIVE" { guard task.attempts < task.definition.maxAttempts, task.result == nil else { throw CityNeutralTaskError.malformed } }
            else {
                guard let result = task.result, CityNeutralTaskRoute.serverID(result.resultId), UUID(uuidString: result.requestId) != nil,
                      result.outcome == task.status, result.attemptNumber == task.attempts, task.attempts > 0, !result.createdAt.isEmpty,
                      result.verifier == "NATIVE_OBJECTIVE_QA_PICK_V1", task.status != "EXHAUSTED" || task.attempts == task.definition.maxAttempts else { throw CityNeutralTaskError.malformed }
            }
        }
    }
    private func execute(_ path: String, query: [URLQueryItem]? = nil, body: Data? = nil) async throws -> (Data, Int) {
        var parts = URLComponents(url: approval.context.baseURL.appendingPathComponent("api/city-game/neutral-tasks/" + path), resolvingAgainstBaseURL: false)!; parts.queryItems = query
        var request = URLRequest(url: parts.url!); request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body; request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let result = try await transport.send(request); if result.1 == 401 { throw APIError.unauthorized }
        if result.1 == 403 { throw CityNeutralTaskError.server(403, "FORBIDDEN") }
        guard result.0.count <= 262144 else { throw CityNeutralTaskError.malformed }; return result
    }
    private func authorizeHeader(_ data: Data) throws {
        let header = try JSONDecoder().decode(Header.self, from: data)
        if header.code == 401 { throw APIError.unauthorized }
        if header.code == 403 { throw CityNeutralTaskError.server(403, "FORBIDDEN") }
    }
}
