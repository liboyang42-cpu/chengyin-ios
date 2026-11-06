import SwiftUI

@MainActor struct NativeRpgResourceAuthorEntry:View {
    @ObservedObject var model:ProjectEditModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale
    private var copy: NativeRpgResourceAuthorPresentation { .init(locale: locale) }
    @State private var editToken = UUID()
    @State private var editor:NativeRpgResourceAuthorDraft?
    @State private var capture:Capture?
    @State private var reviewed:ProjectEditJSON?
    @State private var message:String?
    private struct Capture {
        let incarnation:UUID;let revision:Int;let session:ProjectEditSession;let snapshot:ProjectEditSnapshot
        let draft:ProjectEditDraft;let draftBytes:Data;let lease:ProjectEditStarterController.Lease
    }
    private var current:Bool {
        guard scenePhase == .active,let capture,model.fullEdit,model.confirmation == nil else{return false}
        return model.editorIncarnation == capture.incarnation && model.draftMutationRevision == capture.revision
            && model.coordinator.session == capture.session
            && model.coordinator.session?.storageNamespace.utf8.elementsEqual(capture.session.storageNamespace.utf8) == true
            && model.coordinator.snapshot == capture.snapshot && model.draft == capture.draft
            && ProjectEditPendingMaterials.exactData(model.draft) == capture.draftBytes
            && model.isCurrentStarterLease(capture.lease)
    }
    private func close(){editToken = UUID();editor = nil;capture = nil;reviewed = nil}
    private func mutate(_ token: UUID, _ action:(inout NativeRpgResourceAuthorDraft)->Void){guard current,editToken == token,var next = editor else{return};action(&next);editor = next;editToken = UUID();reviewed = nil;message = nil}
    private func field(_ name:String,_ field:String)->Binding<String>{let token = editToken; return Binding(get:{editor?.text(name,field) ?? ""},set:{value in mutate(token){$0.edit(name,field,value)}})}
    var body:some View {
        let token = editToken
        Section(copy.text("rpgResource.copy.000")) {
            if editor == nil {
                Button(copy.text("rpgResource.copy.001")) {
                    guard editToken == token,capture == nil,scenePhase == .active,model.fullEdit,model.confirmation == nil,let session = model.coordinator.session,let snapshot = model.coordinator.snapshot,
                          let lease = model.captureStarterLease(),let bytes = ProjectEditPendingMaterials.exactData(model.draft) else{return}
                    do {editor = try .init(draft:model.draft);capture = .init(incarnation:model.editorIncarnation,revision:model.draftMutationRevision,session:session,snapshot:snapshot,draft:model.draft,draftBytes:bytes,lease:lease);message = nil}
                    catch {message = "须已有原schema2 journeyRules；不转换schema1、不新建角色或资源模板。"}
                }.disabled(scenePhase != .active || !model.fullEdit || model.confirmation != nil).accessibilityIdentifier("rpgResource.open")
            } else if current,let draft = editor {
                Group {
                    Text(copy.text("rpgResource.copy.003")).nativeAuthorSupportingCopy()
                    ForEach(NativeRpgResourceAuthorDraft.names,id:\.self){name in
                        VStack(alignment:.leading){
                            Text(verbatim: copy.resource(name)).font(.headline)
                            Picker(copy.text("rpgResource.copy.004"),selection:field(name,"enabled")) {Text(copy.text("rpgResource.copy.005")).tag("");Text(copy.text("rpgResource.copy.006")).tag("true");Text(copy.text("rpgResource.copy.007")).tag("false")}
                                .accessibilityLabel(Text(verbatim: copy.resource(name) + ": " + copy.text("rpgResource.copy.004"))).accessibilityIdentifier("rpgResource.\(name).enabled")
                            TextField(copy.text("rpgResource.copy.008"),text:field(name,"init")).keyboardType(.numberPad)
                                .frame(minHeight: 44).accessibilityLabel(Text(verbatim: copy.resource(name) + ": " + copy.text("rpgResource.copy.008"))).accessibilityIdentifier("rpgResource.\(name).initial")
                            TextField(copy.text("rpgResource.copy.009"),text:field(name,"max")).keyboardType(.numberPad)
                                .frame(minHeight: 44).accessibilityLabel(Text(verbatim: copy.resource(name) + ": " + copy.text("rpgResource.copy.009"))).accessibilityIdentifier("rpgResource.\(name).maximum")
                            Text(name == "hp" ? copy.text("rpgResource.copy.010") : name == "luck" ? copy.text("rpgResource.copy.011") : copy.text("rpgResource.copy.012"))
                            Button(copy.text("rpgResource.copy.013")){mutate(token){$0.restore(name)}}.accessibilityIdentifier("rpgResource.\(name).restore")
                        }
                    }
                    VStack(alignment:.leading){
                        Text(copy.text("rpgResource.copy.014")).font(.headline)
                        TextField(copy.text("rpgResource.copy.015"),text:Binding(get:{editor?.stageMoraleFloorText ?? ""},set:{value in mutate(token){$0.editStageMoraleFloor(value)}})).keyboardType(.numberPad).frame(minHeight: 44).accessibilityIdentifier("rpgResource.moraleFloor")
                        Text(copy.text("rpgResource.copy.016")).nativeAuthorSupportingCopy()
                        Button(copy.text("rpgResource.copy.017")){mutate(token){$0.restoreStageMoraleFloor()}}.accessibilityIdentifier("rpgResource.moraleFloor.restore")
                    }
                    ForEach(Array(draft.issues.enumerated()),id:\.offset){_,issue in NativeAuthorNotice(text: Text(verbatim: copy.message(issue)), tone: .attention)}
                    Button(copy.text("rpgResource.copy.018")) {
                        guard current, editToken == token else{return}
                        do {reviewed = try draft.applying(to:model.draft).preserved["journeyRules"];message = nil}
                        catch {reviewed = nil;message = "字段或原草稿不可用，未生成可确认预览。"}
                    }.disabled(!draft.issues.isEmpty).accessibilityIdentifier("rpgResource.review")
                    if let reviewed {
                        Text(verbatim: reviewed.text ?? "").font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("rpgResource.preview")
                        Button(copy.text("rpgResource.copy.020")) {
                            guard current,editToken == token,let reviewedText = reviewed.text,let currentReview = self.reviewed?.text,
                                  currentReview.utf8.elementsEqual(reviewedText.utf8),let capture,let editor,
                                  let proposed = try? editor.applying(to:model.draft),let proposedText = proposed.preserved["journeyRules"]?.text,
                                  proposedText.utf8.elementsEqual(reviewedText.utf8) else{return}
                            guard model.persistLocalChange(proposed,lease:capture.lease) else {
                                message = "原本地保存未确认；保留资源编辑副本，可再次确认本地保存，尚未保存服务器或发布。";return
                            }
                            close();message = "已沿原保存器保存本地草稿，尚未保存服务器或发布。"
                        }.nativeAuthorPrimaryAction().accessibilityIdentifier("rpgResource.confirm").accessibilityHint(Text(copy.text("rpgResource.localOnly")))
                    }
                    Text("沿原项目保存／同请求恢复／发布及真实新局初始化。旧局不补资源、不迁移余额；原消费、技能点、专长及TEAM写端均不改；阶段士气保底只由原STAGE_REST写端使用明确冻结值。角色页另读本人原局当前资源，检定结果展示该原请求已保存余额。").nativeAuthorSupportingCopy()
                }.disabled(!current)
                Button(copy.text("rpgResource.copy.024")){guard editToken == token else{return};close()}.accessibilityIdentifier("rpgResource.close")
            } else {
                Text(copy.text("rpgResource.copy.025"))
                Button(copy.text("rpgResource.copy.024")){guard editToken == token else{return};close()}.accessibilityIdentifier("rpgResource.close")
            }
            if let message{NativeAuthorNotice(text: Text(verbatim: copy.message(message))).accessibilityIdentifier("rpgResource.notice")}
        }.accessibilityIdentifier("rpgResource.author").onDisappear{close()}.onChange(of:current){_,valid in if !valid{close()}}
    }
}
