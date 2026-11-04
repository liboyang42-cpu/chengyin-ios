import Foundation
import CoreFoundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Normal consumer of ChannelRoleService. Persisted intent never grants MANAGE_ROLE.
@MainActor @Observable public final class NativeChannelRoleFlow {
    public struct Role: Identifiable, Equatable {
        public let id: String, name: String, permissions: String, version: String
        public let position: Int, status: Int
        public let system: Bool, managed: Bool, everyone: Bool
        public let color: Int?, displayLevel: String?
        public let hoist: Bool, mentionable: Bool
    }
    public struct Member: Identifiable, Equatable {
        public let id: String, nickname: String
        public let roleIDs: [String]
        public let joinTime: String?
    }
    private var memberRows: [Member] = []
    private var memberCursor: String?
    private var memberFilter: String?
    private var memberSourceSelected = false
    private var memberMore = false
    private var memberBusy = false
    private var memberGeneration: UInt64 = 0
    public private(set) var memberReadUnavailable = false
    public var members: [Member] { isCurrent ? memberRows : [] }
    public var canReadMembers: Bool { isCurrent && !memberBusy && permits("GET",memberPath) }
    public var canReadMoreMembers: Bool { canReadMembers && memberMore && memberCursor != nil }
    private var memberPath: String { "api/channels/"+captured.channelID.rawValue+"/members" }
    public func clearMemberSelectionSource() { memberGeneration &+= 1;memberRows=[];memberCursor=nil;memberMore=false;memberFilter=nil;memberBusy=false;memberSourceSelected=false }
    public func readMembers(roleID: String? = nil, more: Bool = false) async {
        guard canReadMembers, roleID == nil || Self.positive(roleID) != nil else { return }
        if more { guard canReadMoreMembers,roleID == memberFilter else { return } }
        memberBusy=true;memberGeneration &+= 1;let run=memberGeneration
        defer { if run == memberGeneration { memberBusy=false } }
        let cursor=more ? memberCursor : nil
        if !more { memberRows=[];memberCursor=nil;memberMore=false;memberFilter=roleID }
        memberReadUnavailable=false;memberSourceSelected=true
        do {
            var query=[URLQueryItem(name:"limit",value:"50")]
            if let roleID { query.append(.init(name:"role_id",value:roleID)) }
            if let cursor { query.append(.init(name:"cursor",value:cursor)) }
            // No online/relation query: the original service explicitly has no such projection.
            let result=try await exchange("GET",memberPath,query:query)
            guard isCurrent,run == memberGeneration,let list=result["list"] as? [[String:Any]],list.count <= 50,
                  let hasMore=result["has_more"] as? Int,[0,1].contains(hasMore) else { throw APIError.malformedResponse }
            let values=try list.map { value -> Member in
                guard let id=Self.positive(value["member_id"]) else { throw APIError.malformedResponse }
                return Member(id:id,nickname:value["nickname"] as? String ?? id,roleIDs:try receiptIDs(value["role_ids"]),joinTime:value["join_time"] as? String)
            }
            let next=result["next_cursor"] as? String
            guard Set(values.map(\.id)).count == values.count,
                  hasMore == 0 || (next != nil && !(next?.isEmpty ?? true) && next != cursor && !values.isEmpty),
                  next.map({ $0.utf8.count <= 4096 }) ?? true else { throw APIError.malformedResponse }
            if more { guard Set(memberRows.map(\.id)).isDisjoint(with:values.map(\.id)) else { throw APIError.malformedResponse };memberRows += values }
            else { memberRows=values }
            memberMore=hasMore == 1;memberCursor=next
        } catch { if run == memberGeneration { memberRows=[];memberCursor=nil;memberMore=false;memberReadUnavailable=true } }
    }
    public struct Options {
        public var color: Int? = nil
        public var displayLevel: String? = nil
        public var hoist = false
        public var mentionable = false
        public var position: Int? = nil
        public var enabled = true
        public var guildScope = false
        public var expiresAt: Date? = nil
        public init() {}
    }
    public enum Operation: String, Codable, CaseIterable { case create, edit, delete, memberRoles, roleMembers }
    public enum State: Equatable { case idle, loading, ready, reviewing, submitting, unknown, applied, unavailable }
    public private(set) var state: State = .idle
    public private(set) var reviewedSummary = ""
    public private(set) var originalRequestID: String?
    private var rows: [Role] = []
    private var resultText = ""
    private var generation: UInt64 = 0
    private var active = false
    private var busy = false
    private var failedStorage = false
    private var highest: Int?
    private var pending: Record?
    private var review: Record?
    @ObservationIgnored private let captured: NativeChannelManagementIntegrationContext
    @ObservationIgnored private let channels: any NativeChannelManagementIntegrationContextProviding
    @ObservationIgnored private let context: RuntimeDependencyContext
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let storage: any ProjectEditDataStorage
    @ObservationIgnored private let current: () -> Bool
    @ObservationIgnored private let permits: (String,String) -> Bool
    @ObservationIgnored private let unauthorized: () -> Void
    private static var leases: Set<String> = []
    private struct Record: Codable, Equatable {
        let schema: Int, owner: String, operation: Operation, requestID: String, target: String, body: Data
    }
    private var owner: String { [context.session.namespace,context.baseURL.absoluteString,String(context.session.accountID),"1",captured.ownerID.rawValue,captured.channelID.rawValue].map { "\($0.utf8.count):\($0)" }.joined() }
    private var key: String { "channel-role.v1." + Data(owner.utf8).base64EncodedString() }
    public var isCurrent: Bool { active && current() && channels.contextIsCurrent(captured) }
    public var roles: [Role] { isCurrent ? rows : [] }
    public var result: String { isCurrent ? resultText : "" }
    public var hasPending: Bool { pending != nil }
    public var canRecover: Bool { isCurrent && !busy && !failedStorage && pending.map { permits("GET",receiptPath($0.requestID)) } == true }
    public var canRetry: Bool { canRecover && pending.map(canWrite) == true }
    private var manager: Bool { isCurrent && captured.serverPermissionNames.contains("MANAGE_ROLE") }
    public init(captured: NativeChannelManagementIntegrationContext, channels: any NativeChannelManagementIntegrationContextProviding,
                context: RuntimeDependencyContext, transport: any HTTPTransport, storage: any ProjectEditDataStorage,
                current: @escaping () -> Bool, permits: @escaping (String,String) -> Bool, unauthorized: @escaping () -> Void) throws {
        guard captured.ownerType == "CLUB", captured.identity.owner.accountID == context.session.accountID,
              captured.identity.owner.namespace == context.session.namespace, captured.identity.owner.baseURL == context.baseURL.absoluteString,
              captured.identity.epoch == context.session.epoch, channels.contextIsCurrent(captured) else { throw APIError.unauthorized }
        self.captured=captured;self.channels=channels;self.context=context;self.transport=transport;self.storage=storage
        self.current=current;self.permits=permits;self.unauthorized=unauthorized
        do { pending=try restore();originalRequestID=pending?.requestID;if pending != nil { state = .unknown } }
        catch { failedStorage=true;state = .unavailable }
    }
    public func deactivate() { generation &+= 1; clearMemberSelectionSource();active=false;review=nil;reviewedSummary="";rows=[];highest=nil;resultText="";state = .unavailable }
    public func activate() async { guard !active else { return };active=true;await refresh() }
    public func refresh() async {
        guard isCurrent,!busy,!failedStorage,Self.leases.insert(key).inserted else { return }
        busy=true;let run = generation;defer { busy=false;Self.leases.remove(key) }
        do {
            pending=try restore();originalRequestID=pending?.requestID
            if let pending { state = .unknown; _ = try await recover(pending); guard valid(run) else { return }; if self.pending != nil { return } }
            state = .loading;rows=[];highest=nil
            let data=try await exchange("GET","api/im/roles",query:[.init(name:"guild_kind",value:"1"),.init(name:"guild_id",value:captured.ownerID.rawValue),.init(name:"include_disabled",value:"true")])
            guard valid(run),let list=data["list"] as? [[String:Any]],list.count <= 500,data["has_more"] as? Bool == false else { throw APIError.malformedResponse }
            let values=try list.map(parseRole);guard Set(values.map(\.id)).count == values.count else { throw APIError.malformedResponse }
            rows=values;highest=data["my_highest_position"] as? Int;state = .ready
        } catch { guard valid(run) else { return }; rows=[];highest=nil;if isCurrent { state = pending == nil ? .unavailable : .unknown } }
    }
    public func canPrepare(_ operation: Operation, target: String) -> Bool {
        guard manager,!busy,!failedStorage,pending == nil else { return false }
        let route=route(operation,target)
        guard permits(route.0,route.1) else { return false }
        if operation == .create { return true } // Server platform switch is still required, never inferred here.
        if operation == .memberRoles { return Self.positive(target) != nil }
        guard let role=rows.first(where:{$0.id == target}),let highest,role.position < highest || role.everyone else { return false }
        if operation == .edit { return (!role.system && !role.managed) || role.everyone }
        return !role.system && !role.managed && !role.everyone
    }
    /// ids is the COMPLETE replacement set, never interpreted as an additive grant.
    @discardableResult public func prepare(_ operation: Operation,target: String,name: String,permissions: String,ids: [String],reason: String,options: Options = .init()) -> Bool {
        let reason=reason.trimmingCharacters(in:.whitespacesAndNewlines),name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard canPrepare(operation,target:target),!reason.isEmpty,reason.utf16.count <= 120,
              ids.count <= 500,Set(ids).count == ids.count,ids.allSatisfy({Self.positive($0) != nil}),
              options.color.map({ (0...0xFFFFFF).contains($0) }) ?? true,
              options.displayLevel.map({ $0.utf16.count <= 8 }) ?? true,
              options.expiresAt.map({ $0 > Date() }) ?? true else { return false }
        let id=UUID().uuidString.lowercased();var body:[String:Any]=["request_id":id]
        switch operation {
        case .create:
            guard !name.isEmpty,name.unicodeScalars.count <= 32,Self.validBits(permissions) else { return false }
            body.merge(["guild_kind":1,"guild_id":captured.ownerID.rawValue,"name":name,"permissions":permissions,"hoist":options.hoist ? 1 : 0,"mentionable":options.mentionable ? 1 : 0,"reason":reason]) { _,new in new }
            body["color"]=options.color.map { $0 as Any } ?? NSNull()
            body["display_level"]=options.displayLevel.map { $0 as Any } ?? NSNull()
        case .edit:
            guard let role=rows.first(where:{$0.id == target}),Self.validBits(permissions) else { return false }
            body["version"]=role.version;body["permissions"]=permissions;body["reason"]=reason
            if !role.everyone {
                guard !name.isEmpty,name.unicodeScalars.count <= 32,let position=options.position,
                      let highest,(0...1000).contains(position),position < highest else { return false }
                body["name"]=name;body["position"]=position;body["status"]=options.enabled ? 1 : 0
                body["color"]=options.color.map { $0 as Any } ?? NSNull()
                body["hoist"]=options.hoist ? 1 : 0;body["mentionable"]=options.mentionable ? 1 : 0
                // Original PATCH has no display_level field; do not invent one.
            }
        case .delete:
            guard let role=rows.first(where:{$0.id == target}) else { return false }
            body["version"]=role.version;body["reason"]=reason
        case .memberRoles,.roleMembers:
            if operation == .memberRoles {
                guard ids.allSatisfy({id in rows.contains(where:{$0.id == id && !$0.system && !$0.managed && !$0.everyone})}) else { return false }
                body["guild_kind"]=1;body["guild_id"]=captured.ownerID.rawValue;body["role_ids"]=ids
            } else { body["member_ids"]=ids }
            body["scope_type"]=options.guildScope ? "GUILD" : "CHANNEL"
            body["scope_id"]=options.guildScope ? captured.ownerID.rawValue : captured.channelID.rawValue
            body["expires_at"]=options.expiresAt.map { ISO8601DateFormatter().string(from:$0) as Any } ?? NSNull()
            body["grant_reason"]=reason
        }
        guard let bytes=try? JSONSerialization.data(withJSONObject:body,options:[.sortedKeys]),bytes.count <= 32768 else { return false }
        review=Record(schema:1,owner:owner,operation:operation,requestID:id,target:target,body:bytes)
        reviewedSummary="\(operation.rawValue) · 组织 \(captured.ownerID.rawValue) · 频道 \(captured.channelID.rawValue) · 目标 \(target)\n名称：\(name)\n权限位：\(permissions)\n完整替换集合：\(ids.joined(separator:", "))\n理由：\(reason)\n替换范围：\(options.guildScope ? "整个组织" : "当前频道")；到期：\(options.expiresAt.map { ISO8601DateFormatter().string(from:$0) } ?? "无到期")。颜色：\(options.color.map(String.init) ?? "无")；层级：\(options.position.map(String.init) ?? "原创建默认")；启用：\(options.enabled)；独立展示：\(options.hoist)；允许提及：\(options.mentionable)。空集合撤销所选范围内全部对应增量。EVERYONE 仅提交权限位。最终权限与层级由原服务端判定。"
        state = .reviewing;return true
    }
    public func cancelReview() { review=nil;reviewedSummary="";state = pending == nil ? .ready : .unknown }
    public func confirm() async {
        guard let original=review,canWrite(original),!busy,pending == nil,Self.leases.insert(key).inserted else { return }
        busy=true;let run = generation;defer { busy=false;Self.leases.remove(key) }
        do {
            guard try restore() == nil else { throw APIError.invalidRequest }
            try storage.write(JSONEncoder().encode(original),key:key)
            guard try restore() == original else { throw APIError.malformedResponse }
            pending=original;originalRequestID=original.requestID;review=nil;state = .submitting
            let route=route(original.operation,original.target)
            let result = try await exchange(route.0,route.1,body:original.body)
            guard valid(run) else { return }
            try await settle(original,result)
        } catch { guard valid(run) else { return }; if pending == nil { failedStorage=true };if isCurrent { state = pending == nil ? .unavailable : .unknown } }
    }
    public func retryOriginal() async {
        guard canRetry,let original=pending,Self.leases.insert(key).inserted else { return }
        busy=true;let run = generation;defer { busy=false;Self.leases.remove(key) }
        do {
            guard try restore() == original else { throw APIError.malformedResponse }
            if try await recover(original) { return }
            guard valid(run) else { return }
            let receipt=try await exchange("GET",receiptPath(original.requestID))
            guard valid(run) else { throw APIError.unauthorized }
            guard valid(run),receipt["state"] as? String == "NOT_FOUND",receipt["retry_with_original_request"] as? Bool == true,canWrite(original) else { state = .unknown;return }
            let route=route(original.operation,original.target);state = .submitting
            let result = try await exchange(route.0,route.1,body:original.body)
            guard valid(run) else { return }
            try await settle(original,result)
        } catch { guard valid(run) else { return }; if isCurrent { state = .unknown } }
    }
    private func recover(_ original: Record) async throws -> Bool {
        let run = generation
        let receipt=try await exchange("GET",receiptPath(original.requestID))
        guard valid(run) else { throw APIError.unauthorized }
        guard valid(run),receipt["state"] as? String == "APPLIED",receipt["request_id"] as? String == original.requestID,
              let value=receipt["result"] as? [String:Any] else { return false }
        try await settle(original,value);return true
    }
    private func settle(_ original: Record,_ value: [String:Any]) async throws {
        guard isCurrent,try restore() == original,value["request_id"] as? String == original.requestID,
              value["state"] as? String == "APPLIED",Self.positive(value["audit_id"]) != nil else { throw APIError.malformedResponse }
        let outcome: String
        switch original.operation {
        case .create,.edit:
            let role=try parseRole(value)
            guard original.operation == .create || role.id == original.target else { throw APIError.malformedResponse }
            outcome="角色 \(role.id) · \(role.name) · 版本 \(role.version) · 权限 \(role.permissions) · 层级 \(role.position) · 状态 \(role.status)"
        case .delete:
            guard Self.positive(value["id"]) == original.target,value["deleted"] as? Bool == true,
                  let count=value["revoked_grants"] as? Int,count >= 0 else { throw APIError.malformedResponse }
            outcome="原角色 \(original.target) 已删除；原回执撤销增量数 \(count)。"
        case .memberRoles:
            guard Self.positive(value["member_id"]) == original.target,
                  let body=try JSONSerialization.jsonObject(with:original.body) as? [String:Any],let wanted=body["role_ids"] as? [String],
                  try receiptIDs(value["role_ids"]) == wanted else { throw APIError.malformedResponse }
            outcome="成员 \(original.target) · 已设置角色：\(wanted.joined(separator:", "))\n新增：\(try receiptIDs(value["granted"]).joined(separator:", "))\n撤销：\(try receiptIDs(value["revoked"]).joined(separator:", "))"
        case .roleMembers:
            guard Self.positive(value["role_id"]) == original.target else { throw APIError.malformedResponse }
            outcome="角色 \(original.target)\n新增成员：\(try receiptIDs(value["added"]).joined(separator:", "))\n移除成员：\(try receiptIDs(value["removed"]).joined(separator:", "))"
        }
        try storage.remove(key);guard try restore() == nil else { throw APIError.malformedResponse }
        pending=nil;originalRequestID=nil;rows=[];highest=nil;reviewedSummary=""
        let rereadMembers=memberSourceSelected,selectedFilter=memberFilter
        // Role/grant mutations invalidate current effective role labels and filtered
        // membership. Retire the cursor AND in-flight generation before any await.
        clearMemberSelectionSource()
        resultText=outcome+"\n原请求 \(original.requestID) 已记录；审计 \(Self.positive(value["audit_id"]) ?? "")。请刷新原角色列表查看当前状态。";state = .applied
        // Only a previously opened independent member reader is refreshed. Its result
        // or failure is current projection, never proof of the original mutation.
        if rereadMembers { await readMembers(roleID:selectedFilter) }
    }
    private func receiptIDs(_ raw: Any?) throws -> [String] {
        guard let values=raw as? [Any],values.count <= 500 else { throw APIError.malformedResponse }
        let ids=values.compactMap(Self.positive)
        guard ids.count == values.count,Set(ids).count == ids.count else { throw APIError.malformedResponse };return ids
    }
    private func parseRole(_ value: [String:Any]) throws -> Role {
        guard Self.positive(value["guild_kind"]) == "1",Self.positive(value["guild_id"]) == captured.ownerID.rawValue,
              let id=Self.positive(value["id"]),let version=Self.roleVersion(value["version"]),let name=value["name"] as? String,
              let bits=value["permissions"] as? String,Self.validBits(bits),let position=value["position"] as? Int,
              let status=value["status"] as? Int,let system=value["is_system"] as? Int,let managed=value["managed"] as? Int,
              let everyone=value["is_everyone"] as? Int,[0,1].contains(status),[0,1].contains(system),[0,1].contains(managed),[0,1].contains(everyone) else { throw APIError.malformedResponse }
        guard let hoist=value["hoist"] as? Int,let mentionable=value["mentionable"] as? Int,
              [0,1].contains(hoist),[0,1].contains(mentionable) else { throw APIError.malformedResponse }
        let color=value["color"] as? Int,display=value["display_level"] as? String
        guard value["color"] == nil || value["color"] is NSNull || color != nil,
              color.map({ (0...0xFFFFFF).contains($0) }) ?? true else { throw APIError.malformedResponse }
        return Role(id:id,name:name,permissions:bits,version:version,position:position,status:status,system:system == 1,managed:managed == 1,everyone:everyone == 1,color:color,displayLevel:display,hoist:hoist == 1,mentionable:mentionable == 1)
    }
    private func restore() throws -> Record? {
        guard let bytes=try storage.read(key) else { return nil }
        guard bytes.count <= 65536 else { throw APIError.malformedResponse }
        let row=try JSONDecoder().decode(Record.self,from:bytes)
        guard row.schema == 1,row.owner == owner,UUID(uuidString:row.requestID) != nil,row.body.count <= 32768,
              (row.operation == .create ? row.target.isEmpty : Self.positive(row.target) != nil),
              let body=try JSONSerialization.jsonObject(with:row.body) as? [String:Any],body["request_id"] as? String == row.requestID else { throw APIError.malformedResponse }
        if row.operation == .create || row.operation == .memberRoles {
            guard Self.positive(body["guild_kind"]) == "1",body["guild_id"] as? String == captured.ownerID.rawValue else { throw APIError.malformedResponse }
        }
        if row.operation == .memberRoles || row.operation == .roleMembers {
            let scope=body["scope_type"] as? String
            guard scope == "CHANNEL" || scope == "GUILD",
                  body["scope_id"] as? String == (scope == "GUILD" ? captured.ownerID.rawValue : captured.channelID.rawValue),
                  body["expires_at"] is NSNull || body["expires_at"] is String else { throw APIError.malformedResponse }
            // Do not change an expired pending request on restoration; only its original receipt can settle it.
        }
        return row
    }
    private func canWrite(_ original: Record) -> Bool { let route=route(original.operation,original.target);return manager && permits(route.0,route.1) }
    private func route(_ operation: Operation,_ target: String) -> (String,String) {
        switch operation { case .create:return ("POST","api/im/roles");case .edit:return ("PATCH","api/im/roles/"+target);case .delete:return ("DELETE","api/im/roles/"+target);case .memberRoles:return ("PUT","api/im/members/\(target)/roles");case .roleMembers:return ("PUT","api/im/roles/\(target)/members") }
    }
    // Original im_role starts at version 0. Versions are not entity identifiers.
    private static func roleVersion(_ value: Any?) -> String? {
        if let text=value as? String,let version=Int64(text),version>=0,String(version)==text {return text}
        if let number=value as? NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID(),
           let version=Int64(number.stringValue),version>=0,String(version)==number.stringValue {return number.stringValue}
        return nil
    }
    private static func positive(_ value: Any?) -> String? { NativeChannelGovernanceNotice.positive(value) }
    private static func validBits(_ value: String) -> Bool { value.hasPrefix("0x") && value.count > 2 && value.count <= 18 && UInt64(value.dropFirst(2),radix:16) != nil }
    private func receiptPath(_ id: String) -> String { "api/channel-platform/governance/requests/"+id }
    private func valid(_ run: UInt64) -> Bool { run == generation && isCurrent && !Task.isCancelled }
    private func exchange(_ method: String,_ path: String,body: Data? = nil,query: [URLQueryItem] = []) async throws -> [String:Any] {
        let run = generation
        guard valid(run),permits(method,path) else { throw APIError.unauthorized }
        let fresh=try await channels.currentChannelContext(channelID:captured.channelID)
        guard valid(run),permits(method,path),fresh == captured else { throw APIError.unauthorized }
        guard var url=URLComponents(url:context.baseURL.appendingPathComponent(path),resolvingAgainstBaseURL:false) else { throw APIError.invalidRequest }
        if !query.isEmpty { url.queryItems=query };guard let target=url.url else { throw APIError.invalidRequest }
        var request=URLRequest(url:target);request.httpMethod=method;request.httpShouldHandleCookies=false
        request.setValue(context.session.token,forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Accept")
        if let body { request.httpBody=body;request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
        guard valid(run), permits(method,path) else { throw APIError.unauthorized }
        try Task.checkCancellation();let (bytes,status)=try await transport.send(request)
        guard valid(run), permits(method,path) else { throw APIError.unauthorized };try Task.checkCancellation()
        if status == 401 { unauthorized();throw APIError.unauthorized }
        guard bytes.count <= 512*1024,let envelope=try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else { throw APIError.malformedResponse }
        let code=(envelope["code"] as? NSNumber)?.intValue
        if status == 401 || code == 401 { unauthorized();throw APIError.unauthorized }
        guard (200..<300).contains(status),code == 200,let result=envelope["data"] as? [String:Any] else { throw APIError.malformedResponse };return result
    }
}
