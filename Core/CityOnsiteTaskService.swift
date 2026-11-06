import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CityOnsiteTaskError: Error, Equatable { case disabled, stale, malformed, unknown, server(Int, String) }
public enum CityOnsiteTaskAction: String, Codable { case accept = "ACCEPT", submit = "SUBMIT" }

/// Independent reviewed deployment grant. Login, player role and board visibility never create it.
@available(macOS 14.0, *) @MainActor @Observable public final class CityOnsiteTaskApproval {
    public let context: RuntimeDependencyContext
    public let regionID: String
    public let allowsWrite: Bool
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, regionID: String, allowsWrite: Bool = false, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role), context.session.accountID > 0, context.session.role == context.role,
              AuthRequestBuilder.isValidToken(context.session.token), CityReadRoute.validID(regionID),
              expiresAt > Date(), expiresAt.timeIntervalSinceNow <= 86400 else { throw CityOnsiteTaskError.disabled }
        self.context = context; self.regionID = regionID; self.allowsWrite = allowsWrite; self.expiresAt = expiresAt
    }
    public func revoke() { revoked = true }
    public func matches(_ live: RuntimeDependencyContext) -> Bool { !revoked && Date() < expiresAt && ContentDraftContextFence.matches(context, live) && context.session == live.session && live.session.role == live.role }
}
public struct CityOnsiteTaskDefinition: Codable, Equatable {
    public struct Option: Codable, Equatable, Identifiable { public let id, label: String }
    public let taskId, pointId, title, type, access, arrivalRequirement, scope, question, acceptanceReason, evidencePolicy, evidenceUse, reviewerPolicy, effectsPolicy: String
    public let options: [Option]
    public let maxAttempts, pointCost, pointReward, actionCost: Int
    var valid: Bool {
        CityReadRoute.validID(taskId) && CityReadRoute.validID(pointId) && !acceptanceReason.isEmpty && acceptanceReason.count <= 500 && !title.isEmpty && title.count <= 160 && !question.isEmpty && question.count <= 1000 &&
        type == "QA_PICK" && access == "ONSITE_ZERO_EFFECT" && arrivalRequirement == "MERCHANT_ATTESTED" && scope == "MEMBER_POINT_TEAM_ROUND" &&
        evidencePolicy == "SAME_EVIDENCE_VALID_ON_ACCEPT_AND_EACH_SUBMIT" && evidenceUse == "SINGLE_TASK_INSTANCE" && reviewerPolicy == "CURRENT_STORE_PERMISSION_AND_REVIEWER_VERIFY" && effectsPolicy == "NO_AUTOMATIC_EFFECTS" &&
        pointCost == 0 && pointReward == 0 && actionCost == 0 && (1...20).contains(maxAttempts) &&
        (2...8).contains(options.count) && Set(options.map(\.id)).count == options.count &&
        options.allSatisfy { CityReadRoute.validID($0.id) && !$0.label.isEmpty && $0.label.count <= 160 }
    }
}
public struct CityOnsiteTaskEvidence: Codable, Equatable {
    public let evidenceId, pointId, teamId, sessionId, contentHash, policyHash, roundId, expiresAt, assurance: String
    public let memberId, merchantId, placeId, releaseId: Int64
    public var unexpired: Bool { guard let date = CityOnsiteDates.parse(expiresAt) else { return false }; return Date() < date }
}
public struct CityOnsiteTaskResult: Codable, Equatable {
    public let resultId, instanceId, taskId, requestId, acceptRequestId, outcome, createdAt, evidenceCheckedAt, evidenceExpiresAt, evidenceId, evidencePolicyHash, pointId, teamId, sessionId, regionId, boardId, seasonId, roundId, rulesReleaseId, contentHash, taskHash, verifier, arrivalAssurance, effectsStatus: String
    public let memberId, merchantId, placeId, releaseId: Int64
    public let attemptNumber: Int
}
private enum CityOnsiteDates {
    static func parse(_ value: String) -> Date? { let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) }
}
public struct CityOnsiteTask: Codable, Equatable, Identifiable {
    public let definition: CityOnsiteTaskDefinition
    public let status, eligibility: String
    public let canAct: Bool
    public let evidence: CityOnsiteTaskEvidence?
    public let version: Int64
    public let attempts: Int
    public let instanceId, acceptedAt, evidenceId, acceptRequestId: String?
    public let result: CityOnsiteTaskResult?
    public var id: String { definition.taskId }
}
public struct CityOnsiteTaskSnapshot: Decodable, Equatable {
    public let contract, scope, status: String
    public let writeApproved: Bool
    public let binding: CityOnsiteTaskBinding?
    public let teamId, sessionId: String?
    public let teamVersion, memberId: Int64?
    public let tasks: [CityOnsiteTask]
    public let arrivalProof, ownershipEffect, pointsEffect, effectsStatus: String?
}
public struct CityOnsiteTaskCommand: Codable, Equatable {
    public let requestId, regionId, teamId, contentHash, taskId, evidenceId: String
    public let kind: CityOnsiteTaskAction
    public let expectedTeamVersion, releaseId, expectedVersion: Int64
    public let instanceId, optionId: String?
    public init(id: UUID, kind: CityOnsiteTaskAction, binding: CityOnsiteTaskBinding, teamId: String, teamVersion: Int64, task: CityOnsiteTask, optionId: String?) {
        requestId = id.uuidString; regionId = binding.regionId; self.teamId = teamId; contentHash = binding.contentHash
        taskId = task.id; evidenceId = task.evidence?.evidenceId ?? ""; self.kind = kind; expectedTeamVersion = teamVersion; releaseId = binding.releaseId
        expectedVersion = task.version; instanceId = kind == .submit ? task.instanceId : nil; self.optionId = kind == .submit ? optionId : nil
    }
}
public struct CityOnsiteTaskReceipt: Equatable { public let requestId: String; public let succeeded: Bool; public let errorCode: String?; public let result: CityOnsiteTaskResult? }

