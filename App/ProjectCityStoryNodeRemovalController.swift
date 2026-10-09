import SwiftUI

struct ProjectCityStoryNodeRemovalHostIdentity:Hashable { let owner:ObjectIdentifier,chapter:Data }

@MainActor final class ProjectCityStoryNodeRemovalController:ObservableObject {
    struct Capture {
        let controllerID:UUID,generation:Int,lease:ProjectEditStarterController.Lease
        let revision:Int,bytes:Data
        let nodeIDs:[String],blockIDs:[String],blockNodeIDs:[String?]
    }
    struct Confirmation:Identifiable { let id=UUID();let capture:Capture,receipt:ProjectCityStoryNodeRemoval.Receipt }
    struct Undo:Identifiable { let id=UUID();let capture:Capture,receipt:ProjectCityStoryNodeRemoval.Receipt;let deadline:TimeInterval }
    @Published private(set) var confirmation:Confirmation?
    @Published private(set) var undo:Undo?
    @Published private(set) var blocked=false
    @Published private(set) var saveUnconfirmed=false
    @Published private var active=false
    let model:ProjectEditModel,chapterID:String
    private let controllerID=UUID(),now:()->TimeInterval
    private var generation=0,expiry:Task<Void,Never>?
    init(model:ProjectEditModel,chapterID:String,now:@escaping()->TimeInterval={ProcessInfo.processInfo.systemUptime}) { self.model=model;self.chapterID=chapterID;self.now=now }
    func setActive(_ value:Bool) { guard active != value else{return};active=value;if !value{retire()} }
    func capture()->Capture? {
        guard active,!saveUnconfirmed,model.fullEdit,model.draft.product == .city,model.draft.owner == .personal,
              let lease=model.captureStarterLease(),
              let chapter=model.draft.chapters.first(where:{Data($0.id.utf8)==Data(chapterID.utf8)}),
              let bytes=ProjectEditPendingMaterials.exactData(model.draft) else{return nil}
        let blocks=chapter.blocks ?? []
        return .init(controllerID:controllerID,generation:generation,lease:lease,revision:model.draftMutationRevision,bytes:bytes,
                     nodeIDs:chapter.nodes.map(\.id),blockIDs:blocks.map(\.id),blockNodeIDs:blocks.map{$0.kind == .node ? $0.nodeID:nil})
    }
    private func current(_ capture:Capture)->Bool {
        active && !saveUnconfirmed && capture.controllerID==controllerID && capture.generation==generation &&
        model.fullEdit && model.draft.product == .city && model.draft.owner == .personal && model.isCurrentStarterLease(capture.lease) &&
        model.draftMutationRevision==capture.revision && ProjectEditPendingMaterials.exactData(model.draft)==capture.bytes
    }
    func canRemove(_ nodeID:String,captured:Capture?)->Bool {
        guard let captured,current(captured),confirmation==nil else{return false}
        return (try? ProjectCityStoryNodeRemoval.removing(nodeID:nodeID,chapterID:chapterID,in:model.draft)) != nil
    }
    func isCurrent(_ value:Confirmation)->Bool { confirmation?.id==value.id && current(value.capture) }
    func canUndo(_ value:Undo)->Bool { undo?.id==value.id && now()<value.deadline && current(value.capture) }
    /// Returns false only for an all-non-node story selection, whose old handler remains owner.
    func interceptStory(offsets:IndexSet,captured:Capture?)->Bool {
        guard let captured else{blocked=true;return true}
        guard current(captured),!offsets.isEmpty,offsets.allSatisfy({captured.blockIDs.indices.contains($0)}) else{blocked=true;return true}
        let nodeIDs=offsets.compactMap{captured.blockNodeIDs[$0]}
        if nodeIDs.isEmpty{return false}
        guard offsets.count==1,nodeIDs.count==1 else{blocked=true;return true}
        open(nodeIDs[0],captured:captured);return true
    }
    func openNodes(offsets:IndexSet,captured:Capture?) {
        guard let captured,current(captured),offsets.count==1,let index=offsets.first,captured.nodeIDs.indices.contains(index) else{blocked=true;return}
        open(captured.nodeIDs[index],captured:captured)
    }
    func open(_ nodeID:String,captured:Capture?) {
        guard let captured,canRemove(nodeID,captured:captured),
              let receipt=try? ProjectCityStoryNodeRemoval.removing(nodeID:nodeID,chapterID:chapterID,in:model.draft) else{blocked=true;return}
        blocked=false;confirmation = .init(capture:captured,receipt:receipt)
    }
    func confirm(_ original:Confirmation) {
        guard isCurrent(original) else{return}
        var receipt=original.receipt
        if let undo,canUndo(undo),let combined=try? ProjectCityStoryNodeRemoval.combining(undo.receipt,with:receipt){receipt=combined}
        guard persist(original.receipt.after,captured:original.capture) else{failSave();return}
        confirmation=nil
        guard let nextCapture=capture() else{retire();return}
        let next=Undo(capture:nextCapture,receipt:receipt,deadline:now()+5)
        undo=next;expiry?.cancel()
        expiry=Task{[weak self]in
            do{try await Task.sleep(nanoseconds:5_000_000_000)}catch{return}
            guard !Task.isCancelled else{return};self?.expire(next.id)
        }
    }
    func restore(_ original:Undo) {
        guard canUndo(original),let before=try? ProjectCityStoryNodeRemoval.restoring(original.receipt,in:model.draft) else{synchronize();return}
        guard persist(before,captured:original.capture) else{failSave();return}
        undo=nil;expiry?.cancel();generation+=1
    }
    private func persist(_ draft:ProjectEditDraft,captured:Capture)->Bool {
        guard current(captured) else{return false}
        guard model.persistLocalChange(draft,lease:captured.lease) else{return false}
        return active && model.isCurrentStarterLease(captured.lease) && model.draftMutationRevision==captured.revision+1 &&
            ProjectEditPendingMaterials.exactData(model.draft)==ProjectEditPendingMaterials.exactData(draft)
    }
    private func failSave() { saveUnconfirmed=true;confirmation=nil;undo=nil;expiry?.cancel();generation+=1 }
    private func expire(_ id:UUID) { if undo?.id==id{undo=nil} }
    func synchronize() {
        if let confirmation,!isCurrent(confirmation){self.confirmation=nil}
        if let undo,!canUndo(undo){self.undo=nil;expiry?.cancel()}
    }
    func close(_ original:Confirmation) { if confirmation?.id==original.id{confirmation=nil} }
    func retire() { confirmation=nil;undo=nil;blocked=false;expiry?.cancel();generation+=1 }
    func binding(_ original:Confirmation?)->Binding<Confirmation?> {
        .init(get:{guard let original,self.isCurrent(original)else{return nil};return original},set:{if $0==nil,let original{self.close(original)}})
    }
}

