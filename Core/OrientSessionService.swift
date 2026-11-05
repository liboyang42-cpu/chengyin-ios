import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OrientSessionFailure: Error, Equatable {
    public let httpStatus: Int?
    public let code: Int?
    public let err: String?
    public let errorCode: String?
    public let message: String?
    public let data: OrientSessionJSON?
    public var isUnauthorized: Bool { httpStatus == 401 || code == 401 || err == "ORIENT_LOGIN_REQUIRED" || errorCode == "ORIENT_LOGIN_REQUIRED" }
    /// Only explicit lifecycle precondition rejections establish that no write ran.
    /// A missing receipt, conflict, malformed reply or transport error never does.
    var rejectedWithoutWrite: Bool {
        guard httpStatus == nil, let code, (400..<500).contains(code), let err else { return false }
        return ["ORIENT_SESSION_DISABLED", "ORIENT_ACK_REQUIRED", "ORIENT_SESSION_TERMINAL",
            "ORIENT_PRODUCT_TYPE_UNSUPPORTED", "ORIENT_TEAM_UNSUPPORTED", "ORIENT_BAD_REQUEST",
            "ORIENT_TASK_EVIDENCE_MISSING", "ORIENT_SESSION_NOT_STARTED", "ORIENT_TASK_NOT_FOUND"].contains(err)
    }
}

public enum OrientSessionWriteReceipt: Equatable {
    case session(OrientSessionView), task(OrientSessionTaskReceipt)
    case settlement(OrientSessionSettlement), alternative(OrientSessionAlternativeReceipt)
}

