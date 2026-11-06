import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Original moderation commands only. A protected pending intent is not authority and is never auto-sent.
@MainActor @Observable public final class NativeChannelModerationFlow {
    public struct Action: Identifiable, Equatable {
        public let id: String, target: String, type: String, status: String, version: String
        public let scopeType: String, scopeID: String, reason: String, expiresAt: String
    }
    public enum Operation: String, Codable, CaseIterable { case timeout, kick, ban, revoke }
    public enum State: Equatable { case idle, loading, ready, reviewing, submitting, unknown, applied, unavailable }
    public private(set) var state: State = .idle
    public private(set) var reviewedSummary = ""
    public private(set) var originalRequestID: String?
    public private(set) var readingCurrent = false
    public private(set) var currentReadFailed = false
    private var storedActions: [Action] = []
    private var storedResult: Action?
    private var cursor: String?
    private var more = false
    private var generation: UInt64 = 0
    private var active = false
    private var busy = false
    private var storageFailed = false
    private var pending: Record?
    private var review: Record?
    @ObservationIgnored private let captured: NativeChannelManagementIntegrationContext
    @ObservationIgnored private let channels: any NativeChannelManagementIntegrationContextProviding
    @ObservationIgnored private let context: RuntimeDependencyContext
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let storage: any ProjectEditDataStorage
    @ObservationIgnored private let current: () -> Bool
    @ObservationIgnored private let permits: (String, String) -> Bool
    @ObservationIgnored private let unauthorized: () -> Void
    private static var leases: Set<String> = []
    private struct Record: Codable, Equatable {
        let version: Int
        let owner: String
        let operation: Operation
        let requestID: String
        let targetID: String
        let actionID: String?
        let actionType: String
        let path: String
        let body: Data
    }
    private var owner: String { [context.session.namespace,context.baseURL.absoluteString,String(context.session.accountID),"1",captured.ownerID.rawValue,captured.channelID.rawValue].map { "\($0.utf8.count):\($0)" }.joined() }
    private var key: String { "channel-moderation.v1." + Data(owner.utf8).base64EncodedString() }
    public var isCurrent: Bool { active && current() && channels.contextIsCurrent(captured) }
    public var actions: [Action] { isCurrent ? storedActions : [] }
    public var result: Action? { isCurrent ? storedResult : nil }
    public var hasPending: Bool { pending != nil }
    public var canReadMore: Bool { isCurrent && !busy && more && cursor != nil }
    public var canRecover: Bool { isCurrent && !busy && !storageFailed && pending.map { permits("GET",receiptPath($0.requestID)) } == true }
    public var canRetry: Bool { canRecover && pending.map { permits("POST",$0.path) && capability($0.actionType) } == true }
    public func canPrepare(_ operation: Operation) -> Bool {
        isCurrent && !busy && !storageFailed && pending == nil && operation != .revoke
            && capability(operation.rawValue.uppercased()) && permits("POST","api/im/moderation/" + operation.rawValue)
    }
    public func canRevoke(_ action: Action) -> Bool {
        isCurrent && !busy && !storageFailed && pending == nil && action.status == "ACTIVE"
            && ["TIMEOUT","BAN"].contains(action.type) && capability(action.type)
            && permits("POST","api/im/moderation/\(action.id)/revoke")
    }
    public init(captured: NativeChannelManagementIntegrationContext, channels: any NativeChannelManagementIntegrationContextProviding,
                context: RuntimeDependencyContext, transport: any HTTPTransport, storage: any ProjectEditDataStorage,
                current: @escaping () -> Bool, permits: @escaping (String,String) -> Bool, unauthorized: @escaping () -> Void) throws {
        guard captured.ownerType == "CLUB", captured.identity.owner.accountID == context.session.accountID,
              captured.identity.owner.namespace == context.session.namespace, captured.identity.owner.baseURL == context.baseURL.absoluteString,
              captured.identity.epoch == context.session.epoch, channels.contextIsCurrent(captured) else { throw APIError.unauthorized }
        self.captured = captured; self.channels = channels; self.context = context; self.transport = transport; self.storage = storage
        self.current = current; self.permits = permits; self.unauthorized = unauthorized
        do { pending = try restore(); originalRequestID = pending?.requestID; if pending != nil { state = .unknown } }
        catch { storageFailed = true; state = .unavailable }
    }
    public func deactivate() { generation &+= 1; active = false; readingCurrent = false; currentReadFailed = false; review = nil; reviewedSummary = ""; storedActions = []; storedResult = nil; cursor = nil; more = false; state = .unavailable }
    public func activate() async { guard !active else { return }; active = true; await refresh() }
    public func refresh() async { await load(before: nil) }
    public func loadMore() async { guard canReadMore, let cursor else { return }; await load(before: cursor) }
    private func load(before: String?) async {
        guard isCurrent, !busy, !storageFailed, Self.leases.insert(key).inserted else { return }
        busy = true; let run = generation; defer { busy = false; Self.leases.remove(key) }
        do {
            pending = try restore(); originalRequestID = pending?.requestID
            if let original = pending {
                state = .unknown
                let receipt = try await exchange("GET",receiptPath(original.requestID))
                guard valid(run) else { throw APIError.unauthorized }
                if receipt["state"] as? String == "APPLIED", let result = receipt["result"] as? [String:Any] { try await settle(original,result) }
                return // Recovery retires the old page cursor; never append through it.
            }
            await readCurrent(before:before,afterApplied:state == .applied)
        } catch { guard valid(run) else { return }; storedActions = []; cursor = nil; more = false; if isCurrent { state = pending == nil ? .unavailable : .unknown } }
    }
    /// Current records and the original immutable command result are separate facts.
    private func readCurrent(before: String?, afterApplied: Bool) async {
        let run = generation
        readingCurrent = true; currentReadFailed = false
        if before == nil { storedActions = []; cursor = nil; more = false }
        if !afterApplied { state = .loading }
        defer { readingCurrent = false }
        do {
            guard captured.serverPermissionNames.contains("VIEW_AUDIT") else { throw APIError.unauthorized }
            var query = [URLQueryItem(name:"guild_kind",value:"1"),URLQueryItem(name:"guild_id",value:captured.ownerID.rawValue),URLQueryItem(name:"limit",value:"50")]
            if let before { query.append(URLQueryItem(name:"cursor",value:before)) }
            let data = try await exchange("GET","api/im/moderation/actions",query:query)
            guard valid(run), let values = data["list"] as? [[String:Any]], values.count <= 50, let hasMore = data["has_more"] as? Bool else { throw APIError.malformedResponse }
            let page = try values.map(parseAction); var previous = before.flatMap(Int64.init)
            for row in page { guard let id = Int64(row.id), previous.map({ id < $0 }) ?? true else { throw APIError.malformedResponse }; previous = id }
            let next = NativeChannelGovernanceNotice.positive(data["next_cursor"])
            guard hasMore ? next != nil && next == page.last?.id : next == nil else { throw APIError.malformedResponse }
            if before == nil { storedActions = page } else {
                guard Set(storedActions.map(\.id)).isDisjoint(with:page.map(\.id)) else { throw APIError.malformedResponse }; storedActions += page
            }
            cursor = next; more = hasMore; state = afterApplied ? .applied : .ready
        } catch {
            guard valid(run) else { return }
            storedActions = []; cursor = nil; more = false
            if isCurrent { currentReadFailed = true; state = afterApplied ? .applied : .unavailable }
        }
    }
    @discardableResult public func prepare(_ operation: Operation, target: String, seconds: Int, reasonCode: String, reason: String, deleteMessageSeconds: Int = 0) -> Bool {
        let reason = reason.trimmingCharacters(in:.whitespacesAndNewlines), code = reasonCode.trimmingCharacters(in:.whitespacesAndNewlines)
        guard canPrepare(operation), NativeChannelGovernanceNotice.positive(target) != nil, !reason.isEmpty, reason.utf16.count <= 500,
              (code == "NOISE" || NativeChannelReportReason(rawValue: code) != nil),
              (0...604800).contains(deleteMessageSeconds), operation == .ban || deleteMessageSeconds == 0,
              operation == .timeout ? (60...2419200).contains(seconds) : operation == .ban ? (60...7776000).contains(seconds) : seconds == 0 else { return false }
        let id = UUID().uuidString.lowercased(), type = operation.rawValue.uppercased()
        let body: [String:Any] = ["guild_kind":1,"guild_id":captured.ownerID.rawValue,"target_member_id":target,
            "scope_type":operation == .timeout ? "CHANNEL" : "GUILD","scope_id":operation == .timeout ? captured.channelID.rawValue : captured.ownerID.rawValue,
            "duration_sec":seconds,"reason_code":code,"reason_text":reason,"request_id":id,"delete_message_sec":deleteMessageSeconds]
        return stage(operation,id:id,target:target,action:nil,type:type,path:"api/im/moderation/" + operation.rawValue,body:body,
                     summary:"\(type) · 成员 \(target) · \(seconds) 秒\n\(reason)\n历史消息删除窗口：\(deleteMessageSeconds) 秒。" +
                        (deleteMessageSeconds > 0 ? "撤销封禁不会恢复这部分历史删除。" : "不删除历史消息。") + "最终层级与资格由原服务端判定。")
    }
    @discardableResult public func prepareRevoke(_ action: Action, reason: String) -> Bool {
        let reason = reason.trimmingCharacters(in:.whitespacesAndNewlines)
        guard canRevoke(action), storedActions.contains(action), !reason.isEmpty, reason.utf16.count <= 500 else { return false }
        let id = UUID().uuidString.lowercased()
        return stage(.revoke,id:id,target:action.target,action:action.id,type:action.type,path:"api/im/moderation/\(action.id)/revoke",
                     body:["request_id":id,"version":action.version,"reason":reason],
                     summary:"撤销原 \(action.type) 处置 \(action.id) · 成员 \(action.target)\n\(reason)\n不恢复已取消的历史删除，也不自动恢复成员或角色。")
    }
    private func stage(_ operation: Operation,id: String,target: String,action: String?,type: String,path: String,body: [String:Any],summary: String) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject:body,options:[.sortedKeys,.withoutEscapingSlashes]) else { return false }
        review = Record(version:1,owner:owner,operation:operation,requestID:id,targetID:target,actionID:action,actionType:type,path:path,body:data)
        reviewedSummary = summary; state = .reviewing; return true
    }
    public func cancelReview() { review = nil; reviewedSummary = ""; if pending == nil { state = .ready } }
    public func confirm() async {
        guard isCurrent, !busy, !storageFailed, pending == nil, let original = review, capability(original.actionType),
              permits("POST",original.path), Self.leases.insert(key).inserted else { return }
        busy = true; let run = generation; defer { busy = false; Self.leases.remove(key) }
        do {
            guard try restore() == nil else { throw APIError.invalidRequest }
            try storage.write(JSONEncoder().encode(original),key:key)
            guard try restore() == original else { throw APIError.malformedResponse }
            pending = original; originalRequestID = original.requestID; review = nil; state = .submitting
            let result = try await exchange("POST",original.path,body:original.body)
            guard valid(run) else { return }
            try await settle(original,result)
        } catch { guard valid(run) else { return }; if isCurrent { state = pending == nil ? .unavailable : .unknown }; if pending == nil { storageFailed = true } }
    }
    public func retryOriginal() async {
        guard canRetry, let original = pending, Self.leases.insert(key).inserted else { return }
        busy = true; let run = generation; defer { busy = false; Self.leases.remove(key) }
        do {
            guard try restore() == original else { throw APIError.invalidRequest }
            let receipt = try await exchange("GET",receiptPath(original.requestID))
            guard valid(run) else { throw APIError.unauthorized }
            if receipt["state"] as? String == "APPLIED", let result = receipt["result"] as? [String:Any] { try await settle(original,result); return }
            guard receipt["state"] as? String == "NOT_FOUND", receipt["retry_with_original_request"] as? Bool == true else { state = .unknown; return }
            state = .submitting
            let result = try await exchange("POST",original.path,body:original.body)
            guard valid(run) else { return }
            try await settle(original,result)
        } catch { guard valid(run) else { return }; if isCurrent { state = .unknown } }
    }
    private func settle(_ original: Record,_ value: [String:Any]) async throws {
        guard isCurrent, try restore() == original, value["request_id"] as? String == original.requestID,
              value["state"] as? String == "APPLIED" else { throw APIError.malformedResponse }
        let action = try parseAction(value)
        guard action.target == original.targetID,
              original.operation == .revoke ? NativeChannelGovernanceNotice.positive(value["revoked_action_id"]) == original.actionID
                : action.type == original.actionType else { throw APIError.malformedResponse }
        try storage.remove(key); guard try restore() == nil else { throw APIError.malformedResponse }
        pending = nil; originalRequestID = nil; storedResult = action; state = .applied
        // A revoke receipt may describe a new reversal action; do not patch its
        // fields into the old ACTIVE target or retain that target as selectable.
        storedActions = []; cursor = nil; more = false
        await readCurrent(before:nil,afterApplied:true)
    }
    private func parseAction(_ value: [String:Any]) throws -> Action {
        guard NativeChannelGovernanceNotice.positive(value["guild_kind"]) == "1", NativeChannelGovernanceNotice.positive(value["guild_id"]) == captured.ownerID.rawValue,
              let id = NativeChannelGovernanceNotice.positive(value["action_id"]), let target = NativeChannelGovernanceNotice.positive(value["target_member_id"]),
              let type = value["action_type"] as? String, let status = value["status"] as? String,
              let version = value["version"] as? String, let n = Int64(version), n >= 0, String(n) == version,
              let scope = value["scope_type"] as? String, ["GUILD","CHANNEL"].contains(scope),
              let scopeID = NativeChannelGovernanceNotice.positive(value["scope_id"]),
              scope != "GUILD" || scopeID == captured.ownerID.rawValue else { throw APIError.malformedResponse }
        return Action(id:id,target:target,type:type,status:status,version:version,scopeType:scope,scopeID:scopeID,
                      reason:value["reason_text"] as? String ?? "",expiresAt:value["expires_at"] as? String ?? "")
    }
    private func restore() throws -> Record? {
        guard let data = try storage.read(key) else { return nil }; guard data.count <= 16 * 1024 else { throw APIError.malformedResponse }
        let row = try JSONDecoder().decode(Record.self,from:data), encoded = try JSONEncoder().encode(JSONDecoder().decode(Record.self,from:data))
        guard row.version == 1, row.owner == owner, UUID(uuidString:row.requestID) != nil, NativeChannelGovernanceNotice.positive(row.targetID) != nil,
              row.body.count <= 8192, (try JSONSerialization.jsonObject(with:data) as? NSDictionary) == (try JSONSerialization.jsonObject(with:encoded) as? NSDictionary),
              let body = try JSONSerialization.jsonObject(with:row.body) as? [String:Any], body["request_id"] as? String == row.requestID else { throw APIError.malformedResponse }
        if row.operation == .revoke {
            guard let action = row.actionID, NativeChannelGovernanceNotice.positive(action) != nil, ["TIMEOUT","BAN"].contains(row.actionType),
                  row.path == "api/im/moderation/\(action)/revoke", body["version"] is String, body["reason"] is String else { throw APIError.malformedResponse }
        } else {
            guard row.path == "api/im/moderation/" + row.operation.rawValue, row.actionID == nil, row.actionType == row.operation.rawValue.uppercased(),
                  NativeChannelGovernanceNotice.positive(body["guild_kind"]) == "1", body["guild_id"] as? String == captured.ownerID.rawValue,
                  body["target_member_id"] as? String == row.targetID,
                  body["scope_type"] as? String == (row.operation == .timeout ? "CHANNEL" : "GUILD"),
                  body["scope_id"] as? String == (row.operation == .timeout ? captured.channelID.rawValue : captured.ownerID.rawValue) else { throw APIError.malformedResponse }
        }
        return row
    }
    private func capability(_ type: String) -> Bool {
        let permission: String
        switch type { case "TIMEOUT": permission = "TIMEOUT_MEMBER"; case "KICK": permission = "KICK_MEMBER"; case "BAN": permission = "BAN_MEMBER"; default: return false }
        return captured.serverPermissionNames.contains(permission)
    }
    private func receiptPath(_ id: String) -> String { "api/channel-platform/governance/moderation/requests/" + id }
    private func valid(_ run: UInt64) -> Bool { run == generation && isCurrent && !Task.isCancelled }
    private func exchange(_ method: String,_ path: String,body: Data? = nil,query: [URLQueryItem] = []) async throws -> [String:Any] {
        let run = generation
        guard valid(run), permits(method,path) else { throw APIError.unauthorized }
        let fresh = try await channels.currentChannelContext(channelID:captured.channelID)
        guard valid(run), permits(method,path), fresh == captured else { throw APIError.unauthorized }
        guard var components = URLComponents(url:context.baseURL.appendingPathComponent(path),resolvingAgainstBaseURL:false) else { throw APIError.invalidRequest }
        if !query.isEmpty { components.queryItems = query }; guard let url = components.url else { throw APIError.invalidRequest }
        var request = URLRequest(url:url); request.httpMethod = method; request.httpShouldHandleCookies = false
        request.setValue(context.session.token,forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Accept")
        if let body { request.httpBody = body;request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        guard valid(run), permits(method,path) else { throw APIError.unauthorized }
        try Task.checkCancellation();let (bytes,status) = try await transport.send(request)
        guard valid(run), permits(method,path) else { throw APIError.unauthorized };try Task.checkCancellation()
        if status == 401 { unauthorized();throw APIError.unauthorized }
        guard bytes.count <= 512 * 1024,let response = try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else { throw APIError.malformedResponse }
        let code = (response["code"] as? NSNumber)?.intValue
        if status == 401 || code == 401 { unauthorized();throw APIError.unauthorized }
        guard (200..<300).contains(status),code == 200,let value = response["data"] as? [String:Any] else { throw APIError.malformedResponse };return value
    }
}