/// Exact onsite-only routes under a separate approval. Never aliases REMOTE_NEUTRAL or normal PlayTeam.
@available(macOS 14.0, *) @MainActor public struct CityOnsiteTaskRoute {
    public let write: Bool
    public let regionID: String?
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpBodyStream == nil, let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.fragment == nil, parts.user == nil, parts.password == nil else { return nil }
        let prefix = baseURL.appendingPathComponent("api/city-game/onsite-tasks").absoluteString
        if request.httpMethod == "GET", request.httpBody == nil {
            if let items = parts.queryItems, items.count == 1, items[0].name == "regionId", let region = items[0].value, CityReadRoute.validID(region) {
                var canonical = URLComponents(string: prefix + "/state")!; canonical.queryItems = [.init(name: "regionId", value: region)]
                guard canonical.url == url else { return nil }; write = false; regionID = region; return
            }
            if parts.query == nil, let id = UUID(uuidString: url.lastPathComponent), url.absoluteString == prefix + "/request/" + id.uuidString { write = false; regionID = nil; return }
            if parts.query == nil, Self.serverID(url.lastPathComponent), url.absoluteString == prefix + "/result/" + url.lastPathComponent { write = false; regionID = nil; return }
        }
        if request.httpMethod == "POST", url.absoluteString == prefix + "/command", parts.query == nil,
           request.value(forHTTPHeaderField: "Content-Type") == "application/json", let data = request.httpBody, data.count <= 4096,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String:Any], let command = try? JSONDecoder().decode(CityOnsiteTaskCommand.self, from: data) {
            var keys: Set<String> = ["requestId", "regionId", "kind", "releaseId", "contentHash", "teamId", "expectedTeamVersion", "taskId", "evidenceId", "expectedVersion"]
            if command.kind == .submit { keys.formUnion(["instanceId", "optionId"]) }
            guard Set(object.keys) == keys, UUID(uuidString: command.requestId)?.uuidString == command.requestId,
                  CityReadRoute.validID(command.regionId), CityReadRoute.validID(command.taskId), Self.serverID(command.evidenceId), Self.serverID(command.teamId),
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
@available(macOS 14.0, *) @MainActor public final class CityOnsiteTaskTransport: HTTPTransport {
    private let approval: CityOnsiteTaskApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let selected: (RuntimeDependencyContext) -> CityOnsiteTaskApproval?
    public init(approval: CityOnsiteTaskApproval, underlying: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?, selected: @escaping (RuntimeDependencyContext) -> CityOnsiteTaskApproval?) {
        self.approval = approval; self.underlying = underlying; self.current = current; self.selected = selected
    }
    public func isCurrent() -> Bool { guard let live = current(), approval.matches(live), let selected = selected(live) else { return false }; return selected.revision == approval.revision && selected.matches(live) }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent(), !request.httpShouldHandleCookies, request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Authorization") == approval.context.session.token,
              let route = CityOnsiteTaskRoute(request: request, baseURL: approval.context.baseURL),
              route.regionID == nil || route.regionID == approval.regionID, !route.write || approval.allowsWrite else { throw CityOnsiteTaskError.disabled }
        let result = try await underlying.send(request)
        try Task.checkCancellation(); guard isCurrent() else { throw CityOnsiteTaskError.stale }; return result
    }
}
@available(macOS 14.0, *) @MainActor public final class CityOnsiteTaskService {
    public let approval: CityOnsiteTaskApproval
    public let transport: CityOnsiteTaskTransport
    public let board: CityReadBoard
    public init(approval: CityOnsiteTaskApproval, transport: CityOnsiteTaskTransport, board: CityReadBoard) { self.approval = approval; self.transport = transport; self.board = board }
    private struct Envelope<T: Decodable>: Decodable { let code: Int; let errorCode: String?; let data: T? }
    private struct EnvelopeStatus: Decodable { let code: Int }
    private struct EnvelopeError: Decodable { let errorCode: String? }
    private struct ReceiptData: Decodable { let requestId, requestStatus: String; let result: CityOnsiteTaskResult? }
    private struct ResultData: Decodable { let contract, effectsStatus: String; let result: CityOnsiteTaskResult }
    public func state() async throws -> CityOnsiteTaskSnapshot {
        let (data, status) = try await execute("state", query: [.init(name: "regionId", value: approval.regionID)])
        try rejectCurrentDenial(data, status)
        let envelope = try JSONDecoder().decode(Envelope<CityOnsiteTaskSnapshot>.self, from: data)
        if status == 401 || envelope.code == 401 { throw APIError.unauthorized }
        guard status == 200, envelope.code == 200, let value = envelope.data else { throw CityOnsiteTaskError.server(status, envelope.errorCode ?? "UNAVAILABLE") }
        try validate(value); return value
    }
    public func submit(_ command: CityOnsiteTaskCommand) async throws {
        let (data, status) = try await execute("command", body: JSONEncoder().encode(command), permitsStoredRejection: true)
        // A stored business rejection may use 401/403. It still requires the original request GET.
        let envelope = try? JSONDecoder().decode(Envelope<ReceiptData>.self, from: data)
        if envelope?.code != status || envelope?.data?.requestId != command.requestId || envelope?.data?.requestStatus != "COMPLETE" {
            try rejectCurrentDenial(data, status)
        }
        // Never derive success or replay from a POST response, including a timeout or a server error.
    }
    public func receipt(_ id: UUID) async throws -> CityOnsiteTaskReceipt {
        let (data, status) = try await execute("request/" + id.uuidString, permitsStoredRejection: true)
        guard let envelope = try? JSONDecoder().decode(Envelope<ReceiptData>.self, from: data),
              let receipt = envelope.data, receipt.requestId == id.uuidString,
              receipt.requestStatus == "COMPLETE", envelope.code == status else {
            try rejectCurrentDenial(data, status)
            throw CityOnsiteTaskError.unknown
        }
        if status == 200 {
            guard envelope.errorCode == nil else { throw CityOnsiteTaskError.malformed }
            if let result = receipt.result { try validateResult(result); guard result.requestId == id.uuidString else { throw CityOnsiteTaskError.malformed } }
            return .init(requestId: receipt.requestId, succeeded: true, errorCode: nil, result: receipt.result)
        }
        guard (400...599).contains(status), let code = envelope.errorCode, !code.isEmpty, receipt.result == nil else {
            try rejectCurrentDenial(data, status)
            throw CityOnsiteTaskError.unknown
        }
        return .init(requestId: receipt.requestId, succeeded: false, errorCode: code, result: nil)
    }
    public func result(_ id: String) async throws -> CityOnsiteTaskResult {
        guard CityOnsiteTaskRoute.serverID(id) else { throw CityOnsiteTaskError.malformed }
        let (data, status) = try await execute("result/" + id)
        try rejectCurrentDenial(data, status)
        let envelope = try JSONDecoder().decode(Envelope<ResultData>.self, from: data)
        guard status == 200, envelope.code == 200, let value = envelope.data else { throw CityOnsiteTaskError.server(status, envelope.errorCode ?? "UNAVAILABLE") }
        guard value.contract == "CITY_ONSITE_TASK_V1", value.effectsStatus == "NOT_EXECUTED", value.result.resultId == id else { throw CityOnsiteTaskError.malformed }
        try validateResult(value.result); return value.result
    }
    private func validateResult(_ value: CityOnsiteTaskResult) throws {
        guard [value.resultId, value.instanceId, value.evidenceId, value.teamId, value.sessionId].allSatisfy(CityOnsiteTaskRoute.serverID),
              [value.taskId, value.requestId, value.acceptRequestId, value.pointId, value.roundId, value.rulesReleaseId].allSatisfy(CityReadRoute.validID),
              value.memberId == Int64(approval.context.session.accountID), value.regionId == approval.regionID, value.boardId == board.boardId, value.seasonId == board.seasonId,
              [value.memberId, value.merchantId, value.placeId, value.releaseId].allSatisfy({ $0 > 0 && $0 <= 9_007_199_254_740_991 }),
              [value.contentHash, value.taskHash, value.evidencePolicyHash].allSatisfy({ $0.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }),
              ["PASSED", "EXHAUSTED"].contains(value.outcome), (1...20).contains(value.attemptNumber), value.verifier == "NATIVE_OBJECTIVE_QA_PICK_V1",
              value.arrivalAssurance == "MERCHANT_ATTESTED", value.effectsStatus == "NOT_EXECUTED", CityOnsiteDates.parse(value.createdAt) != nil,
              let checked = CityOnsiteDates.parse(value.evidenceCheckedAt), let expires = CityOnsiteDates.parse(value.evidenceExpiresAt), checked < expires else { throw CityOnsiteTaskError.malformed }
    }
    func validate(_ value: CityOnsiteTaskSnapshot) throws {
        guard value.contract == "CITY_ONSITE_TASK_V1", value.scope == "CITY" else { throw CityOnsiteTaskError.malformed }
        if value.status == "JOIN_REQUIRED" {
            guard !value.writeApproved, value.binding == nil, value.teamId == nil, value.sessionId == nil, value.tasks.isEmpty else { throw CityOnsiteTaskError.malformed }; return
        }
        guard ["AVAILABLE", "TEAM_NOT_READY", "NOT_CONFIGURED"].contains(value.status), let binding = value.binding, binding.valid,
              binding.regionId == approval.regionID, binding.regionId == board.regionId, binding.boardId == board.boardId, binding.seasonId == board.seasonId,
              let team = value.teamId, CityOnsiteTaskRoute.serverID(team), let version = value.teamVersion, version > 0, version <= 9_007_199_254_740_991,
              value.memberId == Int64(approval.context.session.accountID), value.arrivalProof == "MERCHANT_ATTESTED_ONLY", value.ownershipEffect == "NONE", value.pointsEffect == "NONE", value.effectsStatus == "NOT_EXECUTED",
              value.tasks.count <= 50, Set(value.tasks.map(\.id)).count == value.tasks.count else { throw CityOnsiteTaskError.malformed }
        if value.status == "AVAILABLE" { guard let session = value.sessionId, CityOnsiteTaskRoute.serverID(session) else { throw CityOnsiteTaskError.malformed } }
        else if value.writeApproved { throw CityOnsiteTaskError.malformed }
        for task in value.tasks {
            guard task.definition.valid, task.version >= 0, task.version <= 9_007_199_254_740_991, (0...task.definition.maxAttempts).contains(task.attempts) else { throw CityOnsiteTaskError.malformed }
            guard !task.canAct || value.writeApproved && value.status == "AVAILABLE" && task.eligibility == "ELIGIBLE" && task.evidence != nil && ["NOT_ACCEPTED", "ACTIVE"].contains(task.status) else { throw CityOnsiteTaskError.malformed }
            if let evidence = task.evidence {
                guard CityOnsiteTaskRoute.serverID(evidence.evidenceId), evidence.memberId == value.memberId, evidence.pointId == task.definition.pointId,
                      evidence.teamId == team, evidence.sessionId == value.sessionId, evidence.releaseId == binding.releaseId, evidence.roundId == binding.rules.roundId,
                      evidence.contentHash == binding.contentHash, evidence.policyHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                      evidence.merchantId > 0, evidence.placeId > 0, evidence.assurance == "MERCHANT_ATTESTED", CityOnsiteDates.parse(evidence.expiresAt) != nil else { throw CityOnsiteTaskError.malformed }
            }
            if task.status == "NOT_ACCEPTED" {
                guard task.version == 0, task.attempts == 0, task.instanceId == nil, task.evidenceId == nil, task.acceptRequestId == nil, task.result == nil else { throw CityOnsiteTaskError.malformed }; continue
            }
            guard ["ACTIVE", "PASSED", "EXHAUSTED"].contains(task.status), task.version == Int64(task.attempts) + 1,
                  let instance = task.instanceId, CityOnsiteTaskRoute.serverID(instance), let evidenceId = task.evidenceId, CityOnsiteTaskRoute.serverID(evidenceId), evidenceId == task.evidence?.evidenceId, let acceptRequest = task.acceptRequestId, CityReadRoute.validID(acceptRequest), let time = task.acceptedAt, CityOnsiteDates.parse(time) != nil else { throw CityOnsiteTaskError.malformed }
            if task.status == "ACTIVE" { guard task.attempts < task.definition.maxAttempts, task.result == nil else { throw CityOnsiteTaskError.malformed } }
            else {
                guard let result = task.result, CityOnsiteTaskRoute.serverID(result.resultId), CityReadRoute.validID(result.requestId),
                      result.outcome == task.status, result.attemptNumber == task.attempts, task.attempts > 0, !result.createdAt.isEmpty,
                      result.verifier == "NATIVE_OBJECTIVE_QA_PICK_V1", task.status != "EXHAUSTED" || task.attempts == task.definition.maxAttempts else { throw CityOnsiteTaskError.malformed }
                try validateResult(result)
                guard result.taskId == task.id, result.instanceId == instance, result.evidenceId == evidenceId, result.acceptRequestId == acceptRequest, result.pointId == task.definition.pointId,
                      result.teamId == team, result.sessionId == value.sessionId, result.releaseId == binding.releaseId, result.contentHash == binding.contentHash,
                      result.roundId == binding.rules.roundId, result.rulesReleaseId == binding.rulesReleaseId else { throw CityOnsiteTaskError.malformed }
            }
        }
    }
    private func rejectCurrentDenial(_ data: Data, _ status: Int) throws {
        let header = try? JSONDecoder().decode(EnvelopeStatus.self, from: data)
        if status == 401 || header?.code == 401 { throw APIError.unauthorized }
        if status == 403 || header?.code == 403 {
            let detail = try? JSONDecoder().decode(EnvelopeError.self, from: data)
            throw CityOnsiteTaskError.server(403, detail?.errorCode ?? "FORBIDDEN")
        }
    }
    private func execute(_ path: String, query: [URLQueryItem]? = nil, body: Data? = nil, permitsStoredRejection: Bool = false) async throws -> (Data, Int) {
        var parts = URLComponents(url: approval.context.baseURL.appendingPathComponent("api/city-game/onsite-tasks/" + path), resolvingAgainstBaseURL: false)!; parts.queryItems = query
        var request = URLRequest(url: parts.url!); request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body; request.cachePolicy = .reloadIgnoringLocalCacheData; request.httpShouldHandleCookies = false
        request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let result = try await transport.send(request)
        guard result.0.count <= 1048576 else {
            if result.1 == 401 { throw APIError.unauthorized }
            if result.1 == 403 { throw CityOnsiteTaskError.server(403, "FORBIDDEN") }
            throw CityOnsiteTaskError.malformed
        }
        if !permitsStoredRejection { try rejectCurrentDenial(result.0, result.1) }
        return result
    }
}
