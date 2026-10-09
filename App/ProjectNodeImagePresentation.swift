import SwiftUI

/// StateObject lifetime includes the actual owner object, not just reusable node IDs.
struct ProjectNodeImageHostIdentity:Hashable {
    let owner:ObjectIdentifier,chapter:Data,node:Data
}

@MainActor final class ProjectNodeImagePresentation:ObservableObject {
    struct Opening {
        let lease:ProjectEditStarterController.Lease
        let context:ProjectNodeImageContext
        let source:any ProjectNodeImageUploading
        let journal:ProjectNodeImageJournal
        let recoveryOnly:ProjectNodeImageJournal.Entry?
        let nodeName:String
        let hostID:UUID
    }
    struct Presentation:Identifiable {
        let opening:Opening,flow:ProjectNodeImageFlow
        var id:UUID{flow.id}
    }
    @Published private(set) var presentation:Presentation?
    @Published private var active=false
    private var hostID=UUID()
    private var savedRevision:(id:UUID,revision:Int)?
    let editor:ProjectEditModel
    let chapterID:String,nodeID:String
    init(editor:ProjectEditModel,chapterID:String,nodeID:String){self.editor=editor;self.chapterID=chapterID;self.nodeID=nodeID}
    func setActive(_ value:Bool){
        guard active != value else{return};active=value
        if !value{hostID=UUID();if let original=presentation{close(original)}}
    }
    func capture()->Opening?{
        guard active,editor.fullEdit,presentation==nil,let lease=editor.captureStarterLease(),
              let source=editor.coordinator.nodeImageSource,let journal=editor.coordinator.nodeImageJournal,
              let node=editor.draft.chapters.first(where:{Data($0.id.utf8)==Data(chapterID.utf8)})?.nodes.first(where:{Data($0.id.utf8)==Data(nodeID.utf8)})else{return nil}
        let revision=editor.draftMutationRevision,nonce=UUID()
        func context(_ target:ProjectNodeImageTarget)->ProjectNodeImageContext?{
            try? .init(target:target,session:lease.session,identity:lease.identity,editorID:lease.incarnation,presentationID:nonce,draftRevision:revision)
        }
        let fresh=try? ProjectNodeImageTarget(draft:editor.draft,identity:lease.identity,session:lease.session,scope:.full,chapterID:chapterID,nodeID:nodeID)
        var recovery:ProjectNodeImageJournal.Entry?
        let field=ProjectNodePhotoRemoval(draft:editor.draft,chapterID:chapterID,nodeID:nodeID)
        if fresh==nil,field.isCurrent(in:editor.draft),field.photos.count==9,
           let saved=try? journal.read(session:lease.session,identity:lease.identity){
            let matches=saved.entries.filter{entry in
                guard !entry.applied,entry.target.chapterID==Data(chapterID.utf8),entry.target.nodeID==Data(nodeID.utf8),
                      let receipt=entry.receipt,let ctx=context(entry.target),source.permitsReference(receipt,context:ctx)else{return false}
                return entry.target.hasAppliedReference(receipt,in:editor.draft,identity:lease.identity,session:lease.session)
            }
            if matches.count==1{recovery=matches[0]}
        }
        guard let target=fresh ?? recovery?.target,let ctx=context(target),source.isCurrent(context:ctx)else{return nil}
        return .init(lease:lease,context:ctx,source:source,journal:journal,recoveryOnly:recovery,nodeName:node.name,hostID:hostID)
    }
    func isCurrent(_ original:Opening)->Bool{
        let revision=savedRevision?.id==original.context.presentationID ? savedRevision?.revision:original.context.draftRevision
        guard active,original.hostID==hostID,editor.fullEdit,editor.isCurrentStarterLease(original.lease),
              editor.editorIncarnation==original.context.editorID,editor.draftMutationRevision==revision,
              original.context.target.chapterID==Data(chapterID.utf8),original.context.target.nodeID==Data(nodeID.utf8),
              editor.coordinator.session==original.context.session,editor.coordinator.identity==original.context.identity,
              let source=editor.coordinator.nodeImageSource,ObjectIdentifier(source)==ObjectIdentifier(original.source),
              editor.coordinator.nodeImageJournal===original.journal else{return false}
        return source.isCurrent(context:original.context)
    }
    func open(_ original:Opening){
        guard presentation==nil,isCurrent(original)else{return}
        if let entry=original.recoveryOnly {
            guard !entry.applied,entry.target==original.context.target,let receipt=entry.receipt,
                  let saved=try? original.journal.read(session:original.context.session,identity:original.context.identity),saved.entries.contains(entry),
                  original.source.permitsReference(receipt,context:original.context),
                  entry.target.hasAppliedReference(receipt,in:editor.draft,identity:original.context.identity,session:original.context.session)else{return}
        }else{guard original.context.target.matches(editor.draft,identity:original.context.identity,session:original.context.session)else{return}}
        savedRevision=nil
        let flow=ProjectNodeImageFlow(context:original.context,source:original.source,journal:original.journal,recoveryOnly:original.recoveryOnly,
            currentDraft:{[weak self]in self?.editor.draft},parentCurrent:{[weak self]in self?.isCurrent(original)==true})
        presentation = .init(opening:original,flow:flow)
    }
    func apply(_ original:Presentation){
        guard presentation?.id==original.id,isCurrent(original.opening),let next=original.flow.draftForApply()else{return}
        let before=editor.draftMutationRevision
        guard editor.persistLocalChange(next,lease:original.opening.lease)else{original.flow.localSaveFailed();return}
        guard presentation?.id==original.id,active,original.opening.hostID==hostID,editor.isCurrentStarterLease(original.opening.lease),
              editor.draftMutationRevision==before+1,ProjectEditPendingMaterials.exactData(editor.draft)==ProjectEditPendingMaterials.exactData(next)else{close(original);return}
        savedRevision=(original.opening.context.presentationID,editor.draftMutationRevision)
        original.flow.didSaveAppliedDraft();if original.flow.state == .applied{close(original)}
    }
    func close(_ original:Presentation){original.flow.close();guard presentation?.id==original.id else{return};presentation=nil;savedRevision=nil}
    func binding(_ original:Presentation?)->Binding<Presentation?>{
        .init(get:{guard let original,self.presentation?.id==original.id,self.isCurrent(original.opening)else{return nil};return original},
              set:{if $0==nil,let original{self.close(original)}})
    }
}
