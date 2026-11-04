import Foundation
import CryptoKit

public enum IMFileFailure: Error { case unavailable, invalid, unsafe, unknown, stale, linkExpired, unsupported }
/// Selected bytes are not a safety decision. Server format detection, scanning and original review remain mandatory.
public struct IMFileSelection: Equatable {
    public static let maximumBytes = 20 * 1024 * 1024
    public static let extensions: Set<String> = ["pdf","doc","docx","xls","xlsx","ppt","pptx","zip","txt"]
    public let name: String
    public let bytes: Data
    public let fileExtension: String
    public var sha256: String { SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined() }
    public init(name:String,bytes:Data) throws {
        guard !bytes.isEmpty,bytes.count<=Self.maximumBytes,name==name.trimmingCharacters(in:.whitespacesAndNewlines),
              !name.isEmpty,name.utf8.count<=240,!name.contains("/"),!name.contains("\\"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {throw IMFileFailure.invalid}
        let ext=(name as NSString).pathExtension.lowercased()
        guard Self.extensions.contains(ext) else{throw IMFileFailure.unsupported}
        self.name=name;self.bytes=bytes;self.fileExtension=ext
    }
}
/// Original immutable upload reference. Only a separate CLEAN + APPROVED receipt permits send.
/// No direct URL is placed in an outgoing message; recipients request their own authorized preview.
public struct IMFileReference: Codable, Equatable {
    public let uploadRequestID:String
    public let attachmentID:String
    public let name:String
    public let size:Int
    public let mime:String
    public let ext:String
    public let sha256:String
    public func validate() throws {
        guard let request=UUID(uuidString:uploadRequestID),request.uuidString.lowercased()==uploadRequestID,
              let id=Int64(attachmentID),id>0,String(id)==attachmentID,size>0,size<=IMFileSelection.maximumBytes,
              !name.isEmpty,name.utf8.count<=240,!name.contains("/"),!name.contains("\\"),
              !name.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}),
              IMFileSelection.extensions.contains(ext),(name as NSString).pathExtension.lowercased()==ext,
              Self.mimes[ext]==mime,sha256.count==64,sha256.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else{throw IMFileFailure.invalid}
    }
    public static let mimes:[String:String] = ["pdf":"application/pdf","doc":"application/msword","docx":"application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "xls":"application/vnd.ms-excel","xlsx":"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet","ppt":"application/vnd.ms-powerpoint",
        "pptx":"application/vnd.openxmlformats-officedocument.presentationml.presentation","zip":"application/zip","txt":"text/plain"]
    public func wireFields() throws -> [String:String] {
        try validate()
        let value:[String:Any] = ["source":"original-im-file-v1","uploadRequestId":uploadRequestID,"attachmentId":attachmentID,"size":size,"mime":mime,"ext":ext,"sha256":sha256]
        let data=try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys,.withoutEscapingSlashes])
        guard let extra=String(data:data,encoding:.utf8) else{throw IMFileFailure.invalid}
        return ["msg_type":"12","content":name,"extra_json":extra]
    }
    public static func read(_ message:MessagingMessage)->Self? {
        guard message.type==12,message.isPayloadVisible,let name=message.content,let data=message.extraJSON?.data(using:.utf8),data.count<=4096,
              let value=(try? JSONSerialization.jsonObject(with:data)) as? [String:Any],value["source"] as? String=="original-im-file-v1",
              let request=value["uploadRequestId"] as? String,let id=value["attachmentId"] as? String,let size=value["size"] as? Int,
              let mime=value["mime"] as? String,let ext=value["ext"] as? String,let hash=value["sha256"] as? String else{return nil}
        let reference=Self(uploadRequestID:request,attachmentID:id,name:name,size:size,mime:mime,ext:ext,sha256:hash)
        do{try reference.validate();return reference}catch{return nil}
    }
}

public struct IMFileUploadReceipt: Decodable {
    public let source: String
    public let ownerMemberID: String
    public let conversationID: String
    public let requestID: String
    public let sourceSHA256: String
    public let state: String
    public let scanState: String?
    public let reviewState: String?
    public let reference: IMFileReference?
    enum CodingKeys: String, CodingKey {
        case source,state,reference
        case ownerMemberID="owner_member_id", conversationID="conversation_id", requestID="upload_request_id"
        case sourceSHA256="source_sha256", scanState="scan_state", reviewState="review_state"
    }
    public var ready: Bool { state == "UPLOADED" && scanState == "CLEAN" && reviewState == "APPROVED" && reference != nil }
    public func validate(scope: IMScope, requestID: String, hash: String) throws {
        guard source == "original-im-file-upload-v1", ownerMemberID == String(scope.identity.accountID),
              conversationID == String(scope.conversationID), self.requestID == requestID, sourceSHA256 == hash,
              ["NOT_FOUND","RESERVED","UPLOADED"].contains(state) else { throw IMFileFailure.invalid }
        if let reference {
            try reference.validate()
            guard reference.uploadRequestID == requestID, reference.sha256 == hash else { throw IMFileFailure.invalid }
        }
        if state != "NOT_FOUND" {
            guard reference != nil, let scanState, ["PENDING","UNKNOWN","CLEAN","INFECTED"].contains(scanState),
                  let reviewState, ["HOLD","APPROVED","REJECTED"].contains(reviewState) else { throw IMFileFailure.invalid }
        }
    }
}
