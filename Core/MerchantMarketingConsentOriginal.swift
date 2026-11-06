import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct MerchantMarketingConsentOriginalGrant:Equatable,Hashable {
 public let merchantID:Int,ownerID:Int,channel:String,optedIn:Bool
 public init(merchantID:Int,ownerID:Int,channel:ComplianceMarketingChannel,optedIn:Bool)throws{
  guard merchantID>0,ownerID>0 else{throw APIError.invalidConfiguration};self.merchantID=merchantID;self.ownerID=ownerID;self.channel=channel.rawValue;self.optedIn=optedIn
 }
}
/// Independent exact endpoint scope, default nil at host. Never enables campaign dispatch or generic compliance writes.
public struct MerchantMarketingConsentOriginalApproval:Equatable {
 public let revision:UUID,baseURL:URL,namespace:String,accountID:Int,grants:Set<MerchantMarketingConsentOriginalGrant>
 public init(baseURL:URL,namespace:String,accountID:Int,grants:Set<MerchantMarketingConsentOriginalGrant> = [],revision:UUID=UUID())throws{
  _ = try OperationEndpointApproval(baseURL:baseURL,namespace:namespace,accountID:accountID,paths:[MerchantMarketingConsentOriginalClient.path,MerchantMarketingConsentOriginalClient.resultPath])
  self.baseURL=baseURL;self.namespace=namespace;self.accountID=accountID;self.grants=grants;self.revision=revision
 }
 public func matches(_ c:RuntimeDependencyContext)->Bool{c.market == .china && c.baseURL.absoluteString.utf8.elementsEqual(baseURL.absoluteString.utf8) && c.session.namespace.utf8.elementsEqual(namespace.utf8) && c.session.accountID==accountID}
 public func permits(_ row:ComplianceMarketingConsent,_ channel:ComplianceMarketingChannel,_ optedIn:Bool)->Bool{
  grants.contains{ $0.merchantID==row.merchantRowId && $0.ownerID==row.merchantOwnerMemberId && $0.channel==channel.rawValue && $0.optedIn==optedIn }
 }
}
public struct MerchantMarketingConsentOriginalTarget:Equatable {
 public let merchantID:Int,ownerID:Int,channel:ComplianceMarketingChannel
 public init?(intent:CompliancePendingOperation){
  let p=intent.operation.split(separator:"|",omittingEmptySubsequences:false)
  guard p.count==4,p[0]=="marketing",let m=Int(p[1]),m>0,String(m)==String(p[1]),let o=Int(p[2]),o>0,String(o)==String(p[2]),let c=ComplianceMarketingChannel(rawValue:String(p[3])),MerchantMarketingConsentOriginalClient.validRequestID(intent.requestID) else{return nil}
  merchantID=m;ownerID=o;channel=c
 }
}
public struct MerchantMarketingConsentOriginalReceipt:Decodable,Equatable,Identifiable {
 public let receiptVersion:Int,actorId:Int,merchantRowId:Int,merchantOwnerMemberId:Int,channel:String,requestId:String,outcome:String
 public let consentId:Int?,eventType:String?,recordedAt:Int64?
 public var id:String{requestId+"|"+String(merchantRowId)+"|"+String(merchantOwnerMemberId)+"|"+channel}
 public var recorded:Bool{outcome=="RECORDED"}
 public func validate(_ intent:CompliancePendingOperation,session:ComplianceSession)throws{
  guard let target=MerchantMarketingConsentOriginalTarget(intent:intent),intent.scope==session.journalScope,receiptVersion==1,actorId==session.accountID,merchantRowId==target.merchantID,merchantOwnerMemberId==target.ownerID,channel==target.channel.rawValue,requestId.utf8.elementsEqual(intent.requestID.utf8) else{throw ComplianceFailure.readbackMismatch}
  if outcome=="NOT_OBSERVED"{guard consentId==nil,eventType==nil,recordedAt==nil else{throw ComplianceFailure.malformed};return}
  guard recorded,let expected=intent.marketingOptedIn,eventType==(expected ? "OPT_IN":"OPT_OUT"),(consentId ?? 0)>0,(recordedAt ?? 0)>0 else{throw ComplianceFailure.readbackMismatch}
 }
}
@MainActor public final class MerchantMarketingConsentOriginalClient {
 /// Original request IDs also include legacy non-UUID references; keep their exact format.
 public nonisolated static func validRequestID(_ value: String) -> Bool {
  value.utf8.count <= 64 && value.range(of: #"\A[A-Za-z0-9._:-]+\z"#, options: .regularExpression) != nil
 }
 public static let path="api/merchant/crm/marketing-consents",resultPath=path+"/result"
 public let context:RuntimeDependencyContext,approval:MerchantMarketingConsentOriginalApproval
 private let transport:any HTTPTransport,current:()->RuntimeDependencyContext?,stillApproved:()->Bool
 private let unauthorized:()->Void
 private var sent:Set<String> = []
 public init(context:RuntimeDependencyContext,approval:MerchantMarketingConsentOriginalApproval,transport:any HTTPTransport,current:@escaping()->RuntimeDependencyContext?,stillApproved:@escaping()->Bool,onUnauthorized:@escaping()->Void = {}){self.context=context;self.approval=approval;self.transport=transport;self.current=current;self.stillApproved=stillApproved;self.unauthorized=onUnauthorized}
 public var isCurrent:Bool{ContentDraftContextFence.matches(current(), context) && current()?.session.role.utf8.elementsEqual(context.session.role.utf8) == true && context.role.utf8.elementsEqual(context.session.role.utf8) && approval.matches(context) && stillApproved()}
 public func matches(_ session:ComplianceSession)->Bool{isCurrent && session.accountID==context.session.accountID && session.epoch==context.session.epoch && session.namespace.utf8.elementsEqual(context.session.namespace.utf8) && session.market=="CN"}
 public func canWrite(_ row:ComplianceMarketingConsent,_ channel:ComplianceMarketingChannel,_ optedIn:Bool)->Bool{isCurrent && row.valid && approval.permits(row,channel,optedIn)}
 private func check(_ session:ComplianceSession)throws{guard matches(session) else{throw ComplianceFailure.unavailable};try Task.checkCancellation()}
 private func request(_ path:String,query:[String:String]=[:],body:[String:Any]?=nil)throws->URLRequest{
  var c=URLComponents(url:context.baseURL.appendingPathComponent(path),resolvingAgainstBaseURL:false)!;if !query.isEmpty{c.queryItems=query.sorted{$0.key<$1.key}.map{URLQueryItem(name:$0.key,value:$0.value)}}
  guard let url=c.url else{throw ComplianceFailure.invalidInput};var r=URLRequest(url:url);r.httpMethod=body==nil ? "GET":"POST";r.cachePolicy = .reloadIgnoringLocalCacheData;r.timeoutInterval=20;r.httpShouldHandleCookies=false
  r.setValue(context.session.token,forHTTPHeaderField:"Authorization");r.setValue("application/json",forHTTPHeaderField:"Accept")
  if let body{r.httpBody=try JSONSerialization.data(withJSONObject:body,options:.sortedKeys);r.setValue("application/json",forHTTPHeaderField:"Content-Type")};return r
 }
 private struct Envelope<T:Decodable>:Decodable{let code:Int;let data:T?}
 private func send<T:Decodable>(_ request:URLRequest,session:ComplianceSession,as:T.Type)async throws->T{
  try check(session);guard Self.accepts(request,context:context,approval:approval) else{throw ComplianceFailure.unavailable}
  let(data,status)=try await transport.send(request)
  // Retired or cancelled authentication responses cannot affect the new viewer.
  try check(session)
  if status==401{unauthorized();throw APIError.unauthorized};if status==403{throw MerchantBusinessFailure.denied}
  guard data.count<=2*1024*1024,let raw=String(data:data,encoding:.utf8),(try? ContentDraftJSON.parse(raw)) != nil else{throw ComplianceFailure.malformed}
  let e=try JSONDecoder().decode(Envelope<T>.self,from:data);if e.code==401{unauthorized();throw APIError.unauthorized};if e.code==403{throw MerchantBusinessFailure.denied}
  guard (200..<300).contains(status),e.code==200,let value=e.data else{throw ComplianceFailure.unresolved};try check(session);return value
 }
 public func list(session:ComplianceSession)async throws->[ComplianceMarketingConsent]{
  let rows:[ComplianceMarketingConsent]=try await send(request(Self.path),session:session,as:[ComplianceMarketingConsent].self)
  guard rows.allSatisfy(\.valid),Set(rows.map(\.merchantRowId)).count==rows.count else{throw ComplianceFailure.malformed};return rows
 }
 public func result(_ intent:CompliancePendingOperation,session:ComplianceSession)async throws->MerchantMarketingConsentOriginalReceipt{
  guard let target=MerchantMarketingConsentOriginalTarget(intent:intent),intent.marketingRealm?.utf8.elementsEqual(context.baseURL.absoluteString.utf8) == true else{throw ComplianceFailure.unresolved}
  let r:MerchantMarketingConsentOriginalReceipt=try await send(request(Self.resultPath,query:["merchantRowId":String(target.merchantID),"merchantOwnerMemberId":String(target.ownerID),"channel":target.channel.rawValue,"requestId":intent.requestID]),session:session,as:MerchantMarketingConsentOriginalReceipt.self)
  try r.validate(intent,session:session);return r
 }
 public func write(_ row:ComplianceMarketingConsent,channel:ComplianceMarketingChannel,optedIn:Bool,intent:CompliancePendingOperation,session:ComplianceSession)async throws{
  try check(session);guard canWrite(row,channel,optedIn),intent.scope==session.journalScope,intent.operation==row.operation(channel),intent.marketingOptedIn==optedIn,intent.marketingRealm?.utf8.elementsEqual(context.baseURL.absoluteString.utf8) == true,MerchantMarketingConsentOriginalClient.validRequestID(intent.requestID),!sent.contains(intent.requestID) else{throw ComplianceFailure.unresolved}
  let r=try request(Self.path,body:["merchantRowId":row.merchantRowId,"merchantOwnerMemberId":row.merchantOwnerMemberId,"channel":channel.rawValue,"optedIn":optedIn,"requestId":intent.requestID]);sent.insert(intent.requestID)
  // Original append-only writer response is not latest boolean proof. Exact GET is mandatory after this one dispatch.
  _ = try await send(r,session:session,as:MerchantBusinessValue.self)
 }
 public static func accepts(_ request:URLRequest,context:RuntimeDependencyContext,approval:MerchantMarketingConsentOriginalApproval)->Bool{
  guard approval.matches(context), !request.httpShouldHandleCookies, request.value(forHTTPHeaderField:"Accept")=="application/json", request.value(forHTTPHeaderField:"Authorization").map({ Data($0.utf8) }) == Data(context.session.token.utf8),request.value(forHTTPHeaderField:"Cookie")==nil,request.value(forHTTPHeaderField:"Proxy-Authorization")==nil,request.httpBodyStream==nil,let url=request.url,var parts=URLComponents(url:url,resolvingAgainstBaseURL:false),parts.fragment==nil else{return false}
  if request.httpMethod=="GET",request.httpBody==nil{
   if url==context.baseURL.appendingPathComponent(path){return true}
   guard let q=parts.queryItems,q.count==4,Set(q.map(\.name))==Set(["merchantRowId","merchantOwnerMemberId","channel","requestId"]) else{return false};parts.query=nil
   guard parts.url==context.baseURL.appendingPathComponent(resultPath) else{return false}
   for key in ["merchantRowId","merchantOwnerMemberId"]{guard let raw=q.first(where:{$0.name==key})?.value,let id=Int(raw),id>0,String(id)==raw else{return false}}
   guard let channel=q.first(where:{$0.name=="channel"})?.value,ComplianceMarketingChannel(rawValue:channel) != nil,let uuid=q.first(where:{$0.name=="requestId"})?.value,MerchantMarketingConsentOriginalClient.validRequestID(uuid) else{return false};return true
  }
  guard request.httpMethod=="POST",url==context.baseURL.appendingPathComponent(path),let data=request.httpBody,let raw=String(data:data,encoding:.utf8),(try? ContentDraftJSON.parse(raw)) != nil,
   let o=try? JSONDecoder().decode(MerchantBusinessValue.self,from:data).object,Set(o.keys)==Set(["merchantRowId","merchantOwnerMemberId","channel","optedIn","requestId"]),
   let merchant=try? o.mbInt("merchantRowId",minimum:1),let owner=try? o.mbInt("merchantOwnerMemberId",minimum:1),let channel=o.mbText("channel"),let c=ComplianceMarketingChannel(rawValue:channel),let choice=o["optedIn"]?.bool,let uuid=o.mbText("requestId"),MerchantMarketingConsentOriginalClient.validRequestID(uuid),
   let grant=try? MerchantMarketingConsentOriginalGrant(merchantID:merchant,ownerID:owner,channel:c,optedIn:choice),approval.grants.contains(grant),let expected=try? JSONSerialization.data(withJSONObject:["merchantRowId":merchant,"merchantOwnerMemberId":owner,"channel":channel,"optedIn":choice,"requestId":uuid],options:.sortedKeys) else{return false}
  return data==expected && request.value(forHTTPHeaderField:"Content-Type")=="application/json"
 }
}
