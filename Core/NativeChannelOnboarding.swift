import Foundation
import CoreFoundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private enum NativeOnboardingReadFailure:Error { case notConfigured,screeningPending }

/// Only J15/J16 and the existing personal admission receipt. Config publishing is not a member capability.
public struct NativeChannelOnboardingApproval:Equatable {
    public static let read="api/onboarding/get",submit="api/onboarding/submit",receipts="api/channel-platform/admission/requests/"
    public let endpoint:OperationEndpointApproval
    public let expiresAt:Date
    public let issuanceID:UUID
    public init(endpoint:OperationEndpointApproval,expiresAt:Date,issuanceID:UUID=UUID()) throws {
        guard Set([Self.read,Self.receipts]).isSubset(of:endpoint.paths),endpoint.paths.isSubset(of:[Self.read,Self.submit,Self.receipts]),expiresAt.timeIntervalSince1970.isFinite else { throw APIError.invalidConfiguration }
        self.endpoint=endpoint;self.expiresAt=expiresAt;self.issuanceID=issuanceID
    }
}
public struct NativeOnboardingAnswer:Codable,Equatable {
    public let promptID:String,optionIDs:[String]
    enum CodingKeys:String,CodingKey { case promptID="prompt_id",optionIDs="option_ids" }
}
public struct NativeOnboardingSnapshot:Decodable,Equatable {
    public struct Option:Decodable,Equatable,Identifiable {
        public let id:String,label:String,description:String,emoji:String,channelIDs:[String],roleIDs:[String]
        enum CodingKeys:String,CodingKey { case id="option_id",label,description,emoji,channelIDs="channel_ids",roleIDs="role_ids" }
        public var hasEffects:Bool { !channelIDs.isEmpty || !roleIDs.isEmpty }
    }
    public struct Prompt:Decodable,Equatable,Identifiable {
        public let id:String,title:String,singleSelect:Bool,required:Bool,enabled:Bool,options:[Option],selected:[String],previousAnswerExists:Bool,answerSourceCurrent:Bool
        public let answerConfigurationHash:String?
        enum CodingKeys:String,CodingKey { case id="prompt_id",title,singleSelect="single_select",required,enabled,options,selected="selected_option_ids",previousAnswerExists="previous_answer_exists",answerSourceCurrent="answer_source_current",answerConfigurationHash="answer_configuration_hash" }
    }
    public let viewerID:String,guildID:String,configurationHash:String,completionPolicy:String,answerState:String,next:String
    public let guildKind:Int,submitted:Int,canSkip:Bool,prompts:[Prompt]
    enum CodingKeys:String,CodingKey { case viewerID="viewer_id",guildID="guild_id",configurationHash="configuration_hash",completionPolicy="completion_policy",answerState="answer_state",guildKind="guild_kind",submitted,canSkip="can_skip",prompts,next }
    public func valid(context:RuntimeDependencyContext,scope:NativeChannelManagementScope)->Bool {
        viewerID == String(context.session.accountID) && guildID == scope.guildID.rawValue && guildKind == scope.guildKind && Self.hash(configurationHash)
            && [0,1].contains(submitted) && ["ALL_REQUIRED_INTERSECTION","UNRESOLVED_OPTIONAL_POLICY"].contains(completionPolicy)
            && ["NONE","CURRENT","SOURCE_CHANGED"].contains(answerState) && canSkip && next == "welcome_screen"
            && !prompts.isEmpty && prompts.count<=3 && Set(prompts.map(\.id)).count == prompts.count
            && prompts.allSatisfy { p in
                Self.id(p.id) && !p.title.isEmpty && p.title.utf16.count<=100 && p.enabled && !p.options.isEmpty && p.options.count<=8
                && Set(p.options.map(\.id)).count == p.options.count && Set(p.selected).count == p.selected.count && Set(p.selected).isSubset(of:Set(p.options.map(\.id)))
                && (!p.singleSelect || p.selected.count<=1) && (!p.answerSourceCurrent || p.previousAnswerExists && p.answerConfigurationHash == configurationHash)
                && p.options.allSatisfy { o in Self.id(o.id) && !o.label.isEmpty && o.label.utf16.count<=50 && o.description.utf16.count<=200 && o.emoji.utf16.count<=32
                    && o.channelIDs.count<=100 && o.roleIDs.count<=100 && o.channelIDs.allSatisfy(Self.id) && o.roleIDs.allSatisfy(Self.id) }
            } && (completionPolicy != "ALL_REQUIRED_INTERSECTION" || prompts.allSatisfy(\.required))
            && (submitted==0 || answerState=="CURRENT" && prompts.allSatisfy{$0.answerSourceCurrent && !$0.selected.isEmpty})
            && (answerState != "CURRENT" || submitted==1)
    }
    static func id(_ value:String)->Bool { Int64(value).map{$0>0 && String($0)==value} == true }
    static func hash(_ value:String)->Bool { value.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil }
}
public enum NativeChannelOnboardingPolicy {
    public static func accepts(_ request:URLRequest,context:RuntimeDependencyContext,approval:NativeChannelOnboardingApproval)->Bool {
        guard context.market == .china,context.baseURL == approval.endpoint.baseURL,context.session.accountID == approval.endpoint.accountID,context.session.namespace == approval.endpoint.namespace,Date()<approval.expiresAt,
              !request.httpShouldHandleCookies,request.httpBodyStream == nil,request.value(forHTTPHeaderField:"Cookie") == nil,request.value(forHTTPHeaderField:"Cookie2") == nil,request.value(forHTTPHeaderField:"Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField:"Authorization") == context.session.token,request.value(forHTTPHeaderField:"Accept") == "application/json",let url=request.url,url.query == nil,url.fragment == nil,url.user == nil,url.password == nil else { return false }
        let prefix=context.baseURL.appendingPathComponent(NativeChannelOnboardingApproval.receipts).absoluteString
        if url.absoluteString.hasPrefix(prefix) {
            let id=String(url.absoluteString.dropFirst(prefix.count))
            return UUID(uuidString:id) != nil && approval.endpoint.paths.contains(NativeChannelOnboardingApproval.receipts) && request.httpMethod == "GET" && request.httpBody == nil && url == context.baseURL.appendingPathComponent(NativeChannelOnboardingApproval.receipts+id)
        }
        guard request.httpMethod == "POST",request.value(forHTTPHeaderField:"Content-Type") == "application/json",let path=approval.endpoint.paths.first(where:{context.baseURL.appendingPathComponent($0)==url}),let body=request.httpBody,body.count<=16384,
              let fields=(try? JSONSerialization.jsonObject(with:body)) as? [String:Any],(try? JSONSerialization.data(withJSONObject:fields,options:.sortedKeys))==body,
              let kind=number(fields["guild_kind"]),[1,3].contains(kind),let guild=fields["guild_id"] as? String,NativeOnboardingSnapshot.id(guild) else { return false }
        if path == NativeChannelOnboardingApproval.read { return Set(fields.keys)==["guild_kind","guild_id"] }
        guard path == NativeChannelOnboardingApproval.submit,Set(fields.keys)==["guild_kind","guild_id","request_id","configuration_hash","answers"],let id=fields["request_id"] as? String,UUID(uuidString:id) != nil,let hash=fields["configuration_hash"] as? String,NativeOnboardingSnapshot.hash(hash),
              let answers=fields["answers"] as? [[String:Any]],!answers.isEmpty,answers.count<=3 else { return false }
        var prompts=Set<String>()
        return answers.allSatisfy { row in
            guard Set(row.keys)==["prompt_id","option_ids"],let prompt=row["prompt_id"] as? String,NativeOnboardingSnapshot.id(prompt),prompts.insert(prompt).inserted,let options=row["option_ids"] as? [String],!options.isEmpty,options.count<=8,Set(options).count==options.count,options.allSatisfy(NativeOnboardingSnapshot.id) else{return false};return true
        }
    }
    static func number(_ value:Any?)->Int64? { if let s=value as? String,let n=Int64(s),String(n)==s{return n};if let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite,n.doubleValue==Double(n.int64Value){return n.int64Value};return nil }
}
@MainActor @Observable public final class NativeChannelOnboardingFlow {
    public struct Command:Codable,Equatable { public let owner:String,id:String,configurationHash:String,answers:[NativeOnboardingAnswer],body:Data }
    public let scope:NativeChannelManagementScope
    public private(set) var snapshot:NativeOnboardingSnapshot?
    public private(set) var pending:Command?
    public private(set) var review:Command?
    public private(set) var confirmed:String?
    public private(set) var issue:String?
    public private(set) var busy=false
    public private(set) var storageFailed=false
    private let context:RuntimeDependencyContext,approval:NativeChannelOnboardingApproval
    private let transport:any HTTPTransport,storage:any ProjectEditDataStorage,current:()->Bool,unauthorized:()->Void
    private var active=false
    private var retired=false
    private var generation=0
    private static var leases:Set<String>=[]
    private var owner:String { [context.baseURL.absoluteString,context.session.namespace,String(context.session.accountID),String(scope.guildKind),scope.guildID.rawValue].map{"\($0.utf8.count):\($0)"}.joined() }
    private var key:String { "onboarding-original.v1."+Data(owner.utf8).base64EncodedString() }
    public var isCurrent:Bool { if retired || !current() || Date()>=approval.expiresAt { retired=true;return false };return active }
    public var canPrepare:Bool { isCurrent && !busy && !storageFailed && pending==nil && approval.endpoint.paths.contains(NativeChannelOnboardingApproval.submit) && snapshot.map{$0.submitted==0 && $0.answerState=="NONE" && $0.completionPolicy=="ALL_REQUIRED_INTERSECTION"}==true }
    public init(scope:NativeChannelManagementScope,context:RuntimeDependencyContext,approval:NativeChannelOnboardingApproval,transport:any HTTPTransport,storage:any ProjectEditDataStorage,current:@escaping()->Bool,unauthorized:@escaping()->Void) throws {
        guard [1,3].contains(scope.guildKind),context.market == .china,context.baseURL==approval.endpoint.baseURL,context.session.namespace==approval.endpoint.namespace,context.session.accountID==approval.endpoint.accountID,Date()<approval.expiresAt else { throw APIError.invalidConfiguration }
        self.scope=scope;self.context=context;self.approval=approval;self.transport=transport;self.storage=storage;self.current=current;self.unauthorized=unauthorized
    }
    public func activate() async { active=true;await refresh() }
    public func deactivate() { active=false;generation += 1;snapshot=nil;review=nil;confirmed=nil;issue=nil }
    public func refresh() async {
        guard isCurrent,!busy,Self.leases.insert(key).inserted else{return};busy=true;let run=generation;defer{busy=false;Self.leases.remove(key)};snapshot=nil;review=nil
        do { pending=try restore();if let pending {try await recover(pending,run:run)}else{await readCurrent(run:run)} }catch{if valid(run){issue="原回答或保护记录待核对；只查原UUID，不重发。"}}
    }
    public func prepare(_ selected:[String:Set<String>]) {
        guard canPrepare,let snapshot,Set(selected.keys).isSubset(of:Set(snapshot.prompts.map(\.id))) else{return}
        var answers:[NativeOnboardingAnswer]=[]
        for prompt in snapshot.prompts {
            let choices=selected[prompt.id] ?? []
            guard !choices.isEmpty,(!prompt.singleSelect || choices.count==1),choices.isSubset(of:Set(prompt.options.map(\.id))) else {issue="请按原单/多选要求回答全部必答问题；也可跳过整个引导。";return}
            guard !prompt.options.contains(where:{choices.contains($0.id)&&$0.hasEffects}) else{issue="所选项需要尚未闭合的原角色/频道委托，不能只保存答案就声称授予；可跳过，不改准入。";return}
            answers.append(.init(promptID:prompt.id,optionIDs:choices.sorted{Int64($0)!<Int64($1)!}))
        }
        answers.sort{Int64($0.promptID)!<Int64($1.promptID)!};let id=UUID().uuidString.lowercased()
        do { let rows=answers.map{["prompt_id":$0.promptID,"option_ids":$0.optionIDs] as [String:Any]};let body=try JSONSerialization.data(withJSONObject:["guild_kind":scope.guildKind,"guild_id":scope.guildID.rawValue,"request_id":id,"configuration_hash":snapshot.configurationHash,"answers":rows],options:.sortedKeys)
            review = .init(owner:owner,id:id,configurationHash:snapshot.configurationHash,answers:answers,body:body);issue=nil
        }catch{issue="原回答无法冻结，未发送。"}
    }
    public func cancelReview(){guard !busy else{return};review=nil}
    public func confirm() async {
        guard canPrepare,let command=review,Self.leases.insert(key).inserted else{return};busy=true;let run=generation;defer{busy=false;Self.leases.remove(key)}
        do {
            let fresh=try await readSnapshot(run:run);guard fresh.configurationHash==command.configurationHash,fresh.submitted==0,fresh.answerState=="NONE",fresh.completionPolicy=="ALL_REQUIRED_INTERSECTION",valid(run),try restore()==nil else{throw APIError.invalidRequest}
            try storage.write(JSONEncoder().encode(command),key:key);guard try restore()==command else{throw APIError.malformedResponse};pending=command;review=nil;snapshot=nil;confirmed=nil
            do {_ = try await exchange(NativeChannelOnboardingApproval.submit,body:command.body,run:run)}catch{guard valid(run) else{return}}
            try await recover(command,run:run)
        }catch{if valid(run){snapshot=nil;review=nil;issue=pending==nil ? "配置、本人状态或保护存储已变化，未发送，请重新读取。":"原回答结果未知；保留原字节与UUID，只查询不重发。"}}
    }
    private func recover(_ command:Command,run:Int) async throws {
        let data=try await exchange(NativeChannelOnboardingApproval.receipts+command.id,body:nil,run:run)
        guard let row=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],row["request_id"] as? String==command.id else{throw APIError.malformedResponse}
        guard row["state"] as? String=="APPLIED" else{issue="原回答仍为 UNKNOWN/PENDING；保留原请求，不重发。";return}
        guard row["operation"] as? String=="ONBOARDING_SUBMIT",NativeChannelOnboardingPolicy.number(row["guild_kind"])==Int64(scope.guildKind),row["guild_id"] as? String==scope.guildID.rawValue,NativeChannelOnboardingPolicy.number(row["object_id"])==0,
              let hash=row["request_hash"] as? String,NativeOnboardingSnapshot.hash(hash),let result=row["result"] as? [String:Any],result["request_id"] as? String==command.id,result["state"] as? String=="APPLIED",result["viewer_id"] as? String==String(context.session.accountID),result["guild_id"] as? String==scope.guildID.rawValue,NativeChannelOnboardingPolicy.number(result["guild_kind"])==Int64(scope.guildKind),NativeChannelOnboardingPolicy.number(result["submitted"])==1,result["configuration_hash"] as? String==command.configurationHash,result["effects_state"] as? String=="NONE",
              let roles=result["granted_role_ids"] as? [String],roles.isEmpty,let channels=result["joined_channel_ids"] as? [String],channels.isEmpty,
              let answers=result["answers"],let bytes=try? JSONSerialization.data(withJSONObject:answers),let original=try? JSONDecoder().decode([NativeOnboardingAnswer].self,from:bytes),original==command.answers,try restore()==command else{throw APIError.malformedResponse}
        try storage.remove(key);guard try restore()==nil else{throw APIError.malformedResponse};pending=nil;confirmed="原回答UUID \(command.id) 已持久确认；该请求没有授角色或加入频道。当前答案另读。";await readCurrent(run:run)
    }
    private func readCurrent(run:Int) async {snapshot=nil;do{let value=try await readSnapshot(run:run);guard valid(run) else{return};snapshot=value;issue=nil}catch{if valid(run){switch error {case NativeOnboardingReadFailure.notConfigured:issue="本空间尚未配置/启用引导，可直接查看欢迎屏；不是加入失败。";case NativeOnboardingReadFailure.screeningPending:issue="原逐条规则尚未完成。跳过引导不替代规则同意。";default:issue="当前引导配置或本人答案不可读；原已确认事实不变，不以历史答案授权下一操作。"}}}}
    private func readSnapshot(run:Int) async throws -> NativeOnboardingSnapshot {
        let body=try JSONSerialization.data(withJSONObject:["guild_kind":scope.guildKind,"guild_id":scope.guildID.rawValue],options:.sortedKeys);let data=try await exchange(NativeChannelOnboardingApproval.read,body:body,run:run)
        let value=try JSONDecoder().decode(NativeOnboardingSnapshot.self,from:data);guard value.valid(context:context,scope:scope) else{throw APIError.malformedResponse};return value
    }
    private func restore() throws -> Command? {do{guard let bytes=try storage.read(key) else{return nil};guard bytes.count<=32768 else{throw APIError.malformedResponse};let row=try JSONDecoder().decode(Command.self,from:bytes)
        guard row.owner==owner,UUID(uuidString:row.id) != nil,NativeOnboardingSnapshot.hash(row.configurationHash),row.body.count<=16384,
              let fields=(try? JSONSerialization.jsonObject(with:row.body)) as? [String:Any],Set(fields.keys)==["guild_kind","guild_id","request_id","configuration_hash","answers"],!row.answers.isEmpty,row.answers.count<=3,Set(row.answers.map(\.promptID)).count==row.answers.count,row.answers.allSatisfy({NativeOnboardingSnapshot.id($0.promptID) && !$0.optionIDs.isEmpty && $0.optionIDs.count<=8 && Set($0.optionIDs).count==$0.optionIDs.count && $0.optionIDs.allSatisfy(NativeOnboardingSnapshot.id)}),fields["request_id"] as? String==row.id,fields["configuration_hash"] as? String==row.configurationHash,fields["guild_id"] as? String==scope.guildID.rawValue,NativeChannelOnboardingPolicy.number(fields["guild_kind"])==Int64(scope.guildKind),let answers=fields["answers"],let data=try? JSONSerialization.data(withJSONObject:answers),try JSONDecoder().decode([NativeOnboardingAnswer].self,from:data)==row.answers else{throw APIError.malformedResponse};return row
    }catch{storageFailed=true;throw error}}
    private func valid(_ run:Int)->Bool{generation==run&&isCurrent && !Task.isCancelled}
    private func exchange(_ path:String,body:Data?,run:Int) async throws -> Data {
        guard valid(run) else{throw APIError.unauthorized};var request=URLRequest(url:context.baseURL.appendingPathComponent(path));request.httpMethod=body==nil ? "GET":"POST";request.httpBody=body;request.httpShouldHandleCookies=false;request.cachePolicy = .reloadIgnoringLocalCacheData;request.timeoutInterval=20
        request.setValue(context.session.token,forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Accept");if body != nil{request.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        guard NativeChannelOnboardingPolicy.accepts(request,context:context,approval:approval) else{throw APIError.invalidRequest};let(data,status)=try await transport.send(request);guard valid(run) else{throw APIError.unauthorized}
        if status==401{unauthorized();retired=true;throw APIError.unauthorized};guard data.count<=1048576,let envelope=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else{throw APIError.malformedResponse}
        if NativeChannelOnboardingPolicy.number(envelope["code"])==401{unauthorized();retired=true;throw APIError.unauthorized}
        if path==NativeChannelOnboardingApproval.read,NativeChannelOnboardingPolicy.number(envelope["code"]) != 200 {
            if envelope["errorCode"] as? String=="ONBOARDING_NOT_CONFIGURED"{throw NativeOnboardingReadFailure.notConfigured}
            if envelope["errorCode"] as? String=="SCREENING_PENDING"{throw NativeOnboardingReadFailure.screeningPending}
        }
        guard (200..<300).contains(status),NativeChannelOnboardingPolicy.number(envelope["code"])==200,let value=envelope["data"] else{throw APIError.malformedResponse};return try JSONSerialization.data(withJSONObject:value,options:.sortedKeys)
    }
}
