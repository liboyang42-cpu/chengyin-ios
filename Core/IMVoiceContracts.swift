import Foundation
import CryptoKit

public enum IMVoiceFailure:Error { case unavailable,invalid,stale,unknown,notApproved }
/// Native AAC/M4A is supported by the original upload boundary. No NPC training constraints.
public struct IMVoiceClip:Codable,Equatable {
    public let bytes:Data
    public let waveform:Data
    public let durationMS:Int
    public var sha256:String { SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined() }
    public init(bytes:Data,waveform:Data,durationMS:Int) throws {
        guard !bytes.isEmpty,bytes.count<=2*1024*1024,!waveform.isEmpty,waveform.count<=256,
              durationMS>0,durationMS<=60_000 else { throw IMVoiceFailure.invalid }
        self.bytes=bytes;self.waveform=waveform;self.durationMS=durationMS
    }
    public func validate() throws { _ = try Self(bytes:bytes,waveform:waveform,durationMS:durationMS) }
}
public struct IMVoiceReference:Codable,Equatable {
    public let uploadRequestID:String
    public let assetID:Int
    public let durationMS:Int
    public let waveform:String
    public let size:Int
    public var mime:String { "audio/mp4" }
    public func validate() throws {
        guard let id=UUID(uuidString:uploadRequestID),id.uuidString.lowercased()==uploadRequestID,assetID>0,
              durationMS>0,durationMS<=60_000,size>0,size<=2*1024*1024,
              let points=Data(base64Encoded:waveform),!points.isEmpty,points.count<=256,
              points.base64EncodedString()==waveform else { throw IMVoiceFailure.invalid }
    }
    public func wireFields() throws -> [String:String] {
        try validate()
        let data=try JSONSerialization.data(withJSONObject:["source":"original-im-voice-v1","uploadRequestId":uploadRequestID,
            "assetId":String(assetID),"durationSec":Double(durationMS)/1000,"waveform":waveform,"size":size,"mime":mime],options:[.sortedKeys,.withoutEscapingSlashes])
        guard let extra=String(data:data,encoding:.utf8) else { throw IMVoiceFailure.invalid }
        return ["msg_type":"10","content":"[语音]","extra_json":extra]
    }
    public static func read(_ message:MessagingMessage)->Self? {
        guard message.isPayloadVisible,message.type==10,message.content=="[语音]",
              let data=message.extraJSON?.data(using:.utf8),data.count<=4096,
              let value=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
              value["source"] as? String == "original-im-voice-v1",value["mime"] as? String == "audio/mp4",
              let request=value["uploadRequestId"] as? String,
              let raw=value["assetId"] as? String,let asset=Int(raw),String(asset)==raw,
              let duration=value["durationSec"] as? NSNumber,let size=value["size"] as? NSNumber,
              let waveform=value["waveform"] as? String else{return nil}
        let ms=duration.doubleValue*1000
        guard ms.isFinite,ms>0,ms<=60_000,abs(ms.rounded()-ms)<0.0001 else{return nil}
        let ref=Self(uploadRequestID:request,assetID:asset,durationMS:Int(ms.rounded()),waveform:waveform,size:size.intValue)
        do { try ref.validate(); return ref } catch { return nil }
    }
}
public struct IMVoiceUploadReceipt:Decodable,Equatable {
    public let source:String,state:String,requestID:String,sourceHash:String,conversationID:String,ownerID:String
    public let assetID:String?,reviewState:String?,durationMS:Int?,size:Int?,waveform:String?,asrState:String?
    enum CodingKeys:String,CodingKey {
        case source,state,requestID="upload_request_id",sourceHash="source_sha256",conversationID="conversation_id",ownerID="owner_member_id"
        case assetID="asset_id",reviewState="review_state",durationMS="duration_ms",size,waveform,asrState="asr_state"
    }
    public func validate(scope:IMScope,requestID:String,hash:String) throws {
        guard source=="original-im-voice-upload-v1",self.requestID==requestID,sourceHash==hash,
              conversationID==String(scope.conversationID),ownerID==String(scope.identity.accountID),
              ["NOT_FOUND","PENDING","UPLOADED"].contains(state) else { throw IMVoiceFailure.invalid }
        if state=="UPLOADED" { guard reference != nil,["HOLD","APPROVED","REJECTED"].contains(reviewState ?? ""),asrState=="TEXT_APPROVED" else { throw IMVoiceFailure.invalid } }
    }
    public var reference:IMVoiceReference? {
        guard let raw=assetID,let asset=Int(raw),String(asset)==raw,let durationMS,let size,let waveform else{return nil}
        let ref=IMVoiceReference(uploadRequestID:requestID,assetID:asset,durationMS:durationMS,waveform:waveform,size:size)
        do { try ref.validate(); return ref } catch { return nil }
    }
    public var ready:Bool { state=="UPLOADED" && reviewState=="APPROVED" && asrState=="TEXT_APPROVED" && reference != nil }
}
