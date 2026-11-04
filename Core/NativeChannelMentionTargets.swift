import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Read-only original target projections. This is not a sender, recipient ledger or grant source.
@MainActor @Observable public final class NativeChannelMentionTargets {
    public struct Member: Identifiable, Equatable { public let id: NativeChannelMessageID, name: String }
    public struct Role: Identifiable, Equatable { public let id: NativeChannelMessageID, name: String, mentionable: Bool }
    public let binding: NativeChannelMessageBinding
    private var memberRows: [Member] = []
    private var roleRows: [Role] = []
    private var cursor: String?
    private var more = false
    private var retired = false
    public private(set) var busy = false
    public private(set) var issue: String?
    @ObservationIgnored private let captured: NativeChannelManagementIntegrationContext
    @ObservationIgnored private let channels: any NativeChannelManagementIntegrationContextProviding
    @ObservationIgnored private let context: RuntimeDependencyContext
    @ObservationIgnored private let transport: any HTTPTransport
    @ObservationIgnored private let current: () -> Bool
    @ObservationIgnored private let permits: (String,String) -> Bool
    @ObservationIgnored private let unauthorized: () -> Void
    public var isCurrent: Bool { !retired && current() && channels.contextIsCurrent(captured) }
    public var members: [Member] { isCurrent ? memberRows : [] }
    public var roles: [Role] { isCurrent ? roleRows : [] }
    public var allowsEveryone: Bool { isCurrent && captured.serverPermissionNames.contains("MENTION_EVERYONE") }
    private var memberPath: String { "api/channels/"+captured.channelID.rawValue+"/members" }
    public var canReadMembers: Bool { isCurrent && !busy && permits("GET",memberPath) }
    public var canReadRoles: Bool { isCurrent && !busy && permits("GET","api/im/roles") }
    public var canReadMore: Bool { canReadMembers && more && cursor != nil }
    public init(binding: NativeChannelMessageBinding,captured: NativeChannelManagementIntegrationContext,
                channels: any NativeChannelManagementIntegrationContextProviding,context: RuntimeDependencyContext,
                transport: any HTTPTransport,current: @escaping () -> Bool,permits: @escaping (String,String) -> Bool,unauthorized: @escaping () -> Void) throws {
        guard captured.ownerType == "CLUB",captured.channelID.rawValue == binding.channelID.rawValue,
              captured.identity.owner.accountID == context.session.accountID,captured.identity.owner.namespace == context.session.namespace,
              captured.identity.owner.baseURL == context.baseURL.absoluteString,captured.identity.epoch == context.session.epoch,
              channels.contextIsCurrent(captured) else { throw APIError.unauthorized }
        self.binding=binding;self.captured=captured;self.channels=channels;self.context=context;self.transport=transport
        self.current=current;self.permits=permits;self.unauthorized=unauthorized
    }
    public func retire() { retired=true;memberRows=[];roleRows=[];cursor=nil;more=false }
    public func validates(_ reference: NativeChannelMessageTextReference) -> Bool {
        guard isCurrent,reference.binding.sameTarget(as:binding),!reference.mentionEveryone || allowsEveryone,
              reference.memberIDs.allSatisfy({ id in memberRows.contains(where:{$0.id == id}) }),
              reference.roleIDs.allSatisfy({ id in roleRows.contains(where:{$0.id == id && ($0.mentionable || allowsEveryone)}) }) else { return false }
        return true // Original server resolves current recipients, blocks, role visibility and daily limits.
    }
    public func readMembers(next: Bool = false) async {
        guard next ? canReadMore : canReadMembers else { return }
        busy=true;defer { busy=false };issue=nil
        let after=next ? cursor : nil
        if !next { memberRows=[];cursor=nil;more=false }
        do {
            var query=[URLQueryItem(name:"limit",value:"50")];if let after { query.append(.init(name:"cursor",value:after)) }
            let result=try await exchange(memberPath,query:query)
            guard let values=result["list"] as? [[String:Any]],values.count <= 50,
                  let flag=result["has_more"] as? Int,[0,1].contains(flag) else { throw APIError.malformedResponse }
            let rows=try values.map { value -> Member in
                guard let raw=NativeChannelGovernanceNotice.positive(value["member_id"]),let id=NativeChannelMessageID(rawValue:raw) else { throw APIError.malformedResponse }
                return Member(id:id,name:value["nickname"] as? String ?? raw)
            }
            let nextCursor=result["next_cursor"] as? String
            guard Set(rows.map(\.id)).count == rows.count,flag == 0 || (nextCursor != nil && nextCursor != after && !rows.isEmpty),
                  nextCursor.map({ !$0.isEmpty && $0.utf8.count <= 4096 }) ?? true else { throw APIError.malformedResponse }
            if next { guard Set(memberRows.map(\.id)).isDisjoint(with:rows.map(\.id)) else { throw APIError.malformedResponse };memberRows += rows }
            else { memberRows=rows }
            cursor=nextCursor;more=flag == 1
        } catch { memberRows=[];cursor=nil;more=false;if isCurrent { issue="原成员名单不可用，未借用其他读取权限。" } }
    }
    public func readRoles() async {
        guard canReadRoles else { return };busy=true;defer { busy=false };roleRows=[];issue=nil
        do {
            let result=try await exchange("api/im/roles",query:[.init(name:"guild_kind",value:"1"),.init(name:"guild_id",value:captured.ownerID.rawValue),.init(name:"include_disabled",value:"false")])
            guard let values=result["list"] as? [[String:Any]],values.count <= 500,result["has_more"] as? Bool == false else { throw APIError.malformedResponse }
            var rows:[Role]=[]
            for value in values {
                guard NativeChannelGovernanceNotice.positive(value["guild_kind"]) == "1",NativeChannelGovernanceNotice.positive(value["guild_id"]) == captured.ownerID.rawValue,
                      let raw=NativeChannelGovernanceNotice.positive(value["id"]),let id=NativeChannelMessageID(rawValue:raw),let name=value["name"] as? String,
                      let status=value["status"] as? Int,let mentionable=value["mentionable"] as? Int,[0,1].contains(mentionable) else { throw APIError.malformedResponse }
                if status == 1 { rows.append(Role(id:id,name:name,mentionable:mentionable == 1)) }
            }
            guard Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse };roleRows=rows
        } catch { roleRows=[];if isCurrent { issue="原角色来源不可用；没有从权限名称猜造角色编号。" } }
    }
    private func exchange(_ path: String,query: [URLQueryItem]) async throws -> [String:Any] {
        guard isCurrent,permits("GET",path) else { throw APIError.unauthorized }
        let fresh=try await channels.currentChannelContext(channelID:captured.channelID)
        guard isCurrent,fresh == captured else { throw APIError.unauthorized }
        guard var url=URLComponents(url:context.baseURL.appendingPathComponent(path),resolvingAgainstBaseURL:false) else { throw APIError.invalidRequest }
        url.queryItems=query;guard let target=url.url else { throw APIError.invalidRequest }
        var request=URLRequest(url:target);request.httpMethod="GET";request.httpShouldHandleCookies=false
        request.setValue(context.session.token,forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Accept")
        try Task.checkCancellation();let (bytes,status)=try await transport.send(request)
        guard isCurrent else { throw APIError.unauthorized };try Task.checkCancellation()
        if status == 401 { unauthorized();throw APIError.unauthorized }
        guard bytes.count <= 512*1024,let envelope=try JSONSerialization.jsonObject(with:bytes) as? [String:Any] else { throw APIError.malformedResponse }
        let code=(envelope["code"] as? NSNumber)?.intValue
        if code == 401 { unauthorized();throw APIError.unauthorized }
        guard (200..<300).contains(status),code == 200,let result=envelope["data"] as? [String:Any] else { throw APIError.malformedResponse };return result
    }
}
