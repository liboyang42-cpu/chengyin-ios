import SwiftUI
import UIKit

@MainActor final class ProjectNodeImageAuthorModel:ObservableObject {
    let original:ProjectNodeImagePresentation.Presentation
    let pickerHost=RetainedImagePickerHost()
    @Published private(set) var revision=0
    @Published private(set) var preview:UIImage?
    let crop:ProjectNodeImageCrop
    private let injectedPicker:(any OwnedTopicCoverSelecting)?
    private let applyDraft:(ProjectNodeImagePresentation.Presentation)->Void
    private lazy var nativePicker=pickerHost.makePicker(selectionApproval:{[weak self]in
        guard let self else{return false};return self.flow.isCurrent && self.flow.matchesCapturedDraft && self.original.opening.source.permitsPicker(context:self.flow.context)
    })
    private var picker:any OwnedTopicCoverSelecting{injectedPicker ?? nativePicker}
    private var pickerTask:Task<Void,Never>?,pickerID:UUID?,cropPickerID:UUID?
    var flow:ProjectNodeImageFlow{original.flow}
    var canChoose:Bool{flow.canPick && crop.draft==nil && pickerTask==nil}
    init(original:ProjectNodeImagePresentation.Presentation,picker:(any OwnedTopicCoverSelecting)?=nil,
         apply:@escaping(ProjectNodeImagePresentation.Presentation)->Void){
        self.original=original;injectedPicker=picker;applyDraft=apply
        crop = .init(current:{original.flow.isCurrent && original.flow.matchesCapturedDraft})
    }
    func load(){flow.load();revision+=1}
    func choose()async{
        guard canChoose,let id=flow.beginPicking()else{return};pickerID=id;revision+=1
        let selected=picker
        let task=Task{[weak self]in
            guard let self else{return}
            defer{if self.pickerID==id{self.pickerID=nil;self.pickerTask=nil;self.revision+=1}}
            do{
                let image=try await selected.select()
                guard self.pickerID==id,!Task.isCancelled,self.flow.isCurrent else{return}
                if let image,self.flow.matchesCapturedDraft,let policy=self.original.opening.source.policy(context:self.flow.context){
                    self.crop.stage(image,policy:policy)
                    if self.crop.draft != nil{self.cropPickerID=id}else{self.flow.finishPicking(nil,original:id)}
                }else{self.flow.finishPicking(nil,original:id)}
            }catch{if self.pickerID==id{self.flow.finishPicking(nil,original:id)}}
        };pickerTask=task
        await withTaskCancellationHandler(operation:{await task.value},onCancel:{task.cancel()})
    }
    func confirmCrop(_ id:UUID,_ horizontal:Double,_ vertical:Double,_ zoom:Double){
        guard let pickerID=cropPickerID,let image=crop.confirm(id,horizontal:horizontal,vertical:vertical,zoom:zoom)else{revision+=1;return}
        flow.finishPicking(image,original:pickerID);cropPickerID=nil
        if flow.review?.image.jpeg==image.jpeg{preview=UIImage(data:image.jpeg)};revision+=1
    }
    func cancelCrop(_ id:UUID){guard crop.draft?.id==id else{return};crop.cancel(id);if let pickerID=cropPickerID{flow.finishPicking(nil,original:pickerID);cropPickerID=nil};revision+=1}
    func cancel(_ review:ProjectNodeImageFlow.Review){flow.cancelReview(review);if flow.review==nil{preview=nil};revision+=1}
    func upload(_ review:ProjectNodeImageFlow.Review){
        guard crop.draft==nil,pickerTask==nil,let claim=flow.claimUpload(review)else{return};revision+=1
        Task{[weak self,flow]in await flow.upload(claim);self?.revision+=1}
    }
    func persistReceipt(){flow.persistReceipt();revision+=1}
    func apply(){guard flow.canApply else{return};applyDraft(original);revision+=1}
    func close(){pickerTask?.cancel();pickerTask=nil;pickerID=nil;cropPickerID=nil;picker.cancel();crop.invalidate();flow.close();preview=nil;revision+=1}
}
@MainActor struct ProjectNodeImageAuthorView:View {
    let original:ProjectNodeImagePresentation.Presentation
    let close:()->Void
    @StateObject private var model:ProjectNodeImageAuthorModel
    @Environment(\.scenePhase) private var scenePhase
    init(original:ProjectNodeImagePresentation.Presentation,picker:(any OwnedTopicCoverSelecting)?=nil,
         apply:@escaping(ProjectNodeImagePresentation.Presentation)->Void,close:@escaping()->Void){
        self.original=original;self.close=close;_model=StateObject(wrappedValue:.init(original:original,picker:picker,apply:apply))
    }
    var body:some View{
        let flow=model.flow
        NavigationStack{
            Form{
                Section{
                    Text("projectNodeImage.scope",tableName:"ProjectNodeImageAuthor")
                    Text(verbatim:original.opening.nodeName).accessibilityIdentifier("projectNodeImage.node")
                    Button{Task{await model.choose()}}label:{Text("projectNodeImage.choose",tableName:"ProjectNodeImageAuthor")}
                        .disabled(!model.canChoose).accessibilityIdentifier("projectNodeImage.choose")
                    if let draft=model.crop.draft{ProjectNodeImageCropView(draft:draft,confirm:model.confirmCrop,cancel:model.cancelCrop).id(draft.id)}
                    if let preview=model.preview{Image(uiImage:preview).resizable().scaledToFit().accessibilityIdentifier("projectNodeImage.localPreview")}
                    if let review=flow.review{
                        Text("projectNodeImage.uploadReview",tableName:"ProjectNodeImageAuthor")
                        Button{model.upload(review)}label:{Text("projectNodeImage.upload",tableName:"ProjectNodeImageAuthor")}
                            .disabled(!flow.canUpload(review)).accessibilityIdentifier("projectNodeImage.upload")
                        Button("action.cancel",role:.cancel){model.cancel(review)}.disabled(flow.busy).accessibilityIdentifier("projectNodeImage.cancelReview")
                    }
                    if flow.busy{ProgressView().accessibilityIdentifier("projectNodeImage.busy")}
                    if flow.unresolvedUploadCount>0 || flow.state == .unknown{Text("projectNodeImage.unknown",tableName:"ProjectNodeImageAuthor")}
                    if flow.state == .failed || flow.state == .unauthorized{Text("projectNodeImage.failed",tableName:"ProjectNodeImageAuthor")}
                    if let receipt=flow.receipt{
                        Text(verbatim:receipt.reference).textSelection(.enabled).accessibilityIdentifier("projectNodeImage.receipt")
                        Text("projectNodeImage.receiptOnly",tableName:"ProjectNodeImageAuthor")
                        if !flow.referenceFitsCSV{Text("projectNodeImage.unsupportedReference",tableName:"ProjectNodeImageAuthor")}
                        if flow.hasUnstoredReceipt{
                            Text("projectNodeImage.unstored",tableName:"ProjectNodeImageAuthor")
                            Button{model.persistReceipt()}label:{Text("projectNodeImage.persistReceipt",tableName:"ProjectNodeImageAuthor")}
                                .disabled(!flow.canPersistReceipt).accessibilityIdentifier("projectNodeImage.persistReceipt")
                        }
                        Button{model.apply()}label:{Text(LocalizedStringKey(flow.alreadyApplied ? "projectNodeImage.finishLocal":"projectNodeImage.append"),tableName:"ProjectNodeImageAuthor")}
                            .disabled(!flow.canApply).accessibilityIdentifier("projectNodeImage.append")
                    }
                    if flow.state == .localSaveFailed{Text("projectNodeImage.localFailure",tableName:"ProjectNodeImageAuthor")}
                }
            }.navigationTitle(Text("projectNodeImage.title",tableName:"ProjectNodeImageAuthor"))
                .toolbar{ToolbarItem(placement:.cancellationAction){Button{model.close();close()}label:{Text("projectNodeImage.close",tableName:"ProjectNodeImageAuthor")}.accessibilityIdentifier("projectNodeImage.close")}}
                .task{model.load()}.background(RetainedImagePresenterHost(host:model.pickerHost).frame(width:0,height:0))
                .onChange(of:scenePhase){_,phase in if phase != .active{model.close();close()}}
                .onDisappear{model.close()}
        }
    }
}
@MainActor struct ProjectNodeImageAuthorField:View {
    @ObservedObject private var model:ProjectEditModel
    @StateObject private var photos:ProjectNodeImagePresentation
    @Environment(\.scenePhase) private var scenePhase
    init(model:ProjectEditModel,chapterID:String,nodeID:String){self.model=model;_photos=StateObject(wrappedValue:.init(editor:model,chapterID:chapterID,nodeID:nodeID))}
    var body:some View{
        let captured=photos.capture(),original=photos.presentation
        Button{if let captured{photos.open(captured)}}label:{Text("projectNodeImage.add",tableName:"ProjectNodeImageAuthor")}
            .disabled(captured==nil).accessibilityIdentifier("projectNodeImage.add")
            .sheet(item:photos.binding(original)){value in ProjectNodeImageAuthorView(original:value,apply:photos.apply,close:{photos.close(value)})}
            .onAppear{photos.setActive(scenePhase == .active)}
            .onChange(of:scenePhase){_,phase in photos.setActive(phase == .active)}
            .onChange(of:model.editorIncarnation){_,_ in photos.setActive(false)}
            .onDisappear{photos.setActive(false)}
    }
}
