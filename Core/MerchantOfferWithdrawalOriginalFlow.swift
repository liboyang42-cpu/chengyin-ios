import Foundation
import CryptoKit
import CoreFoundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
public struct MerchantOfferWithdrawalOriginalCurrent:Decodable,Equatable {
    public let receiptVersion:Int,actorId:Int,merchantId:Int,ownerId:Int,offerId:Int
    public let topicId:Int?,chapterId:Int?,status:Int?,validEndEpoch:Int64?,updatedAtEpoch:Int64?
    public let termsMode:String?,quotaTotal:Int?,quotaUsed:Int?,perkId:Int?,perHeadFee:String?,withdrawReason:String?,withdrawRequired:Bool?
    public let chapterRequired:Int?,requiredByOriginalRule:Bool?,topicLifecycle:Int?,topicUserStatus:Int?,isOrdinary:Bool,canWithdraw:Bool,snapshotSHA256:String
}
public struct MerchantOfferWithdrawalOriginalReceipt:Decodable,Equatable {
    public let receiptVersion:Int,actorId:Int,merchantId:Int,ownerId:Int,offerId:Int,requestId:String,outcome:String
    public let intentSHA256:String?,receivedSHA256:String?,expectedSHA256:String?,reasonSHA256:String?,receivedReasonSHA256:String?,completedAt:Int64?
    public let topicId:Int?,chapterId:Int?,statusAtWrite:Int?,requiredAtWrite:Int?,userStatusAtWrite:Int?,offerUpdatedAt:Int64?
    public var known:Bool{["WITHDRAWN","REJECTED_CHANGED","REJECTED_STATE","REJECTED_INPUT"].contains(outcome)}
}
public struct MerchantOfferWithdrawalOriginalReview:Identifiable,Equatable {
    public let id:UUID,intentSHA256:String,reasonSHA256:String,source:MerchantOfferWithdrawalOriginalCurrent,reason:String
    public var fields:[String:Any]{["offerId":source.offerId,"reason":reason,"reasonSHA256":reasonSHA256,"expectedSHA256":source.snapshotSHA256]}
}
@MainActor public final class MerchantOfferWithdrawalOriginalFlow {
    public static let base="api/merchant/offer-withdrawal/request/"
    public static let paths:Set<String>=[base+"current",base+"result",base+"withdraw"]
    private static func intent(_ fields:[String:Any])throws->String{SHA256.hash(data:try JSONSerialization.data(withJSONObject:fields,options:[.sortedKeys])).map{String(format:"%02x",$0)}.joined()}
    private static func positive(_ value:Any?)->Int?{guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),let v=Int(n.stringValue),v>0 else{return nil};return v}
    /// Exact original Java String.trim / UTF-16 length contract, not an invented byte/character threshold.
    public static func originalReason(_ value:String)throws->String{
        var scalars=value.unicodeScalars
        while let first=scalars.first,first.value<=0x20{scalars.removeFirst()}
        while let last=scalars.last,last.value<=0x20{scalars.removeLast()}
        let reason=String(scalars);guard !reason.isEmpty,reason.utf16.count<=500 else{throw MerchantOfferWithdrawalOriginalFailure.invalid};return reason
    }
    private static func reasonHash(_ value:String)->String{SHA256.hash(data:Data(value.utf8)).map{String(format:"%02x",$0)}.joined()}
    public static func accepts(_ r:URLRequest,path:String,merchantID:Int,offerID:Int)->Bool{
        guard merchantID>0,offerID>0,r.httpBodyStream==nil,let u=r.url,let p=URLComponents(url:u,resolvingAgainstBaseURL:false) else{return false};let q=p.queryItems ?? []
        if r.httpMethod=="GET"{
            guard [base+"current",base+"result"].contains(path),r.httpBody==nil,r.value(forHTTPHeaderField:"Content-Type")==nil,q.count==(path==base+"current" ? 2:3),
                q[0].name=="merchantId",q[0].value==String(merchantID),q[1].name=="offerId",q[1].value==String(offerID) else{return false}
            if path==base+"current"{return true};guard q[2].name=="requestId",let id=q[2].value else{return false};return UUID(uuidString:id)?.uuidString.lowercased()==id
        }
        guard r.httpMethod=="POST",path==base+"withdraw",q.isEmpty,r.value(forHTTPHeaderField:"Content-Type")=="application/json",let data=r.httpBody,data.count<=16384,
            let raw=String(data:data,encoding:.utf8),(try? ContentDraftJSON.parse(raw)) != nil,var f=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
            Set(f.keys)==["merchantId","offerId","requestId","intentSHA256","expectedSHA256","reasonSHA256","reason"],
            positive(f["merchantId"])==merchantID,positive(f["offerId"])==offerID,
            let id=f["requestId"] as? String,UUID(uuidString:id)?.uuidString.lowercased()==id,let hash=f["intentSHA256"] as? String,MerchantOfferWithdrawalOriginalPending.hash(hash),
            let expected=f["expectedSHA256"] as? String,MerchantOfferWithdrawalOriginalPending.hash(expected),let reason=f["reason"] as? String,(try? originalReason(reason))==reason,
            let reasonSHA=f["reasonSHA256"] as? String,reasonSHA==reasonHash(reason) else{return false}
        f.removeValue(forKey:"merchantId");f.removeValue(forKey:"requestId");f.removeValue(forKey:"intentSHA256");return (try? intent(f))==hash
    }
    private let api:APIConfiguration,transport:any HTTPTransport,journal:MerchantOfferWithdrawalOriginalJournal
    private let actorID:Int,ownerID:Int,namespace:String
    public let merchantID:Int,offerID:Int
    private let token:()->String?,current:()->Bool,allowed:(String)->Bool,authorize:()async throws->Void,unauthorized:()->Void
    private var generation=UUID(),retired=false,transmission:Task<(Data,Int),Error>?
    public private(set) var busy=false,issue:String?,snapshot:MerchantOfferWithdrawalOriginalCurrent?,receipt:MerchantOfferWithdrawalOriginalReceipt?,review:MerchantOfferWithdrawalOriginalReview?
    public private(set) var draftRetirement=UUID()
    private var receiptPending: MerchantOfferWithdrawalOriginalPending?
    public private(set) var receiptIsFresh = false
    public var canAcknowledgeKnown: Bool {
        guard isCurrent, !busy, receiptIsFresh, receipt?.known == true, let p = receiptPending else { return false }
        return (try? journal.canAcknowledge(p)) == true
    }
    public var onChange:(()->Void)?
    public init(api:APIConfiguration,transport:any HTTPTransport,journal:MerchantOfferWithdrawalOriginalJournal,actorID:Int,merchantID:Int,ownerID:Int,offerID:Int,namespace:String,
        token:@escaping()->String?,current:@escaping()->Bool,allowed:@escaping(String)->Bool,authorize:@escaping()async throws->Void,unauthorized:@escaping()->Void){
        self.api=api;self.transport=transport;self.journal=journal;self.actorID=actorID;self.merchantID=merchantID;self.ownerID=ownerID;self.offerID=offerID;self.namespace=namespace
        self.token=token;self.current=current;self.allowed=allowed;self.authorize=authorize;self.unauthorized=unauthorized
    }
    public var isCurrent:Bool{!retired && current()}
    public var canPrepare:Bool{
        guard journal.canBegin,isCurrent,!busy,snapshot?.canWithdraw==true,allowed(Self.base+"result"),allowed(Self.base+"withdraw") else{return false}
        do{return try pending()==nil}catch{return false}
    }
    public func pending()throws->MerchantOfferWithdrawalOriginalPending?{try journal.read(account:actorID,merchant:merchantID,offer:offerID,namespace:namespace,realm:api.baseURL.absoluteString)}
    public func stop(){generation=UUID();transmission?.cancel();transmission=nil;busy=false;snapshot=nil;receipt=nil;receiptPending=nil;receiptIsFresh=false;review=nil;draftRetirement=UUID();onChange?()}
    public func invalidate(){retired=true;stop()}
    public func cancelReview(){review=nil;draftRetirement=UUID();onChange?()}
    private func ensure(_ stamp:UUID)throws{guard isCurrent,generation==stamp,!Task.isCancelled else{throw MerchantOfferWithdrawalOriginalFailure.stale}}
    public func prepare(reason value:String)throws{
        guard canPrepare,let source=snapshot else{throw MerchantOfferWithdrawalOriginalFailure.unavailable};let reason=try Self.originalReason(value),hash=Self.reasonHash(reason)
        let fields:[String:Any]=["offerId":offerID,"reason":reason,"reasonSHA256":hash,"expectedSHA256":source.snapshotSHA256]
        review = .init(id:UUID(),intentSHA256:try Self.intent(fields),reasonSHA256:hash,source:source,reason:reason);onChange?()
    }
    private struct Envelope<T:Decodable>:Decodable{let code:Int;let data:T?}
    private struct ResponseCode: Decodable { let code: Int }
    private func send<T:Decodable>(_ path:String,query:[URLQueryItem]=[],body:Data?=nil,stamp:UUID,as:T.Type)async throws->T{
        try ensure(stamp);guard allowed(path),let credential=token(),AuthRequestBuilder.isValidToken(credential) else{throw MerchantOfferWithdrawalOriginalFailure.unavailable}
        var p=URLComponents(url:api.baseURL.appendingPathComponent(path),resolvingAgainstBaseURL:false)!;if !query.isEmpty{p.queryItems=query}
        var r=URLRequest(url:p.url!);r.httpMethod=body==nil ? "GET":"POST";r.httpBody=body;r.httpShouldHandleCookies=false;r.cachePolicy = .reloadIgnoringLocalCacheData
        r.setValue(credential,forHTTPHeaderField:"Authorization");if body != nil{r.setValue("application/json",forHTTPHeaderField:"Content-Type")}
        let transport=self.transport;let job=Task{try await transport.send(r)};transmission=job;defer{transmission=nil}
        let(data,status)=try await withTaskCancellationHandler(operation:{try await job.value},onCancel:{job.cancel()});try ensure(stamp)
        guard token()==credential,data.count<=1024*1024 else{throw MerchantOfferWithdrawalOriginalFailure.unknown}
        if status==401{unauthorized();invalidate();throw APIError.unauthorized};if status==403{invalidate();throw MerchantOfferWithdrawalOriginalFailure.stale}
        if status==408 || status==429 || (500...599).contains(status) {
            // Explicit authentication/permission denial still wins over a retryable HTTP status.
            if let text=String(data:data,encoding:.utf8), (try? ContentDraftJSON.parse(text)) != nil,
               let code=try? JSONDecoder().decode(ResponseCode.self,from:data).code {
                if code==401{unauthorized();invalidate();throw APIError.unauthorized}
                if code==403{invalidate();throw MerchantOfferWithdrawalOriginalFailure.stale}
            }
            throw APIError.httpStatus(status)
        }
        guard let text=String(data:data,encoding:.utf8) else{throw MerchantOfferWithdrawalOriginalFailure.unknown};_ = try ContentDraftJSON.parse(text)
        let e=try JSONDecoder().decode(Envelope<T>.self,from:data)
        if e.code==401{unauthorized();invalidate();throw APIError.unauthorized};if e.code==403{invalidate();throw MerchantOfferWithdrawalOriginalFailure.stale}
        guard (200..<300).contains(status),e.code==200,let value=e.data else{throw MerchantOfferWithdrawalOriginalFailure.unknown};return value
    }


    private var query:[URLQueryItem]{[.init(name:"merchantId",value:String(merchantID)),.init(name:"offerId",value:String(offerID))]}
    private func currentRows(_ stamp:UUID)async throws->MerchantOfferWithdrawalOriginalCurrent{
        let s=try await send(Self.base+"current",query:query,stamp:stamp,as:MerchantOfferWithdrawalOriginalCurrent.self)
        guard s.receiptVersion==1,s.actorId==actorID,s.merchantId==merchantID,s.ownerId==ownerID,s.offerId==offerID,
            MerchantOfferWithdrawalOriginalPending.hash(s.snapshotSHA256),!s.canWithdraw || s.isOrdinary && s.status==1 && s.requiredByOriginalRule != nil && (s.topicId ?? 0)>0 && (s.chapterId ?? 0)>0 else{throw MerchantOfferWithdrawalOriginalFailure.unknown};return s
    }
    private func accept(_ r:MerchantOfferWithdrawalOriginalReceipt,p:MerchantOfferWithdrawalOriginalPending)throws->MerchantOfferWithdrawalOriginalReceipt{
        guard r.receiptVersion==1,r.actorId==actorID,r.merchantId==merchantID,r.ownerId==ownerID,r.offerId==offerID,UUID(uuidString:r.requestId)==p.requestID,
            r.known || r.outcome=="UNKNOWN",r.reasonSHA256==nil || r.reasonSHA256==p.reasonSHA256,r.intentSHA256==nil || r.intentSHA256==p.intentSHA256,r.expectedSHA256==nil || r.expectedSHA256==p.expectedSHA256 else{throw MerchantOfferWithdrawalOriginalFailure.unknown}
        if r.known{guard r.reasonSHA256==p.reasonSHA256,r.intentSHA256==p.intentSHA256,r.expectedSHA256==p.expectedSHA256,let hash=r.receivedSHA256,MerchantOfferWithdrawalOriginalPending.hash(hash),
            let reason=r.receivedReasonSHA256,MerchantOfferWithdrawalOriginalPending.hash(reason),(r.completedAt ?? 0)>0 else{throw MerchantOfferWithdrawalOriginalFailure.unknown}
            if r.outcome=="WITHDRAWN"{guard reason==p.reasonSHA256,(r.topicId ?? 0)>0,(r.chapterId ?? 0)>0,r.statusAtWrite==0,[0,1].contains(r.requiredAtWrite ?? -1),(r.offerUpdatedAt ?? 0)>0 else{throw MerchantOfferWithdrawalOriginalFailure.unknown}}
            else{guard r.topicId==nil,r.chapterId==nil,r.statusAtWrite==nil,r.requiredAtWrite==nil,r.userStatusAtWrite==nil,r.offerUpdatedAt==nil else{throw MerchantOfferWithdrawalOriginalFailure.unknown}}
        };return r
    }
    private func original(_ p:MerchantOfferWithdrawalOriginalPending,stamp:UUID)async throws->MerchantOfferWithdrawalOriginalReceipt{
        try accept(await send(Self.base+"result",query:query+[.init(name:"requestId",value:p.requestID.uuidString.lowercased())],stamp:stamp,as:MerchantOfferWithdrawalOriginalReceipt.self),p:p)
    }
    private static func isTransientReadFailure(_ error: Error) -> Bool {
        if let error = error as? URLError {
            return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                    .dnsLookupFailed, .notConnectedToInternet].contains(error.code)
        }
        if let error = error as? APIError, case let .httpStatus(status) = error {
            return status == 408 || status == 429 || (500...599).contains(status)
        }
        return false
    }
    private func clearReceipt() { receipt = nil; receiptPending = nil; receiptIsFresh = false }
    /// A cached receipt is display-only after a retry failure. It must still match the
    /// exact durable pending record, and it can never acknowledge UNKNOWN or a new UUID.
    private func retainHistory(after error: Error) -> Bool {
        guard Self.isTransientReadFailure(error), isCurrent, let held = receiptPending,
              let receipt, receipt.known, let live = try? pending(), live == held,
              (try? accept(receipt, p: live)) == receipt else { clearReceipt(); return false }
        receiptIsFresh = false
        return true
    }
    public func recover()async{
        guard isCurrent,!busy else{return};let stamp=generation;busy=true;issue=nil;review=nil;receiptIsFresh=false;draftRetirement=UUID();onChange?();defer{if generation==stamp{busy=false;onChange?()}}
        do{try await authorize();try ensure(stamp)}catch{
            if generation==stamp {
                snapshot=nil
                let retained = retainHistory(after:error)
                issue = retained ? "当前权限暂未重新确认，仅保留同一原请求的已验证历史；不能已阅清除。" : "当前原商家 COOP_MANAGE 权限未确认，停止读取；原请求身份保留。"
            }
            return
        }
        do {
            if let p=try pending() {
                if receiptPending != p { clearReceipt() }
                let result=try await original(p,stamp:stamp)
                guard try pending() == p else { throw MerchantOfferWithdrawalOriginalFailure.stale }
                // A different response cannot replace an already verified immutable result.
                if let previous=receipt, previous.known, previous != result { throw MerchantOfferWithdrawalOriginalFailure.unknown }
                receipt=result;receiptPending=p;receiptIsFresh=true
                if result.outcome=="UNKNOWN"{issue="原退出请求未知，只回读；列表消失或当前已停用不能证明此 UUID 成功。"}
            } else { clearReceipt() }
        } catch {
            if generation==stamp {
                let retained = retainHistory(after:error)
                issue = retained ? "原结果暂未重新确认，仅保留同一原请求的已验证历史；不能已阅清除。" : "原退出结果未确认，持久身份保留。"
            }
        }
        guard isCurrent,generation==stamp,!Task.isCancelled else{return}
        do{snapshot=try await currentRows(stamp)}catch{if generation==stamp{snapshot=nil;issue=(issue ?? "")+" 当前原供给未确认，不代表原写失败。"}}
    }
    public func confirm(_ frozen:MerchantOfferWithdrawalOriginalReview)async{
        guard canPrepare,review==frozen else{return};let stamp=generation;busy=true;issue=nil;onChange?();defer{if generation==stamp{busy=false;onChange?()}}
        do{try await authorize();try ensure(stamp);let fresh=try await currentRows(stamp);snapshot=fresh
            guard fresh==frozen.source,try Self.originalReason(frozen.reason)==frozen.reason,Self.reasonHash(frozen.reason)==frozen.reasonSHA256 else{review=nil;draftRetirement=UUID();throw MerchantOfferWithdrawalOriginalFailure.stale}
            var f=frozen.fields;guard try Self.intent(f)==frozen.intentSHA256,allowed(Self.base+"withdraw") else{throw MerchantOfferWithdrawalOriginalFailure.stale}
            let p=try MerchantOfferWithdrawalOriginalPending(accountID:actorID,merchantID:merchantID,offerID:offerID,namespace:namespace,realm:api.baseURL.absoluteString,requestID:frozen.id,intentSHA256:frozen.intentSHA256,reasonSHA256:frozen.reasonSHA256,expectedSHA256:fresh.snapshotSHA256)
            f["merchantId"]=merchantID;f["requestId"]=p.requestID.uuidString.lowercased();f["intentSHA256"]=p.intentSHA256
            let data=try JSONSerialization.data(withJSONObject:f,options:[.sortedKeys]);guard data.count<=16384 else{throw MerchantOfferWithdrawalOriginalFailure.invalid}
            try ensure(stamp);try journal.begin(p);review=nil;draftRetirement=UUID()
            receipt=try accept(await send(Self.base+"withdraw",body:data,stamp:stamp,as:MerchantOfferWithdrawalOriginalReceipt.self),p:p);receiptPending=p;receiptIsFresh=true
        }catch{if generation==stamp{issue="原退出未确认或写前条件变化；已持久身份仅 GET 恢复，不重发，不借当前停用/列表消失解除。"};return}
        do{snapshot=try await currentRows(stamp)}catch{if generation==stamp{snapshot=nil;issue="原请求结果已保留；当前供给未确认，不重写。"}}
    }
    public func acknowledgeKnown()throws{
        guard canAcknowledgeKnown,let p=try pending(),receiptPending==p,let receipt,receipt.known,try accept(receipt,p:p)==receipt else{throw MerchantOfferWithdrawalOriginalFailure.unknown}
        try journal.acknowledge(p);clearReceipt();review=nil;draftRetirement=UUID();onChange?()
    }
}
