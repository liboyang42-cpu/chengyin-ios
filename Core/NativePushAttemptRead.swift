import Foundation
import Combine
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct NativePushAttempt: Decodable, Identifiable {
    public struct BadgeSnapshot: Decodable {
        public let generation: Int64
        public let count: Int64
        public let network_fenced: Bool
    }
    /// Historical original-attempt selection, not current unread or a delivery/read receipt.
    public let badge_snapshot: BadgeSnapshot?
    public let id: String
    public let attempt_id: String?
    public let source_kind: String?
    public let state: String
    public let provider_status: Int?
    public let reason: String?
    public var sourceLabel: String {
        switch source_kind { case "SYSTEM_INTENT": return "原系统通知"; case "DIRECT_MESSAGE": return "原私信"; case "CHANNEL_MESSAGE": return "原频道消息"; default: return "原通知来源" }
    }
    public var label: String {
        switch state {
        case "PENDING": return "等待原投递任务"
        case "PREPARED", "SUBMITTING": return "原尝试处理中，结果未确认"
        case "PROVIDER_ACCEPTED": return "APNs 已接受，不代表设备已收到"
        case "PROVIDER_REJECTED": return "APNs 明确拒绝，未作为成功"
        case "SUPPRESSED": return "当前权限、静默或设备资格阻止投递"
        case "NOT_ATTEMPTED": return "原发送边界前已停止，尚未请求 APNs"
        default: return "原尝试结果未知，不自动重试"
        }
    }
}
@MainActor public final class NativePushAttemptReader: ObservableObject {
    /// A payload-free wakeup only. The receiver must reread original ownership and read facts.
    public static let originalBadgeWakeup = Notification.Name("native.original-im-badge-wakeup.v1")
    public static func signalOriginalBadgeWakeup() { NotificationCenter.default.post(name: originalBadgeWakeup, object: nil) }
    public static let originalReadCommitted = Notification.Name("native.original-im-read-committed.v1")
    public static func signalOriginalReadCommitted() { NotificationCenter.default.post(name:originalReadCommitted,object:nil) }
    @Published public private(set) var items: [NativePushAttempt]=[]
    @Published public private(set) var issue: String?
    @Published public private(set) var busy=false
    @Published public private(set) var next="0"
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    private let credential: String
    private let installation: String
    private let current: () -> Bool
    private let unauthorized: () -> Void
    private var generation=0
    public var isCurrent: Bool { current() }
    public var recoveryRevision: Int { generation }
    public func recoveryIsCurrent(_ revision: Int) -> Bool { current() && revision==generation }
    public init(configuration:APIConfiguration,transport:any HTTPTransport,credential:String,installation:String,current:@escaping ()->Bool,unauthorized:@escaping ()->Void){
        self.configuration=configuration;self.transport=transport;self.credential=credential;self.installation=installation;self.current=current;self.unauthorized=unauthorized
    }
    private struct Envelope: Decodable { let code:Int;let data:Page }
    private struct Page: Decodable { let source:String;let installation_id:String;let items:[NativePushAttempt];let next_before:String;let delivery_proven:Bool }
    public func load(more:Bool=false) async {
        guard current(),!busy,!more || next != "0" else { return }
        if !more { items=[];next="0" };issue=nil;busy=true;let stamp=generation
        let before = more ? next : "0"
        defer{if stamp==generation{busy=false}}
        do {
            var parts=URLComponents(url:configuration.baseURL.appendingPathComponent("api/im/device/attempts"),resolvingAgainstBaseURL:false)
            parts?.queryItems=[.init(name:"installation_id",value:installation),.init(name:"before",value:before)]
            guard let url=parts?.url else { throw APIError.invalidConfiguration }
            var request=try AuthRequestBuilder.makeFormRequest(url:url,fields:[:],token:credential,includesBody:false)
            request.httpMethod="GET";request.httpShouldHandleCookies=false;request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data,status)=try await transport.send(request)
            guard current(),generation==stamp,!Task.isCancelled else { return }
            if status==401 { unauthorized();throw APIError.unauthorized }
            guard status==200,data.count<=1_048_576 else { throw APIError.malformedResponse }
            struct Code: Decodable { let code:Int }
            if try JSONDecoder().decode(Code.self,from:data).code==401 { unauthorized();throw APIError.unauthorized }
            let response=try JSONDecoder().decode(Envelope.self,from:data)
            if response.code==401{unauthorized();throw APIError.unauthorized}
            let page=response.data
            guard response.code==200,page.source=="original-im-push-attempts-v1",page.installation_id==installation,!page.delivery_proven,
                  page.items.count<=50,Set(page.items.map(\.id)).count==page.items.count,
                  let nextID=Int64(page.next_before),nextID>=0,String(nextID)==page.next_before,
                  let beforeID=Int64(before),beforeID>=0,
                  page.items.allSatisfy({ row in
                    guard let id=Int64(row.id),id>0,String(id)==row.id,beforeID==0 || id<beforeID else { return false }
                    return (row.attempt_id==nil || UUID(uuidString:row.attempt_id!) != nil)
                        && (row.badge_snapshot.map { $0.generation >= 0 && $0.count >= 0 } ?? true)
                        && (row.badge_snapshot == nil || row.attempt_id != nil)
                  }),
                  nextID==0 || (!page.items.isEmpty && (beforeID==0 || nextID<beforeID)
                    && page.items.allSatisfy({ Int64($0.id).map { nextID <= $0 } == true })) else { throw APIError.malformedResponse }
            let existing=Set(items.map(\.id));items+=page.items.filter{!existing.contains($0.id)};next=page.next_before
        }catch{if current(),stamp==generation{items=[];issue="原投递结果暂不可读；没有当作成功或零条"}}
    }
    private struct ReadProofEnvelope: Decodable { let code:Int;let data:ReadProof }
    private struct ReadProof: Decodable { let source:String;let installation_id:String;let read_attempts:[String];let delivery_proven:Bool }
    /// Same own-installation attempt reader, not an ACK, retry, counter or delivery receipt writer.
    public func originalReadProof(attempts:[String]) async throws -> Set<String> {
        guard current(),!Task.isCancelled,(1...50).contains(attempts.count),Set(attempts).count==attempts.count,
              attempts.allSatisfy({ UUID(uuidString:$0)?.uuidString.lowercased()==$0 }) else { throw APIError.invalidRequest }
        let stamp=generation
        var parts=URLComponents(url:configuration.baseURL.appendingPathComponent("api/im/device/attempts"),resolvingAgainstBaseURL:false)
        parts?.queryItems=[.init(name:"installation_id",value:installation),.init(name:"before",value:"0"),.init(name:"read_attempts",value:attempts.sorted().joined(separator:","))]
        guard let url=parts?.url else { throw APIError.invalidConfiguration }
        var request=try AuthRequestBuilder.makeFormRequest(url:url,fields:[:],token:credential,includesBody:false)
        request.httpMethod="GET";request.httpShouldHandleCookies=false;request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data,status)=try await transport.send(request)
        guard recoveryIsCurrent(stamp),!Task.isCancelled else { throw CancellationError() }
        if status==401 { unauthorized();throw APIError.unauthorized }
        guard status==200,data.count<=65536 else { throw APIError.malformedResponse }
        struct Code: Decodable { let code:Int }
        if try JSONDecoder().decode(Code.self,from:data).code==401 { unauthorized();throw APIError.unauthorized }
        let result=try JSONDecoder().decode(ReadProofEnvelope.self,from:data);let proof=result.data
        guard result.code==200,proof.source=="original-im-push-read-reconciliation-v1",proof.installation_id==installation,!proof.delivery_proven,
              proof.read_attempts.count<=attempts.count,Set(proof.read_attempts).count==proof.read_attempts.count,
              Set(proof.read_attempts).isSubset(of:Set(attempts)) else { throw APIError.malformedResponse }
        return Set(proof.read_attempts)
    }
    public func retire(){generation+=1;items=[];next="0";busy=false;issue=nil}
}
