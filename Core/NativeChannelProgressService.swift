import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 4176 wire cross-checked against the complete relevant 251834 source files. This service adds no authority, fact writer or management endpoint.
public struct NativeChannelProgressService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) { self.configuration = configuration; self.transport = transport }
    public func definitions(channelID: Int64, token: String) async throws -> NativeChannelProgressDefinitions {
        let result: NativeChannelProgressDefinitions = try await get("api/channel/\(channelID)/board", token: token)
        guard result.visible, let rows = result.list, rows.count <= 10,
              Set(rows.map(\.boardKey)).count == rows.count,
              rows.allSatisfy({ $0.topicId > 0 && $0.activityId >= 0 && $0.revision >= 0 && (1...50).contains($0.rowLimit) }) else { throw NativeChannelProgressError.malformed }
        return result
    }
    public func overview(channelID: Int64, token: String) async throws -> NativeChannelProgressOverview {
        let value: NativeChannelProgressOverview = try await get("api/channel/\(channelID)/progress/overview", token: token)
        if value.visible {
            guard value.channelId == channelID, value.topicId.map({ $0 > 0 }) == true, value.activityId.map({ $0 >= 0 }) == true,
                  value.revision?.isEmpty == false, let members = value.members, (0...50).contains(members.total),
                  (0...members.total).contains(members.completed), members.avgPercent.map({ (0...100).contains($0) }) ?? (members.total == 0) else { throw NativeChannelProgressError.malformed }
        } else if value.members != nil || value.teams != nil { throw NativeChannelProgressError.malformed }
        return value
    }
    public func page(channelID: Int64, query: NativeChannelProgressQuery, detail: Bool, cursor: String?, token: String) async throws -> NativeChannelProgressPage {
        var fields = queryFields(query, filters: detail)
        if let cursor { fields["cursor"] = cursor }
        let page: NativeChannelProgressPage = try await get(boardPath(channelID, query.boardKey) + (detail ? "/detail" : "/top"), query: fields, token: token)
        return try page.validated()
    }
    public func best(channelID: Int64, query: NativeChannelProgressQuery, token: String) async throws -> NativeChannelProgressRow {
        let row: NativeChannelProgressRow = try await get(boardPath(channelID, query.boardKey) + "/me/best", query: ["period":query.period], token: token)
        return try row.validated()
    }
    public func recent(channelID: Int64, query: NativeChannelProgressQuery, cursor: String?, token: String) async throws -> NativeChannelProgressPage {
        var fields = ["period":query.period, "limit":String(query.limit)]
        if let cursor { fields["cursor"] = cursor }
        let result: NativeChannelProgressPage = try await get(boardPath(channelID, query.boardKey) + "/me/recent", query: fields, token: token)
        return try result.validated()
    }
    public func version(channelID: Int64, boardKey: String, token: String) async throws -> NativeChannelProgressVersion {
        let value: NativeChannelProgressVersion = try await get(boardPath(channelID, boardKey) + "/version", token: token)
        guard !value.revision.isEmpty else { throw NativeChannelProgressError.malformed }; return value
    }
    public func meter(channelID: Int64, board: NativeChannelProgressBoard, actorID: Int64, token: String) async throws -> NativeChannelProgressMeter {
        let result: NativeChannelProgressMeter = try await get("api/progress/meter", query: ["channel_id":String(channelID), "topic_id":String(board.topicId),
            "activity_id":String(board.activityId), "subject_type":"MEMBER", "subject_id":String(actorID)], token: token)
        if result.visible {
            guard result.subjectId == actorID, result.topicId == board.topicId, result.activityId == board.activityId,
                  let required = result.required, required > 0, let done = result.done, done >= 0,
                  let percent = result.percent, (0...100).contains(percent), result.revision != nil else { throw NativeChannelProgressError.malformed }
        } else if result.required != nil || result.done != nil || result.percent != nil || result.subjectId != nil { throw NativeChannelProgressError.malformed }
        return result
    }
    public func privacy(channelID: Int64?, token: String) async throws -> NativeChannelProgressPrivacy {
        let result: NativeChannelProgressPrivacy = try await get("api/privacy/progress", query: channelID.map({ ["channel_id":String($0)] }) ?? [:], token: token)
        guard result.revision >= 0, result.effective != nil, result.appliesTo == "CHANNEL_PROGRESS" else { throw NativeChannelProgressError.malformed }
        _ = try result.values(); return result
    }
    public func save(_ command: NativeChannelProgressPrivacyCommand, token: String) async throws -> NativeChannelProgressPrivacy {
        let result: NativeChannelProgressPrivacy = try await execute("api/privacy/progress", method: "POST", body: command.wireBody(), token: token)
        guard command.matches(result) else { throw NativeChannelProgressError.malformed }; return result
    }
    public func receipt(_ command: NativeChannelProgressPrivacyCommand, token: String) async throws -> NativeChannelProgressPrivacy? {
        do {
            let result: NativeChannelProgressPrivacy = try await get("api/progress/requests/\(command.requestId)", token: token)
            guard command.matches(result) else { throw NativeChannelProgressError.malformed }; return result
        } catch NativeChannelProgressError.server(404, "PROGRESS_REQUEST_NOT_FOUND") { return nil }
    }
    private func boardPath(_ channel: Int64, _ key: String) throws -> String {
        guard channel > 0, key.range(of: "^[a-z][a-z0-9_]{0,31}$", options: .regularExpression) != nil else { throw NativeChannelProgressError.invalid }
        return "api/channel/\(channel)/board/\(key)"
    }
    private func queryFields(_ query: NativeChannelProgressQuery, filters: Bool) -> [String:String] {
        var fields = ["period":query.period, "limit":String(query.limit)]
        if filters { if let completed = query.completed { fields["filter[completed]"] = String(completed) }; if let team = query.teamID { fields["filter[team_id]"] = String(team) } }
        return fields
    }
    private func get<Value: Decodable>(_ path: String, query: [String:String] = [:], token: String) async throws -> Value {
        try await execute(path, method: "GET", query: query, token: token)
    }
    private struct Header: Decodable { let code: Int; let errorCode: String?; let outcomeKnown: Bool?; let outcomeConfirmed: Bool? }
    private struct Envelope<Value: Decodable>: Decodable { let data: Value }
    private func execute<Value: Decodable>(_ path: String, method: String, query: [String:String] = [:], body: Data? = nil, token: String) async throws -> Value {
        guard AuthRequestBuilder.isValidToken(token), var parts = URLComponents(url: configuration.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else { throw NativeChannelProgressError.invalid }
        if !query.isEmpty { parts.queryItems = query.sorted { $0.key < $1.key }.map({ URLQueryItem(name: $0.key, value: $0.value) }) }
        guard let url = parts.url else { throw NativeChannelProgressError.invalid }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(token, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        try Task.checkCancellation()
        let (data,status) = try await transport.send(request)
        try Task.checkCancellation()
        guard data.count <= 2 * 1024 * 1024 else { throw NativeChannelProgressError.malformed }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let header = try? decoder.decode(Header.self, from: data)
        if header?.errorCode == "OUTCOME_UNKNOWN" || header?.outcomeKnown == false || header?.outcomeConfirmed == false {
            throw NativeChannelProgressError.server(status: 500, code: "OUTCOME_UNKNOWN")
        }
        guard (200..<300).contains(status), header?.code == 200 else {
            throw NativeChannelProgressError.server(status: (200..<300).contains(status) ? (header?.code ?? status) : status, code: header?.errorCode)
        }
        do { return try decoder.decode(Envelope<Value>.self, from: data).data }
        catch { throw NativeChannelProgressError.malformed }
    }
}