@MainActor struct ProjectCityStoryNodeRemovalHost<Content:View>:View {
    @ObservedObject private var model:ProjectEditModel
    @StateObject private var controller:ProjectCityStoryNodeRemovalController
    @Environment(\.scenePhase) private var phase
    private let content:(ProjectCityStoryNodeRemovalController)->Content
    init(model:ProjectEditModel,chapterID:String,@ViewBuilder content:@escaping(ProjectCityStoryNodeRemovalController)->Content) {
        self.model=model;self.content=content;_controller=StateObject(wrappedValue:.init(model:model,chapterID:chapterID))
    }
    var body:some View {
        content(controller)
            .onAppear{controller.setActive(phase == .active)}
            .onChange(of:phase){_,next in controller.setActive(next == .active)}
            .onChange(of:model.draftMutationRevision){_,_ in controller.synchronize()}
            .onChange(of:model.editorIncarnation){_,_ in controller.setActive(false)}
            .onChange(of:model.coordinator.session){_,_ in controller.setActive(false)}
            .onChange(of:model.canEdit){_,allowed in if !allowed{controller.setActive(false)}}
            .onDisappear{controller.setActive(false)}
    }
}
@MainActor struct ProjectCityStoryNodeRemovalStatus:View {
    @ObservedObject var controller:ProjectCityStoryNodeRemovalController
    var body:some View {
        if controller.saveUnconfirmed {
            Text("projectCityNodeRemoval.saveUnconfirmed",tableName:"ProjectCityStoryNodeRemoval").accessibilityIdentifier("projectCityNodeRemoval.saveUnconfirmed")
        } else if let undo=controller.undo,controller.canUndo(undo) {
            VStack(alignment:.leading){
                Text("projectCityNodeRemoval.removed",tableName:"ProjectCityStoryNodeRemoval")
                Button{controller.restore(undo)}label:{Text("projectCityNodeRemoval.undo",tableName:"ProjectCityStoryNodeRemoval")}.accessibilityIdentifier("projectCityNodeRemoval.undo")
            }
        }
        if controller.blocked{Text("projectCityNodeRemoval.unsupported",tableName:"ProjectCityStoryNodeRemoval").accessibilityIdentifier("projectCityNodeRemoval.unsupported")}
    }
}
@MainActor struct ProjectCityStoryNodeRemovalPresentation:ViewModifier {
    @ObservedObject var controller:ProjectCityStoryNodeRemovalController
    func body(content:Content)->some View {
        let original=controller.confirmation
        content.sheet(item:controller.binding(original)){value in
            NavigationStack{Form{
                Text("projectCityNodeRemoval.warning",tableName:"ProjectCityStoryNodeRemoval")
                ForEach(value.receipt.before.chapters.flatMap(\.nodes).filter{value.receipt.nodeIDs.contains($0.id)}){node in Text(verbatim:node.name)}
                Button(role:.destructive){controller.confirm(value)}label:{Text("projectCityNodeRemoval.confirm",tableName:"ProjectCityStoryNodeRemoval")}
                    .disabled(!controller.isCurrent(value)).accessibilityIdentifier("projectCityNodeRemoval.confirm")
            }.navigationTitle(Text("projectCityNodeRemoval.title",tableName:"ProjectCityStoryNodeRemoval"))
             .toolbar{ToolbarItem(placement:.cancellationAction){Button("action.cancel"){controller.close(value)}.accessibilityIdentifier("projectCityNodeRemoval.cancel")}}}
        }
    }
}
