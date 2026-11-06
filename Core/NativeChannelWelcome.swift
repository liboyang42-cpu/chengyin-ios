import Foundation
import CoreFoundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct NativeChannelWelcomeApproval:Equatable {
    public static let path="api/welcome-screen/get"
    public let endpoint:OperationEndpointApproval
    public let expiresAt:Date
    public let issuanceID:UUID
    public init(endpoint:OperationEndpointApproval,expiresAt:Date,issuanceID:UUID=UUID()) throws {
        guard endpoint.paths == [Self.path],expiresAt.timeIntervalSince1970.isFinite else { throw APIError.invalidConfiguration }
        self.endpoint=endpoint;self.expiresAt=expiresAt;self.issuanceID=issuanceID
    }
}
public struct NativeChannelWelcomeSnapshot:Decodable,Equatable {
    public struct Signpost:Decodable,Equatable,Identifiable {
        public let channelID:NativeChannelManagementID,label:String,emoji:String
        public var id:NativeChannelManagementID { channelID }
        enum CodingKeys:String,CodingKey { case channelID="channel_id",label,emoji }
    }
    public let viewerID:NativeChannelManagementID,guildID:NativeChannelManagementID,entryChannelID:NativeChannelManagementID
    public let guildKind:Int,version:Int64,title:String,description:String,signposts:[Signpost]
    enum CodingKeys:String,CodingKey { case viewerID="viewer_id",guildID="guild_id",entryChannelID="entry_channel_id",guildKind="guild_kind",version,title,description,signposts }
    public func validate(context:RuntimeDependencyContext,scope:NativeChannelManagementScope)->Bool {
        viewerID.rawValue == String(context.session.accountID) && guildID == scope.guildID && guildKind == scope.guildKind && version>=0
            && title.utf16.count<=100 && description.utf16.count<=2000 && signposts.count<=5
            && Set(signposts.map(\.id)).count == signposts.count && signposts.allSatisfy{ !$0.label.isEmpty && $0.label.utf16.count<=200 && $0.emoji.utf16.count<=32 }
    }
}
public enum NativeChannelWelcomePolicy {
    public static func accepts(_ request:URLRequest,context:RuntimeDependencyContext,approval:NativeChannelWelcomeApproval)->Bool {
        guard context.market == .china,context.baseURL == approval.endpoint.baseURL,context.session.accountID == approval.endpoint.accountID,context.session.namespace == approval.endpoint.namespace,
              Date()<approval.expiresAt,request.url == context.baseURL.appendingPathComponent(NativeChannelWelcomeApproval.path),request.httpMethod == "POST",
              !request.httpShouldHandleCookies,request.httpBodyStream == nil,request.value(forHTTPHeaderField:"Cookie") == nil,request.value(forHTTPHeaderField:"Cookie2") == nil,request.value(forHTTPHeaderField:"Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField:"Authorization") == context.session.token,request.value(forHTTPHeaderField:"Accept") == "application/json",request.value(forHTTPHeaderField:"Content-Type") == "application/json",
              let bytes=request.httpBody,bytes.count<=1024,let raw=(try? JSONSerialization.jsonObject(with:bytes)) as? [String:Any],Set(raw.keys) == ["guild_kind","guild_id"],
              let kind=raw["guild_kind"] as? NSNumber,CFGetTypeID(kind) != CFBooleanGetTypeID(),[1.0,3.0].contains(kind.doubleValue),let guild=raw["guild_id"] as? String,(try? NativeChannelManagementID(guild)) != nil,
              (try? JSONSerialization.data(withJSONObject:raw,options:.sortedKeys)) == bytes else { return false }
        return true
    }
}
@MainActor @Observable public final class NativeChannelWelcomeFlow {
    public let scope:NativeChannelManagementScope
    public private(set) var snapshot:NativeChannelWelcomeSnapshot?
    public private(set) var issue:String?
    public private(set) var busy=false
    private let context:RuntimeDependencyContext,approval:NativeChannelWelcomeApproval
    private let transport:any HTTPTransport,current:()->Bool,unauthorized:()->Void
    private var active=false
    private var retired=false
    private var generation=0
    public var isCurrent:Bool { if retired || !current() || Date()>=approval.expiresAt { retired=true;return false };return active }
    public init(scope:NativeChannelManagementScope,context:RuntimeDependencyContext,approval:NativeChannelWelcomeApproval,transport:any HTTPTransport,current:@escaping()->Bool,unauthorized:@escaping()->Void) throws {
        guard [1,3].contains(scope.guildKind),context.market == .china,context.baseURL == approval.endpoint.baseURL,context.session.namespace == approval.endpoint.namespace,context.session.accountID == approval.endpoint.accountID,Date()<approval.expiresAt else { throw APIError.invalidConfiguration }
        self.scope=scope;self.context=context;self.approval=approval;self.transport=transport;self.current=current;self.unauthorized=unauthorized
    }
    public func activate() async { active=true;await refresh() }
    public func deactivate() { active=false;generation += 1;snapshot=nil;issue=nil }
    public func refresh() async {
        guard isCurrent,!busy else { return };busy=true;let run=generation;snapshot=nil;defer{busy=false}
        do {
            var request=URLRequest(url:context.baseURL.appendingPathComponent(NativeChannelWelcomeApproval.path));request.httpMethod="POST";request.httpBody=try JSONSerialization.data(withJSONObject:["guild_kind":scope.guildKind,"guild_id":scope.guildID.rawValue],options:.sortedKeys)
            request.httpShouldHandleCookies=false;request.cachePolicy = .reloadIgnoringLocalCacheData;request.timeoutInterval=20
            request.setValue(context.session.token,forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Accept");request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            guard NativeChannelWelcomePolicy.accepts(request,context:context,approval:approval) else { throw APIError.invalidRequest }
            let (data,status)=try await transport.send(request);guard valid(run) else{return}
            if status == 401 { unauthorized();retired=true;throw APIError.unauthorized }
            guard data.count<=1048576,let header=try? JSONDecoder().decode(Header.self,from:data) else { throw APIError.malformedResponse }
            if header.code == 401 { unauthorized();retired=true;throw APIError.unauthorized }
            guard (200..<300).contains(status),header.code == 200 else {
                if header.errorCode == "WELCOME_SCREEN_NOT_CONFIGURED" { issue="本空间尚未配置或未启用欢迎屏；不是加入失败，不需要重发申请。";return }
                if header.errorCode == "SCREENING_PENDING" { issue="请先完成原逐条规则。欢迎屏不能替代规则同意，也不触发重发消息。";return }
                throw APIError.malformedResponse
            }
            let value=try JSONDecoder().decode(Envelope.self,from:data).data
            guard value.validate(context:context,scope:scope) else { throw APIError.malformedResponse };snapshot=value;issue=nil
        } catch { if valid(run) { issue="当前欢迎配置或访问权限不可确认，旧路标已清除。" } }
    }
    public func permits(_ id:NativeChannelManagementID)->Bool { isCurrent && !busy && snapshot.map{$0.entryChannelID == id || $0.signposts.contains{$0.id == id}} == true }
    private func valid(_ run:Int)->Bool { generation == run && isCurrent && !Task.isCancelled }
    private struct Header:Decodable { let code:Int;let errorCode:String? }
    private struct Envelope:Decodable { let data:NativeChannelWelcomeSnapshot }
}
