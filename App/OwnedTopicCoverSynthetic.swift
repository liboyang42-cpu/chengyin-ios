#if DEBUG
import UIKit
import CryptoKit

/// In-memory producer responses through the real client, and a generated selected-only picker.
/// It never opens Photos, uploads a real file, contacts a provider or grants production capability.
@MainActor final class OwnedTopicCoverSynthetic: OwnedTopicCoverServing {
    @MainActor final class Picker: OwnedTopicCoverSelecting {
        let selected: RetainedSelectedImage
        var calls=0,cancelled=false
        init(_ image:RetainedSelectedImage){selected=image}
        func select()async throws->RetainedSelectedImage?{calls+=1;cancelled=false;return selected}
        func cancel(){cancelled=true}
    }
    @MainActor private final class Wire:HTTPTransport {
        let asset:OwnedTopicCoverAsset,bytes:Data
        let unknownSelection:Bool,unknownUpload:Bool
        var requests:[URLRequest]=[],receipts:[String:OwnedTopicCoverSelectionReceipt]=[:],unknownSent=false
        var selected:OwnedTopicCoverSelectionReceipt?
        var imageUnavailable=false
        var beforeReceipt:(()->Void)?
        init(asset:OwnedTopicCoverAsset,bytes:Data,unknownSelection:Bool,unknownUpload:Bool,beforeReceipt:(()->Void)?){self.asset=asset;self.bytes=bytes;self.unknownSelection=unknownSelection;self.unknownUpload=unknownUpload;self.beforeReceipt=beforeReceipt}
        func send(_ request:URLRequest)async throws->(Data,Int){
            requests.append(request)
            guard let path=request.url?.path else{throw APIError.invalidRequest}
            if path=="/"+OwnedTopicCoverClient.uploadPath {
                guard request.httpMethod=="POST",request.httpBody?.range(of:bytes) != nil else{throw APIError.invalidRequest}
                if unknownUpload{return try response(.null,status:503)}
                beforeReceipt?();return try response(asset.fields)
            }
            if path=="/"+asset.contentPath{return imageUnavailable ? (Data(),503):(bytes,200)}
            if path=="/"+OwnedTopicCoverClient.currentPath {
                let display:ProjectEditJSON=selected == nil ? .null : .object(["assetReference":asset.fields,"displayReference":displayFields])
                return try response(.object(["topicId":.number(7901),"topicConfigVersion":.number(Decimal(selected?.configVersion ?? 1)),"selectionVersion":.number(Decimal(selected?.selectionVersion ?? 0)),"contentSlotId":.number(51),"selectedAtConfigVersion":selected.map{.number(Decimal($0.configVersion))} ?? .null,"selectionState":.string(selected == nil ? "NONE":"CURRENT"),"assetAvailability":.string(selected == nil ? "NONE":"AVAILABLE"),"display":display]))
            }
            guard path=="/"+OwnedTopicCoverClient.selectPath || path=="/"+OwnedTopicCoverClient.statusPath,
                  let body=request.httpBody,let json=try? JSONDecoder().decode(ProjectEditJSON.self,from:body) else{throw APIError.invalidRequest}
            let command=try OwnedTopicCoverSelectionCommand.decode(json,owner:asset.ownerMemberID)
            guard command.asset==asset else{throw APIError.invalidRequest}
            if let previous=receipts[command.requestID]{return try response(previous.fields)}
            guard path=="/"+OwnedTopicCoverClient.selectPath else{return try response(.null,status:409)}
            let receipt=OwnedTopicCoverSelectionReceipt(topicID:command.topicID,configVersion:command.expectedConfigVersion+1,selectionVersion:command.expectedSelectionVersion+1,contentSlotID:command.expectedContentSlotID,asset:asset)
            receipts[command.requestID]=receipt;selected=receipt
            if unknownSelection && !unknownSent{unknownSent=true;return try response(.null,status:503)}
            beforeReceipt?();return try response(receipt.fields)
        }
        var displayFields:ProjectEditJSON{.object(["kind":.string("OWNED_TOPIC_COVER_AUTHENTICATED_CONTENT_V1"),"audience":.string("AUTHOR_ONLY"),"path":.string("/\(asset.contentPath)?sourceVersion=\(asset.sourceVersion)&contentHash=\(asset.contentHash)"),"contentHash":.string(asset.contentHash)])}
        private func response(_ value:ProjectEditJSON,status:Int=200)throws->(Data,Int){(try JSONEncoder().encode(["code":ProjectEditJSON.number(Decimal(status)),"data":value]),status)}
    }
    private let wire:Wire,client:OwnedTopicCoverClient
    let picked:RetainedSelectedImage
    var asset:OwnedTopicCoverAsset{wire.asset}
    func simulateImageReadFailure(){wire.imageUnavailable=true}
    func beforeNextReceipt(_ action:@escaping()->Void){wire.beforeReceipt=action}
    var currentReadCount:Int{wire.requests.filter{$0.url?.path=="/"+OwnedTopicCoverClient.currentPath}.count}
    var uploadCount:Int{wire.requests.filter{$0.url?.path=="/"+OwnedTopicCoverClient.uploadPath}.count}
    var selectCount:Int{wire.requests.filter{$0.url?.path=="/"+OwnedTopicCoverClient.selectPath}.count}
    var statusCount:Int{wire.requests.filter{$0.url?.path=="/"+OwnedTopicCoverClient.statusPath}.count}
    var imageCount:Int{wire.requests.filter{$0.url?.path=="/"+asset.contentPath}.count}
    var requestIDs:[String]{wire.requests.compactMap{r in guard let body=r.httpBody,let row=try? JSONDecoder().decode([String:ProjectEditJSON].self,from:body)else{return nil};return row["requestId"]?.text}}
    var reviewInput:ProjectEditJSON? {
        guard let selected=wire.selected else{return nil}
        var row=ApprovedTopicReviewSynthetic.selectedCoverFields(owner:asset.ownerMemberID,releaseBound:true).object ?? [:]
        row["topicConfigVersion"] = .number(Decimal(selected.configVersion));row["selectionVersion"] = .number(Decimal(selected.selectionVersion))
        row["assetReference"]=asset.fields;row["authorDisplayReference"]=wire.displayFields
        return .object(row)
    }
    init(session:ProjectEditSession,unknownSelection:Bool=false,unknownUpload:Bool=false,beforeReceipt:(()->Void)?=nil,currentSession:@escaping()->ProjectEditSession?)throws{
        let image=UIGraphicsImageRenderer(size:CGSize(width:64,height:48)).image{c in
            UIColor.systemTeal.setFill();c.fill(CGRect(x:0,y:0,width:64,height:48));UIColor.white.setFill();c.fill(CGRect(x:16,y:12,width:32,height:24))
        }
        guard let bytes=image.jpegData(compressionQuality:0.9)else{throw OwnedTopicCoverFailure.invalidResponse}
        picked=try RetainedImageSanitizer.sanitize(bytes)
        let data=picked.jpeg,hash=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
        let asset=OwnedTopicCoverAsset(assetID:"11111111-1111-4111-8111-111111111111",sourceVersion:"22222222-2222-4222-8222-222222222222",contentHash:hash,ownerMemberID:session.accountID)
        wire=Wire(asset:asset,bytes:data,unknownSelection:unknownSelection,unknownUpload:unknownUpload,beforeReceipt:beforeReceipt)
        let config=try APIConfiguration(baseURL:URL(string:"https://example.com")!),approval=try OwnedTopicCoverApproval(baseURL:config.baseURL,namespace:session.storageNamespace,accountID:session.accountID,operations:[.readCurrent,.readAsset,.upload,.select,.status],nativePicker:true)
        client=OwnedTopicCoverClient(configuration:config,approval:approval,jsonTransport:wire,imageTransport:wire,currentCredentials:{guard currentSession()==session else{return nil};return try? .init(session:session,token:"synthetic-author-cover")},currentApproval:{currentSession()==session ? approval:nil})
    }
    func isCurrent(session:ProjectEditSession)->Bool{client.isCurrent(session:session)}
    func permits(_ operation:OwnedTopicCoverOperation,session:ProjectEditSession)->Bool{client.permits(operation,session:session)}
    func permitsNativePicker(session:ProjectEditSession)->Bool{client.permitsNativePicker(session:session)}
    func current(topicID:Int,session:ProjectEditSession)async throws->OwnedTopicCoverCurrent{try await client.current(topicID:topicID,session:session)}
    func upload(_ selection:RetainedSelectedImage,session:ProjectEditSession)async throws->OwnedTopicCoverAsset{try await client.upload(selection,session:session)}
    func select(_ command:OwnedTopicCoverSelectionCommand,session:ProjectEditSession)async throws->OwnedTopicCoverSelectionReceipt{try await client.select(command,session:session)}
    func status(_ command:OwnedTopicCoverSelectionCommand,session:ProjectEditSession)async throws->OwnedTopicCoverSelectionReceipt{try await client.status(command,session:session)}
    func content(_ asset:OwnedTopicCoverAsset,session:ProjectEditSession)async throws->Data{try await client.content(asset,session:session)}
}
#endif