/// Sixteen player routes verified at hengyin 58f4cc4; c6 current and alternative
/// receipt are explicit opt-ins. Inject the approved, no-redirect fenced transport.
@MainActor public struct OrientSessionService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public let contract: OrientSessionContract
    public var supportsSessionDiscovery: Bool { contract == .currentC6 }
    public init(configuration: APIConfiguration, transport: any HTTPTransport, contract: OrientSessionContract = .frozen58) {
        self.configuration = configuration; self.transport = transport; self.contract = contract
    }
    /// c6 current is owner-scoped, read-only and returns data.sessions, including
    /// terminal rows. nil activity deliberately omits the filter; zero means self-play.
    /// Never take the newest/first row as the selected session.
    public func current(topicID: Int, activityID: Int? = nil, token: String) async throws -> OrientSessionList {
        guard supportsSessionDiscovery else { throw OrientSessionFlowError.discoveryUnavailable }
        guard topicID > 0, activityID == nil || activityID! >= 0 else { throw APIError.invalidRequest }
        var fields = ["topicId": String(topicID)]
        if let activityID { fields["activityId"] = String(activityID) }
        let value: OrientSessionList = try await execute(request("api/play/orient/session/current", fields: fields, token: token))
        guard value.sessions.allSatisfy({ $0.scope.topicID == topicID && (activityID == nil || $0.scope.activityID == activityID) }) else {
            throw APIError.malformedResponse
        }
        return value
    }
    public func view(sessionID: Int, scope: OrientSessionScope, token: String) async throws -> OrientSessionView {
        try positive(sessionID)
        let value: OrientSessionView = try await execute(request("api/play/orient/session", fields: ["sessionId": String(sessionID)], token: token))
        guard value.sessionID == sessionID, value.scope == scope else { throw APIError.malformedResponse }
        return value
    }
    public func safety(scope: OrientSessionScope, token: String) async throws -> OrientSessionSafety {
        let value: OrientSessionSafety = try await execute(request("api/orient/safety/check", method: "POST", fields: scope.fields, json: true, token: token))
        guard value.allowed == value.blockers.isEmpty else { throw APIError.malformedResponse }
        return value
    }
    public func lobby(scope: OrientSessionScope, token: String) async throws -> [OrientSessionTeam] {
        let values: [OrientSessionTeam] = try await execute(request("api/orient/team/lobby", fields: scope.ownerFields, token: token))
        guard Set(values.map(\.teamID)).count == values.count else { throw APIError.malformedResponse }
        return values
    }
    public func teamDetail(teamID: Int, token: String) async throws -> OrientSessionJSON {
        try positive(teamID)
        let value: OrientSessionJSON = try await execute(request("api/orient/team/detail", fields: ["teamId": String(teamID)], token: token))
        guard case .object(let root) = value, case .object(let team)? = root["team"],
              team["teamId"] == .integer(teamID) || team["teamId"] == .string(String(teamID)) else { throw APIError.malformedResponse }
        return value
    }
    public func ranking(scope: OrientSessionScope, token: String) async throws -> [OrientSessionRank] {
        let values: [OrientSessionRank] = try await execute(request("api/orient/team/ranking", fields: scope.ownerFields, token: token))
        guard Set(values.map(\.teamID)).count == values.count,
              Set(values.map(\.rank)).count == values.count else { throw APIError.malformedResponse }
        return values
    }
    public func score(sessionID: Int, scope: OrientSessionScope, token: String) async throws -> OrientSessionScore {
        try positive(sessionID)
        let value: OrientSessionScore = try await execute(request("api/orient/scoring/session/\(sessionID)", token: token))
        guard value.sessionID == sessionID, value.scope == scope else { throw APIError.malformedResponse }
        return value
    }
    /// Frozen sync is intrinsically idempotent and accepts no idempotency key or
    /// receipt kind. A timeout requires a score read, never fabricated SYNCED data.
    public func syncScore(sessionID: Int, token: String) async throws -> OrientSessionJSON {
        // c6 changed SYNC to a keyed operation with its own receipt. Do not send
        // the old unkeyed write into a deployment explicitly selected as c6.
        guard contract == .frozen58 else { throw APIError.invalidRequest }
        try positive(sessionID)
        let value: OrientSessionJSON = try await execute(request("api/orient/scoring/session/\(sessionID)/sync", method: "POST", token: token))
        guard case .object(let fields) = value,
              fields["sessionId"] == .integer(sessionID) || fields["sessionId"] == .string(String(sessionID)),
              let added = fields["added"]?.exactInteger, added >= 0,
              fields["totalCenti"]?.exactInteger != nil else { throw APIError.malformedResponse }
        return value
    }
    public func taskState(scope: OrientSessionScope, taskID: Int, playInstanceID: String? = nil, token: String) async throws -> OrientSessionTaskState {
        try positive(taskID)
        var fields = scope.fields; fields["taskId"] = String(taskID)
        if let playInstanceID { guard !playInstanceID.isEmpty else { throw APIError.invalidRequest }; fields["playInstanceId"] = playInstanceID }
        let value: OrientSessionTaskState = try await execute(request("api/orient/task/state", fields: fields, token: token))
        guard value.taskID == taskID else { throw APIError.malformedResponse }
        return value
    }

    public func write(_ pending: OrientSessionPending, token: String) async throws -> OrientSessionWriteReceipt {
        try pending.validate()
        let op = pending.operation
        var fields: [String: String] = ["idempotencyKey": pending.key]
        if let id = op.sessionID { fields["sessionId"] = String(id) }
        let path: String
        var json = false
        switch op {
        case .prepare: path = "api/play/orient/session/prepare"; fields.merge(pending.scope.fields) { _, new in new }
        case .start(_, let version): path = "api/play/orient/session/start"; fields["ackConfigVersion"] = String(version)
        case .abandon: path = "api/play/orient/session/abandon"
        case .task(_, let task, let alternative):
            path = "api/play/orient/session/task/\(task)/result"; fields["alternativeTaskType"] = alternative?.rawValue
        case .settle(let id): path = "api/orient/scoring/session/\(id)/settle"; fields.removeValue(forKey: "sessionId")
        case .alternative(_, let task, let instance, let evidence):
            path = "api/orient/task/alternative/submit"; json = true
            fields.removeValue(forKey: "sessionId"); fields.merge(pending.scope.fields) { _, new in new }
            fields["taskId"] = String(task); fields["playInstanceId"] = instance
            fields["alternativeTaskType"] = evidence.type.rawValue; fields.merge(evidence.fields) { _, new in new }
        }
        return try await receiptValue(request(path, method: "POST", fields: fields, json: json, token: token), pending: pending)
    }

    /// Prepare's session ID must come from a real route-state/session read. The
    /// freeze lacks /current; absence of an ID keeps the original operation pending.
    /// Frozen alternatives recover by explicitly replaying the same stored command.
    /// c6 can read their original scoped receipt; task-state never proves an attempt.
    public func receipt(_ pending: OrientSessionPending, resolvedPrepareSessionID: Int? = nil, token: String) async throws -> OrientSessionWriteReceipt {
        try pending.validate()
        if case .alternative(let id, let task, let instance, _) = pending.operation {
            guard contract == .currentC6 else { throw OrientSessionFlowError.receiptUnresolved }
            _ = try await view(sessionID: id, scope: pending.scope, token: token)
            var fields = pending.scope.fields
            fields["taskId"] = String(task); fields["playInstanceId"] = instance; fields["idempotencyKey"] = pending.key
            return try await receiptValue(request("api/orient/task/alternative/receipt", fields: fields, token: token), pending: pending)
        }
        guard let id = pending.operation.sessionID ?? resolvedPrepareSessionID, id > 0 else { throw OrientSessionFlowError.sessionRequired }
        // Verifies topic/activity before reading a receipt for a supplied candidate ID.
        _ = try await view(sessionID: id, scope: pending.scope, token: token)
        var fields = ["sessionId": String(id), "idempotencyKey": pending.key]
        let path: String
        if case .settle = pending.operation { path = "api/orient/scoring/receipt"; fields["kind"] = "SETTLE" }
        else { path = "api/play/orient/session/receipt" }
        let receipt = try await receiptValue(request(path, fields: fields, token: token), pending: pending)
        if case .session(let value) = receipt, value.sessionID != id { throw APIError.malformedResponse }
        return receipt
    }

    private func receiptValue(_ request: URLRequest, pending: OrientSessionPending) async throws -> OrientSessionWriteReceipt {
        switch pending.operation {
        case .prepare, .start, .abandon:
            let value: OrientSessionView = try await execute(request)
            guard value.scope == pending.scope, pending.operation.sessionID == nil || value.sessionID == pending.operation.sessionID else { throw APIError.malformedResponse }
            if case .prepare = pending.operation { guard !value.phase.isTerminal else { throw APIError.malformedResponse } }
            if case .start = pending.operation { guard value.phase == .running, value.startedAt != nil else { throw APIError.malformedResponse } }
            if case .abandon = pending.operation { guard value.phase == .abandoned else { throw APIError.malformedResponse } }
            return .session(value)
        case .task(let id, let task, let alternative):
            let value: OrientSessionTaskReceipt = try await execute(request, acceptedRejection: "ORIENT_TASK_ALREADY_COMPLETED")
            guard value.sessionID == id, value.taskID == task, value.alternativeTaskType == alternative else { throw APIError.malformedResponse }
            return .task(value)
        case .settle(let id):
            let value: OrientSessionSettlement = try await execute(request)
            guard value.sessionID == id else { throw APIError.malformedResponse }
            return .settlement(value)
        case .alternative(_, let task, _, let evidence):
            let value: OrientSessionAlternativeReceipt = try await execute(request, acceptedRejection: "ORIENT_ALT_VERIFY_FAILED")
            guard value.taskID == task, value.alternativeTaskType == evidence.type else { throw APIError.malformedResponse }
            return .alternative(value)
        }
    }

    private func positive(_ id: Int) throws { guard id > 0 else { throw APIError.invalidRequest } }
    private func request(_ path: String, method: String = "GET", fields: [String: String] = [:], json: Bool = false, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(path))
        request.httpMethod = method; request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue(token, forHTTPHeaderField: "Authorization")
        if method == "GET" {
            guard var url = URLComponents(url: request.url!, resolvingAgainstBaseURL: false) else { throw APIError.invalidConfiguration }
            url.queryItems = fields.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            guard let final = url.url else { throw APIError.invalidRequest }; request.url = final
        } else if json {
            // Spring Map<String,Object> conversion accepts these exact decimal strings.
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        } else {
            // Lifecycle/scoring controllers bind form parameters, not @RequestBody.
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
            let body = try fields.sorted { $0.key < $1.key }.map { key, value -> String in
                guard let k = key.addingPercentEncoding(withAllowedCharacters: allowed),
                      let v = value.addingPercentEncoding(withAllowedCharacters: allowed) else { throw APIError.invalidRequest }
                return k + "=" + v
            }.joined(separator: "&")
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(body.utf8)
        }
        return request
    }
    private struct Header: Decodable {
        let code: Int?
        let err: String?
        let errorCode: String?
        let msg: String?
        let data: OrientSessionJSON?
        private enum CodingKeys: String, CodingKey { case code, err, errorCode, msg, data }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.orientOptionalInt(.code); err = try c.decodeIfPresent(String.self, forKey: .err)
            errorCode = try c.decodeIfPresent(String.self, forKey: .errorCode)
            msg = try c.decodeIfPresent(String.self, forKey: .msg); data = try c.decodeIfPresent(OrientSessionJSON.self, forKey: .data)
        }
    }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value }
    private func execute<Value: Decodable>(_ request: URLRequest, acceptedRejection: String? = nil) async throws -> Value {
        try Task.checkCancellation()
        let (bytes, status) = try await transport.send(request)
        try Task.checkCancellation()
        guard bytes.count <= 1_048_576 else { throw APIError.malformedResponse }
        let header = try? JSONDecoder().decode(Header.self, from: bytes)
        guard (200..<300).contains(status) else {
            throw OrientSessionFailure(httpStatus: status, code: header?.code, err: header?.err,
                errorCode: header?.errorCode, message: header?.msg, data: header?.data)
        }
        guard let header else { throw APIError.malformedResponse }
        let accepted = acceptedRejection == "ORIENT_TASK_ALREADY_COMPLETED" && header.code == 409 && header.err == acceptedRejection
            || acceptedRejection == "ORIENT_ALT_VERIFY_FAILED" && header.code == 500 && header.errorCode == acceptedRejection
        guard header.code == 200 || accepted else {
            throw OrientSessionFailure(httpStatus: nil, code: header.code, err: header.err,
                errorCode: header.errorCode, message: header.msg, data: header.data)
        }
        do { return try JSONDecoder().decode(Envelope<Value>.self, from: bytes).data }
        catch { throw APIError.malformedResponse }
    }
}
